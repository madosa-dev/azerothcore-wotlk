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
#include "StringFormat.h"
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
    std::atomic<bool> omniPetEnable{true};
    std::atomic<bool> worldforgedEnable{true};
    std::atomic<bool> worldforgedAnnounce{true};
    std::atomic<uint32> worldforgedInterval{20};
    std::atomic<uint32> worldforgedLifetime{30};
    std::atomic<uint32> worldforgedMaxActive{1};
    std::atomic<uint32> worldforgedRareChance{15};
    std::atomic<uint32> worldforgedGoldPerLevel{500};
    std::atomic<bool> worldforgedAscensionEnable{true};
    std::atomic<bool> hardcorePvPEnable{true};
    std::atomic<uint32> hardcorePvPXPPercent{10};
    std::atomic<uint32> hardcorePvPMinLevel{20};
    std::atomic<uint32> hardcorePvPToggleCooldown{30};
    std::atomic<bool> hardcorePvPWarModeEnable{true};
    std::atomic<uint32> hardcorePvPWarModeXPPercent{5};
    std::atomic<bool> hardcorePvPInsuranceEnable{true};
    std::atomic<uint32> hardcorePvPInsuranceCost{100};
    std::atomic<uint32> hardcorePvPBountyChance{20};
    std::atomic<bool> hardcorePvPDungeonDropGreyMobs{true};
    std::atomic<bool> hardcorePvPTraitorEnable{true};
    std::atomic<bool> hardcorePvPTraitorGuardsHostile{true};
    std::atomic<uint32> hardcorePvPDropPercent{20};
    std::atomic<uint32> hardcorePvPDropMaxItems{12};
    std::atomic<uint32> hardcorePvPChestLifetime{5};
    std::atomic<uint32> hardcorePvPRepeatKillCooldown{60};
    std::atomic<float> hardcorePvPDungeonDropChance{1.5f};
    std::atomic<uint32> hardcorePvPBotParticipation{10};

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
        { "omnipet.enable",           "Madosa.OmniPet.Enable",             &omniPetEnable,           true },
        { "worldforged.enable",       "Madosa.Worldforged.Enable",         &worldforgedEnable,       true },
        { "worldforged.announce",     "Madosa.Worldforged.Announce",       &worldforgedAnnounce,     true },
        { "worldforged.ascension.enable", "Madosa.Worldforged.Ascension.Enable", &worldforgedAscensionEnable, true },
        { "hardcorepvp.enable",                "Madosa.HardcorePvP.Enable",                &hardcorePvPEnable,              true },
        { "hardcorepvp.warmode.enable",        "Madosa.HardcorePvP.WarModeEnable",         &hardcorePvPWarModeEnable,       true },
        { "hardcorepvp.insurance.enable",      "Madosa.HardcorePvP.InsuranceEnable",       &hardcorePvPInsuranceEnable,     true },
        { "hardcorepvp.dungeondrop.greymobs",  "Madosa.HardcorePvP.DungeonDropGreyMobs",   &hardcorePvPDungeonDropGreyMobs, true },
        { "hardcorepvp.traitor.enable",        "Madosa.HardcorePvP.TraitorEnable",         &hardcorePvPTraitorEnable,       true },
        { "hardcorepvp.traitor.guardshostile", "Madosa.HardcorePvP.TraitorGuardsHostile",  &hardcorePvPTraitorGuardsHostile, true },
    };

    // The numeric settings share the same shape too - a slot, a config key, a
    // default and the range a GM may set them to - so the parse/validate/store
    // block lives in one place instead of once per key. Only settings whose
    // valid range is a plain interval belong here; anything needing a different
    // check stays hand-written in Set().
    struct UIntSetting
    {
        char const* key;
        char const* configKey;
        std::atomic<uint32>* slot;
        uint32 configDefault;
        uint32 min;
        uint32 max;
    };

    UIntSetting const uintSettings[] =
    {
        // Interval and lifetime: a day is the longest that still reads as
        // "recurring", one minute the shortest that leaves time to travel there.
        { "worldforged.interval",     "Madosa.Worldforged.IntervalMinutes", &worldforgedInterval,     20,  1,   1440 },
        { "worldforged.lifetime",     "Madosa.Worldforged.LifetimeMinutes", &worldforgedLifetime,     30,  1,   1440 },
        // Each standing cache keeps its own grid resident, so the cap stays low.
        { "worldforged.maxactive",    "Madosa.Worldforged.MaxActive",       &worldforgedMaxActive,     1,  1,     10 },
        { "worldforged.rarechance",   "Madosa.Worldforged.RareChance",      &worldforgedRareChance,   15,  0,    100 },
        { "worldforged.goldperlevel", "Madosa.Worldforged.GoldPerLevel",    &worldforgedGoldPerLevel, 500, 0, 100000 },
        // Hardcore PvP. The bounds are the range in which each setting still
        // means something: 0% extra XP is "off", 100% is double; a drop share
        // over 100 cannot take more than the bags hold; a loot window holds 18.
        { "hardcorepvp.xppercent",          "Madosa.HardcorePvP.XPPercent",                 &hardcorePvPXPPercent,          10,   0,  100 },
        { "hardcorepvp.warmode.xppercent",  "Madosa.HardcorePvP.WarModeXPPercent",          &hardcorePvPWarModeXPPercent,    5,   0,  100 },
        { "hardcorepvp.insurance.cost",     "Madosa.HardcorePvP.InsuranceCostGold",         &hardcorePvPInsuranceCost,     100,   1, 100000 },
        { "hardcorepvp.bountychance",       "Madosa.HardcorePvP.BountyChance",              &hardcorePvPBountyChance,       20,   0,  100 },
        { "hardcorepvp.minlevel",           "Madosa.HardcorePvP.MinLevel",                  &hardcorePvPMinLevel,           20,   1,   80 },
        { "hardcorepvp.togglecooldown",     "Madosa.HardcorePvP.ToggleCooldownMinutes",     &hardcorePvPToggleCooldown,     30,   0, 1440 },
        { "hardcorepvp.droppercent",        "Madosa.HardcorePvP.DropPercent",               &hardcorePvPDropPercent,        20,   0,  100 },
        { "hardcorepvp.dropmaxitems",       "Madosa.HardcorePvP.DropMaxItems",              &hardcorePvPDropMaxItems,       12,   1,   18 },
        { "hardcorepvp.chestlifetime",      "Madosa.HardcorePvP.ChestLifetimeMinutes",      &hardcorePvPChestLifetime,       5,   1,   60 },
        { "hardcorepvp.repeatkillcooldown", "Madosa.HardcorePvP.RepeatKillCooldownMinutes", &hardcorePvPRepeatKillCooldown, 60,   0, 1440 },
        { "hardcorepvp.botparticipation",   "Madosa.HardcorePvP.BotParticipation",          &hardcorePvPBotParticipation,   10,   0,  100 },
        { "professionxp.skillmultiplier", "Madosa.ProfessionXP.SkillGainMultiplier", &professionXPSkillMultiplier, 2, 1, 100 },
        // Below the server's own primary-profession cap the setting would do
        // nothing; above ~20 there are no more professions left to learn.
        { "professionslots.max",          "Madosa.ProfessionSlots.Max",              &professionSlotsMax,          5, 1,  20 },
    };

    // The float settings work exactly like the integer ones - a slot, a config
    // key, a default and the interval a GM may set them to - and are a table for
    // the same reason: one parse/validate/store block instead of one per key,
    // and one place for MadosaControl to read a slider's range from.
    struct FloatSetting
    {
        char const* key;
        char const* configKey;
        std::atomic<float>* slot;
        float configDefault;
        float min;
        float max;
    };

    FloatSetting const floatSettings[] =
    {
        { "professionxp.percent", "Madosa.ProfessionXP.PercentOfLevelXP", &professionXPPercent, 1.0f, 0.0f, 100.0f },
        // Below ~5yd bots would need to stand on top of the player to trigger;
        // above 60yd exceeds the cast range of every candidate buff.
        { "passerbybuff.radius",  "Madosa.PasserbyBuff.Radius",           &passerbyBuffRadius, 20.0f, 5.0f,  60.0f },
        { "hardcorepvp.dungeondropchance", "Madosa.HardcorePvP.DungeonDropChance", &hardcorePvPDungeonDropChance, 1.5f, 0.0f, 100.0f },
    };

    FloatSetting const* FindFloatSetting(std::string const& key)
    {
        for (FloatSetting const& setting : floatSettings)
            if (key == setting.key)
                return &setting;
        return nullptr;
    }

    UIntSetting const* FindUIntSetting(std::string const& key)
    {
        for (UIntSetting const& setting : uintSettings)
            if (key == setting.key)
                return &setting;
        return nullptr;
    }

    BoolSetting const* FindBoolSetting(std::string const& key)
    {
        for (BoolSetting const& setting : boolSettings)
            if (key == setting.key)
                return &setting;
        return nullptr;
    }


    // What each setting is called and what it does, in one place, so
    // MadosaControl can render a correctly labelled, correctly grouped panel
    // without knowing a single key itself - and a setting added tomorrow shows
    // up there with no client change at all. `group` is the panel it belongs
    // on. A key missing from here still works; it just shows up under its own
    // name in an "Other" group.
    struct SettingText
    {
        char const* key;
        char const* group;
        char const* label;
        char const* help;
    };

    SettingText const settingTexts[] =
    {
        { "professionxp.enable", "Profession XP", "Enabled",
          "Grant XP for every gather or craft attempt that could still raise the skill." },
        { "professionxp.percent", "Profession XP", "XP per attempt (% of level)",
          "As a share of the XP needed for the player's current level, so it stays meaningful at every level." },
        { "professionxp.skillmultiplier", "Profession XP", "Skill-up multiplier",
          "How much more XP an attempt that actually raised the skill is worth." },

        { "professiontools.enable", "Professions", "Hand out gathering tools",
          "Give a player the matching pick, knife or fishing pole the moment they know the profession." },
        { "professionslots.enable", "Professions", "Scroll of Professions",
          "Let the scroll grant a primary profession slot beyond the server's usual limit." },
        { "professionslots.max", "Professions", "Maximum primary professions",
          "The ceiling the scroll can raise a character to." },

        { "autolootpet.enable", "Companions", "Lootbot",
          "The Lootbot companion auto-loots its owner's kills while it is out." },
        { "accountcompanions.enable", "Companions", "Account-wide companions",
          "Once any character learns a Vanity companion, every character on the account knows it." },
        { "instancequestpet.enable", "Companions", "Questbot",
          "Offers every quest of the dungeon you are standing in, all at once." },
        { "repairpet.enable", "Companions", "Repairbot", "Repairs everything you carry, anywhere, for the usual cost." },
        { "mailpet.enable", "Companions", "Mailbot", "Opens your mailbox anywhere." },
        { "omnipet.enable", "Companions", "Omnibot", "One companion offering every service the others do." },

        { "passerbybuff.enable", "Passerby Buffs", "Enabled",
          "Idle playerbots standing near you offer their class buff, the way a friendly player would." },
        { "passerbybuff.radius", "Passerby Buffs", "Radius (yards)", "How close a bot has to be to offer one." },
        { "passerbybuff.priest.fortitude.enable", "Passerby Buffs", "Priest: Fortitude", "" },
        { "passerbybuff.priest.spirit.enable", "Passerby Buffs", "Priest: Divine Spirit", "" },
        { "passerbybuff.mage.intellect.enable", "Passerby Buffs", "Mage: Arcane Intellect", "" },
        { "passerbybuff.druid.markofthewild.enable", "Passerby Buffs", "Druid: Mark of the Wild", "" },
        { "passerbybuff.paladin.kings.enable", "Passerby Buffs", "Paladin: Blessing of Kings", "" },
        { "passerbybuff.paladin.might.enable", "Passerby Buffs", "Paladin: Blessing of Might", "" },
        { "passerbybuff.paladin.wisdom.enable", "Passerby Buffs", "Paladin: Blessing of Wisdom", "" },

        { "worldforged.enable", "Worldforged", "Timed caches",
          "The recurring event: a cache is forged somewhere in the world and its zone announced." },
        { "worldforged.announce", "Worldforged", "Announce the zone",
          "Off means the caches still appear, but nobody is told where to start looking." },
        { "worldforged.interval", "Worldforged", "Forge a cache every (minutes)",
          "How often the timed event hides a new Worldforged Cache somewhere in the world." },
        { "worldforged.lifetime", "Worldforged", "Cache lifetime (minutes)", "How long an unclaimed cache stands." },
        { "worldforged.maxactive", "Worldforged", "Caches at once",
          "Each standing cache keeps a map grid resident for the rest of the uptime, so keep this low." },
        { "worldforged.rarechance", "Worldforged", "Cache holds a rare (%)",
          "Chance that a timed Worldforged Cache rewards a rare instead of a green. This is about the "
          "cache event only - it has nothing to do with what world mobs drop; that is Hardcore PvP's "
          "\"World mob drops dungeon gear\"." },
        { "worldforged.goldperlevel", "Worldforged", "Cache gold per level",
          "Gold in a cache, multiplied by the finder's level." },
        { "worldforged.ascension.enable", "Worldforged", "Ascension's Worldforged",
          "The 3608 fixed spots holding Ascension's own items." },

        { "hardcorepvp.enable", "Hardcore PvP", "Enabled",
          "The whole feature: the Herald, the three risk modes, death chests and world dungeon drops." },
        { "hardcorepvp.warmode.enable", "Hardcore PvP", "Offer War Mode",
          "The middle mode: open-world PvP and bonus experience, with nothing of yours at stake." },
        { "hardcorepvp.warmode.xppercent", "Hardcore PvP", "War Mode bonus XP (%)",
          "Ascension gives War Mode 10% against High-Risk's 15%; the gap is what pays for the risk." },
        { "hardcorepvp.insurance.enable", "Hardcore PvP", "Offer gear insurance",
          "Ascension's High-Risk lets you insure your gear so a death costs gold instead of belongings." },
        { "hardcorepvp.insurance.cost", "Hardcore PvP", "Insurance premium (gold)",
          "Paid up front and covers one death. That same gold is what the killer finds in the chest instead of your bags." },
        { "hardcorepvp.bountychance", "Hardcore PvP", "Bounty: double gold chance (%)",
          "After Ascension's Bounty perk: a chance that a creature's gold is doubled. War Mode and High-Risk both get it." },
        { "hardcorepvp.xppercent", "Hardcore PvP", "High-Risk bonus XP (%)",
          "Multiplies the XP, so it stacks multiplicatively with mod-xpboost rather than adding to it." },
        { "hardcorepvp.minlevel", "Hardcore PvP", "Minimum level",
          "Below this a character cannot enter the mode, and a kill never drops a chest." },
        { "hardcorepvp.togglecooldown", "Hardcore PvP", "Toggle cooldown (minutes)",
          "So the mode cannot be switched off the moment it stops being convenient." },
        { "hardcorepvp.droppercent", "Hardcore PvP", "Bags dropped (%)",
          "Share of the victim's bag stacks that fall. Worn gear, quest items, bags, keys, the Hearthstone and heirlooms never do." },
        { "hardcorepvp.dropmaxitems", "Hardcore PvP", "Most stacks per death",
          "Hard ceiling whatever the percentage works out to. A loot window holds 18." },
        { "hardcorepvp.chestlifetime", "Hardcore PvP", "Chest lifetime (minutes)",
          "It also disappears the moment it is emptied - and whatever is still inside when it goes is mailed back to the victim." },
        { "hardcorepvp.repeatkillcooldown", "Hardcore PvP", "Same-victim cooldown (minutes)",
          "Stops one pair of players farming each other." },
        { "hardcorepvp.dungeondropchance", "Hardcore PvP", "World mob drops dungeon gear (%)",
          "Chance that an ordinary mob out in the world also drops a piece of dungeon or raid gear, "
          "picked for the looter's level rather than the mob's. Requires High-Risk. Not to be confused "
          "with Worldforged's \"Cache holds a rare\", which is about the timed cache event." },
        { "hardcorepvp.dungeondrop.greymobs", "Hardcore PvP", "...including grey mobs",
          "Off means only mobs worth experience can drop. At level 80 everything up to level 71 is grey, which is most of the world - so off makes the drop almost never happen outside Northrend." },
        { "hardcorepvp.botparticipation", "Hardcore PvP", "Playerbots taking part (%)",
          "So there is something to hunt on a realm that is mostly bots. A given bot is consistently in or out, and bots are never traitors." },
        { "hardcorepvp.traitor.enable", "Hardcore PvP", "Allow treason",
          "The second opt-in: traitors are hostile to each other whatever their faction. Hardcore alone never enables friendly fire." },
        { "hardcorepvp.traitor.guardshostile", "Hardcore PvP", "Treason angers your guards",
          "Also turns the traitor's own city factions hostile - which means their vendors and quest givers too." },
    };

    SettingText const* FindSettingText(std::string const& key)
    {
        for (SettingText const& text : settingTexts)
            if (key == text.key)
                return &text;
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

        for (UIntSetting const& setting : uintSettings)
            *setting.slot = sConfigMgr->GetOption<uint32>(setting.configKey, setting.configDefault);

        for (FloatSetting const& setting : floatSettings)
            *setting.slot = sConfigMgr->GetOption<float>(setting.configKey, setting.configDefault);
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
            else if (UIntSetting const* setting = FindUIntSetting(key);
                     setting && ParseUInt(value, u) && u >= setting->min && u <= setting->max)
                *setting->slot = u;
            else if (FloatSetting const* setting = FindFloatSetting(key);
                     setting && ParseFloat(value, f) && f >= setting->min && f <= setting->max)
                *setting->slot = f;
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
    bool GetOmniPetEnable() { return omniPetEnable.load(); }
    bool GetWorldforgedEnable() { return worldforgedEnable.load(); }
    bool GetWorldforgedAnnounce() { return worldforgedAnnounce.load(); }
    // Clamped rather than trusted: a 0 here would forge every tick, or make a
    // cache expire the instant it appears.
    uint32 GetWorldforgedInterval() { return std::max<uint32>(1, worldforgedInterval.load()); }
    uint32 GetWorldforgedLifetime() { return std::max<uint32>(1, worldforgedLifetime.load()); }
    uint32 GetWorldforgedMaxActive() { return std::max<uint32>(1, worldforgedMaxActive.load()); }
    uint32 GetWorldforgedRareChance() { return std::min<uint32>(100, worldforgedRareChance.load()); }
    uint32 GetWorldforgedGoldPerLevel() { return worldforgedGoldPerLevel.load(); }
    bool GetWorldforgedAscensionEnable() { return worldforgedAscensionEnable.load(); }
    bool GetHardcorePvPEnable() { return hardcorePvPEnable.load(); }
    uint32 GetHardcorePvPXPPercent() { return std::min<uint32>(100, hardcorePvPXPPercent.load()); }
    uint32 GetHardcorePvPMinLevel() { return std::max<uint32>(1, hardcorePvPMinLevel.load()); }
    uint32 GetHardcorePvPToggleCooldown() { return hardcorePvPToggleCooldown.load(); }
    bool GetHardcorePvPWarModeEnable() { return hardcorePvPWarModeEnable.load(); }
    uint32 GetHardcorePvPWarModeXPPercent() { return std::min<uint32>(100, hardcorePvPWarModeXPPercent.load()); }
    bool GetHardcorePvPInsuranceEnable() { return hardcorePvPInsuranceEnable.load(); }
    uint32 GetHardcorePvPInsuranceCost() { return std::max<uint32>(1, hardcorePvPInsuranceCost.load()); }
    uint32 GetHardcorePvPBountyChance() { return std::min<uint32>(100, hardcorePvPBountyChance.load()); }
    bool GetHardcorePvPTraitorEnable() { return hardcorePvPTraitorEnable.load(); }
    bool GetHardcorePvPTraitorGuardsHostile() { return hardcorePvPTraitorGuardsHostile.load(); }
    uint32 GetHardcorePvPDropPercent() { return std::min<uint32>(100, hardcorePvPDropPercent.load()); }
    // Clamped rather than trusted: a loot window holds MAX_NR_LOOT_ITEMS, and a
    // drop of nothing would spawn an empty chest.
    uint32 GetHardcorePvPDropMaxItems() { return std::clamp<uint32>(hardcorePvPDropMaxItems.load(), 1, 18); }
    uint32 GetHardcorePvPChestLifetime() { return std::max<uint32>(1, hardcorePvPChestLifetime.load()); }
    uint32 GetHardcorePvPRepeatKillCooldown() { return hardcorePvPRepeatKillCooldown.load(); }
    float GetHardcorePvPDungeonDropChance() { return hardcorePvPDungeonDropChance.load(); }
    bool GetHardcorePvPDungeonDropGreyMobs() { return hardcorePvPDungeonDropGreyMobs.load(); }
    uint32 GetHardcorePvPBotParticipation() { return std::min<uint32>(100, hardcorePvPBotParticipation.load()); }

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
        else if (UIntSetting const* setting = FindUIntSetting(key))
        {
            uint32 u;
            if (!ParseUInt(value, u) || u < setting->min || u > setting->max)
            {
                outError = Acore::StringFormat("value must be a whole number between {} and {}",
                    setting->min, setting->max);
                return false;
            }
            *setting->slot = u;
        }
        else if (FloatSetting const* setting = FindFloatSetting(key))
        {
            float f;
            if (!ParseFloat(value, f) || f < setting->min || f > setting->max)
            {
                outError = Acore::StringFormat("value must be a number between {} and {}",
                    FloatToStr(setting->min), FloatToStr(setting->max));
                return false;
            }
            *setting->slot = f;
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
        if (!FindBoolSetting(key) && !FindUIntSetting(key) && !FindFloatSetting(key))
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
        // Every setting, with everything a panel needs to draw it. Sorted so a
        // feature's settings arrive together and its on/off switch arrives
        // first - MadosaControl builds its category list straight from this
        // order, so the order *is* the layout.
        std::vector<SettingInfo> out;

        auto describe = [](std::string const& key, std::string const& value, char const* type,
                           std::string const& min, std::string const& max)
        {
            SettingInfo info;
            info.key = key;
            info.value = value;
            info.type = type;
            info.min = min;
            info.max = max;

            if (SettingText const* text = FindSettingText(key))
            {
                info.group = text->group;
                info.label = text->label;
                info.help = text->help;
            }
            else
            {
                info.group = "Other";
                info.label = key;
            }

            return info;
        };

        for (BoolSetting const& setting : boolSettings)
            out.push_back(describe(setting.key, BoolToStr(setting.slot->load()), "bool", "0", "1"));

        for (UIntSetting const& setting : uintSettings)
            out.push_back(describe(setting.key, std::to_string(setting.slot->load()), "int",
                std::to_string(setting.min), std::to_string(setting.max)));

        for (FloatSetting const& setting : floatSettings)
            out.push_back(describe(setting.key, FloatToStr(setting.slot->load()), "float",
                FloatToStr(setting.min), FloatToStr(setting.max)));

        std::sort(out.begin(), out.end(), [](SettingInfo const& a, SettingInfo const& b)
        {
            if (a.group != b.group)
                return a.group < b.group;

            // A feature's master switch belongs at the top of its panel, not
            // wherever the alphabet happens to put it.
            bool const aMaster = a.key.size() > 7 && a.key.compare(a.key.size() - 7, 7, ".enable") == 0;
            bool const bMaster = b.key.size() > 7 && b.key.compare(b.key.size() - 7, 7, ".enable") == 0;
            if (aMaster != bMaster)
                return aMaster;

            return a.key < b.key;
        });

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
