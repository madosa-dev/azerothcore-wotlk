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

// Lets the MadosaControl client addon (modules/mod-madosa/addon/MadosaControl)
// read and change MadosaSettings live, with no server restart.
//
// The client sends a normal self-whisper (SendAddonMessage(..., "WHISPER",
// UnitName("player"))) carrying language LANG_ADDON - the client's own addon
// framework glues the "MADOSA\t" prefix onto the message for us, so on this
// end it just looks like a private chat message. Player::Whisper() already
// runs every whisper through PlayerScript::OnPlayerCanUseChat(..., Player*
// receiver) before it's delivered, which is the one hook that sees the
// message early enough to swallow it (return false) instead of letting it
// bounce back to the sender as an ordinary whisper.
//
// Every opcode requires the same RBAC_PERM_COMMAND_MADOSA permission as the
// ".madosa" chat commands (mod_madosa_command.cpp) - the addon is just an
// alternate front-end for the same permission-gated read/write path.

#include "mod_madosa_settings.h"

#include "Chat.h"
#include "Config.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <cstring>
#include <vector>

namespace
{
    constexpr char const* ADDON_PREFIX = "MADOSA\t";
    constexpr char const* PROTOCOL_VERSION = "1";
    constexpr char FIELD_SEP = '~';

    bool AddonBridgeEnabled()
    {
        return sConfigMgr->GetOption<bool>("Madosa.Addon.Enable", true);
    }

    std::vector<std::string> Split(std::string const& value)
    {
        std::vector<std::string> fields;
        size_t start = 0;
        while (start <= value.size())
        {
            size_t pos = value.find(FIELD_SEP, start);
            if (pos == std::string::npos)
            {
                fields.emplace_back(value.substr(start));
                break;
            }
            fields.emplace_back(value.substr(start, pos - start));
            start = pos + 1;
        }
        return fields;
    }

    void SendAddonPacket(Player* player, std::string const& opcode, std::string const& payload = "")
    {
        std::string wire = std::string(ADDON_PREFIX) + opcode;
        if (!payload.empty())
            wire += FIELD_SEP + payload;

        WorldPacket data;
        ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, nullptr, wire.c_str());
        player->SendDirectMessage(&data);
    }

    void SendError(Player* player, std::string const& code, std::string const& message)
    {
        SendAddonPacket(player, "ERROR", code + FIELD_SEP + message);
    }

    void SendSettings(Player* player)
    {
        SendAddonPacket(player, "SETTINGS_BEGIN");
        for (auto const& setting : MadosaSettings::List())
            SendAddonPacket(player, "SETTING", setting.key + FIELD_SEP + setting.value);
        SendAddonPacket(player, "SETTINGS_END");
    }

    void HandleSet(Player* player, std::vector<std::string> const& fields)
    {
        if (fields.size() < 3)
        {
            SendError(player, "BAD_REQUEST", "SET requires a key and a value.");
            return;
        }

        std::string const& key = fields[1];
        std::string const& value = fields[2];

        std::string error;
        bool ok = MadosaSettings::Set(key, value, error);
        SendAddonPacket(player, "SET_ACK", std::string(ok ? "1" : "0") + FIELD_SEP + key + FIELD_SEP + (ok ? value : error));
        if (ok)
            SendSettings(player);
    }

    void HandleReset(Player* player, std::vector<std::string> const& fields)
    {
        if (fields.size() < 2)
        {
            SendError(player, "BAD_REQUEST", "RESET requires a key.");
            return;
        }

        std::string const& key = fields[1];

        std::string error;
        bool ok = MadosaSettings::Reset(key, error);
        SendAddonPacket(player, "RESET_ACK", std::string(ok ? "1" : "0") + FIELD_SEP + key + FIELD_SEP + error);
        if (ok)
            SendSettings(player);
    }
}

class mod_madosa_addon_bridge : public PlayerScript
{
public:
    mod_madosa_addon_bridge() : PlayerScript("mod_madosa_addon_bridge") { }

    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 language, std::string& msg, Player* /*receiver*/) override
    {
        if (!AddonBridgeEnabled() || language != LANG_ADDON || msg.rfind(ADDON_PREFIX, 0) != 0)
            return true; // not ours - let normal whisper handling continue

        if (!player->GetSession() || !player->GetSession()->HasPermission(MadosaSettings::RBAC_PERM_COMMAND_MADOSA))
        {
            SendError(player, "PERMISSION", "mod-madosa requires GM permission (see madosa_settings_rbac.sql).");
            return false;
        }

        std::vector<std::string> fields = Split(msg.substr(strlen(ADDON_PREFIX)));
        std::string const opcode = fields.empty() ? "" : fields[0];

        if (opcode == "HELLO")
            SendAddonPacket(player, "HELLO_ACK", PROTOCOL_VERSION);
        else if (opcode == "GET")
            SendSettings(player);
        else if (opcode == "SET")
            HandleSet(player, fields);
        else if (opcode == "RESET")
            HandleReset(player, fields);
        else
            SendError(player, "BAD_REQUEST", "Unknown opcode.");

        return false; // consumed - don't let it bounce back as a plain whisper
    }
};

void AddSC_madosa_addon_bridge()
{
    new mod_madosa_addon_bridge();
}
