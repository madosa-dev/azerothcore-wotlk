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

// "Worldforged": every so often the server forges a Worldforged Cache at one of
// the spots in mod_madosa_worldforged_spawns, announces the zone to everyone
// online, and whoever gets there first opens it for a randomly enchanted piece
// of gear scaled to their own level. Inspired by Ascension WoW's Worldforged
// drops and the community LootCollector addon that shares their locations.
//
// Three decisions are worth knowing before reading the code:
//
// * **Only real players may open a cache.** This realm runs ~3000 playerbots;
//   without the check a bot would wander past and claim nearly every one of
//   them, and the event would exist only in the announcements. Same
//   GET_PLAYERBOT_AI() bot-detection macro the passerby buff uses, and for the
//   same reason: it is the entire coupling to mod-playerbots' internals.
//
// * **A cache is only forged while a real player is online**, and its spot is
//   picked to suit the level of one of them. Forging into an empty world would
//   just burn a spawn and keep a grid resident for nobody.
//
// * **The reward is scaled to whoever opens it, not to where it spawned.** That
//   is what lets one world-wide spawn table serve every level: the spawn point's
//   level band only decides *where* a cache lands, never what is inside.
//
// The cache object is a GOOBER, not a CHEST, even though it looks like one -
// see the header comment in data/sql/db-world/base/worldforged.sql for why that
// is forced on us by which opcode the client sends.

#include "mod_madosa_worldforged.h"

#include "mod_madosa_settings.h"

#include "Chat.h"
#include "DBCStores.h"
#include "GameObject.h"
#include "GameTime.h"
#include "Item.h"
#include "Log.h"
#include "MapMgr.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Playerbots.h"
#include "Random.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "StringFormat.h"
#include "WorldDatabase.h"

#include <algorithm>
#include <mutex>
#include <shared_mutex>

namespace
{
    constexpr uint32 CACHE_GO_ENTRY = 900400;

    // The forge only ever has to notice that a minute-scale interval elapsed, so
    // half a minute of granularity is plenty and keeps this off the hot path.
    constexpr uint32 TICK_INTERVAL_MS = 30 * IN_MILLISECONDS;

    // How far below the finder's level a reward may be. Wide enough that every
    // level has a real pool to draw from, narrow enough that the item is still
    // worth equipping.
    constexpr uint8 REWARD_LEVEL_WINDOW = 8;

    // How far a spawn point's own level band may miss the player's level before
    // it stops being a sensible place to send them. Two widening steps, then any
    // point at all - see PickSpawnPoint().
    constexpr uint8 SPAWN_LEVEL_SLACK = 5;
    constexpr uint8 SPAWN_LEVEL_SLACK_WIDE = 15;

    struct SpawnPoint
    {
        uint32 id;
        uint32 map;
        float x;
        float y;
        float z;
        float o;
        uint8 minLevel;
        uint8 maxLevel;
    };

    struct RewardItem
    {
        uint32 entry;
        uint8 requiredLevel;
    };

    struct ActiveCache
    {
        ObjectGuid guid;
        uint32 mapId;
        time_t expiry;
        std::string zoneName;
    };

    // Written once at startup, read-only afterwards - no lock needed.
    std::vector<SpawnPoint> spawnPoints;
    std::vector<RewardItem> greenPool; // both sorted by requiredLevel ascending
    std::vector<RewardItem> rarePool;

    // Touched from the world thread (the forge/expiry tick) and from a map
    // thread (a player opening a cache), so it needs a lock. Everything else
    // here is either immutable or thread-local to one of those two.
    std::mutex activeCachesMutex;
    std::vector<ActiveCache> activeCaches;

    time_t nextForgeTime = 0;

    // -----------------------------------------------------------------------
    // Startup data
    // -----------------------------------------------------------------------

    void LoadSpawnPoints()
    {
        spawnPoints.clear();

        QueryResult result = WorldDatabase.Query(
            "SELECT id, map, position_x, position_y, position_z, orientation, min_level, max_level "
            "FROM mod_madosa_worldforged_spawns");
        if (!result)
        {
            LOG_WARN("module", "mod-madosa: Worldforged has no spawn points - the event stays idle.");
            return;
        }

        do
        {
            Field* fields = result->Fetch();
            SpawnPoint point;
            point.id = fields[0].Get<uint32>();
            point.map = fields[1].Get<uint16>();
            point.x = fields[2].Get<float>();
            point.y = fields[3].Get<float>();
            point.z = fields[4].Get<float>();
            point.o = fields[5].Get<float>();
            point.minLevel = fields[6].Get<uint8>();
            point.maxLevel = fields[7].Get<uint8>();

            // A spawn point on a map this server does not have extracted would
            // fail at CreateBaseMap() every single time it was drawn, silently
            // eating a forge, so drop it here instead.
            if (!sMapStore.LookupEntry(point.map))
            {
                LOG_WARN("module", "mod-madosa: Worldforged spawn point {} names unknown map {} - skipped.",
                    point.id, point.map);
                continue;
            }

            spawnPoints.push_back(point);
        } while (result->NextRow());

        LOG_INFO("module", "mod-madosa: Worldforged loaded {} spawn points.", spawnPoints.size());
    }

    void LoadRewardPool()
    {
        greenPool.clear();
        rarePool.clear();

        // Only templates that set exactly one of RandomProperty/RandomSuffix can
        // be forged at all: Item::GenerateItemRandomPropertyId() returns 0 for
        // everything else, which would hand out a plain, unenchanted item. The
        // name filters drop the developer leftovers that share the item id space
        // with real gear.
        QueryResult result = WorldDatabase.Query(
            "SELECT entry, Quality, RequiredLevel FROM item_template "
            "WHERE class IN (2, 4) AND Quality IN (2, 3) "
            "AND ((RandomProperty <> 0) XOR (RandomSuffix <> 0)) "
            "AND RequiredLevel BETWEEN 1 AND 80 AND ItemLevel > 0 "
            "AND name NOT LIKE '%(OLD)%' AND name NOT LIKE '%TEST%' "
            "AND name NOT LIKE '%Monster%' AND name NOT LIKE '%QA%' "
            "ORDER BY RequiredLevel");
        if (!result)
        {
            LOG_WARN("module", "mod-madosa: Worldforged found no forgeable items - the event stays idle.");
            return;
        }

        do
        {
            Field* fields = result->Fetch();
            RewardItem item;
            item.entry = fields[0].Get<uint32>();
            uint32 quality = fields[1].Get<uint8>();
            item.requiredLevel = fields[2].Get<uint8>();

            // Guard against the template vanishing between the query and use:
            // GetItemTemplate() is what every later step reads from.
            if (!sObjectMgr->GetItemTemplate(item.entry))
                continue;

            (quality == ITEM_QUALITY_RARE ? rarePool : greenPool).push_back(item);
        } while (result->NextRow());

        LOG_INFO("module", "mod-madosa: Worldforged loaded {} uncommon and {} rare forgeable items.",
            greenPool.size(), rarePool.size());
    }

    // -----------------------------------------------------------------------
    // Picking what and where
    // -----------------------------------------------------------------------

    // Items in [level - REWARD_LEVEL_WINDOW, level], widening downwards when
    // that window is empty. Both pools are sorted by requiredLevel, so this is
    // two binary searches rather than a scan of a few thousand entries.
    //
    // allowOverlevel decides what happens when the whole pool sits above the
    // player: the rare pool starts at requiredLevel 20, so asking it for a level
    // 12 character has to come back empty (false) and let the caller fall back
    // to a green - handing out an item usable in eight levels' time would be a
    // worse find than a green they can wear now. The green pool, as the last
    // resort, does hand out its lowest item (true), because a level 1-4
    // character would otherwise open a cache and get nothing at all.
    RewardItem const* PickReward(std::vector<RewardItem> const& pool, uint8 level, bool allowOverlevel)
    {
        if (pool.empty())
            return nullptr;

        auto byLevel = [](RewardItem const& item, uint8 value) { return item.requiredLevel < value; };
        auto upperBound = std::upper_bound(pool.begin(), pool.end(), level,
            [](uint8 value, RewardItem const& item) { return value < item.requiredLevel; });

        if (upperBound == pool.begin())
        {
            if (!allowOverlevel)
                return nullptr;

            uint8 lowest = pool.front().requiredLevel;
            auto lowestEnd = std::upper_bound(pool.begin(), pool.end(), lowest,
                [](uint8 value, RewardItem const& item) { return value < item.requiredLevel; });
            return &pool[urand(0, static_cast<uint32>(std::distance(pool.begin(), lowestEnd)) - 1)];
        }

        uint8 floorLevel = level > REWARD_LEVEL_WINDOW ? level - REWARD_LEVEL_WINDOW : 1;
        auto lowerBound = std::lower_bound(pool.begin(), pool.end(), floorLevel, byLevel);
        if (lowerBound == upperBound)
            lowerBound = pool.begin(); // nothing in the window: allow anything usable

        auto count = static_cast<uint32>(std::distance(lowerBound, upperBound));
        return &*(lowerBound + urand(0, count - 1));
    }

    // Spawn points whose own level band is within `slack` of the player's level.
    std::vector<SpawnPoint const*> PointsNear(uint8 level, uint8 slack)
    {
        std::vector<SpawnPoint const*> matches;
        for (SpawnPoint const& point : spawnPoints)
        {
            int32 low = static_cast<int32>(point.minLevel) - slack;
            int32 high = static_cast<int32>(point.maxLevel) + slack;
            if (static_cast<int32>(level) >= low && static_cast<int32>(level) <= high)
                matches.push_back(&point);
        }
        return matches;
    }

    SpawnPoint const* PickSpawnPoint(uint8 level)
    {
        if (spawnPoints.empty())
            return nullptr;

        for (uint8 slack : { SPAWN_LEVEL_SLACK, SPAWN_LEVEL_SLACK_WIDE })
            if (std::vector<SpawnPoint const*> matches = PointsNear(level, slack); !matches.empty())
                return matches[urand(0, static_cast<uint32>(matches.size()) - 1)];

        // No band comes close - send them somewhere anyway rather than skipping
        // the event entirely.
        return &spawnPoints[urand(0, static_cast<uint32>(spawnPoints.size()) - 1)];
    }

    // -----------------------------------------------------------------------
    // Talking to the realm
    // -----------------------------------------------------------------------

    // Bots hold sessions too, and there are thousands of them, so an announcement
    // that went through the usual world-broadcast helpers would build and send
    // thousands of packets nobody reads. Walking the player list and skipping
    // bots costs one comparison each instead.
    void AnnounceToRealPlayers(std::string const& message)
    {
        std::shared_lock<std::shared_mutex> lock(*HashMapHolder<Player>::GetLock());
        for (auto const& [guid, player] : ObjectAccessor::GetPlayers())
        {
            if (!player->IsInWorld() || GET_PLAYERBOT_AI(player) || !player->GetSession())
                continue;

            ChatHandler(player->GetSession()).PSendSysMessage("{}", message);
        }
    }

    // The levels of every real player currently in the world. Both the "is
    // anyone there?" gate and the choice of where to forge come from this.
    std::vector<uint8> OnlineRealPlayerLevels()
    {
        std::vector<uint8> levels;
        std::shared_lock<std::shared_mutex> lock(*HashMapHolder<Player>::GetLock());
        for (auto const& [guid, player] : ObjectAccessor::GetPlayers())
            if (player->IsInWorld() && !GET_PLAYERBOT_AI(player))
                levels.push_back(player->GetLevel());

        return levels;
    }

    std::string ZoneNameAt(Map* map, float x, float y, float z)
    {
        uint32 zoneId = 0;
        uint32 areaId = 0;
        map->GetZoneAndAreaId(PHASEMASK_NORMAL, zoneId, areaId, x, y, z);

        if (AreaTableEntry const* zone = sAreaTableStore.LookupEntry(zoneId))
            if (char const* name = zone->area_name[DEFAULT_LOCALE])
                return name;

        // Unnamed or unmapped spot: name the continent instead of announcing a
        // cache "somewhere", which would be unsearchable.
        if (MapEntry const* mapEntry = sMapStore.LookupEntry(map->GetId()))
            if (char const* name = mapEntry->name[DEFAULT_LOCALE])
                return name;

        return "parts unknown";
    }

    // |cAARRGGBB|Hitem:id:enchant:gem1:gem2:gem3:0:randomPropertyId:suffixFactor:level|h[Name Suffix]|h|r
    // The field order and the "<name> <suffix>" text are what the client's own
    // link parser expects (see HyperlinkTags.cpp) - get either wrong and the
    // link renders as plain text or is rejected when a player links it onward.
    std::string ItemLink(Item const* item)
    {
        ItemTemplate const* proto = item->GetTemplate();
        int32 randomPropertyId = item->GetItemRandomPropertyId();

        std::string name = proto->Name1;
        if (randomPropertyId < 0)
        {
            if (ItemRandomSuffixEntry const* suffix = sItemRandomSuffixStore.LookupEntry(-randomPropertyId))
                if (char const* suffixName = suffix->Name[DEFAULT_LOCALE])
                    name += Acore::StringFormat(" {}", suffixName);
        }
        else if (randomPropertyId > 0)
        {
            if (ItemRandomPropertiesEntry const* property = sItemRandomPropertiesStore.LookupEntry(randomPropertyId))
                if (char const* propertyName = property->Name[DEFAULT_LOCALE])
                    name += Acore::StringFormat(" {}", propertyName);
        }

        return Acore::StringFormat("|c{:08x}|Hitem:{}:0:0:0:0:0:{}:{}:{}|h[{}]|h|r",
            ItemQualityColors[proto->Quality], proto->ItemId, randomPropertyId,
            item->GetItemSuffixFactor(), item->GetOwner() ? item->GetOwner()->GetLevel() : 0, name);
    }

    // -----------------------------------------------------------------------
    // Forging and expiring
    // -----------------------------------------------------------------------

    bool ForgeCache(std::string& outError)
    {
        if (spawnPoints.empty() || (greenPool.empty() && rarePool.empty()))
        {
            outError = "no spawn points or no forgeable items loaded";
            return false;
        }

        std::vector<uint8> levels = OnlineRealPlayerLevels();
        if (levels.empty())
        {
            outError = "no real player is online to forge for";
            return false;
        }

        // Pick one online player's level rather than an average: with several
        // players online this rotates fairly between them over time, where an
        // average would keep landing in a band that suits nobody.
        uint8 level = levels[urand(0, static_cast<uint32>(levels.size()) - 1)];

        SpawnPoint const* point = PickSpawnPoint(level);
        if (!point)
        {
            outError = "no usable spawn point";
            return false;
        }

        Map* map = sMapMgr->CreateBaseMap(point->map);
        if (!map)
        {
            outError = Acore::StringFormat("map {} is not available", point->map);
            return false;
        }

        // The cache may well land where nobody has been, so make sure the grid is
        // really there before putting an object in it. Grids are never unloaded
        // at runtime in this core (Map::UnloadGrid is only reached from
        // Map::UnloadAll), so once loaded it stays standing until someone finds
        // it - at the cost of that grid staying resident, which is why the forge
        // interval is minutes and not seconds.
        map->LoadGrid(point->x, point->y);

        GameObject* cache = new GameObject();
        G3D::Quat rotation = G3D::Quat::fromAxisAngleRotation(G3D::Vector3::unitZ(), point->o);
        if (!cache->Create(map->GenerateLowGuid<HighGuid::GameObject>(), CACHE_GO_ENTRY, map, PHASEMASK_NORMAL,
            point->x, point->y, point->z, point->o, rotation, 0, GO_STATE_READY))
        {
            delete cache;
            outError = Acore::StringFormat("could not create gameobject {} (is worldforged.sql applied?)",
                CACHE_GO_ENTRY);
            return false;
        }

        // AddToMap refuses coordinates outside the map grid. Every shipped spawn
        // point comes from a real creature spawn so this should not happen, but a
        // hand-added row could get it wrong, and the alternative is tracking a
        // cache guid that never made it into the world.
        if (!map->AddToMap(cache))
        {
            delete cache;
            outError = Acore::StringFormat("spawn point {} has coordinates the map rejected", point->id);
            return false;
        }

        cache->setActive(true);

        std::string zoneName = ZoneNameAt(map, point->x, point->y, point->z);
        uint32 lifetimeMinutes = MadosaSettings::GetWorldforgedLifetime();

        {
            std::lock_guard<std::mutex> lock(activeCachesMutex);
            activeCaches.push_back({ cache->GetGUID(), point->map,
                GameTime::GetGameTime().count() + lifetimeMinutes * MINUTE, zoneName });
        }

        LOG_INFO("module", "mod-madosa: Worldforged cache forged at spawn point {} in {} (map {}).",
            point->id, zoneName, point->map);

        if (MadosaSettings::GetWorldforgedAnnounce())
            AnnounceToRealPlayers(Acore::StringFormat(
                "|cff00ccffWorldforged:|r a cache has been forged somewhere in |cffffffff{}|r. "
                "It will hold for {} minutes.", zoneName, lifetimeMinutes));

        return true;
    }

    // Removes the cache with this guid from the world. Must be called with a map
    // that is not being updated by another thread - i.e. from the world tick, or
    // from a script running on that very map.
    void DeleteCacheObject(ObjectGuid guid, uint32 mapId)
    {
        if (Map* map = sMapMgr->FindBaseNonInstanceMap(mapId))
            if (GameObject* cache = map->GetGameObject(guid))
                cache->Delete();
    }

    void ExpireCaches()
    {
        time_t now = GameTime::GetGameTime().count();

        std::vector<ActiveCache> expired;
        {
            // partition keeps everything still standing at the front and hands
            // back the boundary, so the tail is exactly what has run out.
            std::lock_guard<std::mutex> lock(activeCachesMutex);
            auto firstExpired = std::partition(activeCaches.begin(), activeCaches.end(),
                [now](ActiveCache const& cache) { return cache.expiry > now; });
            expired.assign(firstExpired, activeCaches.end());
            activeCaches.erase(firstExpired, activeCaches.end());
        }

        for (ActiveCache const& cache : expired)
        {
            DeleteCacheObject(cache.guid, cache.mapId);

            if (MadosaSettings::GetWorldforgedAnnounce())
                AnnounceToRealPlayers(Acore::StringFormat(
                    "|cff00ccffWorldforged:|r the cache in |cffffffff{}|r crumbled away unclaimed.", cache.zoneName));
        }
    }

    // -----------------------------------------------------------------------
    // Opening one
    // -----------------------------------------------------------------------

    // Hands the finder their reward. Returns false when nothing was given and the
    // cache should stay standing - a full bag is the player's problem to fix, not
    // a reason to lose the find.
    bool GrantReward(Player* player, std::string& outAnnouncement)
    {
        uint8 level = player->GetLevel();

        bool wantRare = roll_chance_i(static_cast<int32>(MadosaSettings::GetWorldforgedRareChance()));
        RewardItem const* reward = wantRare ? PickReward(rarePool, level, false) : nullptr;
        if (!reward)
            reward = PickReward(greenPool, level, true); // no rare fits this level yet

        if (!reward)
        {
            ChatHandler(player->GetSession()).PSendSysMessage("The cache is empty - the forge has nothing for you.");
            return false;
        }

        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, reward->entry, 1) != EQUIP_ERR_OK)
        {
            ChatHandler(player->GetSession()).PSendSysMessage(
                "The Worldforged Cache will not open - you have no room to carry what is inside.");
            return false;
        }

        Item* item = player->StoreNewItem(dest, reward->entry, true, Item::GenerateItemRandomPropertyId(reward->entry));
        if (!item)
        {
            ChatHandler(player->GetSession()).PSendSysMessage("The Worldforged Cache will not open - try again.");
            return false;
        }

        player->SendNewItem(item, 1, true, false);

        uint32 gold = level * MadosaSettings::GetWorldforgedGoldPerLevel();
        if (gold)
        {
            // +/-20% so two finds at the same level don't read as a fixed payout.
            gold = gold * urand(80, 120) / 100;
            player->ModifyMoney(static_cast<int32>(gold));
        }

        std::string link = ItemLink(item);
        ChatHandler(player->GetSession()).PSendSysMessage("You pry open the Worldforged Cache and find {}.", link);

        outAnnouncement = Acore::StringFormat("|cff00ccffWorldforged:|r |cffffffff{}|r claimed the cache and drew {}.",
            player->GetName(), link);
        return true;
    }
}

namespace MadosaWorldforged
{
    bool ForgeNow(std::string& outError)
    {
        {
            std::lock_guard<std::mutex> lock(activeCachesMutex);
            if (activeCaches.size() >= MadosaSettings::GetWorldforgedMaxActive())
            {
                outError = "the maximum number of caches is already standing";
                return false;
            }
        }

        return ForgeCache(outError);
    }

    uint32 ClearAll()
    {
        std::vector<ActiveCache> removed;
        {
            std::lock_guard<std::mutex> lock(activeCachesMutex);
            removed.swap(activeCaches);
        }

        for (ActiveCache const& cache : removed)
            DeleteCacheObject(cache.guid, cache.mapId);

        return static_cast<uint32>(removed.size());
    }

    std::vector<std::string> Status()
    {
        time_t now = GameTime::GetGameTime().count();

        std::vector<std::string> lines;
        std::lock_guard<std::mutex> lock(activeCachesMutex);
        for (ActiveCache const& cache : activeCaches)
        {
            time_t remaining = cache.expiry > now ? cache.expiry - now : 0;
            lines.push_back(Acore::StringFormat("{} - {} minute(s) left", cache.zoneName, remaining / MINUTE));
        }

        return lines;
    }
}

class mod_madosa_worldforged_world : public WorldScript
{
    uint32 _timer = 0;

public:
    mod_madosa_worldforged_world() : WorldScript("mod_madosa_worldforged_world") { }

    void OnStartup() override
    {
        LoadSpawnPoints();
        LoadRewardPool();
    }

    void OnUpdate(uint32 diff) override
    {
        _timer += diff;
        if (_timer < TICK_INTERVAL_MS)
            return;

        _timer = 0;

        // Expiry runs even while the event is switched off, so turning it off
        // clears the world out instead of leaving caches standing forever.
        ExpireCaches();

        if (!MadosaSettings::GetWorldforgedEnable())
            return;

        time_t now = GameTime::GetGameTime().count();
        if (now < nextForgeTime)
            return;

        // Set the next attempt before trying, so a failure (nobody online, say)
        // waits out the interval like a success would instead of retrying every
        // tick.
        nextForgeTime = now + MadosaSettings::GetWorldforgedInterval() * MINUTE;

        {
            std::lock_guard<std::mutex> lock(activeCachesMutex);
            if (activeCaches.size() >= MadosaSettings::GetWorldforgedMaxActive())
                return;
        }

        std::string error;
        if (!ForgeCache(error))
            LOG_DEBUG("module", "mod-madosa: Worldforged did not forge a cache: {}", error);
    }
};

class go_madosa_worldforged_cache : public GameObjectScript
{
public:
    go_madosa_worldforged_cache() : GameObjectScript("go_madosa_worldforged_cache") { }

    // Always returns true: this suppresses GameObject::Use()'s default handling
    // entirely, which is the whole point of the goober - the script, not the
    // template, decides what opening a cache does.
    bool OnGossipHello(Player* player, GameObject* go) override
    {
        if (!MadosaSettings::GetWorldforgedEnable())
            return true;

        // Bots get nothing and are told nothing - they have no one to tell.
        if (GET_PLAYERBOT_AI(player))
            return true;

        std::string announcement;
        if (!GrantReward(player, announcement))
            return true; // cache stays standing; the player was told why

        {
            std::lock_guard<std::mutex> lock(activeCachesMutex);
            ObjectGuid guid = go->GetGUID();
            activeCaches.erase(std::remove_if(activeCaches.begin(), activeCaches.end(),
                [guid](ActiveCache const& cache) { return cache.guid == guid; }), activeCaches.end());
        }

        // Safe from here: we are running inside this very map's update, so the
        // object cannot be going away underneath us.
        go->Delete();

        if (MadosaSettings::GetWorldforgedAnnounce())
            AnnounceToRealPlayers(announcement);

        return true;
    }
};

void AddSC_madosa_worldforged()
{
    new mod_madosa_worldforged_world();
    new go_madosa_worldforged_cache();
}
