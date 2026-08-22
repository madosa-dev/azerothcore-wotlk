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

// Grants a bit of XP for every gather/craft attempt that still has a chance to
// raise the profession - not just the ones that actually roll a skill point,
// since e.g. a "green" recipe/node can be crafted/gathered many times before
// it turns grey. OnPlayerUpdateGatheringSkill and OnPlayerUpdateCraftingSkill
// both fire unconditionally, before Player::UpdateSkillPro() rolls the dice,
// and carry the same grey-threshold the roll itself uses - so checking
// current skill value against that threshold reproduces "does this still
// give a skill-up chance" without duplicating the roll. Once the skill is
// grey, no more XP - matching the request exactly.
//
// Fishing has no equivalent pre-roll hook in the core, so it falls back to
// OnPlayerUpdateSkill (only fires on an actual skill-up) for that one skill.
//
// Also multiplies how many skill points an actual skill-up grants (all
// professions, primary and secondary). OnPlayerUpdateGatheringSkill and
// OnPlayerUpdateCraftingSkill both take their "gain" (the step size fed into
// UpdateSkillPro) by reference, so scaling it there is enough for everything
// except fishing, which again has no pre-roll hook - handled by re-applying
// the same step one more time (per extra multiplier) after the fact via
// SetSkill(), which is exactly what a second, immediate skill-up would have
// done.

#include "Config.h"
#include "DBCStores.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "World.h"

namespace
{
    void GrantProfessionXP(Player* player)
    {
        if (!sConfigMgr->GetOption<bool>("Madosa.ProfessionXP.Enable", true))
            return;

        if (player->GetLevel() >= sWorld->getIntConfig(CONFIG_MAX_PLAYER_LEVEL))
            return;

        float percent = sConfigMgr->GetOption<float>("Madosa.ProfessionXP.PercentOfLevelXP", 1.0f);
        if (percent <= 0.0f)
            return;

        uint32 xp = uint32(sObjectMgr->GetXPForLevel(player->GetLevel()) * (percent / 100.0f));
        if (xp)
            player->GiveXP(xp, nullptr);
    }

    uint32 SkillGainMultiplier()
    {
        return std::max<uint32>(1, sConfigMgr->GetOption<uint32>("Madosa.ProfessionXP.SkillGainMultiplier", 2));
    }
}

class mod_madosa_profession_xp : public PlayerScript
{
public:
    mod_madosa_profession_xp() : PlayerScript("mod_madosa_profession_xp") { }

    void OnPlayerUpdateGatheringSkill(Player* player, uint32 /*skillId*/, uint32 current, uint32 gray, uint32 /*green*/, uint32 /*yellow*/, uint32& gain) override
    {
        if (current < gray)
            GrantProfessionXP(player);

        gain *= SkillGainMultiplier();
    }

    void OnPlayerUpdateCraftingSkill(Player* player, SkillLineAbilityEntry const* skill, uint32 current_level, uint32& gain) override
    {
        if (current_level < skill->TrivialSkillLineRankHigh)
            GrantProfessionXP(player);

        gain *= SkillGainMultiplier();
    }

    void OnPlayerUpdateSkill(Player* player, uint32 skillId, uint32 /*value*/, uint32 max, uint32 step, uint32 newValue) override
    {
        // Only fishing lands here - gathering and crafting skills are handled
        // above via their pre-roll hooks, which also fire when the attempt
        // doesn't raise the skill (e.g. still green).
        if (skillId != SKILL_FISHING)
            return;

        GrantProfessionXP(player);

        uint32 multiplier = SkillGainMultiplier();
        if (multiplier <= 1)
            return;

        uint32 boosted = std::min<uint32>(newValue + step * (multiplier - 1), max);
        if (boosted > newValue)
            player->SetSkill(SKILL_FISHING, player->GetSkillStep(SKILL_FISHING), boosted, max);
    }
};

void AddSC_madosa_profession_xp()
{
    new mod_madosa_profession_xp();
}
