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
    std::atomic<bool> professionToolsEnable{true};
    std::atomic<bool> accountCompanionsEnable{true};
    std::atomic<bool> instanceQuestPetEnable{true};
    std::atomic<bool> professionSlotsEnable{true};
    std::atomic<uint32> professionSlotsMax{5};
    std::atomic<bool> passerbyBuffEnable{true};
    std::atomic<float> passerbyBuffRadius{20.0f};
    std::atomic<bool> passerbyBuffPriestFortitude{true};
    std::atomic<bool> passerbyBuffPriestSpirit{true};
    std::atomic<bool> passerbyBuffMageIntellect{true};
    std::atomic<bool> passerbyBuffDruidMarkOfTheWild{true};
    std::atomic<bool> passerbyBuffPaladinKings{true};
    std::atomic<bool> passerbyBuffPaladinMight{true};
    std::atomic<bool> passerbyBuffPaladinWisdom{true};
    std::atomic<bool> repairPetEnable{true};
    std::atomic<bool> mailPetEnable{true};

    // Every feature toggle behaves identically, so they share one table instead
    // of repeating the same parse/validate/store block per key. Madosa.Addon.Enable
    // is deliberately absent: it gates the bridge this panel talks through, so
    // switching it off from the panel would lock the panel out of the server.
    struct BoolSetting
    {
        char const* key;
        char const* configKey;
        std::atomic<bool>* slot;
        bool configDefault;
    };

    BoolSetting const boolSettings[] =
    {
        { "professionxp.enable",      "Madosa.ProfessionXP.Enable",        &professionXPEnable,      true },
        { "autolootpet.enable",       "Madosa.AutoLootPet.Enable",         &autoLootPetEnable,       true },
        { "professiontools.enable",   "Madosa.ProfessionTools.Enable",     &professionToolsEnable,   true },
        { "accountcompanions.enable", "Madosa.AccountCompanions.Enable",   &accountCompanionsEnable, true },
        { "instancequestpet.enable",  "Madosa.InstanceQuestPet.Enable",    &instanceQuestPetEnable,  true },
        { "professionslots.enable",   "Madosa.ProfessionSlots.Enable",     &professionSlotsEnable,   true },
        { "passerbybuff.enable",                     "Madosa.PasserbyBuff.Enable",                     &passerbyBuffEnable,             true },
        { "passerbybuff.priest.fortitude.enable",    "Madosa.PasserbyBuff.Priest.Fortitude.Enable",    &passerbyBuffPriestFortitude,    true },
        { "passerbybuff.priest.spirit.enable",       "Madosa.PasserbyBuff.Priest.Spirit.Enable",       &passerbyBuffPriestSpirit,       true },
        { "passerbybuff.mage.intellect.enable",      "Madosa.PasserbyBuff.Mage.Intellect.Enable",      &passerbyBuffMageIntellect,      true },
        { "passerbybuff.druid.markofthewild.enable", "Madosa.PasserbyBuff.Druid.MarkOfTheWild.Enable", &passerbyBuffDruidMarkOfTheWild, true },
        { "passerbybuff.paladin.kings.enable",       "Madosa.PasserbyBuff.Paladin.Kings.Enable",       &passerbyBuffPaladinKings,       true },
        { "passerbybuff.paladin.might.enable",       "Madosa.PasserbyBuff.Paladin.Might.Enable",       &passerbyBuffPaladinMight,       true },
        { "passerbybuff.paladin.wisdom.enable",      "Madosa.PasserbyBuff.Paladin.Wisdom.Enable",      &passerbyBuffPaladinWisdom,      true },
        { "repairpet.enable",         "Madosa.RepairPet.Enable",           &repairPetEnable,         true },
        { "mailpet.enable",           "Madosa.MailPet.Enable",             &mailPetEnable,           true },
    };

    BoolSetting const* FindBoolSetting(std::string const& key)
    {
        for (BoolSetting const& setting : boolSettings)
            if (key == setting.key)
                return &setting;
        return nullptr;
    }

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
        for (BoolSetting const& setting : boolSettings)
            *setting.slot = sConfigMgr->GetOption<bool>(setting.configKey, setting.configDefault);

        professionXPPercent = sConfigMgr->GetOption<float>("Madosa.ProfessionXP.PercentOfLevelXP", 1.0f);
        professionXPSkillMultiplier = sConfigMgr->GetOption<uint32>("Madosa.ProfessionXP.SkillGainMultiplier", 2);
        professionSlotsMax = sConfigMgr->GetOption<uint32>("Madosa.ProfessionSlots.Max", 5);
        passerbyBuffRadius = sConfigMgr->GetOption<float>("Madosa.PasserbyBuff.Radius", 20.0f);
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
            if (BoolSetting const* setting = FindBoolSetting(key); setting && ParseBool(value, b))
                *setting->slot = b;
            else if (key == "professionxp.percent" && ParseFloat(value, f))
                professionXPPercent = f;
            else if (key == "professionxp.skillmultiplier" && ParseUInt(value, u))
                professionXPSkillMultiplier = u;
            else if (key == "professionslots.max" && ParseUInt(value, u))
                professionSlotsMax = u;
            else if (key == "passerbybuff.radius" && ParseFloat(value, f))
                passerbyBuffRadius = f;
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
    bool GetProfessionToolsEnable() { return professionToolsEnable.load(); }
    bool GetAccountCompanionsEnable() { return accountCompanionsEnable.load(); }
    bool GetInstanceQuestPetEnable() { return instanceQuestPetEnable.load(); }
    bool GetProfessionSlotsEnable() { return professionSlotsEnable.load(); }
    uint32 GetProfessionSlotsMax() { return std::max<uint32>(1, professionSlotsMax.load()); }
    bool GetPasserbyBuffEnable() { return passerbyBuffEnable.load(); }
    float GetPasserbyBuffRadius() { return passerbyBuffRadius.load(); }
    bool GetPasserbyBuffPriestFortitudeEnable() { return passerbyBuffPriestFortitude.load(); }
    bool GetPasserbyBuffPriestSpiritEnable() { return passerbyBuffPriestSpirit.load(); }
    bool GetPasserbyBuffMageIntellectEnable() { return passerbyBuffMageIntellect.load(); }
    bool GetPasserbyBuffDruidMarkOfTheWildEnable() { return passerbyBuffDruidMarkOfTheWild.load(); }
    bool GetPasserbyBuffPaladinKingsEnable() { return passerbyBuffPaladinKings.load(); }
    bool GetPasserbyBuffPaladinMightEnable() { return passerbyBuffPaladinMight.load(); }
    bool GetPasserbyBuffPaladinWisdomEnable() { return passerbyBuffPaladinWisdom.load(); }
    bool GetRepairPetEnable() { return repairPetEnable.load(); }
    bool GetMailPetEnable() { return mailPetEnable.load(); }

    void Init()
    {
        LoadConfigDefaults();
        LoadOverridesFromDB();
    }

    bool Set(std::string const& key, std::string const& value, std::string& outError)
    {
        if (BoolSetting const* setting = FindBoolSetting(key))
        {
            bool b;
            if (!ParseBool(value, b))
            {
                outError = "value must be 0 or 1";
                return false;
            }
            *setting->slot = b;
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
        else if (key == "professionslots.max")
        {
            uint32 u;
            // Below the server's own primary-profession cap the setting would do
            // nothing; above ~20 there are no more professions left to learn.
            if (!ParseUInt(value, u) || u < 1 || u > 20)
            {
                outError = "value must be a whole number between 1 and 20";
                return false;
            }
            professionSlotsMax = u;
        }
        else if (key == "passerbybuff.radius")
        {
            float f;
            // Below ~5yd bots would need to stand on top of the player to trigger; above 60yd
            // exceeds the cast range of every candidate buff, so the setting would do nothing.
            if (!ParseFloat(value, f) || f < 5.0f || f > 60.0f)
            {
                outError = "value must be a number between 5 and 60";
                return false;
            }
            passerbyBuffRadius = f;
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
        if (!FindBoolSetting(key) && key != "professionxp.percent" &&
            key != "professionxp.skillmultiplier" && key != "professionslots.max" &&
            key != "passerbybuff.radius")
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
        // Order matters only for how the addon lists them: the two numeric
        // profession settings sit next to their own enable toggle.
        std::vector<SettingInfo> out;
        out.push_back({ "professionxp.enable", BoolToStr(GetProfessionXPEnable()) });
        out.push_back({ "professionxp.percent", FloatToStr(GetProfessionXPPercent()) });
        out.push_back({ "professionxp.skillmultiplier", std::to_string(GetProfessionXPSkillMultiplier()) });
        out.push_back({ "professionslots.max", std::to_string(GetProfessionSlotsMax()) });
        out.push_back({ "passerbybuff.radius", FloatToStr(GetPasserbyBuffRadius()) });
        for (BoolSetting const& setting : boolSettings)
            if (std::string(setting.key) != "professionxp.enable")
                out.push_back({ setting.key, BoolToStr(setting.slot->load()) });
        return out;
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
