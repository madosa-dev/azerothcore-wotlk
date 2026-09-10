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

// Makes every Vanity-quality item (Quality 6 - see the client-side
// VanityQuality addon for why that slot was repurposed) account-wide: once
// any character on the account has learned its companion/toy spell (by using
// the item), every other character on that account knows it too, from their
// next login on - no extra purchase, no client changes. The WotLK client's
// own "Pets" / Companions tab already lists whatever the character currently
// knows, so this doesn't need a custom browser window - it just shows up
// there like any other companion, the moment the account owns it.
//
// The mod-madosa companion pets (Lootbot, Classtrainer, Craftbot, Bankbot,
// Auctionbot, Questbot) are Vanity items and get this behavior for free, but
// it isn't specific to them: any future Vanity item that teaches a spell via
// the standard item_template spellid_N/spelltrigger_N =
// ITEM_SPELLTRIGGER_LEARN_SPELL_ID convention (see e.g. class_trainer_pet.sql's
// header comment for why item use teaches that spell rather than the generic
// "learn a companion" wrapper spell) is picked up automatically. This reacts
// to a plain OnPlayerLearnSpell like anything else that grants a spell -
// Player::learnSpell() calls the hook for every caller (item use, trainer,
// quest reward, ...), not just Vanity items specifically.
//
// That hook is a hot path, though: bots and players learn spells constantly,
// and a single Craftbot visit is thousands of learnSpell() calls. So the
// account's unlocked set is read from the DB exactly once, at login, and kept
// on the player; every learn after that is answered from memory and only ever
// writes (asynchronously, and only for a companion we hadn't recorded yet).
// Nothing here may run a blocking CharacterDatabase.Query() per learn - that
// used to stall the world update thread for seconds at a time.

#include "CharacterDatabase.h"
#include "ItemTemplate.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldDatabase.h"
#include "WorldSession.h"
#include "mod_madosa_settings.h"

#include <unordered_set>
#include <vector>

namespace
{
    constexpr uint32 VANITY_QUALITY = 6;
    constexpr char const* COMPANION_DATA_KEY = "mod_madosa_account_companions";

    // Populated once at startup (see mod_madosa_account_companions_world
    // below) from every Vanity item's learn-spell. A restart is needed to
    // pick up a newly added Vanity item, same as trainer/quest data.
    std::vector<uint32> vanityLearnSpells;

    // Lives in the player's own DataMap rather than in a module-global map,
    // so map update threads never touch each other's copy and no locking is
    // needed. It only ever holds the <= vanityLearnSpells.size() companion
    // spells of one account.
    struct AccountCompanionData : public DataMap::Base
    {
        std::unordered_set<uint32> unlocked;
        bool syncing = false;
    };

    void LoadVanityLearnSpells()
    {
        vanityLearnSpells.clear();

        QueryResult result = WorldDatabase.Query(
            "SELECT spellid_1, spelltrigger_1, spellid_2, spelltrigger_2, spellid_3, spelltrigger_3, "
            "spellid_4, spelltrigger_4, spellid_5, spelltrigger_5 FROM item_template WHERE Quality = {}",
            VANITY_QUALITY);
        if (!result)
            return;

        do
        {
            Field* fields = result->Fetch();
            for (uint8 slot = 0; slot < MAX_ITEM_PROTO_SPELLS; ++slot)
            {
                uint32 spellId = fields[slot * 2].Get<uint32>();
                uint32 trigger = fields[slot * 2 + 1].Get<uint32>();
                if (spellId && trigger == ITEM_SPELLTRIGGER_LEARN_SPELL_ID)
                    vanityLearnSpells.push_back(spellId);
            }
        } while (result->NextRow());

        LOG_INFO("module", "mod-madosa: {} vanity companion spell(s) loaded", vanityLearnSpells.size());
    }

    bool AccountCompanionsEnabled()
    {
        return MadosaSettings::GetAccountCompanionsEnable();
    }

    // The one DB read of the whole session. Characters of the same account
    // that are already online keep the set they loaded at their own login -
    // that matches the documented "from their next login on" behavior.
    void LoadAccountCompanions(Player* player)
    {
        AccountCompanionData* data = player->CustomData.GetDefault<AccountCompanionData>(COMPANION_DATA_KEY);
        data->unlocked.clear();

        QueryResult result = CharacterDatabase.Query(
            "SELECT spell_id FROM account_companion_pets WHERE account_id = {}",
            player->GetSession()->GetAccountId());
        if (!result)
            return;

        do
        {
            data->unlocked.insert(result->Fetch()[0].Get<uint32>());
        } while (result->NextRow());
    }

    // Grants any companion the account already owns but this character
    // doesn't know yet, and records any this character knows that the
    // account doesn't have on file yet (first use, or a login predating
    // this feature).
    void SyncAccountCompanions(Player* player)
    {
        if (!AccountCompanionsEnabled())
            return;

        // Absent only for a learn that lands before OnPlayerLogin; the login
        // sync right after it covers those.
        AccountCompanionData* data = player->CustomData.Get<AccountCompanionData>(COMPANION_DATA_KEY);
        if (!data)
            return;

        // learnSpell() below fires OnPlayerLearnSpell again, which lands back
        // here - without this the loop re-enters once per companion granted.
        if (data->syncing)
            return;

        data->syncing = true;

        uint32 accountId = player->GetSession()->GetAccountId();

        for (uint32 spellId : vanityLearnSpells)
        {
            if (player->HasSpell(spellId))
            {
                // insert() tells us whether this is news to the account, so
                // the write happens once per session instead of once per learn.
                if (data->unlocked.insert(spellId).second)
                    CharacterDatabase.Execute(
                        "INSERT IGNORE INTO account_companion_pets (account_id, spell_id) VALUES ({}, {})",
                        accountId, spellId);
            }
            else if (data->unlocked.count(spellId))
                player->learnSpell(spellId);
        }

        data->syncing = false;
    }
}

class mod_madosa_account_companions : public PlayerScript
{
public:
    mod_madosa_account_companions() : PlayerScript("mod_madosa_account_companions", {
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_LOGOUT,
        PLAYERHOOK_ON_LEARN_SPELL
    }) { }

    void OnPlayerLogin(Player* player) override
    {
        if (!AccountCompanionsEnabled())
            return;

        LoadAccountCompanions(player);
        SyncAccountCompanions(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        player->CustomData.Erase(COMPANION_DATA_KEY);
    }

    void OnPlayerLearnSpell(Player* player, uint32 /*spellID*/) override
    {
        SyncAccountCompanions(player);
    }
};

class mod_madosa_account_companions_world : public WorldScript
{
public:
    mod_madosa_account_companions_world() : WorldScript("mod_madosa_account_companions_world") { }

    void OnStartup() override
    {
        LoadVanityLearnSpells();
    }
};

void AddSC_madosa_account_companions()
{
    new mod_madosa_account_companions();
    new mod_madosa_account_companions_world();
}
