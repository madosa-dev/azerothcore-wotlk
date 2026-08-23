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

// Hands out the matching gathering tool (Mining Pick, Skinning Knife, Fishing
// Pole) the moment a player knows a gathering profession that needs one -
// whether they just trained it (OnPlayerLearnSpell) or already knew it
// before this feature existed (OnPlayerLogin backfills it). Deliberately
// keyed off the skill itself (GetSkillValue), not the specific trainer spell
// id, since a trainer "buy" spell is often just a wrapper that casts/learns
// the real skill spell (Trainer::TeachSpell) - checking the resulting skill
// state sidesteps having to know which exact spell id ends up learned.
//
// Crafting professions don't need a tool in their bags, only gathering ones
// (Herbalism doesn't either - you just need the skill).

#include "Config.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"

namespace
{
    struct ProfessionTool
    {
        SkillType skill;
        uint32 itemEntry;
    };

    constexpr ProfessionTool PROFESSION_TOOLS[] = {
        { SKILL_MINING,   2901 }, // Mining Pick
        { SKILL_SKINNING, 7005 }, // Skinning Knife
        { SKILL_FISHING,  6256 }, // Fishing Pole
    };

    void GrantToolIfMissing(Player* player, ProfessionTool const& tool)
    {
        if (!player->GetSkillValue(tool.skill))
            return;

        if (player->HasItemCount(tool.itemEntry, 1, false))
            return;

        player->StoreNewItemInBestSlots(tool.itemEntry, 1);
    }

    void GrantKnownProfessionTools(Player* player)
    {
        if (!sConfigMgr->GetOption<bool>("Madosa.ProfessionTools.Enable", true))
            return;

        for (ProfessionTool const& tool : PROFESSION_TOOLS)
            GrantToolIfMissing(player, tool);
    }
}

class mod_madosa_profession_tools : public PlayerScript
{
public:
    mod_madosa_profession_tools() : PlayerScript("mod_madosa_profession_tools") { }

    void OnPlayerLearnSpell(Player* player, uint32 /*spellID*/) override
    {
        GrantKnownProfessionTools(player);
    }

    void OnPlayerLogin(Player* player) override
    {
        GrantKnownProfessionTools(player);
    }
};

void AddSC_madosa_profession_tools()
{
    new mod_madosa_profession_tools();
}
