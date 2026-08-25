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

// Scroll of Professions: consuming it grants one more primary profession slot.
//
// WotLK does not store how many primary professions a character may still take.
// Player::LoadFromDB calls InitPrimaryProfessions() on *every* login, which sets
// PLAYER_CHARACTER_POINTS2 to CONFIG_MAX_PRIMARY_TRADE_SKILL, and every primary
// profession spell loaded afterwards decrements it in Player::addSpell. The
// counter is therefore derived, never persisted - simply adding one on use would
// be gone at the next login.
//
// So the number of scrolls a character has consumed lives in
// mod_madosa_profession_slots and is added back in OnPlayerLogin, which runs
// after LoadFromDB has finished counting.
//
// One rough edge worth knowing: Player::removeSpell refunds a point only while
// the total stays <= CONFIG_MAX_PRIMARY_TRADE_SKILL, so a character above that
// who unlearns a profession does not get the slot back right away. Relogging
// recomputes it correctly, because this script re-applies the extras from
// scratch. Nothing is lost, it just needs a relog.

#include "Chat.h"
#include "Item.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "PlayerScript.h"
#include "ScriptMgr.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "World.h"
#include "CharacterDatabase.h"
#include "mod_madosa_settings.h"

namespace
{
    uint32 GetExtraSlots(ObjectGuid::LowType guid)
    {
        QueryResult result = CharacterDatabase.Query(
            "SELECT extra_slots FROM mod_madosa_profession_slots WHERE guid = {}", guid);
        return result ? (*result)[0].Get<uint32>() : 0;
    }

    void SetExtraSlots(ObjectGuid::LowType guid, uint32 slots)
    {
        CharacterDatabase.Execute(
            "REPLACE INTO mod_madosa_profession_slots (guid, extra_slots) VALUES ({}, {})",
            guid, slots);
    }

    // How many primary professions the character already knows. Counting the
    // known spells is more reliable than trusting the live counter, which the
    // trainer path and removeSpell both write to.
    uint32 CountKnownPrimaryProfessions(Player* player)
    {
        uint32 known = 0;
        for (auto const& itr : player->GetSpellMap())
        {
            if (itr.second->State == PLAYERSPELL_REMOVED)
                continue;

            SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(itr.first);
            if (spellInfo && spellInfo->IsPrimaryProfessionFirstRank())
                ++known;
        }
        return known;
    }

    uint32 BaseSlots()
    {
        return sWorld->getIntConfig(CONFIG_MAX_PRIMARY_TRADE_SKILL);
    }

    // Recomputes the free-slot counter as (base + purchased) - already known,
    // instead of nudging whatever value happens to be in the field.
    void ApplyExtraSlots(Player* player)
    {
        uint32 const extra = GetExtraSlots(player->GetGUID().GetCounter());
        if (!extra)
            return;

        uint32 const total = BaseSlots() + extra;
        uint32 const known = CountKnownPrimaryProfessions(player);
        uint32 const free = total > known ? total - known : 0;

        player->SetFreePrimaryProfessions(static_cast<uint16>(free));
    }
}

class mod_madosa_profession_scroll : public ItemScript
{
public:
    mod_madosa_profession_scroll() : ItemScript("item_madosa_profession_scroll") { }

    bool OnUse(Player* player, Item* item, SpellCastTargets const& /*targets*/) override
    {
        if (!MadosaSettings::GetProfessionSlotsEnable())
        {
            ChatHandler(player->GetSession()).PSendSysMessage("Extra profession slots are disabled on this server.");
            return true;
        }

        ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
        uint32 const extra = GetExtraSlots(guid);
        uint32 const maxTotal = MadosaSettings::GetProfessionSlotsMax();
        uint32 const base = BaseSlots();

        if (base + extra >= maxTotal)
        {
            ChatHandler(player->GetSession()).PSendSysMessage(
                "You already have the maximum of {} primary profession slots.", maxTotal);
            return true;   // handled: do not cast, do not consume
        }

        SetExtraSlots(guid, extra + 1);

        uint32 const total = base + extra + 1;
        uint32 const known = CountKnownPrimaryProfessions(player);
        player->SetFreePrimaryProfessions(static_cast<uint16>(total > known ? total - known : 0));

        player->DestroyItemCount(item->GetEntry(), 1, true);

        ChatHandler(player->GetSession()).PSendSysMessage(
            "The scroll unravels. You can now learn up to {} primary professions ({} still free).",
            total, total > known ? total - known : 0);
        return true;
    }
};

class mod_madosa_profession_slots : public PlayerScript
{
public:
    mod_madosa_profession_slots() : PlayerScript("mod_madosa_profession_slots") { }

    // Runs after LoadFromDB has reset the counter and counted known professions.
    void OnPlayerLogin(Player* player) override
    {
        if (!MadosaSettings::GetProfessionSlotsEnable())
            return;

        ApplyExtraSlots(player);
    }
};

void AddSC_madosa_profession_slots()
{
    new mod_madosa_profession_scroll();
    new mod_madosa_profession_slots();
}
