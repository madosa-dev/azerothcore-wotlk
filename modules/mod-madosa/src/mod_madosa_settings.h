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

#ifndef MOD_MADOSA_SETTINGS_H
#define MOD_MADOSA_SETTINGS_H

#include "Define.h"

#include <string>
#include <vector>

// Runtime-tunable mod-madosa settings: seeded from mod_madosa.conf.dist on
// startup, then changeable at any time (by GM chat command or the addon
// bridge) without a server restart. Changes are kept in the mod_madosa_settings
// world DB table, so they also survive restarts - the conf file only supplies
// the initial/install-time value, exactly like a first-run default.
namespace MadosaSettings
{
    // RBAC permission id for the ".madosa" command and the addon bridge; see
    // data/sql/db-auth/base/madosa_settings_rbac.sql.
    constexpr uint32 RBAC_PERM_COMMAND_MADOSA = 1001;

    // Everything MadosaControl needs to render one row without knowing a thing
    // about the setting itself: which widget (type), what it may be set to
    // (min/max), which panel it belongs on (group) and what to call it.
    // Keeping this here rather than in the addon means a new setting shows up
    // in the panel, correctly labelled and correctly bounded, with no client
    // change at all.
    struct SettingInfo
    {
        std::string key;
        std::string value;
        std::string type;    // "bool", "int" or "float"
        std::string min;
        std::string max;
        std::string group;   // display name of the panel it belongs on
        std::string label;
        std::string help;
    };

    void Init();

    bool GetProfessionXPEnable();
    float GetProfessionXPPercent();
    uint32 GetProfessionXPSkillMultiplier();
    bool GetAutoLootPetEnable();
    bool GetProfessionToolsEnable();
    bool GetAccountCompanionsEnable();
    bool GetInstanceQuestPetEnable();
    bool GetProfessionSlotsEnable();
    uint32 GetProfessionSlotsMax();
    bool GetPasserbyBuffEnable();
    float GetPasserbyBuffRadius();
    bool GetPasserbyBuffPriestFortitudeEnable();
    bool GetPasserbyBuffPriestSpiritEnable();
    bool GetPasserbyBuffMageIntellectEnable();
    bool GetPasserbyBuffDruidMarkOfTheWildEnable();
    bool GetPasserbyBuffPaladinKingsEnable();
    bool GetPasserbyBuffPaladinMightEnable();
    bool GetPasserbyBuffPaladinWisdomEnable();
    bool GetRepairPetEnable();
    bool GetMailPetEnable();
    bool GetOmniPetEnable();
    bool GetWorldforgedEnable();
    bool GetWorldforgedAnnounce();
    uint32 GetWorldforgedInterval();
    uint32 GetWorldforgedLifetime();
    uint32 GetWorldforgedMaxActive();
    uint32 GetWorldforgedRareChance();
    uint32 GetWorldforgedGoldPerLevel();
    bool GetWorldforgedAscensionEnable();
    bool GetHardcorePvPEnable();
    uint32 GetHardcorePvPXPPercent();
    uint32 GetHardcorePvPMinLevel();
    uint32 GetHardcorePvPToggleCooldown();
    bool GetHardcorePvPWarModeEnable();
    uint32 GetHardcorePvPWarModeXPPercent();
    bool GetHardcorePvPInsuranceEnable();
    uint32 GetHardcorePvPInsuranceCost();
    uint32 GetHardcorePvPBountyChance();
    bool GetHardcorePvPTraitorEnable();
    bool GetHardcorePvPTraitorGuardsHostile();
    uint32 GetHardcorePvPDropPercent();
    uint32 GetHardcorePvPDropMaxItems();
    uint32 GetHardcorePvPChestLifetime();
    uint32 GetHardcorePvPRepeatKillCooldown();
    float GetHardcorePvPDungeonDropChance();
    bool GetHardcorePvPDungeonDropGreyMobs();
    uint32 GetHardcorePvPBotParticipation();

    // Parses and applies value for key, persisting it to the DB override
    // table. Returns false (and fills outError) if key is unknown or value
    // fails validation - nothing is changed in that case.
    bool Set(std::string const& key, std::string const& value, std::string& outError);

    // Drops the DB override for key (if any) and reverts it to the conf file
    // value. Returns false (and fills outError) if key is unknown.
    bool Reset(std::string const& key, std::string& outError);

    std::vector<SettingInfo> List();
}

#endif
