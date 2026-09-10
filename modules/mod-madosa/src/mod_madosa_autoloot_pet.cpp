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
// Who the pet loots for
// ---------------------
// The core credits a kill to the Unit that landed the killing blow, and that
// is a Player only for a direct hit. A totem's Searing Bolt, Fire Nova
// rippling out of a totem, a pet's bite, a guardian's swing - all of those
// reach Unit::Kill() with the totem/pet as the killer, and
// PlayerScript::OnPlayerCreatureKill() never fires for them, because Kill()
// only dispatches it for killer->ToPlayer(). An aura can even arrive with no
// killer at all once its caster is no longer resolvable. So this listens on
// UnitScript::OnUnitDeath() instead - the last thing Unit::Kill() does, after
// the loot is filled and UNIT_DYNFLAG_LOOTABLE is set - and asks who holds
// loot rights rather than who struck last: the player behind the killer (the
// owner of a pet/totem, or the player themself), then the corpse's loot
// recipient, then the recipient group's members in loot range. The first of
// those with the pet out loots; what they may actually take is still decided
// by SendLoot()/StoreLootItem() exactly as before.
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
//
// Reaching a corpse that is not underfoot
// ---------------------------------------
// Looting is gated on INTERACTION_DISTANCE (5.5 yards) in four separate places
// - Player::SendLoot(), both loot opcode handlers, and DoLootRelease() - which
// is right for a player reaching into a corpse and wrong for a bot doing it on
// their behalf. A kill made at range leaves its corpse where it fell, so before
// this the pet only worked for things killed in melee: a hunter or a caster
// watched it do nothing at all, which is not a subtle failure but it does look
// like one, because the same character's melee kills loot fine.
//
// Rather than reimplement those checks' surroundings, the core asks
// PlayerScript::OnPlayerCanLootOutOfRange() when a corpse is out of reach, and
// this script answers true for exactly the corpse it is looting, for exactly
// as long as it is looting it. Everything else - permission, group rolls,
// master loot, the gold split, achievements - runs the same code it always
// did. The window is a thread_local rather than a plain global because maps
// update in parallel: two players on two maps can be inside AutoLoot() at the
// same moment, and each thread must only ever see its own.
//
// The release path is the one that is easy to miss and the worst to get wrong.
// DoLootRelease() is where an emptied corpse loses UNIT_DYNFLAG_LOOTABLE and
// gets AllLootRemovedFromCorpse() and loot->clear(); its distance check returns
// before all of that. Lift the first three gates and not this one and the pet
// works perfectly while leaving a trail of empty corpses that still advertise
// loot - a worse bug than the one being fixed.
//
// No distance limit is imposed on a kill: you killed it, the loot recipient
// rules already say it is yours, and a hunter's 41 yards is as legitimate as a
// warrior's 3. The catch-up loot on summoning keeps a bound, because there the
// kill could have been minutes and a zone ago.

#include "mod_madosa_settings.h"

#include "Creature.h"
#include "Group.h"
#include "Loot/LootMgr.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "TemporarySummon.h"
#include "WorldSession.h"

#include <algorithm>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace
{
    constexpr uint32 LOOT_RAT_ENTRY = 16549; // "Lootbot" (renamed from "Whiskers the Rat") - confirmed in-game
    constexpr uint32 OMNIBOT_ENTRY  = 40703; // "Omnibot" (renamed from "Lil' XT") - see service_pets.sql

    // How far the corpse of the last kill may be when the pet is summoned and
    // catches up on it. Comfortably past any weapon range, so summoning right
    // after a ranged kill works, and still close enough that it is plainly the
    // thing you just killed rather than something you left behind a hill ago.
    constexpr float SUMMON_CATCHUP_RANGE = 60.0f;

    // Omnibot exists because only one companion can be summoned at a time, so it
    // has to cover auto-looting too - otherwise picking it would silently cost the
    // player Lootbot's whole reason for existing.
    constexpr bool IsAutoLootCompanion(uint32 entry)
    {
        return entry == LOOT_RAT_ENTRY || entry == OMNIBOT_ENTRY;
    }

    // Most recent kill per player that still had loot on it, so summoning
    // Lootbot right after a kill can catch that corpse too. Only the latest
    // one is tracked - deliberately not a full nearby-corpse sweep. Written
    // from map-update threads, which run in parallel, hence the lock.
    std::mutex lastLootableKillLock;
    std::unordered_map<ObjectGuid, ObjectGuid> lastLootableKill;

    void RememberKill(Player* player, Creature* corpse)
    {
        std::lock_guard<std::mutex> lock(lastLootableKillLock);
        lastLootableKill[player->GetGUID()] = corpse->GetGUID();
    }

    ObjectGuid RememberedKill(Player* player)
    {
        std::lock_guard<std::mutex> lock(lastLootableKillLock);
        auto itr = lastLootableKill.find(player->GetGUID());
        return itr != lastLootableKill.end() ? itr->second : ObjectGuid::Empty;
    }

    // The one corpse this thread is currently auto-looting, and for whom. Read
    // by the OnPlayerCanLootOutOfRange hook and set only by the guard below, so
    // the distance gate is lifted for this loot and nothing else - a client
    // packet arriving for any other corpse still finds it shut.
    thread_local ObjectGuid t_reachingFor;
    thread_local ObjectGuid t_reachingPlayer;

    class ReachGuard
    {
    public:
        ReachGuard(Player* player, ObjectGuid loot)
        {
            t_reachingPlayer = player->GetGUID();
            t_reachingFor = loot;
        }

        ~ReachGuard()
        {
            t_reachingPlayer.Clear();
            t_reachingFor.Clear();
        }

        ReachGuard(ReachGuard const&) = delete;
        ReachGuard& operator=(ReachGuard const&) = delete;
    };

    bool HasAutoLootCompanion(Player* player)
    {
        ObjectGuid critterGuid = player->GetCritterGUID();
        if (!critterGuid)
            return false;

        Creature* critter = ObjectAccessor::GetCreature(*player, critterGuid);
        return critter && IsAutoLootCompanion(critter->GetEntry());
    }

    // Everyone the core credits with this kill, in the order they should get
    // first go at the corpse. See "Who the pet loots for" at the top.
    std::vector<Player*> LootCandidates(Creature* corpse, Unit* killer)
    {
        std::vector<Player*> candidates;
        auto add = [&candidates](Player* player)
        {
            if (player && std::find(candidates.begin(), candidates.end(), player) == candidates.end())
                candidates.push_back(player);
        };

        if (killer)
            add(killer->GetCharmerOrOwnerPlayerOrPlayerItself());

        add(corpse->GetLootRecipient());

        if (Group* group = corpse->GetLootRecipientGroup())
            for (GroupReference* itr = group->GetFirstMember(); itr; itr = itr->next())
                if (Player* member = itr->GetSource())
                    if (member->IsAtLootRewardDistance(corpse))
                        add(member);

        return candidates;
    }

    void AutoLoot(Player* player, Creature* target)
    {
        ObjectGuid guid = target->GetGUID();
        Loot* loot = &target->loot;

        ReachGuard reach(player, guid);

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

    // Lift the core's INTERACTION_DISTANCE gate for the corpse AutoLoot() is
    // working on right now, and for nothing else. See the note at the top.
    [[nodiscard]] bool OnPlayerCanLootOutOfRange(Player* player, ObjectGuid lootGuid) override
    {
        return t_reachingFor && lootGuid == t_reachingFor && player->GetGUID() == t_reachingPlayer;
    }

    void OnPlayerBeforeTempSummonInitStats(Player* player, TempSummon* tempSummon, uint32& /*duration*/) override
    {
        if (!IsAutoLootCompanion(tempSummon->GetEntry()))
            return;

        if (!MadosaSettings::GetAutoLootPetEnable())
            return;

        ObjectGuid corpse = RememberedKill(player);
        if (!corpse)
            return;

        Creature* target = ObjectAccessor::GetCreature(*player, corpse);
        if (target && target->IsInWorld() && target->HasDynamicFlag(UNIT_DYNFLAG_LOOTABLE)
            && player->IsWithinDistInMap(target, SUMMON_CATCHUP_RANGE))
            AutoLoot(player, target);
    }
};

// Fires for every death, not only the ones a player landed - see "Who the pet
// loots for" at the top.
class mod_madosa_autoloot_pet_death : public UnitScript
{
public:
    mod_madosa_autoloot_pet_death() : UnitScript("mod_madosa_autoloot_pet_death", true, { UNITHOOK_ON_UNIT_DEATH }) { }

    void OnUnitDeath(Unit* unit, Unit* killer) override
    {
        if (!MadosaSettings::GetAutoLootPetEnable())
            return;

        Creature* killed = unit->ToCreature();
        if (!killed || !killed->HasDynamicFlag(UNIT_DYNFLAG_LOOTABLE))
            return;

        std::vector<Player*> candidates = LootCandidates(killed, killer);
        for (Player* player : candidates)
            RememberKill(player, killed);

        for (Player* player : candidates)
            if (HasAutoLootCompanion(player))
            {
                AutoLoot(player, killed);
                return;
            }
    }
};

void AddSC_madosa_autoloot_pet()
{
    new mod_madosa_autoloot_pet();
    new mod_madosa_autoloot_pet_death();
}
