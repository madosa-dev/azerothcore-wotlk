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

// The second half of Hardcore PvP (mod_madosa_hardcore_pvp.cpp): while the
// mode is on, an ordinary mob out in the world may drop a piece of gear that
// normally only exists inside a dungeon or a raid.
//
// Where the item pool comes from
// ------------------------------
// Nothing is hand-listed. At startup the loot tables are asked which items
// drop off creatures that are actually spawned inside an instance map -
// creature_loot_template (and the reference table it points at) joined against
// where those creatures stand, checked against Map.dbc through sMapStore,
// the same way mod_madosa_instance_quest_pet.cpp works out which quests belong
// to which instance. So the pool follows the database: add a dungeon, and its
// loot is in here after the next restart.
//
// Scaled to the looter, not to the mob
// ------------------------------------
// Same principle as Worldforged: one pool serves every level because the item
// is chosen for the player holding the loot window, never for what died. A
// level 24 character gets level 24 dungeon gear off a boar, and a find is
// always something they can actually equip.
//
// Why OnPlayerBeforeSendLoot
// --------------------------
// It is the one hook that runs after the creature's own loot has been rolled
// and before the packet is built (Player.cpp:8369), so the extra item can be
// appended to a finished loot. Rolling in a kill hook instead would mean
// guessing at loot that does not exist yet.

#include "mod_madosa_hardcore_pvp.h"
#include "mod_madosa_settings.h"

#include "Chat.h"
#include "Creature.h"
#include "DBCStores.h"
#include "GameTime.h"
#include "Log.h"
#include "LootMgr.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "SpellMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldDatabase.h"

#include <algorithm>
#include <array>
#include <iterator>
#include <mutex>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    constexpr uint32 PRUNE_INTERVAL_MS = 60000;

    // A corpse's loot is rolled once, but SendLoot runs again every time the
    // window is reopened, so a guid already rolled for is remembered until the
    // entry is pruned.
    constexpr uint32 ROLL_MEMORY_SECONDS = 600;

    // Below uncommon there is nothing worth calling a dungeon drop.
    constexpr uint32 MIN_QUALITY = ITEM_QUALITY_UNCOMMON;

    // The level bands, and the whole point of them: a player can see which
    // dungeons they are currently pulling gear from, and watch it move on as
    // they level - the thing Ascension's High-Risk does with an aura.
    //
    // This table is the *rule*, not a label for one. The band decides which
    // items may drop and which aura is worn, so the tooltip cannot promise a
    // tier the roll does not use. Change a boundary here and both follow.
    //
    // Spell ids 900010-900017 are built by tools/clientpatch/build_patches.py
    // from the same boundaries.
    struct LootBand
    {
        uint8 min;
        uint8 max;
        uint32 spellId;
    };

    constexpr std::array<LootBand, 8> LOOT_BANDS =
    {{
        {  1, 19, 900010 },
        { 20, 29, 900011 },
        { 30, 39, 900012 },
        { 40, 49, 900013 },
        { 50, 59, 900014 },
        { 60, 69, 900015 },
        { 70, 79, 900016 },
        { 80, 80, 900017 },
    }};

    LootBand const* BandFor(uint8 level)
    {
        for (LootBand const& band : LOOT_BANDS)
            if (level >= band.min && level <= band.max)
                return &band;
        return nullptr;
    }

    // byLevel[requiredLevel] - the instance items a character of exactly that
    // level may equip. Immutable after startup.
    std::array<std::vector<uint32>, DEFAULT_MAX_LEVEL + 1> byLevel;
    uint32 pooledItems = 0;

    std::unordered_map<ObjectGuid, time_t> rolled;
    std::mutex rolledMutex;

    bool IsInstanceMap(uint32 mapId)
    {
        MapEntry const* map = sMapStore.LookupEntry(mapId);
        return map && (map->IsDungeon() || map->IsRaid());
    }

    // Weapons and armour only: a dungeon's cloth, ore and quest debris is not
    // what "a raid item dropped in the open world" is meant to mean.
    bool IsWorthDropping(ItemTemplate const* proto)
    {
        if (!proto)
            return false;

        if (proto->Class != ITEM_CLASS_WEAPON && proto->Class != ITEM_CLASS_ARMOR)
            return false;

        if (proto->Quality < MIN_QUALITY || proto->Quality > ITEM_QUALITY_EPIC)
            return false;

        // RequiredLevel is what decides whether the finder can use it, so an
        // item that does not state one has no place in a level-indexed pool.
        if (!proto->RequiredLevel || proto->RequiredLevel > DEFAULT_MAX_LEVEL)
            return false;

        if (proto->Bonding == BIND_QUEST_ITEM || proto->HasFlag(ITEM_FLAG_NO_USER_DESTROY))
            return false;

        return true;
    }

    void LoadPool()
    {
        // Both halves of a creature's loot table in one pass: the items listed
        // against it directly, and the ones it pulls in by reference. Anything
        // deeper (a reference to a reference) is not chased - the pool is a
        // sample of what instances hold, not an inventory of it.
        QueryResult result = WorldDatabase.Query(
            "SELECT DISTINCT lt.Item, c.map "
            "FROM creature_loot_template lt "
            "JOIN creature_template ct ON ct.lootid = lt.Entry "
            "JOIN creature c ON c.id = ct.entry "
            "WHERE lt.Reference = 0 AND lt.Item > 0 "
            "UNION "
            "SELECT DISTINCT rt.Item, c.map "
            "FROM creature_loot_template lt "
            "JOIN reference_loot_template rt ON rt.Entry = lt.Reference "
            "JOIN creature_template ct ON ct.lootid = lt.Entry "
            "JOIN creature c ON c.id = ct.entry "
            "WHERE lt.Reference > 0 AND rt.Item > 0");

        if (!result)
        {
            LOG_ERROR("module", "mod-madosa: Hardcore PvP found no creature loot at all - "
                "world drops will not happen.");
            return;
        }

        std::unordered_set<uint32> seen;
        do
        {
            Field* fields = result->Fetch();
            uint32 const item = fields[0].Get<uint32>();
            uint32 const mapId = fields[1].Get<uint32>();

            if (!IsInstanceMap(mapId) || !seen.insert(item).second)
                continue;

            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item);
            if (!IsWorthDropping(proto))
                continue;

            byLevel[proto->RequiredLevel].push_back(item);
            ++pooledItems;
        } while (result->NextRow());

        LOG_INFO("module", "mod-madosa: Hardcore PvP world drops loaded {} instance item(s).", pooledItems);
    }

    // Everything in the player's band that they can equip right now - so the
    // top of the band opens up as they grow into it, and a find is never a
    // piece they have to carry around until later.
    //
    // Crossing into a new band narrows the pool to its first level for a while;
    // that is the band change being felt rather than a defect, and even the
    // thinnest first level of a band carries a few dozen items in this
    // database.
    uint32 PickItem(uint8 level)
    {
        if (!level || level > DEFAULT_MAX_LEVEL)
            return 0;

        LootBand const* band = BandFor(level);
        if (!band)
            return 0;

        uint32 const highest = std::min<uint32>(band->max, level);

        uint32 total = 0;
        for (uint32 required = band->min; required <= highest; ++required)
            total += uint32(byLevel[required].size());

        if (!total)
            return 0;

        uint32 roll = urand(0, total - 1);
        for (uint32 required = band->min; required <= highest; ++required)
        {
            if (roll < byLevel[required].size())
                return byLevel[required][roll];

            roll -= uint32(byLevel[required].size());
        }

        return 0;
    }

    bool AlreadyRolled(ObjectGuid guid)
    {
        std::lock_guard<std::mutex> lock(rolledMutex);
        time_t const now = GameTime::GetGameTime().count();
        auto itr = rolled.find(guid);
        if (itr != rolled.end() && now < itr->second)
            return true;

        rolled[guid] = now + ROLL_MEMORY_SECONDS;
        return false;
    }

    void PruneRolled()
    {
        time_t const now = GameTime::GetGameTime().count();
        std::lock_guard<std::mutex> lock(rolledMutex);
        for (auto itr = rolled.begin(); itr != rolled.end();)
            itr = now >= itr->second ? rolled.erase(itr) : std::next(itr);
    }
}

namespace MadosaHardcorePvP
{
    void UpdateLootBandAura(Player* player, bool hardcore)
    {
        // Bots never wear it: unlike the Hardcore mark, which exists so other
        // players can read a target, this one is the player's own information.
        if (!player || IsBot(player))
            return;

        // Nothing to promise if the pool never loaded or the drop is switched
        // off - a tooltip must not describe a drop that cannot happen.
        bool const active = hardcore && pooledItems
            && MadosaSettings::GetHardcorePvPEnable()
            && MadosaSettings::GetHardcorePvPDungeonDropChance() > 0.0f;

        LootBand const* wanted = active ? BandFor(player->GetLevel()) : nullptr;

        for (LootBand const& band : LOOT_BANDS)
            if ((!wanted || band.spellId != wanted->spellId) && player->HasAura(band.spellId))
                player->RemoveAurasDueToSpell(band.spellId);

        if (!wanted || player->HasAura(wanted->spellId))
            return;

        // Missing only means the client patch has not been rebuilt since these
        // were added; the drops themselves do not depend on the aura.
        if (!sSpellMgr->GetSpellInfo(wanted->spellId))
            return;

        player->AddAura(wanted->spellId, player);
    }
}

class mod_madosa_hardcore_pvp_loot_player : public PlayerScript
{
public:
    mod_madosa_hardcore_pvp_loot_player() : PlayerScript("mod_madosa_hardcore_pvp_loot_player",
        { PLAYERHOOK_ON_BEFORE_SEND_LOOT, PLAYERHOOK_ON_LEVEL_CHANGED, PLAYERHOOK_ON_BEFORE_LOOT_MONEY }) { }

    // Ascension's Bounty perk (83284-83286): "You have a X% chance to double a
    // creature's gold." Both flagged modes get it - it is the one reward War
    // Mode has of its own, standing in for the crafting materials Ascension
    // gives it and this realm has no equivalent for.
    void OnPlayerBeforeLootMoney(Player* player, Loot* loot) override
    {
        if (!loot || !loot->gold || !MadosaSettings::GetHardcorePvPEnable())
            return;

        uint32 const chance = MadosaSettings::GetHardcorePvPBountyChance();
        if (!chance || !MadosaHardcorePvP::IsFlagged(player) || MadosaHardcorePvP::IsBot(player))
            return;

        // Only what a creature was carrying. A chest, a fishing pool or another
        // player's death chest is not a bounty.
        if (!loot->sourceWorldObjectGUID.IsCreature())
            return;

        if (!roll_chance_i(int32(chance)))
            return;

        loot->gold *= 2;
        ChatHandler(player->GetSession()).PSendSysMessage("Bounty: the purse is heavier than it looked.");
    }

    // Levelling is the only thing that moves a player between bands; logging in
    // and toggling the mode both go through ApplyMarks, which calls the same
    // function.
    void OnPlayerLevelChanged(Player* player, uint8 /*oldLevel*/) override
    {
        MadosaHardcorePvP::UpdateLootBandAura(player, MadosaHardcorePvP::IsHighRisk(player));
    }

    void OnPlayerBeforeSendLoot(Player* player, ObjectGuid lootGuid, Loot* loot) override
    {
        if (!loot || !pooledItems || !MadosaSettings::GetHardcorePvPEnable())
            return;

        float const chance = MadosaSettings::GetHardcorePvPDungeonDropChance();
        if (chance <= 0.0f)
            return;

        if (!lootGuid.IsCreature() || !MadosaHardcorePvP::IsHighRisk(player))
            return;

        // Bots are in the mode so that there is something worth fighting, not
        // so they can farm gear nobody will ever see. A real player running the
        // self-bot AI is still a real player, which is why this asks the
        // session rather than GET_PLAYERBOT_AI.
        if (MadosaHardcorePvP::IsBot(player))
            return;

        Map* map = player->GetMap();
        if (!map || map->Instanceable())
            return;   // inside a dungeon the real loot table is already doing this

        Creature* creature = ObjectAccessor::GetCreature(*player, lootGuid);
        if (!creature)
            return;

        // Never from a critter, a totem, a pet or anything flagged to give no
        // experience: those are scenery, not a hunt.
        if (creature->IsTotem() || creature->IsCritter() || creature->IsPet()
            || creature->HasFlagsExtra(CREATURE_FLAG_EXTRA_NO_XP))
            return;

        // The grey-level rule is a setting, and it has to be, because it is far
        // sharper than it sounds: Player::isHonorOrXPTarget() calls everything
        // at or below GetGrayLevel() worthless, and at level 80 that is every
        // mob up to level 71 - which is most of the world outside Northrend. A
        // max-level character with this on would see nothing drop at any
        // percentage, which is exactly how this was first reported.
        //
        // The cost of allowing them is real and worth stating: the reward is
        // picked for the *looter's* level, so mass-killing trivial mobs farms
        // current-tier gear. The drop chance is the throttle for that.
        if (!MadosaSettings::GetHardcorePvPDungeonDropGreyMobs() && !player->isHonorOrXPTarget(creature))
            return;

        if (loot->items.size() >= MAX_NR_LOOT_ITEMS)
            return;

        if (!roll_chance_f(chance))
            return;

        // Remembered only once the roll has succeeded: a corpse whose roll
        // failed never mattered, and this keeps the map down to the corpses
        // that actually paid out.
        if (AlreadyRolled(lootGuid))
            return;

        uint32 const item = PickItem(player->GetLevel());
        if (!item)
            return;

        LootStoreItem storeItem(item, 0, 100.0f, false, LOOT_MODE_DEFAULT, 0, 1, 1);
        LootItem generated(storeItem);   // rolls its own random property, as a real drop would

        // The count has to be set by hand, and forgetting it is silent: the
        // LootItem constructor leaves it at 0 and it is Loot::AddItem() - which
        // this deliberately does not use - that fills it in from the store
        // item's min/max afterwards. A zero-count entry is drawn in the loot
        // window like any other and then cannot be taken, because storing zero
        // of something fails without a message. "I can see it but not loot it"
        // is exactly what that looks like.
        generated.count = 1;
        generated.itemIndex = loot->items.size();
        loot->items.push_back(generated);
        ++loot->unlootedCount;

        ChatHandler(player->GetSession()).PSendSysMessage(
            "Something that has no business out here fell with it.");
    }
};

class mod_madosa_hardcore_pvp_loot_world : public WorldScript
{
    uint32 _timer = 0;

public:
    mod_madosa_hardcore_pvp_loot_world() : WorldScript("mod_madosa_hardcore_pvp_loot_world") { }

    void OnStartup() override
    {
        LoadPool();
    }

    void OnUpdate(uint32 diff) override
    {
        _timer += diff;
        if (_timer < PRUNE_INTERVAL_MS)
            return;

        _timer = 0;
        PruneRolled();
    }
};

void AddSC_madosa_hardcore_pvp_loot()
{
    new mod_madosa_hardcore_pvp_loot_player();
    new mod_madosa_hardcore_pvp_loot_world();
}
