/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

// Periodically snapshots every online player's (and bot's) position into the
// `live_player_positions` table, for the standalone webapp/server.py dashboard
// to poll. World-only on purpose: no core files touched, no new thread, no
// sockets opened from inside the game process - just a throttled WorldScript
// tick writing plain SQL, matching the pattern used elsewhere in this repo's
// custom modules (see mod-xpboost).
//
// Position is stored both as raw world coordinates (pos_x/pos_y/pos_z) and as
// the 0-100 zone-relative percentage (pct_x/pct_y) that the client's own
// minimap/coordinate addons use, via the core's Map2ZoneCoordinates() helper -
// so the dashboard doesn't need to guess at continent bounding boxes.

#include "CharacterDatabase.h"
#include "DBCStores.h"
#include "GuildMgr.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "Playerbots.h"
#include "ScriptMgr.h"

#include <cmath>
#include <sstream>
#include <unordered_map>
#include <vector>

namespace
{
    constexpr uint32 LIVE_DASHBOARD_UPDATE_INTERVAL_MS = 2000;

    // Every this many ticks the whole table is rewritten regardless of what
    // changed, so a row that went wrong on the database side (a manual edit,
    // a restore, a lost write) cannot stay wrong for the rest of the uptime.
    constexpr uint32 FULL_RESYNC_EVERY_TICKS = 30;   // one minute

    // A character who has not moved this far is written as standing still.
    // Well under what a dot on the dashboard can show, so nothing visible is
    // lost - and it is what turns three thousand rows a tick into a few
    // hundred, because most bots are idle most of the time: BotActiveAlone
    // keeps the ones nobody is near from doing anything at all.
    constexpr float MOVED_THRESHOLD = 0.5f;

    // What was last written for each character, so the next tick can skip
    // everyone whose row would come out the same. The dashboard reads the
    // table, not this map, so getting it wrong can only cost an extra write.
    struct LastWritten
    {
        float x = 0.0f;
        float y = 0.0f;
        float z = 0.0f;
        uint32 areaId = 0;
        uint32 mapId = 0;
        uint32 zoneId = 0;
        uint32 level = 0;
        uint32 hpPct = 0;
        bool isBot = false;
        std::string guildName;
    };

    std::unordered_map<ObjectGuid::LowType, LastWritten> lastWritten;
    uint32 ticksSinceFullResync = FULL_RESYNC_EVERY_TICKS;   // the first tick is a full one

    std::string EscapedCopy(std::string str)
    {
        CharacterDatabase.EscapeString(str);
        return str;
    }
}

class live_dashboard_worldscript : public WorldScript
{
public:
    live_dashboard_worldscript() : WorldScript("live_dashboard_worldscript") { }

    void OnUpdate(uint32 diff) override
    {
        _timer += diff;
        if (_timer < LIVE_DASHBOARD_UPDATE_INTERVAL_MS)
            return;

        _timer = 0;
        UpdateSnapshot();
    }

private:
    uint32 _timer = 0;

    static void UpdateSnapshot()
    {
        // The first version rewrote all three thousand rows every two seconds
        // and then deleted everyone not in a three-thousand-entry NOT IN list.
        // On the world thread that was a few milliseconds of string building;
        // on the single character-database worker it was a three-thousand-row
        // upsert, binlog included, every two seconds, queued ahead of every
        // player save and chronicle line. Now a row is written only when it
        // would differ from the last one written, and a departed character is
        // deleted by guid rather than by exclusion.
        bool const fullResync = ++ticksSinceFullResync >= FULL_RESYNC_EVERY_TICKS;
        if (fullResync)
            ticksSinceFullResync = 0;

        std::unordered_map<ObjectGuid::LowType, LastWritten> seen;
        seen.reserve(lastWritten.size() + 64);

        std::ostringstream rows;
        bool first = true;
        uint32 written = 0;

        for (auto const& [guid, player] : ObjectAccessor::GetPlayers())
        {
            if (!player || !player->IsInWorld())
                continue;

            ObjectGuid::LowType const low = player->GetGUID().GetCounter();

            LastWritten now;
            now.x = player->GetPositionX();
            now.y = player->GetPositionY();
            now.z = player->GetPositionZ();
            now.areaId = player->GetAreaId();
            now.mapId = player->GetMapId();
            now.zoneId = player->GetZoneId();
            now.level = player->GetLevel();
            now.hpPct = uint32(player->GetHealthPct());
            now.isBot = sPlayerbotsMgr.GetPlayerbotAI(player) != nullptr;
            if (Guild* guild = sGuildMgr->GetGuildById(player->GetGuildId()))
                now.guildName = guild->GetName();

            auto previous = lastWritten.find(low);
            bool changed = fullResync || previous == lastWritten.end();
            if (!changed)
            {
                LastWritten const& was = previous->second;
                changed = std::fabs(was.x - now.x) > MOVED_THRESHOLD
                    || std::fabs(was.y - now.y) > MOVED_THRESHOLD
                    || std::fabs(was.z - now.z) > MOVED_THRESHOLD
                    || was.areaId != now.areaId || was.mapId != now.mapId || was.zoneId != now.zoneId
                    || was.level != now.level || was.hpPct != now.hpPct || was.isBot != now.isBot
                    || was.guildName != now.guildName;
            }

            if (!changed)
            {
                seen.emplace(low, previous->second);
                continue;
            }

            std::string areaName;
            if (AreaTableEntry const* area = sAreaTableStore.LookupEntry(now.areaId))
                areaName = area->area_name[DEFAULT_LOCALE];

            float pctX = now.x;
            float pctY = now.y;
            Map2ZoneCoordinates(pctX, pctY, now.areaId);

            // Areas without proper WorldMapArea bounds make Map2ZoneCoordinates divide by
            // zero (e.g. some instance/phased areas), yielding inf/nan - which would be
            // written into the SQL as a bareword and break the query ("Unknown column 'inf'").
            if (!std::isfinite(pctX))
                pctX = 0.0f;
            if (!std::isfinite(pctY))
                pctY = 0.0f;

            if (!first)
                rows << ",";
            first = false;
            ++written;

            rows << "(" << low
                 << ",'" << EscapedCopy(player->GetName()) << "'"
                 << "," << (now.isBot ? 1 : 0)
                 << "," << now.level
                 << "," << uint32(player->getClass())
                 << "," << uint32(player->getRace())
                 << "," << now.mapId
                 << "," << now.zoneId
                 << "," << now.areaId
                 << ",'" << EscapedCopy(areaName) << "'"
                 << "," << now.x
                 << "," << now.y
                 << "," << now.z
                 << "," << pctX
                 << "," << pctY
                 << "," << now.hpPct
                 << ",'" << EscapedCopy(now.guildName) << "')";

            seen.emplace(low, std::move(now));
        }

        // Whoever was in the table last tick and is not in the world now.
        std::ostringstream gone;
        bool anyGone = false;
        for (auto const& [low, unused] : lastWritten)
        {
            if (seen.count(low))
                continue;
            if (anyGone)
                gone << ",";
            anyGone = true;
            gone << low;
        }

        lastWritten = std::move(seen);

        if (fullResync)
        {
            // Everyone is being rewritten, so anything else in the table is a
            // leftover from a previous run or a crash - clear it in one go.
            if (lastWritten.empty())
            {
                CharacterDatabase.Execute("DELETE FROM live_player_positions");
                return;
            }

            std::ostringstream keep;
            bool firstKeep = true;
            for (auto const& [low, unused] : lastWritten)
            {
                if (!firstKeep)
                    keep << ",";
                firstKeep = false;
                keep << low;
            }
            CharacterDatabase.Execute("DELETE FROM live_player_positions WHERE guid NOT IN ({})", keep.str());
        }
        else if (anyGone)
            CharacterDatabase.Execute("DELETE FROM live_player_positions WHERE guid IN ({})", gone.str());

        if (!written)
            return;

        std::string sql =
            "INSERT INTO live_player_positions "
            "(guid, name, is_bot, level, class, race, map_id, zone_id, area_id, area_name, pos_x, pos_y, pos_z, pct_x, pct_y, hp_pct, guild_name) "
            "VALUES " + rows.str() +
            " ON DUPLICATE KEY UPDATE name = VALUES(name), is_bot = VALUES(is_bot), level = VALUES(level), "
            "class = VALUES(class), race = VALUES(race), map_id = VALUES(map_id), zone_id = VALUES(zone_id), "
            "area_id = VALUES(area_id), area_name = VALUES(area_name), pos_x = VALUES(pos_x), pos_y = VALUES(pos_y), "
            "pos_z = VALUES(pos_z), pct_x = VALUES(pct_x), pct_y = VALUES(pct_y), hp_pct = VALUES(hp_pct), "
            "guild_name = VALUES(guild_name)";

        CharacterDatabase.Execute(sql);
    }
};

void AddSC_live_dashboard()
{
    new live_dashboard_worldscript();
}
