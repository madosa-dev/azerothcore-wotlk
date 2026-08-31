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

    struct SettingInfo
    {
        std::string key;
        std::string value;
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
    uint32 GetWorldforgedAscensionRespawn();

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
