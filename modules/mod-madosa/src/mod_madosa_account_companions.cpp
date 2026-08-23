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

// Makes the mod-madosa companion pets (Lootbot, Classtrainer, Craftbot,
// Bankbot, Auctionbot, Questbot) account-wide: once any character on the account has
// learned one (by using the item bought from the Special Vendor), every
// other character on that account knows it too, from their next login on -
// no extra purchase, no client changes. The WotLK client's own "Pets" /
// Companions tab already lists whatever the character currently knows, so
// this doesn't need a custom "vanity" browser window - it just shows up
// there like any other companion, the moment the account owns it.
//
// Keyed off the item's real companion-teach spell (item_template.spellid_2
// with spelltrigger_2 = ITEM_SPELLTRIGGER_LEARN_SPELL_ID, see e.g.
// class_trainer_pet.sql's header comment for why item use teaches that spell
// rather than the generic "learn a companion" wrapper spell), so this reacts
// to a plain OnPlayerLearnSpell like anything else that grants a spell -
// Player::learnSpell() calls the hook for every caller (item use, trainer,
// quest reward, ...), not just these companions specifically.

#include "Config.h"
#include "CharacterDatabase.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldSession.h"

#include <array>

namespace
{
    struct CompanionPet
    {
        char const* name;
        uint32 spellId;
    };

    constexpr std::array<CompanionPet, 6> COMPANION_PETS = {{
        { "Lootbot", 28740 },
        { "Classtrainer", 43918 },
        { "Craftbot", 52615 },
        { "Bankbot", 45174 },
        { "Auctionbot", 45175 },
        { "Questbot", 43697 },
    }};

    bool AccountCompanionsEnabled()
    {
        return sConfigMgr->GetOption<bool>("Madosa.AccountCompanions.Enable", true);
    }

    // Grants any companion the account already owns but this character
    // doesn't know yet, and records any this character knows that the
    // account doesn't have on file yet (first use, or a login predating
    // this feature).
    void SyncAccountCompanions(Player* player)
    {
        if (!AccountCompanionsEnabled())
            return;

        uint32 accountId = player->GetSession()->GetAccountId();

        for (CompanionPet const& companion : COMPANION_PETS)
        {
            if (player->HasSpell(companion.spellId))
            {
                CharacterDatabase.Execute(
                    "INSERT IGNORE INTO account_companion_pets (account_id, spell_id) VALUES ({}, {})",
                    accountId, companion.spellId);
                continue;
            }

            QueryResult result = CharacterDatabase.Query(
                "SELECT 1 FROM account_companion_pets WHERE account_id = {} AND spell_id = {}",
                accountId, companion.spellId);
            if (result)
                player->learnSpell(companion.spellId);
        }
    }
}

class mod_madosa_account_companions : public PlayerScript
{
public:
    mod_madosa_account_companions() : PlayerScript("mod_madosa_account_companions") { }

    void OnPlayerLogin(Player* player) override
    {
        SyncAccountCompanions(player);
    }

    void OnPlayerLearnSpell(Player* player, uint32 /*spellID*/) override
    {
        SyncAccountCompanions(player);
    }
};

void AddSC_madosa_account_companions()
{
    new mod_madosa_account_companions();
}
