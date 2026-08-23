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

// Backing store for MadosaSettings (see mod_madosa_settings.h): an in-memory
// value per setting (read on every gameplay hook, so changes are instant),
// seeded from mod_madosa.conf.dist at startup and then overlaid with any
// rows already saved in mod_madosa_settings - that table is the persistence
// layer that lets a GM change - Reset() re-derives every key from scratch
// (config default, then re-apply whatever DB overrides remain) instead of
// tracking per-key defaults separately - cheap with only four settings.

#include "mod_madosa_settings.h"

#include "Config.h"
#include "Log.h"
#include "ScriptMgr.h"
#include "WorldDatabase.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>

namespace
{
    std::atomic<bool> professionXPEnable{true};
    std::atomic<float> professionXPPercent{1.0f};
    std::atomic<uint32> professionXPSkillMultiplier{2};
    std::atomic<bool> autoLootPetEnable{true};

    bool ParseBool(std::string const& value, bool& out)
    {
        if (value == "0" || value == "false")
        {
            out = false;
            return true;
        }
        if (value == "1" || value == "true")
        {
            out = true;
            return true;
        }
        return false;
    }

    bool ParseFloat(std::string const& value, float& out)
    {
        if (value.empty())
            return false;

        char* end = nullptr;
        float parsed = std::strtof(value.c_str(), &end);
        if (end != value.c_str() + value.size() || !std::isfinite(parsed))
            return false;

        out = parsed;
        return true;
    }

    bool ParseUInt(std::string const& value, uint32& out)
    {
        if (value.empty() || value[0] == '-')
            return false;

        char* end = nullptr;
        unsigned long parsed = std::strtoul(value.c_str(), &end, 10);
        if (end != value.c_str() + value.size())
            return false;

        out = static_cast<uint32>(parsed);
        return true;
    }

    std::string BoolToStr(bool value)
    {
        return value ? "1" : "0";
    }

    std::string FloatToStr(float value)
    {
        std::string text = std::to_string(value);
        while (!text.empty() && text.back() == '0')
            text.pop_back();
        if (!text.empty() && text.back() == '.')
            text.pop_back();
        return text;
    }

    void SaveOverride(std::string const& key, std::string const& value)
    {
        WorldDatabase.Execute("REPLACE INTO mod_madosa_settings (setting_key, setting_value) VALUES ('{}', '{}')", key, value);
    }

    void DeleteOverride(std::string const& key)
    {
        WorldDatabase.Execute("DELETE FROM mod_madosa_settings WHERE setting_key = '{}'", key);
    }

    void LoadConfigDefaults()
    {
        professionXPEnable = sConfigMgr->GetOption<bool>("Madosa.ProfessionXP.Enable", true);
        professionXPPercent = sConfigMgr->GetOption<float>("Madosa.ProfessionXP.PercentOfLevelXP", 1.0f);
        professionXPSkillMultiplier = sConfigMgr->GetOption<uint32>("Madosa.ProfessionXP.SkillGainMultiplier", 2);
        autoLootPetEnable = sConfigMgr->GetOption<bool>("Madosa.AutoLootPet.Enable", true);
    }

    void LoadOverridesFromDB()
    {
        QueryResult result = WorldDatabase.Query("SELECT setting_key, setting_value FROM mod_madosa_settings");
        if (!result)
            return;

        do
        {
            Field* fields = result->Fetch();
            std::string key = fields[0].Get<std::string>();
            std::string value = fields[1].Get<std::string>();

            bool b;
            float f;
            uint32 u;
            if (key == "professionxp.enable" && ParseBool(value, b))
                professionXPEnable = b;
            else if (key == "professionxp.percent" && ParseFloat(value, f))
                professionXPPercent = f;
            else if (key == "professionxp.skillmultiplier" && ParseUInt(value, u))
                professionXPSkillMultiplier = u;
            else if (key == "autolootpet.enable" && ParseBool(value, b))
                autoLootPetEnable = b;
            else
                LOG_ERROR("module", "mod-madosa: ignoring stored setting {}={} (unknown key or invalid value)", key, value);
        } while (result->NextRow());
    }
}

namespace MadosaSettings
{
    bool GetProfessionXPEnable() { return professionXPEnable.load(); }
    float GetProfessionXPPercent() { return professionXPPercent.load(); }
    uint32 GetProfessionXPSkillMultiplier() { return std::max<uint32>(1, professionXPSkillMultiplier.load()); }
    bool GetAutoLootPetEnable() { return autoLootPetEnable.load(); }

    void Init()
    {
        LoadConfigDefaults();
        LoadOverridesFromDB();
    }

    bool Set(std::string const& key, std::string const& value, std::string& outError)
    {
        if (key == "professionxp.enable")
        {
            bool b;
            if (!ParseBool(value, b))
            {
                outError = "value must be 0 or 1";
                return false;
            }
            professionXPEnable = b;
        }
        else if (key == "professionxp.percent")
        {
            float f;
            if (!ParseFloat(value, f) || f < 0.0f || f > 100.0f)
            {
                outError = "value must be a number between 0 and 100";
                return false;
            }
            professionXPPercent = f;
        }
        else if (key == "professionxp.skillmultiplier")
        {
            uint32 u;
            if (!ParseUInt(value, u) || u < 1 || u > 100)
            {
                outError = "value must be a whole number between 1 and 100";
                return false;
            }
            professionXPSkillMultiplier = u;
        }
        else if (key == "autolootpet.enable")
        {
            bool b;
            if (!ParseBool(value, b))
            {
                outError = "value must be 0 or 1";
                return false;
            }
            autoLootPetEnable = b;
        }
        else
        {
            outError = "unknown setting key";
            return false;
        }

        SaveOverride(key, value);
        return true;
    }

    bool Reset(std::string const& key, std::string& outError)
    {
        if (key != "professionxp.enable" && key != "professionxp.percent" &&
            key != "professionxp.skillmultiplier" && key != "autolootpet.enable")
        {
            outError = "unknown setting key";
            return false;
        }

        DeleteOverride(key);
        LoadConfigDefaults();
        LoadOverridesFromDB(); // re-apply whatever overrides remain for the *other* keys
        return true;
    }

    std::vector<SettingInfo> List()
    {
        return {
            { "professionxp.enable", BoolToStr(GetProfessionXPEnable()) },
            { "professionxp.percent", FloatToStr(GetProfessionXPPercent()) },
            { "professionxp.skillmultiplier", std::to_string(GetProfessionXPSkillMultiplier()) },
            { "autolootpet.enable", BoolToStr(GetAutoLootPetEnable()) },
        };
    }
}

class mod_madosa_settings_world : public WorldScript
{
public:
    mod_madosa_settings_world() : WorldScript("mod_madosa_settings_world") { }

    void OnStartup() override
    {
        MadosaSettings::Init();
    }
};

void AddSC_madosa_settings()
{
    new mod_madosa_settings_world();
}
