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

// Ascension's Worldforged, reproduced: 3608 fixed spots across the world, each
// holding the specific item Ascension players recorded finding there. Both the
// items and the locations are real Ascension data - see the tools under
// tools/worldforged/ for where they come from and how they were verified.
//
// This is a different system from the timed event in mod_madosa_worldforged.cpp,
// which forges one randomly enchanted item somewhere and announces it. Here
// nothing is announced and nothing moves: a spot always holds what it holds, and
// finding it is a matter of going there.
//
// Streamed, not spawned
// ---------------------
// 3608 permanent objects would mean 3608 map grids resident for the rest of the
// uptime, because this core never unloads a grid once loaded. So caches are
// streamed instead: a periodic scan spawns the ones near a real player and
// despawns them again once nobody is close. The player cannot tell the
// difference - a cache is always there when you get there - but only a handful
// exist at any moment, in grids that are loaded anyway because a player is
// standing in them.
//
// That also solves the ground-height problem for free. The spawn table carries
// no Z, because computing one needs the server's map data; by the time a cache
// is streamed in, its grid is loaded and Map::GetHeight() answers exactly.
//
// Only real players stream caches in, and only real players may open one. On a
// realm with ~3000 playerbots the alternative is that bots empty the world of
// Worldforged items before a person ever walks past one.
//
// One find per item, per character
// --------------------------------
// A character may claim each distinct Worldforged item once, tracked in
// character_worldforged_ascension_loot. Keyed by item rather than by spot,
// because the 1509 items are spread over 3599 places: claiming a Silverbound
// Dagger at one of them finishes every other spot holding one, instead of
// letting you farm duplicates a few hills apart.
//
// A cache is never consumed and never removed: it stands where it stands, for
// everyone, and claiming its item only records that this character has had it.
// There is no respawn timer because nothing ever despawns, and a fresh character
// finds every spot still holding what it always held.

#include "mod_madosa_chronicle.h"
#include "mod_madosa_settings.h"

#include "CharacterDatabase.h"
#include "Chat.h"
#include "GameObject.h"
#include "GameTime.h"
#include "Log.h"
#include "MapMgr.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Playerbots.h"
#include "ScriptMgr.h"
#include "StringFormat.h"
#include "WorldSession.h"
#include "WorldDatabase.h"

#include <cmath>
#include <mutex>
#include <shared_mutex>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    constexpr uint32 CACHE_GO_ENTRY = 900401;
    constexpr uint32 SCAN_INTERVAL_MS = 5000;

    // Spawn well beyond what the player can see so a cache is already standing by
    // the time it comes into view, and drop it again only somewhat further out, so
    // walking back and forth over the boundary does not thrash.
    constexpr float STREAM_IN_RANGE = 300.0f;
    constexpr float STREAM_OUT_RANGE = 450.0f;

    // Half a yard above the ground: flush with the terrain the model sinks into it.
    constexpr float GROUND_OFFSET = 0.5f;

    // A treasure nobody can walk to is not a treasure. Ascension's coordinates
    // record where the *finder stood*, and they arrive here through two
    // coordinate systems, so a spot can land a few yards onto a slope too steep
    // for WoW to climb - which is how caches ended up embedded in a Dun Morogh
    // mountainside. Sample the ground around a point and, when it is that steep,
    // spiral outwards for somewhere level.
    constexpr float SLOPE_SAMPLE = 3.0f;         // how far out to sample, in yards
    constexpr float MAX_SLOPE_RISE = 1.6f;       // ~28 degrees across SLOPE_SAMPLE
    constexpr float FLAT_SEARCH_RADIUS = 25.0f;  // far enough to leave a slope, near
    constexpr uint32 FLAT_SEARCH_RINGS = 5;      // enough that it is still "the spot"
    constexpr uint32 FLAT_SEARCH_POINTS = 8;

    struct SpawnPoint
    {
        uint32 id;
        uint32 map;
        float x;
        float y;
        uint32 item;
        std::string zone;
    };

    // Immutable after startup.
    std::vector<SpawnPoint> spawnPoints;

    // Everything below is reached from the world tick (the streaming scan) and
    // from a map thread (a player opening a cache), so it is all under one lock.
    std::mutex stateMutex;
    std::unordered_map<uint32, ObjectGuid> liveCaches;      // spawn point id -> object
    std::unordered_map<ObjectGuid, uint32> cacheOwners;     // object -> spawn point id

    // What each online character has already claimed, keyed by item rather than
    // by spot: several places hold the same item, and one claim finishes all of
    // them for that character. Loaded on login, dropped on logout, so this only
    // ever holds rows for players who are actually here.
    std::unordered_map<ObjectGuid::LowType, std::unordered_set<uint32>> claimedItems;

    void LoadSpawnPoints()
    {
        spawnPoints.clear();

        QueryResult result = WorldDatabase.Query(
            "SELECT id, map, position_x, position_y, item, zone FROM mod_madosa_worldforged_ascension_spawns");
        if (!result)
        {
            LOG_WARN("module", "mod-madosa: no Ascension Worldforged locations - that half stays idle.");
            return;
        }

        uint32 unknownItems = 0;
        do
        {
            Field* fields = result->Fetch();
            SpawnPoint point;
            point.id = fields[0].Get<uint32>();
            point.map = fields[1].Get<uint16>();
            point.x = fields[2].Get<float>();
            point.y = fields[3].Get<float>();
            point.item = fields[4].Get<uint32>();
            point.zone = fields[5].Get<std::string>();

            // A location whose item never made it into item_template would hand out
            // nothing, so drop it here rather than at the player's click.
            if (!sObjectMgr->GetItemTemplate(point.item))
            {
                ++unknownItems;
                continue;
            }

            spawnPoints.push_back(point);
        } while (result->NextRow());

        if (unknownItems)
            LOG_WARN("module", "mod-madosa: {} Ascension Worldforged locations name an item that is not in "
                "item_template - is worldforged_ascension_items.sql applied?", unknownItems);

        LOG_INFO("module", "mod-madosa: loaded {} Ascension Worldforged locations.", spawnPoints.size());
    }

    // Positions of every real player in the world, so the scan knows where to
    // stream. Bots are skipped: they must neither pull caches into existence nor
    // keep them alive.
    struct Watcher
    {
        ObjectGuid::LowType guid;
        uint32 map;
        float x;
        float y;
        float z;
    };

    std::vector<Watcher> RealPlayerPositions()
    {
        std::vector<Watcher> out;
        std::shared_lock<std::shared_mutex> lock(*HashMapHolder<Player>::GetLock());
        for (auto const& [guid, player] : ObjectAccessor::GetPlayers())
            if (player->IsInWorld() && !GET_PLAYERBOT_AI(player))
                out.push_back({ player->GetGUID().GetCounter(), player->GetMapId(),
                    player->GetPositionX(), player->GetPositionY(), player->GetPositionZ() });

        return out;
    }

    // Has this character already claimed this item? Callers hold stateMutex.
    bool AlreadyClaimed(ObjectGuid::LowType guid, uint32 item)
    {
        auto claimed = claimedItems.find(guid);
        return claimed != claimedItems.end() && claimed->second.count(item);
    }

    // The nearest real player within range, or nothing. A cache stands wherever
    // it stands for everyone: claiming its item stops you taking it again, but it
    // does not take the chest out of the world - the landscape keeps its
    // treasures whether or not this particular character is done with them.
    // Callers hold stateMutex.
    Watcher const* NearestWatcher(SpawnPoint const& point, std::vector<Watcher> const& watchers, float range)
    {
        float rangeSq = range * range;
        Watcher const* best = nullptr;
        float bestDistSq = rangeSq;

        for (Watcher const& w : watchers)
        {
            if (w.map != point.map)
                continue;

            float dx = w.x - point.x;
            float dy = w.y - point.y;
            float distSq = dx * dx + dy * dy;
            if (distSq > rangeSq || distSq > bestDistSq)
                continue;

            // The nearest of them, because their height is what the ground search
            // starts from - and the nearest is the likeliest to be standing on the
            // same floor as the find.
            best = &w;
            bestDistSq = distSq;
        }
        return best;
    }

    // The steepest rise from (x, y) to the ground a few yards around it, and the
    // ground height itself. Negative when there is no ground to stand on.
    float GroundRoughness(Map* map, float x, float y, float from, float& outZ)
    {
        outZ = map->GetHeight(x, y, from);
        if (outZ <= INVALID_HEIGHT)
            return -1.0f;

        float worst = 0.0f;
        for (uint32 i = 0; i < 4; ++i)
        {
            float angle = static_cast<float>(i) * static_cast<float>(M_PI) / 2.0f;
            float nz = map->GetHeight(x + std::cos(angle) * SLOPE_SAMPLE,
                y + std::sin(angle) * SLOPE_SAMPLE, outZ + SLOPE_SAMPLE);
            if (nz <= INVALID_HEIGHT)
                return -1.0f;

            worst = std::max(worst, std::fabs(nz - outZ));
        }
        return worst;
    }

    // Ground a player could stand on at or near (x, y), searched downwards from
    // `from`. Where the spot itself is too steep, the most level place found
    // spiralling outwards is used instead - close enough to still be the same
    // find, far enough to be off the cliff.
    bool FindStandableGround(Map* map, float from, float& x, float& y, float& z)
    {
        float groundZ = 0.0f;
        float roughness = GroundRoughness(map, x, y, from, groundZ);
        if (roughness >= 0.0f && roughness <= MAX_SLOPE_RISE)
        {
            z = groundZ;
            return true;
        }

        float bestX = x, bestY = y, bestZ = groundZ, best = roughness;
        for (uint32 ring = 1; ring <= FLAT_SEARCH_RINGS; ++ring)
        {
            float radius = FLAT_SEARCH_RADIUS * static_cast<float>(ring) / static_cast<float>(FLAT_SEARCH_RINGS);
            for (uint32 i = 0; i < FLAT_SEARCH_POINTS; ++i)
            {
                float angle = static_cast<float>(i) * 2.0f * static_cast<float>(M_PI)
                    / static_cast<float>(FLAT_SEARCH_POINTS);
                float cx = x + std::cos(angle) * radius;
                float cy = y + std::sin(angle) * radius;
                float cz = 0.0f;
                float r = GroundRoughness(map, cx, cy, from, cz);
                if (r < 0.0f)
                    continue;

                if (r <= MAX_SLOPE_RISE)
                {
                    x = cx;
                    y = cy;
                    z = cz;
                    return true;
                }

                if (best < 0.0f || r < best)
                {
                    best = r;
                    bestX = cx;
                    bestY = cy;
                    bestZ = cz;
                }
            }
        }

        if (best < 0.0f)
            return false;

        x = bestX;
        y = bestY;
        z = bestZ;
        return true;
    }

    void SpawnCache(SpawnPoint const& point, float searchFrom)
    {
        Map* map = sMapMgr->FindBaseNonInstanceMap(point.map);
        if (!map)
            return;

        // A real player is within STREAM_IN_RANGE, but that is further than a grid
        // is wide, so the cache's own grid still may not be loaded.
        map->LoadGrid(point.x, point.y);


        // The spawn table has no Z on purpose; the ground is found here, now that
        // the grid is loaded. Searching down from MAX_HEIGHT would be the obvious
        // thing and is wrong: several of these spots are inside caves, and the
        // first surface below the sky is the mountain sitting on top of one. So
        // the search starts a little above the player who pulled this cache in -
        // they are within 300 yards and, if the find is in a cave, they are in it.
        float x = point.x;
        float y = point.y;
        float z = 0.0f;
        if (!FindStandableGround(map, searchFrom + SLOPE_SAMPLE, x, y, z)
            && !FindStandableGround(map, MAX_HEIGHT, x, y, z))
        {
            LOG_DEBUG("module", "mod-madosa: Ascension Worldforged spot {} has no standable ground at {}, {} "
                "on map {}.", point.id, point.x, point.y, point.map);
            return;
        }

        GameObject* cache = new GameObject();
        G3D::Quat rotation = G3D::Quat::fromAxisAngleRotation(G3D::Vector3::unitZ(), 0.0f);
        if (!cache->Create(map->GenerateLowGuid<HighGuid::GameObject>(), CACHE_GO_ENTRY, map, PHASEMASK_NORMAL,
            x, y, z + GROUND_OFFSET, 0.0f, rotation, 0, GO_STATE_READY))
        {
            delete cache;
            LOG_ERROR("module", "mod-madosa: could not create gameobject {} (is worldforged.sql applied?)",
                CACHE_GO_ENTRY);
            return;
        }

        if (!map->AddToMap(cache))
        {
            delete cache;
            return;
        }

        std::lock_guard<std::mutex> lock(stateMutex);
        liveCaches[point.id] = cache->GetGUID();
        cacheOwners[cache->GetGUID()] = point.id;
    }

    // Removes a cache from the world. Safe from the world tick (no map thread is
    // running then) and from a script on that same map.
    void DespawnCache(uint32 mapId, ObjectGuid guid)
    {
        if (Map* map = sMapMgr->FindBaseNonInstanceMap(mapId))
            if (GameObject* cache = map->GetGameObject(guid))
                cache->Delete();
    }

    void StreamCaches()
    {
        std::vector<Watcher> watchers = RealPlayerPositions();

        std::vector<std::pair<SpawnPoint const*, float>> toSpawn;
        std::vector<std::pair<uint32, ObjectGuid>> toDespawn;

        {
            std::lock_guard<std::mutex> lock(stateMutex);
            for (SpawnPoint const& point : spawnPoints)
            {
                auto live = liveCaches.find(point.id);
                if (live != liveCaches.end())
                {
                    // Standing: keep it until everyone has walked well away.
                    if (!NearestWatcher(point, watchers, STREAM_OUT_RANGE))
                    {
                        toDespawn.push_back({ point.map, live->second });
                        cacheOwners.erase(live->second);
                        liveCaches.erase(live);
                    }
                    continue;
                }

                if (Watcher const* watcher = NearestWatcher(point, watchers, STREAM_IN_RANGE))
                    toSpawn.push_back({ &point, watcher->z });
            }
        }

        for (auto const& [mapId, guid] : toDespawn)
            DespawnCache(mapId, guid);

        for (auto const& [point, searchFrom] : toSpawn)
            SpawnCache(*point, searchFrom);
    }

    void LoadClaimedItems(ObjectGuid::LowType guid)
    {
        std::unordered_set<uint32> claimed;

        QueryResult result = CharacterDatabase.Query(
            "SELECT item FROM character_worldforged_ascension_loot WHERE guid = {}", guid);
        if (result)
            do
            {
                claimed.insert(result->Fetch()[0].Get<uint32>());
            } while (result->NextRow());

        std::lock_guard<std::mutex> lock(stateMutex);
        claimedItems[guid] = std::move(claimed);
    }

    void ForgetClaimedItems(ObjectGuid::LowType guid)
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        claimedItems.erase(guid);
    }

    void RecordClaim(ObjectGuid::LowType guid, uint32 item)
    {
        {
            std::lock_guard<std::mutex> lock(stateMutex);
            claimedItems[guid].insert(item);
        }

        CharacterDatabase.Execute(
            "REPLACE INTO character_worldforged_ascension_loot (guid, item, looted_at) VALUES ({}, {}, {})",
            guid, item, static_cast<int64>(GameTime::GetGameTime().count()));
    }

}

class mod_madosa_worldforged_ascension_world : public WorldScript
{
    uint32 _timer = 0;

public:
    mod_madosa_worldforged_ascension_world() : WorldScript("mod_madosa_worldforged_ascension_world") { }

    void OnStartup() override
    {
        LoadSpawnPoints();
    }

    void OnUpdate(uint32 diff) override
    {
        _timer += diff;
        if (_timer < SCAN_INTERVAL_MS)
            return;

        _timer = 0;

        if (!MadosaSettings::GetWorldforgedAscensionEnable() || spawnPoints.empty())
            return;

        StreamCaches();
    }
};

// The claimed-item sets are kept only for players who are actually online, since
// that is the only time the streaming scan needs to ask about them.
class mod_madosa_worldforged_ascension_player : public PlayerScript
{
public:
    mod_madosa_worldforged_ascension_player() : PlayerScript("mod_madosa_worldforged_ascension_player") { }

    void OnPlayerLogin(Player* player) override
    {
        // The session flag, not GET_PLAYERBOT_AI: mod-playerbots attaches the AI
        // after login, from a queued world-thread operation, so at this point
        // every bot still looks like a person - which is how this ended up
        // running a query per bot login against its own comment. Only real
        // players can open a cache, so a bot's claimed set is never asked about.
        if (!player->GetSession() || !player->GetSession()->IsBot())
            LoadClaimedItems(player->GetGUID().GetCounter());
    }

    void OnPlayerLogout(Player* player) override
    {
        ForgetClaimedItems(player->GetGUID().GetCounter());
    }
};

class go_madosa_worldforged_ascension : public GameObjectScript
{
public:
    go_madosa_worldforged_ascension() : GameObjectScript("go_madosa_worldforged_ascension") { }

    // Always true: this suppresses GameObject::Use()'s default handling, so the
    // script alone decides what opening a cache does.
    bool OnGossipHello(Player* player, GameObject* go) override
    {
        if (GET_PLAYERBOT_AI(player))
            return true; // bots get nothing, and have nobody to tell

        ObjectGuid::LowType playerGuid = player->GetGUID().GetCounter();

        uint32 pointId = 0;
        uint32 item = 0;
        {
            std::lock_guard<std::mutex> lock(stateMutex);
            auto owner = cacheOwners.find(go->GetGUID());
            if (owner == cacheOwners.end())
                return true; // not one of ours, or already claimed this tick

            pointId = owner->second;
            for (SpawnPoint const& point : spawnPoints)
                if (point.id == pointId)
                {
                    item = point.item;
                    break;
                }

            // Each Worldforged item is one find per character. The streaming scan
            // will not normally show a character a cache they have finished, so
            // reaching here means someone else's cache, or a click that beat the
            // next scan - either way, say so plainly rather than silently.
            if (item && AlreadyClaimed(playerGuid, item))
            {
                ChatHandler(player->GetSession()).PSendSysMessage(
                    "You have already claimed this Worldforged find.");
                return true;
            }
        }

        if (!item)
            return true;

        ItemPosCountVec dest;
        // Let the client render whatever the real reason is. A full bag is the
        // common one, but 27 of these items are unique, and telling someone who
        // already owns one that their bags are full would just be wrong.
        if (InventoryResult result = player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, item, 1);
            result != EQUIP_ERR_OK)
        {
            player->SendEquipError(result, nullptr, nullptr, item);
            return true; // the cache stays standing; this is not a reason to lose the find
        }

        Item* created = player->StoreNewItem(dest, item, true);
        if (!created)
            return true;

        player->SendNewItem(created, 1, true, false);
        RecordClaim(playerGuid, item);
        MadosaChronicle::Record("worldforged", player, nullptr, int64(item),
            created->GetTemplate() ? created->GetTemplate()->Name1 : "");

        // The chest stays. Claiming its item is recorded against the character,
        // not against the world, so the next click tells this player they have
        // already had it while anyone else still finds it waiting.
        return true;
    }
};

void AddSC_madosa_worldforged_ascension()
{
    new mod_madosa_worldforged_ascension_world();
    new mod_madosa_worldforged_ascension_player();
    new go_madosa_worldforged_ascension();
}
