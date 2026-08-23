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

#include "mod_madosa_settings.h"

#include "Chat.h"
#include "CommandScript.h"

using namespace Acore::ChatCommands;

class mod_madosa_commandscript : public CommandScript
{
public:
    mod_madosa_commandscript() : CommandScript("mod_madosa_commandscript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable madosaCommandTable =
        {
            { "status", HandleMadosaStatusCommand, MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::No },
            { "set",    HandleMadosaSetCommand,    MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::No },
            { "reset",  HandleMadosaResetCommand,  MadosaSettings::RBAC_PERM_COMMAND_MADOSA, Console::No },
        };
        static ChatCommandTable commandTable =
        {
            { "madosa", madosaCommandTable },
        };
        return commandTable;
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
};

void AddSC_madosa_command()
{
    new mod_madosa_commandscript();
}
