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

// Persistent, GM-granted per-character XP boost.
//
// The boost percentage is plain data (character_xp_boost table) applied via the
// OnPlayerGiveXP hook - it is not tied to a spell aura, so it survives death,
// logout and server restarts by construction. A real (but purely cosmetic) aura
// is (re-)applied on login/resurrect just so the boost is visible as a buff icon.
//
// Everything here is module-local on purpose: no core files are touched. The
// active-player boost percentages are cached in memory (populated on login,
// cleared on logout) instead of a Player member, and the DB access uses plain
// queries instead of core prepared statements, since modules cannot extend the
// core CharacterDatabaseStatements enum.

#include "Chat.h"
#include "CharacterDatabase.h"
#include "CommandScript.h"
#include "Language.h"
#include "Player.h"
#include "PlayerScript.h"

using namespace Acore::ChatCommands;

namespace
{
    // Purely cosmetic buff icon shown while a boost is active - it has no bearing
    // on the actual XP math. Use ".lookup spell <name>" in-game to find a spell
    // whose icon/tooltip you like, then set its id here. 0 = no icon, boost still works.
    constexpr uint32 XP_BOOST_VISUAL_SPELL_ID = 0;

    constexpr uint16 XP_BOOST_MAX_PCT = 2000;

    // Matches the id inserted by data/sql/db-auth/base/xpboost_rbac.sql.
    constexpr uint32 RBAC_PERM_COMMAND_XPBOOST = 1000;

    // Active players' boost percentages, keyed by low GUID. Populated on login,
    // erased on logout - avoids adding a field to the core Player class.
    std::unordered_map<ObjectGuid::LowType, uint16> ActiveXpBoosts;

    uint16 LoadXpBoostPct(ObjectGuid::LowType lowGuid)
    {
        QueryResult result = CharacterDatabase.Query("SELECT pct FROM character_xp_boost WHERE guid = {}", lowGuid);
        if (!result)
            return 0;

        return result->Fetch()[0].Get<uint16>();
    }

    void SaveXpBoostPct(ObjectGuid::LowType lowGuid, uint16 pct)
    {
        if (pct == 0)
        {
            CharacterDatabase.Execute("DELETE FROM character_xp_boost WHERE guid = {}", lowGuid);
            return;
        }

        CharacterDatabase.Execute("REPLACE INTO character_xp_boost (guid, pct) VALUES ({}, {})", lowGuid, pct);
    }

    uint16 GetActiveXpBoostPct(ObjectGuid::LowType lowGuid)
    {
        auto itr = ActiveXpBoosts.find(lowGuid);
        return itr != ActiveXpBoosts.end() ? itr->second : 0;
    }

    void ApplyVisual(Player* player, bool active)
    {
        if (!XP_BOOST_VISUAL_SPELL_ID)
            return;

        if (active)
            player->CastSpell(player, XP_BOOST_VISUAL_SPELL_ID, true);
        else
            player->RemoveAurasDueToSpell(XP_BOOST_VISUAL_SPELL_ID);
    }
}

class xp_boost_playerscript : public PlayerScript
{
public:
    xp_boost_playerscript() : PlayerScript("xp_boost_playerscript") { }

    void OnPlayerLogin(Player* player) override
    {
        uint16 pct = LoadXpBoostPct(player->GetGUID().GetCounter());
        if (pct)
        {
            ActiveXpBoosts[player->GetGUID().GetCounter()] = pct;
            ApplyVisual(player, true);
        }
    }

    void OnPlayerLogout(Player* player) override
    {
        ActiveXpBoosts.erase(player->GetGUID().GetCounter());
    }

    void OnPlayerResurrect(Player* player, float /*restore_percent*/, bool& /*applySickness*/) override
    {
        if (GetActiveXpBoostPct(player->GetGUID().GetCounter()))
            ApplyVisual(player, true);
    }

    void OnPlayerGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 /*xpSource*/) override
    {
        uint16 pct = GetActiveXpBoostPct(player->GetGUID().GetCounter());
        if (pct)
            amount = uint32(amount * ((100.0f + pct) / 100.0f));
    }
};

class xp_boost_commandscript : public CommandScript
{
public:
    xp_boost_commandscript() : CommandScript("xp_boost_commandscript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable xpBoostCommandTable =
        {
            { "set",    HandleXpBoostSetCommand,    RBAC_PERM_COMMAND_XPBOOST, Console::No },
            { "remove", HandleXpBoostRemoveCommand, RBAC_PERM_COMMAND_XPBOOST, Console::No },
            { "info",   HandleXpBoostInfoCommand,   RBAC_PERM_COMMAND_XPBOOST, Console::No },
        };
        static ChatCommandTable commandTable =
        {
            { "xpboost", xpBoostCommandTable },
        };
        return commandTable;
    }

    static bool HandleXpBoostSetCommand(ChatHandler* handler, uint16 pct, Optional<PlayerIdentifier> player)
    {
        if (!player)
            player = PlayerIdentifier::FromTargetOrSelf(handler);

        if (!player)
        {
            handler->SendErrorMessage(LANG_PLAYER_NOT_FOUND);
            return false;
        }

        if (pct == 0 || pct > XP_BOOST_MAX_PCT)
        {
            handler->PSendSysMessage("XP boost must be between 1 and {} percent.", XP_BOOST_MAX_PCT);
            handler->SetSentErrorMessage(true);
            return false;
        }

        SaveXpBoostPct(player->GetGUID().GetCounter(), pct);

        if (Player* target = player->GetConnectedPlayer())
        {
            ActiveXpBoosts[target->GetGUID().GetCounter()] = pct;
            ApplyVisual(target, true);
        }

        handler->PSendSysMessage("{} now gains +{}% experience until they reach max level.", player->GetName(), pct);
        handler->SetSentErrorMessage(false);
        return true;
    }

    static bool HandleXpBoostRemoveCommand(ChatHandler* handler, Optional<PlayerIdentifier> player)
    {
        if (!player)
            player = PlayerIdentifier::FromTargetOrSelf(handler);

        if (!player)
        {
            handler->SendErrorMessage(LANG_PLAYER_NOT_FOUND);
            return false;
        }

        SaveXpBoostPct(player->GetGUID().GetCounter(), 0);

        if (Player* target = player->GetConnectedPlayer())
        {
            ActiveXpBoosts.erase(target->GetGUID().GetCounter());
            ApplyVisual(target, false);
        }

        handler->PSendSysMessage("Removed the XP boost from {}.", player->GetName());
        handler->SetSentErrorMessage(false);
        return true;
    }

    static bool HandleXpBoostInfoCommand(ChatHandler* handler, Optional<PlayerIdentifier> player)
    {
        if (!player)
            player = PlayerIdentifier::FromTargetOrSelf(handler);

        if (!player)
        {
            handler->SendErrorMessage(LANG_PLAYER_NOT_FOUND);
            return false;
        }

        uint16 pct = LoadXpBoostPct(player->GetGUID().GetCounter());

        if (pct)
            handler->PSendSysMessage("{} has a +{}% XP boost active.", player->GetName(), pct);
        else
            handler->PSendSysMessage("{} has no XP boost active.", player->GetName());

        handler->SetSentErrorMessage(false);
        return true;
    }
};

void AddSC_xp_boost()
{
    new xp_boost_playerscript();
    new xp_boost_commandscript();
}
