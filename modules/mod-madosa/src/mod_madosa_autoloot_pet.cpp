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

// While the "Lootbot" companion (see auto_loot_pet.sql) is summoned, the
// owner's kills auto-loot everything they'd be allowed to take themselves -
// items still under a pending need/greed roll, or restricted by master loot
// to someone else, are deliberately left alone for the player to handle the
// normal way. Also: if the player's most recent kill is still sitting there
// unlooted (e.g. they killed something before summoning Lootbot), summoning
// it immediately loots that corpse too, instead of waiting for the next kill.
//
// There's no single "give the player everything" helper in the core, and
// group loot permission (round robin turn, master loot, need/greed rolls) is
// resolved as a side effect deep inside Player::SendLoot()/StoreLootItem(),
// not exposed as a standalone query - so this reuses those exact functions
// (plus the same opcode handlers the client's own loot actions call) rather
// than re-deriving who's allowed to loot what. StoreLootItem() reacts to a
// small number of "you can't have this" cases by releasing the whole loot
// session (SendLootRelease) as a side effect; where that's cheap to predict
// (is_blocked, a roll already won by someone else) it's checked up front via
// the side-effect-free LootItemInSlot() peek, and for the rest (e.g. a
// master-loot restriction) the loop just notices the session got released
// and reopens it via SendLoot() before continuing to the next slot.

#include "mod_madosa_settings.h"

#include "Creature.h"
#include "Loot/LootMgr.h"
#include "ObjectAccessor.h"
#include "ObjectDefines.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "TemporarySummon.h"
#include "WorldSession.h"

#include <unordered_map>

namespace
{
    constexpr uint32 LOOT_RAT_ENTRY = 16549; // "Lootbot" (renamed from "Whiskers the Rat") - confirmed in-game

    // Most recent kill per player that still had loot on it, so summoning
    // Lootbot right after a kill can catch that corpse too. Only the latest
    // one is tracked - deliberately not a full nearby-corpse sweep.
    std::unordered_map<ObjectGuid, ObjectGuid> lastLootableKill;

    bool HasAutoLootCompanion(Player* player)
    {
        ObjectGuid critterGuid = player->GetCritterGUID();
        if (!critterGuid)
            return false;

        Creature* critter = ObjectAccessor::GetCreature(*player, critterGuid);
        return critter && critter->GetEntry() == LOOT_RAT_ENTRY;
    }

    void AutoLoot(Player* player, Creature* target)
    {
        ObjectGuid guid = target->GetGUID();
        Loot* loot = &target->loot;

        player->SendLoot(guid, LOOT_CORPSE);
        if (player->GetLootGUID() != guid)
            return; // no permission to loot this corpse at all (too far, not the recipient, ...)

        uint32 maxSlot = loot->GetMaxSlotInLootFor(player);
        for (uint32 slot = 0; slot < maxSlot; ++slot)
        {
            if (player->GetLootGUID() != guid)
            {
                // A previous slot's StoreLootItem() released the session (e.g. a
                // master-loot restriction) - reopen it for the remaining slots.
                player->SendLoot(guid, LOOT_CORPSE);
                if (player->GetLootGUID() != guid)
                    break;
            }

            QuestItem* qitem = nullptr;
            LootItem* item = loot->LootItemInSlot(slot, player, &qitem, nullptr, nullptr);
            if (!item)
                continue;

            // Leave pending need/greed rolls, and rolls already won by someone
            // else, for the normal loot window to handle.
            if (!qitem && item->is_blocked)
                continue;
            if (item->rollWinnerGUID && item->rollWinnerGUID != player->GetGUID())
                continue;

            WorldPacket data;
            data << uint8(slot);
            player->GetSession()->HandleAutostoreLootItemOpcode(data);
        }

        if (player->GetLootGUID() == guid && loot->gold > 0)
        {
            WorldPacket data;
            player->GetSession()->HandleLootMoneyOpcode(data);
        }

        if (player->GetLootGUID() == guid)
            player->GetSession()->DoLootRelease(guid);
    }
}

class mod_madosa_autoloot_pet : public PlayerScript
{
public:
    mod_madosa_autoloot_pet() : PlayerScript("mod_madosa_autoloot_pet") { }

    void OnPlayerCreatureKill(Player* killer, Creature* killed) override
    {
        if (!MadosaSettings::GetAutoLootPetEnable())
            return;

        if (!killed->HasDynamicFlag(UNIT_DYNFLAG_LOOTABLE))
            return;

        lastLootableKill[killer->GetGUID()] = killed->GetGUID();

        if (!HasAutoLootCompanion(killer))
            return;

        AutoLoot(killer, killed);
    }

    void OnPlayerBeforeTempSummonInitStats(Player* player, TempSummon* tempSummon, uint32& /*duration*/) override
    {
        if (tempSummon->GetEntry() != LOOT_RAT_ENTRY)
            return;

        if (!MadosaSettings::GetAutoLootPetEnable())
            return;

        auto itr = lastLootableKill.find(player->GetGUID());
        if (itr == lastLootableKill.end())
            return;

        Creature* target = ObjectAccessor::GetCreature(*player, itr->second);
        if (target && target->IsInWorld() && target->HasDynamicFlag(UNIT_DYNFLAG_LOOTABLE) && player->IsWithinDistInMap(target, INTERACTION_DISTANCE))
            AutoLoot(player, target);
    }
};

void AddSC_madosa_autoloot_pet()
{
    new mod_madosa_autoloot_pet();
}
