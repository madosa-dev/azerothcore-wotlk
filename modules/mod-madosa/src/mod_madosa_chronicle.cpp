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

// mod-madosa's half of the Chronicle (mod-live-dashboard's `live_chronicle`).
//
// The two modules share a table, not a header. mod-madosa does not include
// anything from mod-live-dashboard and does not require it to be installed:
// this file asks the database once at startup whether the table is there, and
// if it is not, every Record() call is a no-op for the rest of the uptime. That
// keeps a feature module from depending on a dashboard module while still
// letting the dashboard tell the whole story.
//
// The generic events - kills, milestones, boss kills, epic loot - are captured
// on the dashboard's own side. What is written here is the part only this
// module knows about: who took which Worldforged item, who staked what on
// High-Risk, whose bags ended up in a chest.

#include "mod_madosa_chronicle.h"

#include "CharacterDatabase.h"
#include "DBCStores.h"
#include "GameTime.h"
#include "Log.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "World.h"
#include "WorldSession.h"

#include <atomic>

namespace
{
    std::atomic<bool> chronicleAvailable{false};

    bool IsBotSession(Player const* player)
    {
        return player && player->GetSession() && player->GetSession()->IsBot();
    }

    std::string ZoneNameOf(Player const* player)
    {
        AreaTableEntry const* area = sAreaTableStore.LookupEntry(player->GetZoneId());
        if (!area)
            return "";

        char const* name = area->area_name[sWorld->GetDefaultDbcLocale()];
        return name ? name : "";
    }

    // Trimmed to the column first, escaped second - the other way round could
    // cut an escape sequence in half.
    std::string Escape(std::string value)
    {
        if (value.size() > 250)
            value.resize(250);

        CharacterDatabase.EscapeString(value);
        return value;
    }
}

namespace MadosaChronicle
{
    void Record(std::string const& kind, Player const* actor, Player const* target,
                int64 value, std::string const& detail)
    {
        if (!chronicleAvailable.load() || !actor)
            return;

        CharacterDatabase.Execute(
            "INSERT INTO live_chronicle (at, kind, actor, actor_bot, actor_class, actor_level, "
            "target, target_bot, zone, map, value, detail) "
            "VALUES ({}, '{}', '{}', {}, {}, {}, '{}', {}, '{}', {}, {}, '{}')",
            uint32(GameTime::GetGameTime().count()), Escape(kind),
            Escape(actor->GetName()), IsBotSession(actor) ? 1 : 0,
            uint32(actor->getClass()), uint32(actor->GetLevel()),
            target ? Escape(target->GetName()) : "", target && IsBotSession(target) ? 1 : 0,
            Escape(ZoneNameOf(actor)), actor->GetMapId(), value, Escape(detail));
    }
}

class mod_madosa_chronicle_world : public WorldScript
{
public:
    mod_madosa_chronicle_world() : WorldScript("mod_madosa_chronicle_world") { }

    void OnStartup() override
    {
        // Asked once, and cheaply: LIMIT 0 returns no rows either way, so the
        // question is only whether the statement is valid at all.
        QueryResult result = CharacterDatabase.Query(
            "SELECT COUNT(*) FROM information_schema.TABLES "
            "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'live_chronicle'");

        bool const present = result && result->Fetch()[0].Get<uint64>() > 0;
        chronicleAvailable = present;

        LOG_INFO("module", "mod-madosa: chronicle {} (live_chronicle table {})",
            present ? "enabled" : "disabled", present ? "found" : "not installed");
    }
};

void AddSC_madosa_chronicle()
{
    new mod_madosa_chronicle_world();
}
