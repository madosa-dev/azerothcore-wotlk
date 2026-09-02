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

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <list>
#include <shared_mutex>

namespace
{
    constexpr uint32 SCAN_INTERVAL_MS = 5000;

    // "Rank 4" -> 4. Ranks live in their own spell field, separate from the
    // name, and a buff without one (a single-rank spell) counts as rank 0.
    int RankOf(SpellInfo const* spellInfo)
    {
        char const* rankText = spellInfo ? spellInfo->Rank[LOCALE_enUS] : nullptr;
        if (!rankText)
            return 0;

        size_t digitStart = strcspn(rankText, "0123456789");
        return rankText[digitStart] ? std::atoi(rankText + digitStart) : 0;
    }

    // Finds the highest rank of `name` the bot currently has in its own spellbook
    // (mirrors mod-playerbots' own by-name spell resolution: a bot only ever
    // offers a buff rank it actually knows for its current level).
    uint32 ResolveHighestKnownSpellByName(Player* bot, char const* name, int* outRank = nullptr)
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

            int const rank = RankOf(spellInfo);
            if (rank >= highestRank)
            {
                highestRank = rank;
                highestSpellId = spellId;
            }
        }

        if (outRank)
            *outRank = highestRank;

        return highestSpellId;
    }

    // The group-cast version of each buff. It applies the same thing under a
    // different name and a different rank chain, so a player carrying one must
    // not be offered the single-target version on top of it.
    char const* GroupVersionOf(char const* name)
    {
        struct Pair { char const* single; char const* group; };
        static Pair const pairs[] = {
            { "Power Word: Fortitude", "Prayer of Fortitude" },
            { "Divine Spirit",         "Prayer of Spirit"    },
            { "Arcane Intellect",      "Arcane Brilliance"   },
            { "Mark of the Wild",      "Gift of the Wild"    },
            { "Blessing of Kings",     "Greater Blessing of Kings"  },
            { "Blessing of Wisdom",    "Greater Blessing of Wisdom" },
            { "Blessing of Might",     "Greater Blessing of Might"  },
        };

        for (Pair const& pair : pairs)
            if (StringEqualI(pair.single, name))
                return pair.group;

        return nullptr;
    }

    // Does the target already carry this buff, at *any* rank and from anyone?
    //
    // Comparing spell ids was the bug: every rank of a buff is its own spell id,
    // so a bot that knows rank 4 never saw the rank 7 already on the player -
    // it cast rank 4, which overwrote rank 7, and on the next scan the bot that
    // knows rank 7 saw its own rank missing and cast it back. Two bots of
    // different levels would trade a buff back and forth every five seconds
    // forever, which is exactly what this looked like from the receiving end.
    //
    // Ranks share one spell *name* (the rank lives in a separate field), so
    // comparing names covers every rank at once and needs no chain lookups.
    // Returns the rank already on the target, or -1 for "not buffed at all".
    // The group version counts as unbeatable: it is at least as good as any
    // single-target rank, so replacing it would be a downgrade.
    constexpr int RANK_GROUP_VERSION = 1000;

    int PresentBuffRank(Unit const* target, char const* name)
    {
        char const* group = GroupVersionOf(name);
        int best = -1;

        for (auto const& [spellId, application] : target->GetAppliedAuras())
        {
            if (!application)
                continue;

            SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(spellId);
            if (!spellInfo)
                continue;

            char const* auraName = spellInfo->SpellName[LOCALE_enUS];
            if (!auraName)
                continue;

            if (group && StringEqualI(auraName, group))
                return RANK_GROUP_VERSION;

            if (StringEqualI(auraName, name))
                best = std::max(best, RankOf(spellInfo));
        }

        return best;
    }

    bool TargetAlreadyHasBuff(Unit const* target, char const* name)
    {
        return PresentBuffRank(target, name) >= 0;
    }

    // Casts the bot's own best-known rank of `name` on target if it doesn't already
    // have it. Returns true only once a cast was actually attempted.
    bool TryCastKnownBuff(Player* bot, Player* target, char const* name)
    {
        // Checked before resolving the bot's own spell, and that order matters:
        // reading the target's aura list is a few dozen comparisons, while
        // ResolveHighestKnownSpellByName walks the bot's entire spellbook. The
        // common case by far is "already buffed", so the cheap test goes first.
        int const present = PresentBuffRank(target, name);
        if (present >= RANK_GROUP_VERSION)
            return false;

        int botRank = -1;
        uint32 spellId = ResolveHighestKnownSpellByName(bot, name, &botRank);
        if (!spellId || bot->HasSpellCooldown(spellId))
            return false;

        // Strictly better only. A buff already there is left alone unless this
        // bot knows a higher rank - which stops the constant re-casting and
        // still lets a passing level 70 upgrade what a level 20 handed out.
        // Because the rank can only ever go up, this terminates; the old
        // "is my own exact spell id missing?" test never could.
        if (botRank <= present)
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
                    if (blessing.enabled && TargetAlreadyHasBuff(target, blessing.name))
                        return; // already blessed with an enabled blessing - leave it alone

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
