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

// ".madosa" GM commands over MadosaSettings (mod_madosa_settings.h) - the
// same read/write path the addon bridge (mod_madosa_addon_bridge.cpp) uses,
// so typing these by hand and driving them from the addon are equivalent.

#include "mod_madosa_hardcore_pvp.h"
#include "mod_madosa_settings.h"
#include "mod_madosa_worldforged.h"

#include "Chat.h"
#include "CommandScript.h"

using namespace Acore::ChatCommands;

class mod_madosa_commandscript : public CommandScript
{
public:
    mod_madosa_commandscript() : CommandScript("mod_madosa_commandscript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable worldforgedCommandTable =
        {
            { "status", HandleWorldforgedStatusCommand, MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::Yes },
            { "spawn",  HandleWorldforgedSpawnCommand,  MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::No },
            { "clear",  HandleWorldforgedClearCommand,  MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::No },
        };
        static ChatCommandTable madosaCommandTable =
        {
            // Console-capable, and they have to be: these read and write
            // realm-wide settings and need no player behind them. Leaving them
            // player-only meant the server console and the dashboard's admin
            // panel got a usage message instead of a result - which quietly
            // invalidated a performance measurement taken through the panel
            // before anyone noticed the setting had never changed.
            { "status",      HandleMadosaStatusCommand,   MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::Yes },
            { "set",         HandleMadosaSetCommand,      MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::Yes },
            { "reset",       HandleMadosaResetCommand,    MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::Yes },
            { "hardcore",    HandleMadosaHardcoreCommand, MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::Yes },
            { "worldforged", worldforgedCommandTable },
        };
        // The one player-facing command in this module: it does exactly what
        // the Hardcore Herald does, under exactly the same rules, for people
        // who would rather not walk to the NPC. Hence its own permission,
        // linked to the player role (hardcore_pvp_rbac.sql).
        static ChatCommandTable traitorCommandTable =
        {
            { "on",  HandleTraitorOnCommand,  MadosaHardcorePvP::RBAC_PERM_COMMAND_HARDCORE, Console::No },
            { "off", HandleTraitorOffCommand, MadosaHardcorePvP::RBAC_PERM_COMMAND_HARDCORE, Console::No },
        };
        // "on"/"off" are kept as the names players already learned, now meaning
        // the two ends of the three-mode ladder.
        static ChatCommandTable hardcoreCommandTable =
        {
            { "",        HandleHardcoreStatusCommand, MadosaHardcorePvP::RBAC_PERM_COMMAND_HARDCORE, Console::No },
            { "pve",     HandleModePvECommand,        MadosaHardcorePvP::RBAC_PERM_COMMAND_HARDCORE, Console::No },
            { "war",     HandleModeWarCommand,        MadosaHardcorePvP::RBAC_PERM_COMMAND_HARDCORE, Console::No },
            { "high",    HandleModeHighCommand,       MadosaHardcorePvP::RBAC_PERM_COMMAND_HARDCORE, Console::No },
            { "on",      HandleModeHighCommand,       MadosaHardcorePvP::RBAC_PERM_COMMAND_HARDCORE, Console::No },
            { "off",     HandleModePvECommand,        MadosaHardcorePvP::RBAC_PERM_COMMAND_HARDCORE, Console::No },
            { "insure",  HandleInsureCommand,         MadosaHardcorePvP::RBAC_PERM_COMMAND_HARDCORE, Console::No },
            { "traitor", traitorCommandTable },
        };
        static ChatCommandTable commandTable =
        {
            { "madosa",   madosaCommandTable },
            { "hardcore", hardcoreCommandTable },
        };
        return commandTable;
    }

    static bool HandleMadosaHardcoreCommand(ChatHandler* handler)
    {
        for (std::string const& line : MadosaHardcorePvP::Status())
            handler->PSendSysMessage("{}", line);
        return true;
    }

    // Both toggles answer the same way: the mode function owns every rule and
    // returns the sentence to show when it says no, so the command has no
    // opinion of its own to drift out of sync with the Herald's.
    static bool SwitchMode(ChatHandler* handler, MadosaHardcorePvP::RiskMode mode)
    {
        Player* player = handler->GetSession() ? handler->GetSession()->GetPlayer() : nullptr;
        if (!player)
            return false;

        std::string error;
        if (MadosaHardcorePvP::SetMode(player, mode, error))
            handler->PSendSysMessage("You are now in {}.", MadosaHardcorePvP::ModeName(mode));
        else
            handler->PSendSysMessage("{}", error);
        return true;
    }

    static bool Toggle(ChatHandler* handler, bool enable)
    {
        Player* player = handler->GetSession() ? handler->GetSession()->GetPlayer() : nullptr;
        if (!player)
            return false;

        std::string error;
        if (!MadosaHardcorePvP::SetTraitor(player, enable, error))
        {
            handler->PSendSysMessage("{}", error);
            return true;
        }

        handler->PSendSysMessage(enable
            ? "You have betrayed your faction. Other traitors are fair game now - and your own cities are not yours."
            : "Your treason is forgiven.");
        return true;
    }

    static bool HandleInsureCommand(ChatHandler* handler)
    {
        Player* player = handler->GetSession() ? handler->GetSession()->GetPlayer() : nullptr;
        if (!player)
            return false;

        std::string error;
        if (MadosaHardcorePvP::BuyInsurance(player, error))
            handler->PSendSysMessage("Insured. One death is covered - the killer finds your premium in gold "
                "where your belongings would have been.");
        else
            handler->PSendSysMessage("{}", error);
        return true;
    }

    static bool HandleModePvECommand(ChatHandler* handler) { return SwitchMode(handler, MadosaHardcorePvP::RISK_MODE_PVE); }
    static bool HandleModeWarCommand(ChatHandler* handler) { return SwitchMode(handler, MadosaHardcorePvP::RISK_MODE_WAR); }
    static bool HandleModeHighCommand(ChatHandler* handler) { return SwitchMode(handler, MadosaHardcorePvP::RISK_MODE_HIGH); }
    static bool HandleTraitorOnCommand(ChatHandler* handler) { return Toggle(handler, true); }
    static bool HandleTraitorOffCommand(ChatHandler* handler) { return Toggle(handler, false); }

    static bool HandleHardcoreStatusCommand(ChatHandler* handler)
    {
        Player* player = handler->GetSession() ? handler->GetSession()->GetPlayer() : nullptr;
        if (!player)
            return false;

        handler->PSendSysMessage("Risk mode: {}", MadosaHardcorePvP::ModeName(MadosaHardcorePvP::GetMode(player)));
        handler->PSendSysMessage("Traitor: {}", MadosaHardcorePvP::IsTraitor(player) ? "yes" : "no");
        handler->PSendSysMessage("Insured: {}", MadosaHardcorePvP::IsInsured(player) ? "yes, one death covered" : "no");
        handler->PSendSysMessage("Change with \".hardcore pve|war|high\" or \".hardcore traitor on|off\", "
            "in an inn or a city - or talk to a Hardcore Herald.");
        return true;
    }

    static bool HandleMadosaStatusCommand(ChatHandler* handler)
    {
        for (auto const& setting : MadosaSettings::List())
            handler->PSendSysMessage("{}={}", setting.key, setting.value);

        handler->SetSentErrorMessage(false);
        return true;
    }

    static bool HandleMadosaSetCommand(ChatHandler* handler, std::string key, std::string value)
    {
        std::string error;
        if (!MadosaSettings::Set(key, value, error))
        {
            handler->PSendSysMessage("Failed to set {}: {}", key, error);
            handler->SetSentErrorMessage(true);
            return false;
        }

        handler->PSendSysMessage("{}={}", key, value);
        handler->SetSentErrorMessage(false);
        return true;
    }

    static bool HandleMadosaResetCommand(ChatHandler* handler, std::string key)
    {
        std::string error;
        if (!MadosaSettings::Reset(key, error))
        {
            handler->PSendSysMessage("Failed to reset {}: {}", key, error);
            handler->SetSentErrorMessage(true);
            return false;
        }

        handler->PSendSysMessage("{} reset to the config default.", key);
        handler->SetSentErrorMessage(false);
        return true;
    }

    static bool HandleWorldforgedStatusCommand(ChatHandler* handler)
    {
        std::vector<std::string> caches = MadosaWorldforged::Status();
        if (caches.empty())
            handler->PSendSysMessage("No Worldforged cache is standing right now.");
        else
            for (std::string const& line : caches)
                handler->PSendSysMessage("{}", line);

        handler->SetSentErrorMessage(false);
        return true;
    }

    // Forges one immediately without waiting out the interval. Everything else
    // still applies - a real player has to be online for a spot to be picked for
    // them, and the max-active cap still holds - so this shows the real event
    // rather than a special case of it.
    static bool HandleWorldforgedSpawnCommand(ChatHandler* handler)
    {
        std::string error;
        if (!MadosaWorldforged::ForgeNow(error))
        {
            handler->PSendSysMessage("Could not forge a cache: {}.", error);
            handler->SetSentErrorMessage(true);
            return false;
        }

        handler->PSendSysMessage("A Worldforged cache has been forged.");
        handler->SetSentErrorMessage(false);
        return true;
    }

    static bool HandleWorldforgedClearCommand(ChatHandler* handler)
    {
        handler->PSendSysMessage("Removed {} standing Worldforged cache(s).", MadosaWorldforged::ClearAll());
        handler->SetSentErrorMessage(false);
        return true;
    }
};

void AddSC_madosa_command()
{
    new mod_madosa_commandscript();
}
