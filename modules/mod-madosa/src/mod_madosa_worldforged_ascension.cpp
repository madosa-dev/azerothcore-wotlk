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

#include "mod_madosa_settings.h"

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
#include "WorldDatabase.h"

#include <mutex>
#include <shared_mutex>
#include <unordered_map>
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
    std::unordered_map<uint32, time_t> cooldowns;           // spawn point id -> available again at

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

    void LoadCooldowns()
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        cooldowns.clear();

        QueryResult result = WorldDatabase.Query(
            "SELECT id, available_at FROM mod_madosa_worldforged_ascension_cooldowns");
        if (!result)
            return;

        do
        {
            Field* fields = result->Fetch();
            cooldowns[fields[0].Get<uint32>()] = static_cast<time_t>(fields[1].Get<int64>());
        } while (result->NextRow());
    }

    // Positions of every real player in the world, so the scan knows where to
    // stream. Bots are skipped: they must neither pull caches into existence nor
    // keep them alive.
    struct Watcher
    {
        uint32 map;
        float x;
        float y;
    };

    std::vector<Watcher> RealPlayerPositions()
    {
        std::vector<Watcher> out;
        std::shared_lock<std::shared_mutex> lock(*HashMapHolder<Player>::GetLock());
        for (auto const& [guid, player] : ObjectAccessor::GetPlayers())
            if (player->IsInWorld() && !GET_PLAYERBOT_AI(player))
                out.push_back({ player->GetMapId(), player->GetPositionX(), player->GetPositionY() });

        return out;
    }

    bool WithinRange(SpawnPoint const& point, std::vector<Watcher> const& watchers, float range)
    {
        float rangeSq = range * range;
        for (Watcher const& w : watchers)
        {
            if (w.map != point.map)
                continue;

            float dx = w.x - point.x;
            float dy = w.y - point.y;
            if (dx * dx + dy * dy <= rangeSq)
                return true;
        }
        return false;
    }

    void SpawnCache(SpawnPoint const& point)
    {
        Map* map = sMapMgr->FindBaseNonInstanceMap(point.map);
        if (!map)
            return;

        // A real player is within STREAM_IN_RANGE, but that is further than a grid
        // is wide, so the cache's own grid still may not be loaded.
        map->LoadGrid(point.x, point.y);

        // The spawn table has no Z on purpose. Now that the grid is here, ask the
        // map where the ground actually is; MAX_HEIGHT means "search down from the
        // top", which is what gets a sane answer on a slope or in a canyon.
        float z = map->GetHeight(point.x, point.y, MAX_HEIGHT);
        if (z <= INVALID_HEIGHT)
        {
            LOG_DEBUG("module", "mod-madosa: Ascension Worldforged spot {} has no ground at {}, {} on map {}.",
                point.id, point.x, point.y, point.map);
            return;
        }

        GameObject* cache = new GameObject();
        G3D::Quat rotation = G3D::Quat::fromAxisAngleRotation(G3D::Vector3::unitZ(), 0.0f);
        if (!cache->Create(map->GenerateLowGuid<HighGuid::GameObject>(), CACHE_GO_ENTRY, map, PHASEMASK_NORMAL,
            point.x, point.y, z + GROUND_OFFSET, 0.0f, rotation, 0, GO_STATE_READY))
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
        time_t now = GameTime::GetGameTime().count();

        std::vector<SpawnPoint const*> toSpawn;
        std::vector<std::pair<uint32, ObjectGuid>> toDespawn;

        {
            std::lock_guard<std::mutex> lock(stateMutex);
            for (SpawnPoint const& point : spawnPoints)
            {
                auto live = liveCaches.find(point.id);
                if (live != liveCaches.end())
                {
                    // Standing: keep it until everyone has walked well away.
                    if (!WithinRange(point, watchers, STREAM_OUT_RANGE))
                    {
                        toDespawn.push_back({ point.map, live->second });
                        cacheOwners.erase(live->second);
                        liveCaches.erase(live);
                    }
                    continue;
                }

                if (auto cooldown = cooldowns.find(point.id); cooldown != cooldowns.end())
                {
                    if (cooldown->second > now)
                        continue;
                    cooldowns.erase(cooldown);
                    WorldDatabase.Execute("DELETE FROM mod_madosa_worldforged_ascension_cooldowns WHERE id = {}",
                        point.id);
                }

                if (WithinRange(point, watchers, STREAM_IN_RANGE))
                    toSpawn.push_back(&point);
            }
        }

        for (auto const& [mapId, guid] : toDespawn)
            DespawnCache(mapId, guid);

        for (SpawnPoint const* point : toSpawn)
            SpawnCache(*point);
    }

    void PutOnCooldown(uint32 pointId)
    {
        time_t availableAt = GameTime::GetGameTime().count()
            + MadosaSettings::GetWorldforgedAscensionRespawn() * MINUTE;

        {
            std::lock_guard<std::mutex> lock(stateMutex);
            cooldowns[pointId] = availableAt;
        }

        WorldDatabase.Execute(
            "REPLACE INTO mod_madosa_worldforged_ascension_cooldowns (id, available_at) VALUES ({}, {})",
            pointId, static_cast<int64>(availableAt));
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
        LoadCooldowns();
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

        // Claim the spot before removing the object, so a second click in the same
        // tick finds nothing to claim.
        {
            std::lock_guard<std::mutex> lock(stateMutex);
            cacheOwners.erase(go->GetGUID());
            liveCaches.erase(pointId);
        }

        PutOnCooldown(pointId);
        go->Delete();
        return true;
    }
};

void AddSC_madosa_worldforged_ascension()
{
    new mod_madosa_worldforged_ascension_world();
    new go_madosa_worldforged_ascension();
}
