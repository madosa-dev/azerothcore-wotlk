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

// The Chronicle: a running account of what happens on this realm, written to
// `live_chronicle` for the dashboard to read.
//
// Why it exists
// -------------
// Three thousand playerbots generate stories without pause and nobody ever sees
// one. The map shows where they are; the chronicle shows what they did. It is
// the difference between a population and a world.
//
// What gets in
// ------------
// On a realm this size the hard part is *not* recording everything. A line that
// scrolls past unread is worse than no line, so each kind has a threshold:
// levels only at the round milestones, loot only at epic and above, deaths only
// for real players (a bot dies constantly and it means nothing). PvP kills and
// raid bosses always count, because they are rare enough to matter.
//
// Bot detection uses the session flag rather than GET_PLAYERBOT_AI: the AI is
// attached after login, so at OnPlayerLogin every bot would otherwise look like
// a person. Same reason mod-madosa's Hardcore PvP uses it.

#include "CharacterDatabase.h"
#include "Chat.h"
#include "DBCStores.h"
#include "GameTime.h"
#include "Log.h"
#include "LootMgr.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldSession.h"

#include <iterator>
#include <mutex>
#include <string>
#include <unordered_map>

namespace
{
    // Keep the table from growing without bound. The dashboard shows the recent
    // past and a few all-time records; a year of bot kills is neither.
    constexpr uint32 CHRONICLE_MAX_ROWS = 20000;
    constexpr uint32 PRUNE_INTERVAL_MS = 300000;   // five minutes

    // A loot window can be opened again and again; the drop only happened once.
    std::unordered_map<ObjectGuid, time_t> seenLoot;
    std::mutex seenLootMutex;

    constexpr uint32 SEEN_LOOT_SECONDS = 900;

    bool AlreadySeen(ObjectGuid guid)
    {
        std::lock_guard<std::mutex> lock(seenLootMutex);
        time_t const now = GameTime::GetGameTime().count();
        auto itr = seenLoot.find(guid);
        if (itr != seenLoot.end() && now < itr->second)
            return true;

        seenLoot[guid] = now + SEEN_LOOT_SECONDS;
        return false;
    }

    void PruneSeenLoot()
    {
        time_t const now = GameTime::GetGameTime().count();
        std::lock_guard<std::mutex> lock(seenLootMutex);
        for (auto itr = seenLoot.begin(); itr != seenLoot.end();)
            itr = now >= itr->second ? seenLoot.erase(itr) : std::next(itr);
    }

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

namespace LiveChronicle
{
    void Record(std::string const& kind, Player const* actor, Player const* target,
                int64 value, std::string const& detail)
    {
        CharacterDatabase.Execute(
            "INSERT INTO live_chronicle (at, kind, actor, actor_bot, actor_class, actor_level, "
            "target, target_bot, zone, map, value, detail) "
            "VALUES ({}, '{}', '{}', {}, {}, {}, '{}', {}, '{}', {}, {}, '{}')",
            uint32(GameTime::GetGameTime().count()), Escape(kind),
            actor ? Escape(actor->GetName()) : "", actor && IsBotSession(actor) ? 1 : 0,
            actor ? uint32(actor->getClass()) : 0, actor ? uint32(actor->GetLevel()) : 0,
            target ? Escape(target->GetName()) : "", target && IsBotSession(target) ? 1 : 0,
            actor ? Escape(ZoneNameOf(actor)) : "", actor ? actor->GetMapId() : 0,
            value, Escape(detail));
    }
}

class live_chronicle_player : public PlayerScript
{
public:
    live_chronicle_player() : PlayerScript("live_chronicle_player",
        {
            PLAYERHOOK_ON_PVP_KILL,
            PLAYERHOOK_ON_LEVEL_CHANGED,
            PLAYERHOOK_ON_LOGIN,
            PLAYERHOOK_ON_BEFORE_SEND_LOOT,
            PLAYERHOOK_ON_PLAYER_JUST_DIED,
        }) { }

    void OnPlayerPVPKill(Player* killer, Player* killed) override
    {
        if (killer == killed)
            return;

        LiveChronicle::Record("pvp_kill", killer, killed, 0, "");
    }

    // Every level would be thousands of lines a day and none of them worth
    // reading. The round ones are the ones people mention.
    void OnPlayerLevelChanged(Player* player, uint8 oldLevel) override
    {
        uint8 const level = player->GetLevel();
        if (level <= oldLevel)
            return;

        bool const milestone = (level % 10 == 0) || level == DEFAULT_MAX_LEVEL;
        if (!milestone)
            return;

        LiveChronicle::Record(level == DEFAULT_MAX_LEVEL ? "max_level" : "milestone",
            player, nullptr, level, "");
    }

    // Only people. A bot logging in is not news; the one human on the realm is.
    void OnPlayerLogin(Player* player) override
    {
        if (!IsBotSession(player))
            LiveChronicle::Record("login", player, nullptr, 0, "");
    }

    void OnPlayerJustDied(Player* player) override
    {
        if (!IsBotSession(player))
            LiveChronicle::Record("death", player, nullptr, 0, "");
    }

    // Read from the loot, never from an Item pointer.
    //
    // This used to hang off OnPlayerLootItem and call item->GetTemplate(), and
    // it crashed the server: the hook hands out a raw Item* that can already be
    // freed by the time a script sees it, and running on every loot of every
    // one of three thousand bots is enough attempts to find that window. The
    // stack was Object::GetUInt32Value on a dangling m_uint32Values, reached
    // from PlayerbotHolder::HandleBotPackets.
    //
    // Loot items carry a plain item id instead, which cannot dangle. What gets
    // recorded shifts slightly - "an epic dropped for X" rather than "X picked
    // it up" - and for a chronicle that reads better anyway.
    void OnPlayerBeforeSendLoot(Player* player, ObjectGuid lootGuid, Loot* loot) override
    {
        if (!loot || loot->items.empty())
            return;

        // Look before locking. Every loot window every bot opens comes through
        // here, and AlreadySeen() takes a global mutex - doing that first meant
        // three thousand bots queueing on one lock to establish, almost always,
        // that there was nothing to write down. The scan is a handful of hash
        // lookups and no lock at all, and an epic is rare, so the mutex is now
        // reached about as often as it has something to do.
        bool worthRecording = false;
        for (LootItem const& item : loot->items)
        {
            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item.itemid);
            if (proto && proto->Quality >= ITEM_QUALITY_EPIC)
            {
                worthRecording = true;
                break;
            }
        }

        if (!worthRecording || AlreadySeen(lootGuid))
            return;

        for (LootItem const& item : loot->items)
        {
            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item.itemid);
            if (!proto || proto->Quality < ITEM_QUALITY_EPIC)
                continue;

            LiveChronicle::Record("loot", player, nullptr, int32(item.count), proto->Name1);
        }
    }
};

// Raid and dungeon bosses, from the encounter state the instance itself
// reports - which is more reliable than guessing from a creature entry list.
class live_chronicle_global : public GlobalScript
{
public:
    live_chronicle_global() : GlobalScript("live_chronicle_global",
        { GLOBALHOOK_ON_AFTER_UPDATE_ENCOUNTER_STATE }) { }

    void OnAfterUpdateEncounterState(Map* map, EncounterCreditType type, uint32 /*creditEntry*/,
        Unit* source, Difficulty /*difficulty*/, std::list<DungeonEncounter const*> const* encounters,
        uint32 /*dungeonCompleted*/, bool updated) override
    {
        if (!updated || type != ENCOUNTER_CREDIT_KILL_CREATURE || !map || !encounters || encounters->empty())
            return;

        // Whoever is standing in the instance gets the credit line; the
        // encounter itself carries the name.
        Player* witness = nullptr;
        if (source)
            if (Unit* owner = source->GetCharmerOrOwnerPlayerOrPlayerItself())
                witness = owner->ToPlayer();

        if (!witness)
        {
            Map::PlayerList const& players = map->GetPlayers();
            if (!players.IsEmpty())
                witness = players.begin()->GetSource();
        }

        if (!witness)
            return;

        DungeonEncounter const* encounter = encounters->front();
        LiveChronicle::Record("boss", witness, nullptr, 0,
            encounter && encounter->dbcEntry ? encounter->dbcEntry->encounterName[0] : "");
    }
};

class live_chronicle_world : public WorldScript
{
    uint32 _timer = 0;

public:
    live_chronicle_world() : WorldScript("live_chronicle_world") { }

    void OnUpdate(uint32 diff) override
    {
        _timer += diff;
        if (_timer < PRUNE_INTERVAL_MS)
            return;

        _timer = 0;

        PruneSeenLoot();

        // Trim by id rather than by age: what matters is that the table stays a
        // readable length, not how long ago the oldest line was.
        CharacterDatabase.Execute(
            "DELETE FROM live_chronicle WHERE id <= "
            "(SELECT * FROM (SELECT MAX(id) - {} FROM live_chronicle) AS keep)",
            CHRONICLE_MAX_ROWS);
    }
};

void AddSC_live_chronicle()
{
    new live_chronicle_player();
    new live_chronicle_global();
    new live_chronicle_world();
}
