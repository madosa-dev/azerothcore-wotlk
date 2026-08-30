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

// Questbot (see instance_quest_pet.sql): while inside a dungeon or raid,
// offers every quest that instance has, no matter the usual level/chain-order
// gating; from anywhere, takes back any instance quest currently in the
// player's log that's ready (or on the way) to turn in.
//
// "Which quests belong to which instance" comes primarily from the quest's
// own ZoneOrSort (quest_template.QuestSortID): for a dungeon quest that's
// the instance's zone/area id, which is exactly how the client groups them
// under the dungeon's name in the quest log. Mapping area id -> map id via
// sAreaTableStore then gives the whole set per instance. This is what
// actually matters - most classic dungeon quests are handed out AND turned
// in by hub NPCs outside the instance (all five Deadmines quests are), so
// looking at where the quest giver/ender stands finds almost none of them.
//
// Quest-giver/ender spawn location is still scanned as a supplement, for
// the handful of quests physically anchored inside an instance but sorted
// elsewhere (e.g. a class or event quest that happens to be turned in at an
// NPC standing inside). Both sources feed the same per-map index.
//
// The result is also written into creature_queststarter/creature_questender
// for Questbot's own creature entry, since Creature::hasQuest()/
// hasInvolvedQuest() (checked by the accept/turn-in opcode handlers) only
// look at that per-entry table - what's actually *offered* in the gossip
// window, and what icon is shown over Questbot's head, are filtered
// separately, by map, in OnGossipHello and GetDialogStatus below.
//
// The accept list intentionally skips Player::SatisfyQuestLevel() and the
// prerequisite-chain checks (SatisfyQuestPreviousQuest/NextChain/PrevChain/
// Breadcrumb) - that's the entire point, "every quest this instance has",
// not just the one next in line - but keeps every other real requirement
// (class, race, reputation, exclusivity, disables, conditions). The actual
// accept opcode still runs the full Player::CanTakeQuest() as normal, so a
// quest that genuinely can't be taken yet (e.g. a hard level requirement)
// still gets the standard rejection message instead of silently breaking
// something.

#include "Creature.h"
#include "CreatureScript.h"
#include "DBCStores.h"
#include "DisableMgr.h"
#include "GossipDef.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "PlayerScript.h"
#include "QuestDef.h"
#include "ScriptMgr.h"
#include "ScriptedGossip.h"
#include "WorldDatabase.h"
#include "mod_madosa_settings.h"

#include <algorithm>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    // npc_text/gossip_menu row from instance_quest_pet.sql, sent by hand when
    // there is nothing to offer - see OnGossipHello for why it is not wired
    // through creature_template.gossip_menu_id.
    constexpr uint32 QUESTBOT_FALLBACK_TEXT_ID = 900350;

    constexpr uint32 QUESTBOT_ENTRY = 24388; // "Questbot" (renamed from "Toothy")

    std::unordered_map<uint32, std::vector<uint32>> instanceQuestsByMap;
    std::unordered_set<uint32> allInstanceQuestIds;

    bool InstanceQuestPetEnabled()
    {
        return MadosaSettings::GetInstanceQuestPetEnable();
    }

    void IndexIfInstanceQuest(uint32 mapId, uint32 questId)
    {
        MapEntry const* mapEntry = sMapStore.LookupEntry(mapId);
        if (!mapEntry || !mapEntry->IsDungeon())
            return;

        if (!sObjectMgr->GetQuestTemplate(questId))
            return;

        if (allInstanceQuestIds.insert(questId).second)
            instanceQuestsByMap[mapId].push_back(questId);
    }

    void LoadInstanceQuests()
    {
        instanceQuestsByMap.clear();
        allInstanceQuestIds.clear();

        // Primary source: the quest's own sort id. For a dungeon quest that's
        // the instance's zone/area id (e.g. 1581 = The Deadmines), which is
        // how the client groups them in the quest log - independent of where
        // the quest giver happens to stand.
        std::unordered_map<uint32, uint32> mapIdByAreaId;
        for (uint32 i = 0; i < sAreaTableStore.GetNumRows(); ++i)
            if (AreaTableEntry const* area = sAreaTableStore.LookupEntry(i))
                mapIdByAreaId[area->ID] = area->mapid;

        for (auto const& [questId, quest] : sObjectMgr->GetQuestTemplates())
        {
            int32 zoneOrSort = quest->GetZoneOrSort();
            if (zoneOrSort <= 0) // negative values are QuestSort.dbc categories, not zones
                continue;

            auto areaItr = mapIdByAreaId.find(uint32(zoneOrSort));
            if (areaItr != mapIdByAreaId.end())
                IndexIfInstanceQuest(areaItr->second, questId);
        }

        // Supplement: quests physically anchored inside an instance but
        // sorted elsewhere - picked up from where their giver/ender spawns.
        char const* queries[] = {
            "SELECT DISTINCT c.map, qs.quest FROM creature_queststarter qs JOIN creature c ON c.id = qs.id",
            "SELECT DISTINCT c.map, qe.quest FROM creature_questender qe JOIN creature c ON c.id = qe.id",
            "SELECT DISTINCT g.map, qs.quest FROM gameobject_queststarter qs JOIN gameobject g ON g.id = qs.id",
            "SELECT DISTINCT g.map, qe.quest FROM gameobject_questender qe JOIN gameobject g ON g.id = qe.id",
        };

        for (char const* query : queries)
        {
            if (QueryResult result = WorldDatabase.Query(query))
            {
                do
                {
                    Field* fields = result->Fetch();
                    IndexIfInstanceQuest(fields[0].Get<uint16>(), fields[1].Get<uint32>());
                } while (result->NextRow());
            }
        }

        // Makes Creature::hasQuest()/hasInvolvedQuest() accept every one of
        // these for Questbot, which is what the accept/turn-in opcodes check
        // before letting a quest be picked up or handed in.
        //
        // DirectExecute, not Execute: the async queue would still be draining
        // when the reload below runs. And the reload is required - ObjectMgr
        // populates its in-memory relation maps (the ones hasQuest() actually
        // reads) during LoadQuestStartersAndEnders(), long before OnStartup,
        // so writing the rows alone would only take effect one restart later.
        WorldDatabase.DirectExecute("DELETE FROM creature_queststarter WHERE id = {}", QUESTBOT_ENTRY);
        WorldDatabase.DirectExecute("DELETE FROM creature_questender WHERE id = {}", QUESTBOT_ENTRY);

        if (!allInstanceQuestIds.empty())
        {
            std::ostringstream values;
            bool first = true;
            for (uint32 questId : allInstanceQuestIds)
            {
                if (!first)
                    values << ',';
                values << '(' << QUESTBOT_ENTRY << ',' << questId << ')';
                first = false;
            }

            std::string const rows = values.str();
            WorldDatabase.DirectExecute("INSERT INTO creature_queststarter (id, quest) VALUES {}", rows);
            WorldDatabase.DirectExecute("INSERT INTO creature_questender (id, quest) VALUES {}", rows);
        }

        sObjectMgr->LoadCreatureQuestStarters();
        sObjectMgr->LoadCreatureQuestEnders();

        LOG_INFO("module", "mod-madosa: Questbot indexed {} instance quest(s) across {} map(s)",
            allInstanceQuestIds.size(), instanceQuestsByMap.size());
    }

    bool HasQuestbotSummoned(Player* player)
    {
        ObjectGuid critterGuid = player->GetCritterGUID();
        if (!critterGuid)
            return false;

        Creature* critter = ObjectAccessor::GetCreature(*player, critterGuid);
        return critter && critter->GetEntry() == QUESTBOT_ENTRY;
    }

    // Is this a quest Questbot is currently allowed to hand out to this
    // player - i.e. they have it summoned and are standing in the instance
    // the quest belongs to? Deliberately the exact condition OnGossipHello
    // uses to build the accept list, so what's shown and what the accept
    // opcode allows can't drift apart.
    bool IsOfferableHere(Player* player, uint32 questId)
    {
        if (!InstanceQuestPetEnabled())
            return false;

        if (!player->GetMap() || !player->GetMap()->IsDungeon())
            return false;

        auto itr = instanceQuestsByMap.find(player->GetMapId());
        if (itr == instanceQuestsByMap.end())
            return false;

        if (std::find(itr->second.begin(), itr->second.end(), questId) == itr->second.end())
            return false;

        return HasQuestbotSummoned(player);
    }

    // Same as Player::CanTakeQuest(), minus the level and prerequisite-chain
    // checks - "every quest this instance has", not just the next in line.
    bool CanOfferInstanceQuest(Player* player, Quest const* quest)
    {
        return !sDisableMgr->IsDisabledFor(DISABLE_TYPE_QUEST, quest->GetQuestId(), player)
            && player->SatisfyQuestStatus(quest, false)
            && player->SatisfyQuestExclusiveGroup(quest, false)
            && player->SatisfyQuestClass(quest, false)
            && player->SatisfyQuestRace(quest, false)
            && player->SatisfyQuestSkill(quest, false)
            && player->SatisfyQuestReputation(quest, false)
            && player->SatisfyQuestTimed(quest, false)
            && player->SatisfyQuestDay(quest, false)
            && player->SatisfyQuestWeek(quest, false)
            && player->SatisfyQuestMonth(quest, false)
            && player->SatisfyQuestSeasonal(quest, false)
            && player->SatisfyQuestConditions(quest, false);
    }
}

class npc_madosa_questbot : public CreatureScript
{
public:
    npc_madosa_questbot() : CreatureScript("npc_madosa_questbot") { }

    // Controls the "!"/"?" icon shown over Questbot's head. Without this,
    // the core would compute it from the full static creature_queststarter/
    // creature_questender relation (every instance quest in the game), so
    // the icon would show even outside the matching instance - the whole
    // point of overriding this is to make the icon respect the same
    // location rule as the gossip window itself.
    uint32 GetDialogStatus(Player* player, Creature* /*creature*/) override
    {
        if (!InstanceQuestPetEnabled())
            return DIALOG_STATUS_SCRIPTED_NO_STATUS;

        for (uint32 questId : allInstanceQuestIds)
            if (player->GetQuestStatus(questId) == QUEST_STATUS_COMPLETE)
                return DIALOG_STATUS_REWARD;

        if (player->GetMap() && player->GetMap()->IsDungeon())
        {
            auto itr = instanceQuestsByMap.find(player->GetMapId());
            if (itr != instanceQuestsByMap.end())
            {
                for (uint32 questId : itr->second)
                {
                    if (player->GetQuestStatus(questId) != QUEST_STATUS_NONE)
                        continue;

                    Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
                    if (quest && CanOfferInstanceQuest(player, quest))
                        return DIALOG_STATUS_AVAILABLE;
                }
            }
        }

        for (uint32 questId : allInstanceQuestIds)
            if (player->GetQuestStatus(questId) == QUEST_STATUS_INCOMPLETE)
                return DIALOG_STATUS_INCOMPLETE;

        return DIALOG_STATUS_NONE;
    }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        if (!InstanceQuestPetEnabled())
            return false;

        player->PlayerTalkClass->ClearMenus();
        QuestMenu& questMenu = player->PlayerTalkClass->GetQuestMenu();

        // QuestMenu::AddMenuItem() asserts on more than GOSSIP_MAX_MENU_ITEMS
        // entries, so every add below goes through this cap - a player
        // carrying a lot of instance quests must not crash the server.
        auto addQuest = [&questMenu](uint32 questId, uint8 icon)
        {
            if (questMenu.GetMenuItemCount() >= GOSSIP_MAX_MENU_ITEMS)
                return false;

            questMenu.AddMenuItem(questId, icon);
            return true;
        };

        // Turn-in section: any instance quest currently in the log, from anywhere.
        for (uint32 questId : allInstanceQuestIds)
        {
            QuestStatus status = player->GetQuestStatus(questId);
            if (status == QUEST_STATUS_COMPLETE || status == QUEST_STATUS_INCOMPLETE)
                if (!addQuest(questId, 4))
                    break;
        }

        // Accept section: only while inside the matching instance.
        if (player->GetMap() && player->GetMap()->IsDungeon())
        {
            auto itr = instanceQuestsByMap.find(player->GetMapId());
            if (itr != instanceQuestsByMap.end())
            {
                for (uint32 questId : itr->second)
                {
                    if (player->GetQuestStatus(questId) != QUEST_STATUS_NONE)
                        continue;

                    Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
                    if (!quest || !CanOfferInstanceQuest(player, quest))
                        continue;

                    if (!addQuest(questId, quest->IsAutoComplete() ? 4 : 2))
                        break;
                }
            }
        }

        // Two deliberate paths, both of which Player::SendPreparedGossip() would
        // pick correctly on its own IF the creature carried a gossip_menu_id:
        // with no UNIT_NPC_FLAG_GOSSIP and a non-empty quest menu it jumps
        // straight to the quest list (what we want - no pointless "hello" window
        // in front of the quests), and with an empty one it falls through to the
        // gossip window and shows the creature's menu text.
        //
        // Carrying that menu id on the creature is what made ObjectMgr log
        // "has assigned gossip menu 900350, but npcflag does not include
        // UNIT_NPC_FLAG_GOSSIP" on every startup: the core's data validation has
        // no way to know a script drives both paths. Sending the fallback text
        // explicitly here keeps both behaviors and lets creature_template drop
        // the gossip_menu_id, so the warning goes away for the right reason
        // rather than by adding a flag that would break the quest-list jump.
        if (questMenu.Empty())
        {
            SendGossipMenuFor(player, QUESTBOT_FALLBACK_TEXT_ID, creature);
            return true;
        }

        player->SendPreparedGossip(creature);
        return true;
    }
};

// Questbot's whole point is handing out an instance's quests regardless of
// where the player is in the chain, so the accept has to waive the same
// level/prerequisite checks the offer list already skips - otherwise a quest
// like "Red Silk Bandanas" (needs the Westfall chain starter) shows up but
// silently refuses to be picked up.
class mod_madosa_questbot_prerequisites : public PlayerScript
{
public:
    mod_madosa_questbot_prerequisites() : PlayerScript("mod_madosa_questbot_prerequisites") { }

    bool OnPlayerCanBypassQuestPrerequisites(Player* player, Quest const* quest) override
    {
        return IsOfferableHere(player, quest->GetQuestId());
    }
};

class mod_madosa_instance_quest_pet_world : public WorldScript
{
public:
    mod_madosa_instance_quest_pet_world() : WorldScript("mod_madosa_instance_quest_pet_world") { }

    void OnStartup() override
    {
        LoadInstanceQuests();
    }
};

void AddSC_madosa_instance_quest_pet()
{
    new npc_madosa_questbot();
    new mod_madosa_questbot_prerequisites();
    new mod_madosa_instance_quest_pet_world();
}
