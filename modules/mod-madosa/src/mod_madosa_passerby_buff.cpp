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

// "Passerby buff": random/idle playerbots that are NOT in a real player's group
// give that player their signature buff when standing nearby, the way a friendly
// player might in trade chat. Only classes with a genuine single-target buff that
// WotLK lets you cast on someone outside your own group are eligible - Battle
// Shout, Aspects, Auras and totems only affect the caster's own party/raid, so
// Warrior/Hunter/Shaman/Warlock/Death Knight/Rogue have nothing to offer here.
//
// Deliberately implemented as a periodic scan from the real player's side (cheap:
// there are only ever a handful of real players, however many thousand bots are
// populating the world) instead of hooking into mod-playerbots' own AI/strategy
// system - that keeps this module's only dependency on mod-playerbots down to the
// public GET_PLAYERBOT_AI() bot-detection macro, so `git fetch upstream` on
// mod-playerbots never conflicts with anything here.

#include "mod_madosa_settings.h"

#include "Cell.h"
#include "CellImpl.h"
#include "GridNotifiers.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "Playerbots.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "SpellMgr.h"
#include "Util.h"

#include <cstdlib>
#include <cstring>
#include <list>
#include <shared_mutex>

namespace
{
    constexpr uint32 SCAN_INTERVAL_MS = 5000;

    // Finds the highest rank of `name` the bot currently has in its own spellbook
    // (mirrors mod-playerbots' own by-name spell resolution: a bot only ever
    // offers a buff rank it actually knows for its current level).
    uint32 ResolveHighestKnownSpellByName(Player* bot, char const* name)
    {
        uint32 highestSpellId = 0;
        int highestRank = -1;

        for (auto const& [spellId, playerSpell] : bot->GetSpellMap())
        {
            if (playerSpell->State == PLAYERSPELL_REMOVED || !playerSpell->Active)
                continue;

            SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(spellId);
            if (!spellInfo || spellInfo->IsPassive())
                continue;

            char const* spellName = spellInfo->SpellName[LOCALE_enUS];
            if (!spellName || !StringEqualI(spellName, name))
                continue;

            char const* rankText = spellInfo->Rank[LOCALE_enUS];
            size_t digitStart = rankText ? strcspn(rankText, "0123456789") : 0;
            int rank = (rankText && rankText[digitStart]) ? std::atoi(rankText + digitStart) : 0;

            if (rank >= highestRank)
            {
                highestRank = rank;
                highestSpellId = spellId;
            }
        }

        return highestSpellId;
    }

    // Casts the bot's own best-known rank of `name` on target if it doesn't already
    // have it. Returns true only once a cast was actually attempted.
    bool TryCastKnownBuff(Player* bot, Player* target, char const* name)
    {
        uint32 spellId = ResolveHighestKnownSpellByName(bot, name);
        if (!spellId || target->HasAura(spellId) || bot->HasSpellCooldown(spellId))
            return false;

        bot->CastSpell(target, spellId, false);
        return true;
    }

    void BuffPasserbyFrom(Player* bot, Player* target)
    {
        switch (bot->getClass())
        {
            case CLASS_PRIEST:
                if (MadosaSettings::GetPasserbyBuffPriestFortitudeEnable())
                    TryCastKnownBuff(bot, target, "Power Word: Fortitude");
                if (MadosaSettings::GetPasserbyBuffPriestSpiritEnable())
                    TryCastKnownBuff(bot, target, "Divine Spirit");
                break;

            case CLASS_MAGE:
                if (MadosaSettings::GetPasserbyBuffMageIntellectEnable())
                    TryCastKnownBuff(bot, target, "Arcane Intellect");
                break;

            case CLASS_DRUID:
                if (MadosaSettings::GetPasserbyBuffDruidMarkOfTheWildEnable())
                    TryCastKnownBuff(bot, target, "Mark of the Wild");
                break;

            case CLASS_PALADIN:
            {
                // Blessings share one aura slot: casting a second one just overwrites the
                // first, so re-check every scan would thrash between them forever if two
                // bots (or two enabled blessings) disagreed. Skip entirely once the target
                // already carries any blessing this bot is configured to offer, and
                // otherwise only ever attempt the highest-priority enabled one.
                struct Blessing { bool enabled; char const* name; };
                Blessing const blessings[] = {
                    { MadosaSettings::GetPasserbyBuffPaladinKingsEnable(),  "Blessing of Kings"  },
                    { MadosaSettings::GetPasserbyBuffPaladinWisdomEnable(), "Blessing of Wisdom" },
                    { MadosaSettings::GetPasserbyBuffPaladinMightEnable(),  "Blessing of Might"  },
                };

                for (Blessing const& blessing : blessings)
                {
                    if (!blessing.enabled)
                        continue;

                    uint32 spellId = ResolveHighestKnownSpellByName(bot, blessing.name);
                    if (spellId && target->HasAura(spellId))
                        return; // already blessed with an enabled blessing - leave it alone
                }

                for (Blessing const& blessing : blessings)
                    if (blessing.enabled && TryCastKnownBuff(bot, target, blessing.name))
                        break;
                break;
            }

            default:
                break; // no viable stranger buff for this class
        }
    }

    void ScanForPasserbyBuffs()
    {
        if (!MadosaSettings::GetPasserbyBuffEnable())
            return;

        float radius = MadosaSettings::GetPasserbyBuffRadius();

        std::shared_lock<std::shared_mutex> lock(*HashMapHolder<Player>::GetLock());
        for (auto const& [guid, player] : ObjectAccessor::GetPlayers())
        {
            if (!player->IsInWorld() || !player->IsAlive() || GET_PLAYERBOT_AI(player))
                continue; // only real, active players are buffed here

            std::list<Player*> nearby;
            Acore::AnyPlayerInObjectRangeCheck checker(player, radius);
            Acore::PlayerListSearcher<Acore::AnyPlayerInObjectRangeCheck> searcher(player, nearby, checker);
            Cell::VisitObjects(player, searcher, radius);

            for (Player* bot : nearby)
            {
                if (bot == player || bot->GetTeamId() != player->GetTeamId())
                    continue;

                if (!GET_PLAYERBOT_AI(bot))
                    continue; // stranger buffs only ever come from bots

                if (bot->IsInSameGroupWith(player))
                    continue; // grouped bots already buff normally

                BuffPasserbyFrom(bot, player);
            }
        }
    }
}

class mod_madosa_passerby_buff : public WorldScript
{
    uint32 _timer = 0;

public:
    mod_madosa_passerby_buff() : WorldScript("mod_madosa_passerby_buff") { }

    void OnUpdate(uint32 diff) override
    {
        _timer += diff;
        if (_timer < SCAN_INTERVAL_MS)
            return;

        _timer = 0;
        ScanForPasserbyBuffs();
    }
};

void AddSC_madosa_passerby_buff()
{
    new mod_madosa_passerby_buff();
}
