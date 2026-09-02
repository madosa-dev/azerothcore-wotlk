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

#ifndef MOD_MADOSA_HARDCORE_PVP_H
#define MOD_MADOSA_HARDCORE_PVP_H

#include "Define.h"

#include <string>
#include <vector>

class Player;

// Hardcore PvP (mod_madosa_hardcore_pvp.cpp): the risk modes and the queries
// other parts of the module ask about them. The world-mob dungeon drops
// (mod_madosa_hardcore_pvp_loot.cpp) live in their own file but are the same
// feature, and ask IsHighRisk() here.
namespace MadosaHardcorePvP
{
    // RBAC permission id for the ".hardcore" player command; see
    // data/sql/db-auth/base/hardcore_pvp_rbac.sql. Linked to the player role,
    // not a GM one - the command only does what the Herald NPC does.
    constexpr uint32 RBAC_PERM_COMMAND_HARDCORE = 1002;

    // Ascension's own three, and its own division of them: PvE Mode (84422) is
    // the default and cannot fight or aid anyone, War Mode (84420) is open
    // world PvP with bonus experience and nothing at stake, and High-Risk
    // (84421) adds the world drops and the chest full of your bags.
    enum RiskMode : uint8
    {
        RISK_MODE_PVE  = 0,
        RISK_MODE_WAR  = 1,
        RISK_MODE_HIGH = 2,
    };

    // All cheap enough for a gameplay hook: an unordered_map lookup under a
    // shared lock, over online characters only.
    RiskMode GetMode(Player const* player);
    bool IsHighRisk(Player const* player);
    bool IsFlagged(Player const* player);   // War Mode or High-Risk
    bool IsTraitor(Player const* player);

    // "Is this a playerbot rather than a person?" - the session flag, not
    // GET_PLAYERBOT_AI. It is already true during OnPlayerLogin (the AI is
    // attached later, from a queued operation), and it answers no for a real
    // player running mod-playerbots' self-bot AI, who is still a person.
    bool IsBot(Player const* player);

    // Changes mode or treason, applying every consequence (auras, PvP flag, FFA
    // byte, forced faction reactions) and persisting it. Returns false and
    // fills outError with a player-readable sentence when the character may not
    // change right now - in an inn or a city, out of combat, off cooldown.
    bool SetMode(Player* player, RiskMode mode, std::string& outError);
    bool SetTraitor(Player* player, bool enable, std::string& outError);

    // Ascension's High-Risk lets you insure your gear, so a death costs gold
    // rather than belongings ("or Fel Com gold if your gear is insured", 84421).
    // The premium is paid up front and covers exactly one death - and it is
    // that same gold the killer finds in the chest, so the payout is funded by
    // the person who chose to be protected.
    bool IsInsured(Player const* player);
    bool BuyInsurance(Player* player, std::string& outError);

    // Puts the right level-band aura on the player, or takes the last one off
    // when they are not in High-Risk. Implemented in
    // mod_madosa_hardcore_pvp_loot.cpp, next to the band table it reads, so the
    // aura a player wears and the tier the roll actually uses can only ever
    // come from the same place.
    void UpdateLootBandAura(Player* player, bool highRisk);

    // The display name of a mode, for the Herald and the chat command.
    char const* ModeName(RiskMode mode);

    // One line per fact, for ".madosa hardcore" - how many characters are in
    // each mode right now and how many death chests are standing.
    std::vector<std::string> Status();
}

#endif
