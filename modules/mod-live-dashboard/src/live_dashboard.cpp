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
#include <vector>

namespace
{
    constexpr uint32 LIVE_DASHBOARD_UPDATE_INTERVAL_MS = 2000;

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
        std::vector<ObjectGuid::LowType> onlineGuids;
        std::ostringstream rows;
        bool first = true;

        for (auto const& [guid, player] : ObjectAccessor::GetPlayers())
        {
            if (!player || !player->IsInWorld())
                continue;

            onlineGuids.push_back(player->GetGUID().GetCounter());

            uint32 areaId = player->GetAreaId();

            std::string areaName;
            if (AreaTableEntry const* area = sAreaTableStore.LookupEntry(areaId))
                areaName = area->area_name[DEFAULT_LOCALE];

            std::string guildName;
            if (Guild* guild = sGuildMgr->GetGuildById(player->GetGuildId()))
                guildName = guild->GetName();

            float pctX = player->GetPositionX();
            float pctY = player->GetPositionY();
            Map2ZoneCoordinates(pctX, pctY, areaId);

            // Areas without proper WorldMapArea bounds make Map2ZoneCoordinates divide by
            // zero (e.g. some instance/phased areas), yielding inf/nan - which would be
            // written into the SQL as a bareword and break the query ("Unknown column 'inf'").
            if (!std::isfinite(pctX))
                pctX = 0.0f;
            if (!std::isfinite(pctY))
                pctY = 0.0f;

            bool isBot = sPlayerbotsMgr.GetPlayerbotAI(player) != nullptr;

            if (!first)
                rows << ",";
            first = false;

            rows << "(" << player->GetGUID().GetCounter()
                 << ",'" << EscapedCopy(player->GetName()) << "'"
                 << "," << (isBot ? 1 : 0)
                 << "," << uint32(player->GetLevel())
                 << "," << uint32(player->getClass())
                 << "," << uint32(player->getRace())
                 << "," << player->GetMapId()
                 << "," << player->GetZoneId()
                 << "," << areaId
                 << ",'" << EscapedCopy(areaName) << "'"
                 << "," << player->GetPositionX()
                 << "," << player->GetPositionY()
                 << "," << player->GetPositionZ()
                 << "," << pctX
                 << "," << pctY
                 << "," << uint32(player->GetHealthPct())
                 << ",'" << EscapedCopy(guildName) << "')";
        }

        if (onlineGuids.empty())
        {
            CharacterDatabase.Execute("DELETE FROM live_player_positions");
            return;
        }

        std::ostringstream guidList;
        for (std::size_t i = 0; i < onlineGuids.size(); ++i)
        {
            if (i)
                guidList << ",";
            guidList << onlineGuids[i];
        }

        CharacterDatabase.Execute("DELETE FROM live_player_positions WHERE guid NOT IN ({})", guidList.str());

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
