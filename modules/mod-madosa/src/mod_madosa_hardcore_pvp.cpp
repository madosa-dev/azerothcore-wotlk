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

// Hardcore PvP, after Ascension WoW's mode of the same name: opt in and you
// earn more experience, ordinary world mobs start dropping dungeon and raid
// gear (mod_madosa_hardcore_pvp_loot.cpp), and dying to another player leaves
// a chest holding part of what you were carrying. Toggled in any inn or
// capital city, at the Hardcore Herald or with ".hardcore".
//
// Two separate opt-ins
// --------------------
// Hardcore PvP is one switch; "Traitor to the Alliance" / "Traitor to the
// Horde" is a second, independent one. Hardcore on its own never enables
// friendly fire - only treason does, and it costs you your own side's cities.
//
// The chest needs both sides
// --------------------------
// A chest only ever drops when killer *and* victim are both in Hardcore PvP.
// That is why each mode wears a visible aura: it is not decoration, it is how
// a killer can tell beforehand whether a target is carrying anything worth
// taking, and how a hardcore player can tell they are fair game for loot.
//
// Treason: the core's own FFA flag, re-asserted
// --------------------------------------------
// Same-faction PvP is UNIT_BYTE2_FLAG_FFA_PVP, what Gurubashi Arena uses:
// Unit::GetReactionTo() returns REP_HOSTILE when *both* sides carry it
// (Unit.cpp:7174), so traitors are hostile to each other and to nobody else -
// a loyal player still cannot swing at one. That symmetry is the design, and
// it is also the reason no core file is touched here.
//
// The flag cannot simply be set once, though. Player::UpdateFFAPvPState()
// (PlayerUpdates.cpp:1465) clears it for anyone not standing in an
// AREA_FLAG_ARENA area, and Player::UpdateArea() calls that on every area
// change - after the OnPlayerUpdateArea hook, so a script cannot get its
// answer in first. Rather than fight it, treason marks the player as being in
// an FFA area (pvpInfo.IsInFFAPvPArea) and re-asserts that from the world tick,
// letting the core's own code set the flag. Sanctuaries keep their protection
// for free, because UpdateFFAPvPState() checks IsInNoPvPArea first.
//
// Treason: hostile guards
// -----------------------
// While the traitor flag is on, the character is forced hostile with their own
// side's city factions via ReputationMgr::ApplyForceReaction() - the core's own
// temporary-reaction mechanism, read back inside the very same GetReactionTo()
// path (Unit.cpp:7147). Real reputation values are untouched, so switching off
// restores the character exactly. Note that a forced-hostile city faction also
// means its vendors, flight masters and quest givers refuse the character:
// treason costs you the city, not just its guards. That is why the Herald is
// faction-neutral and also stands in the neutral towns.
//
// The death chest
// ---------------
// A gameobject chest whose template carries no loot id, filled by hand. That
// combination is deliberate: Player::SendLoot() only calls loot->clear() and
// FillLoot() inside `if (lootid)` (Player.cpp:8029), so a chest with none keeps
// whatever was put in it and the client gets an ordinary loot window over the
// victim's own belongings. Enchantments cannot be expressed as loot, so they
// are recorded at drop time and re-applied in OnPlayerLootItem, which hands us
// the freshly created Item.
//
// The sparkle
// -----------
// The one place this feature reaches into the core. The client draws the
// quest glitter on a gameobject the server flags as activatable, and the core
// decides that from the quest log (GameObject::ActivateToQuest), which knows
// nothing about a chest of somebody's bags. GameObjectScript::OnActivateToQuest
// lets the chest's own script answer instead, with the same rule the loot
// check uses - see go_madosa_death_chest at the bottom.

#include "mod_madosa_chronicle.h"
#include "mod_madosa_hardcore_pvp.h"
#include "mod_madosa_settings.h"

#include "Bag.h"
#include "CharacterDatabase.h"
#include "Chat.h"
#include "DBCStores.h"
#include "GameObject.h"
#include "GameTime.h"
#include "Group.h"
#include "Item.h"
#include "Log.h"
#include "Mail.h"
#include "LootMgr.h"
#include "MapMgr.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ReputationMgr.h"
#include "ScriptedGossip.h"
#include "ScriptMgr.h"
#include "SpellAuras.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "WorldSession.h"
#include "StringFormat.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdlib>
#include <iterator>
#include <mutex>
#include <shared_mutex>
#include <unordered_map>
#include <vector>

namespace
{
    // Ids created by tools/clientpatch/build_patches.py (NEW_SPELLS). Purely
    // visual, permanent, self-only dummy auras - the mode itself lives in the
    // table below, never in the aura, so a client that has not taken the patch
    // yet loses the icon and nothing else.
    constexpr uint32 SPELL_HIGH_RISK = 900002;
    constexpr uint32 SPELL_WAR_MODE = 900005;
    constexpr uint32 SPELL_TRAITOR_ALLIANCE = 900003;
    constexpr uint32 SPELL_TRAITOR_HORDE = 900004;

    constexpr uint32 DEATH_CHEST_ENTRY = 900402;
    constexpr uint32 HERALD_GOSSIP_TEXT = 900500;

    constexpr uint32 TICK_INTERVAL_MS = 1000;

    // Never dropped, whatever the settings say - you cannot be stranded by a
    // death, and a quest chain cannot be broken by one.
    constexpr uint32 ITEM_HEARTHSTONE = 6948;

    // The city factions whose guards a traitor answers to. Guards carry their
    // city's faction template, and GetForcedRankIfAny() is keyed by the faction
    // behind that template, so one entry per city covers every guard in it.
    constexpr std::array<uint32, 5> ALLIANCE_CITY_FACTIONS = { 72, 47, 54, 69, 930 };
    constexpr std::array<uint32, 5> HORDE_CITY_FACTIONS = { 76, 81, 68, 530, 911 };

    struct ModeState
    {
        MadosaHardcorePvP::RiskMode mode = MadosaHardcorePvP::RISK_MODE_PVE;
        bool traitor = false;
        bool insured = false;
        time_t since = 0;
        time_t lastToggle = 0;
    };

    // Online characters only: nothing here needs answering about someone who is
    // not logged in, and it keeps the map to the size of the population rather
    // than the realm's character count.
    std::unordered_map<ObjectGuid::LowType, ModeState> states;
    std::shared_mutex statesMutex;

    // What a chest is holding, recorded at drop time. Loot can carry an item's
    // random property but not its enchantments, so those ride along here and
    // are put back on the item the looter actually receives.
    struct DroppedItem
    {
        uint32 entry = 0;
        uint8 count = 0;
        int32 randomPropertyId = 0;
        uint32 suffixFactor = 0;
        std::array<uint32, MAX_ENCHANTMENT_SLOT> enchants{};
    };

    struct DeathChest
    {
        uint64 id = 0;
        uint32 mapId = 0;
        ObjectGuid::LowType victim = 0;
        ObjectGuid owner;
        ObjectGuid ownerGroup;
        time_t expiresAt = 0;
        std::vector<DroppedItem> items;
    };

    std::unordered_map<ObjectGuid, DeathChest> chests;
    std::mutex chestMutex;

    // Chest ids are ours, not the gameobject's: a gameobject guid is per-map and
    // gets reused, which would let a new chest inherit an old one's rows.
    std::atomic<uint64> nextChestId{1};

    // killer+victim -> when that pair may drop a chest again. Memory only: a
    // restart forgiving a cooldown is not worth a table.
    std::unordered_map<uint64, time_t> recentKills;
    std::mutex recentKillsMutex;

    uint64 KillPairKey(Player const* killer, Player const* victim)
    {
        return (uint64(killer->GetGUID().GetCounter()) << 32) | victim->GetGUID().GetCounter();
    }

    // A bot is in or out for good, rather than re-rolling on every login: the
    // point of bot participation is that some of the crowd is worth attacking,
    // which only works if the same faces keep being worth attacking.
    bool BotParticipates(ObjectGuid::LowType guid)
    {
        uint32 share = MadosaSettings::GetHardcorePvPBotParticipation();
        if (!share)
            return false;
        if (share >= 100)
            return true;
        return ((guid * 2654435761u) % 100) < share;
    }

    // See MadosaHardcorePvP::IsBot in the header for why this is the session
    // flag rather than GET_PLAYERBOT_AI.
    //
    // At OnPlayerLogin time a bot has no PlayerbotAI yet: mod-playerbots attaches
    // it from OnBotLogin, which runs later as a queued world-thread operation
    // (Script/WorldThr/PlayerbotOperations.h), and its own login hook tests the
    // session for exactly that reason. The session flag is set before the login
    // even starts - PlayerbotMgr.cpp:203 constructs it with is_bot true - so it
    // is the only bot test that is already true this early.
    //
    bool IsBotSession(Player const* player)
    {
        return player->GetSession() && player->GetSession()->IsBot();
    }

    ModeState GetState(Player const* player)
    {
        if (!player)
            return {};

        std::shared_lock<std::shared_mutex> lock(statesMutex);
        auto itr = states.find(player->GetGUID().GetCounter());
        return itr == states.end() ? ModeState{} : itr->second;
    }

    void AddMarkAura(Player* player, uint32 spellId)
    {
        if (player->HasAura(spellId))
            return;

        // Missing simply means the client patch has not been rebuilt since these
        // spells were added; the mode works without its icon, so say so once
        // rather than failing the toggle.
        if (!sSpellMgr->GetSpellInfo(spellId))
        {
            LOG_DEBUG("module", "mod-madosa: Hardcore PvP aura {} is not in Spell.dbc - "
                "re-run tools/clientpatch/build_patches.py to get the buff icon.", spellId);
            return;
        }

        player->AddAura(spellId, player);
    }

    void ApplyGuardHostility(Player* player, bool apply)
    {
        if (apply && !MadosaSettings::GetHardcorePvPTraitorGuardsHostile())
            apply = false;

        auto const& factions = player->GetTeamId() == TEAM_ALLIANCE ? ALLIANCE_CITY_FACTIONS : HORDE_CITY_FACTIONS;
        for (uint32 faction : factions)
            player->GetReputationMgr().ApplyForceReaction(faction, REP_HOSTILE, apply);

        player->GetReputationMgr().SendForceReactions();
    }

    // Hands the flag back to the core rather than setting the byte ourselves,
    // so controlled pets, the client packet and the sanctuary exception all
    // happen the way they do for a real FFA area.
    //
    // Switching treason off does not force the flag false, it re-reads the area:
    // renouncing your treason while standing in Gurubashi Arena must not take
    // you out of the arena's own free-for-all.
    void ApplyFFA(Player* player, bool apply)
    {
        if (apply)
        {
            player->pvpInfo.IsInFFAPvPArea = true;
        }
        else
        {
            AreaTableEntry const* area = sAreaTableStore.LookupEntry(player->GetAreaId());
            player->pvpInfo.IsInFFAPvPArea = area && (area->flags & AREA_FLAG_ARENA);
        }

        player->UpdateFFAPvPState(false);
    }

    void ApplyMarks(Player* player, ModeState const& state)
    {
        using namespace MadosaHardcorePvP;

        UpdateLootBandAura(player, state.mode == RISK_MODE_HIGH);

        player->RemoveAurasDueToSpell(state.mode == RISK_MODE_HIGH ? SPELL_WAR_MODE : SPELL_HIGH_RISK);

        if (state.mode != RISK_MODE_PVE)
        {
            AddMarkAura(player, state.mode == RISK_MODE_HIGH ? SPELL_HIGH_RISK : SPELL_WAR_MODE);

            // PLAYER_FLAGS_IN_PVP is not decoration, and UpdatePvP() alone is
            // not enough: Player::UpdatePvPState() starts the five-minute
            // unflag timer for any flagged player standing in friendly
            // territory *without* that flag (PlayerUpdates.cpp:1459). It is what
            // the /pvp toggle sets to mean "leave me flagged", and without it a
            // hardcore character quietly stops being attackable a few minutes
            // after walking into their own capital - which would leave the mode
            // with all of its cost and none of its risk.
            player->SetPlayerFlag(PLAYER_FLAGS_IN_PVP);
            player->UpdatePvP(true, true);
        }
        else
        {
            player->RemoveAurasDueToSpell(SPELL_HIGH_RISK);
            player->RemoveAurasDueToSpell(SPELL_WAR_MODE);

            // Leaving the mode un-flags the same way un-toggling /pvp does -
            // by starting the timer rather than dropping the flag on the spot,
            // so leaving cannot be used to step out of a fight
            // (MiscHandler.cpp:514).
            player->RemovePlayerFlag(PLAYER_FLAGS_IN_PVP);
            if (!player->pvpInfo.IsHostile && player->IsPvP())
                player->UpdatePvP(true, false);
        }

        uint32 const traitorSpell = player->GetTeamId() == TEAM_ALLIANCE ? SPELL_TRAITOR_ALLIANCE : SPELL_TRAITOR_HORDE;
        if (state.traitor)
        {
            AddMarkAura(player, traitorSpell);
            ApplyFFA(player, true);
            ApplyGuardHostility(player, true);
        }
        else
        {
            player->RemoveAurasDueToSpell(SPELL_TRAITOR_ALLIANCE);
            player->RemoveAurasDueToSpell(SPELL_TRAITOR_HORDE);
            ApplyFFA(player, false);
            ApplyGuardHostility(player, false);
        }
    }

    void SaveState(ObjectGuid::LowType guid, ModeState const& state)
    {
        CharacterDatabase.Execute(
            "REPLACE INTO character_hardcore_pvp (guid, mode, traitor, insured, mode_since, last_toggle) "
            "VALUES ({}, {}, {}, {}, {}, {})",
            guid, uint32(state.mode), state.traitor ? 1 : 0, state.insured ? 1 : 0,
            static_cast<int64>(state.since), static_cast<int64>(state.lastToggle));
    }

    // Shared by both toggles: everything that decides whether a character may
    // change mode at all, so the Herald and the chat command cannot drift apart.
    bool CanToggle(Player* player, bool enabling, std::string& outError)
    {
        if (!MadosaSettings::GetHardcorePvPEnable())
        {
            outError = "Hardcore PvP is not enabled on this realm.";
            return false;
        }

        if (player->IsInCombat())
        {
            outError = "Not while you are in combat.";
            return false;
        }

        if (player->InBattleground() || player->InArena())
        {
            outError = "Not inside a battleground or an arena.";
            return false;
        }

        if (!player->HasRestFlag(REST_FLAG_IN_TAVERN) && !player->HasRestFlag(REST_FLAG_IN_CITY))
        {
            outError = "You can only change this in an inn or a city.";
            return false;
        }

        if (enabling && player->GetLevel() < MadosaSettings::GetHardcorePvPMinLevel())
        {
            outError = Acore::StringFormat("You must be at least level {}.",
                MadosaSettings::GetHardcorePvPMinLevel());
            return false;
        }

        ModeState const state = GetState(player);
        uint32 const cooldown = MadosaSettings::GetHardcorePvPToggleCooldown();
        if (cooldown)
        {
            time_t const ready = state.lastToggle + time_t(cooldown) * MINUTE;
            time_t const now = GameTime::GetGameTime().count();
            if (now < ready)
            {
                outError = Acore::StringFormat("You changed this too recently - {} minute(s) left.",
                    uint32((ready - now + MINUTE - 1) / MINUTE));
                return false;
            }
        }

        return true;
    }

    bool IsDroppable(Item const* item)
    {
        ItemTemplate const* proto = item->GetTemplate();
        if (!proto)
            return false;

        // Bags, quivers, quest items and keys are infrastructure rather than
        // belongings: losing one costs progress or bag space, not loot.
        if (proto->Class == ITEM_CLASS_QUEST || proto->Class == ITEM_CLASS_CONTAINER
            || proto->Class == ITEM_CLASS_QUIVER || proto->Class == ITEM_CLASS_KEY)
            return false;

        if (proto->ItemId == ITEM_HEARTHSTONE)
            return false;

        if (proto->Bonding == BIND_QUEST_ITEM)
            return false;

        // Conjured food/water would be a pointless drop (it expires), heirlooms
        // belong to the account rather than the character, and NO_USER_DESTROY
        // items are ones the core itself refuses to let go of.
        if (proto->HasFlag(ITEM_FLAG_CONJURED) || proto->HasFlag(ITEM_FLAG_NO_USER_DESTROY)
            || proto->HasFlag(ITEM_FLAG_IS_BOUND_TO_ACCOUNT))
            return false;

        // A LootItem's count is a single byte. Stacks that big are rare enough
        // (and odd enough - tokens, some currencies) to simply leave alone.
        if (item->GetCount() > 250)
            return false;

        return true;
    }

    std::vector<Item*> CollectDroppable(Player* player)
    {
        std::vector<Item*> out;

        auto consider = [&out](Item* item)
        {
            if (item && IsDroppable(item))
                out.push_back(item);
        };

        for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            consider(player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));

        for (uint8 bagSlot = INVENTORY_SLOT_BAG_START; bagSlot < INVENTORY_SLOT_BAG_END; ++bagSlot)
            if (Bag* bag = player->GetBagByPos(bagSlot))
                for (uint32 slot = 0; slot < bag->GetBagSize(); ++slot)
                    consider(player->GetItemByPos(bagSlot, uint8(slot)));

        return out;
    }

    std::string EncodeEnchants(DroppedItem const& drop)
    {
        std::string out;
        for (uint32 slot = 0; slot < MAX_ENCHANTMENT_SLOT; ++slot)
        {
            if (!out.empty())
                out.push_back(',');
            out += std::to_string(drop.enchants[slot]);
        }
        return out;
    }

    // The chest's gold rides in the same table as its items, as one row of its
    // own: slot GOLD_SLOT, item 0. An insurance chest holds nothing but gold,
    // and gold nobody claimed is no more allowed to vanish than an item is.
    constexpr uint32 GOLD_SLOT = 255;

    // Written *before* the items leave the victim's bags - see HandleHardcoreKill.
    // Only for people: a bot's belongings are re-rolled by mod-playerbots
    // anyway, and mailing them back would fill a mailbox nobody ever opens.
    void RecordChestContents(uint64 chestId, Player const* victim, std::vector<DroppedItem> const& dropped,
        uint32 gold)
    {
        if (IsBotSession(victim))
            return;

        time_t const now = GameTime::GetGameTime().count();
        ObjectGuid::LowType const victimGuid = victim->GetGUID().GetCounter();
        for (size_t slot = 0; slot < dropped.size(); ++slot)
        {
            DroppedItem const& drop = dropped[slot];
            CharacterDatabase.Execute(
                "INSERT INTO character_hardcore_pvp_chest "
                "(chest, slot, victim, created_at, item, count, random_property, suffix_factor, enchants) "
                "VALUES ({}, {}, {}, {}, {}, {}, {}, {}, '{}')",
                chestId, uint32(slot), victimGuid, uint32(now), drop.entry, uint32(drop.count),
                drop.randomPropertyId, drop.suffixFactor, EncodeEnchants(drop));
        }

        if (gold)
            CharacterDatabase.Execute(
                "INSERT INTO character_hardcore_pvp_chest (chest, slot, victim, created_at, item, count, gold) "
                "VALUES ({}, {}, {}, {}, 0, 0, {})",
                chestId, GOLD_SLOT, victimGuid, uint32(now), gold);
    }

    // Whatever is still in the chest when it goes away goes back to the person
    // it was taken from. Nothing is destroyed unless somebody actually claimed
    // it - that is the whole point, and the reason this table exists.
    void MailChestBack(uint64 chestId)
    {
        QueryResult result = CharacterDatabase.Query(
            "SELECT victim, item, count, random_property, suffix_factor, enchants, gold "
            "FROM character_hardcore_pvp_chest WHERE chest = {} ORDER BY slot", chestId);

        if (!result)
            return;

        ObjectGuid::LowType victim = 0;
        std::vector<DroppedItem> items;
        uint32 gold = 0;
        do
        {
            Field* fields = result->Fetch();
            victim = fields[0].Get<uint32>();

            if (!fields[1].Get<uint32>())
            {
                gold += fields[6].Get<uint32>();
                continue;
            }

            DroppedItem drop;
            drop.entry = fields[1].Get<uint32>();
            drop.count = uint8(std::min<uint32>(fields[2].Get<uint32>(), 250));
            drop.randomPropertyId = fields[3].Get<int32>();
            drop.suffixFactor = fields[4].Get<uint32>();

            std::string const enchants = fields[5].Get<std::string>();
            size_t pos = 0;
            for (uint32 slot = 0; slot < MAX_ENCHANTMENT_SLOT && pos <= enchants.size(); ++slot)
            {
                size_t const next = enchants.find(',', pos);
                drop.enchants[slot] = uint32(std::strtoul(enchants.substr(pos, next - pos).c_str(), nullptr, 10));
                if (next == std::string::npos)
                    break;
                pos = next + 1;
            }

            items.push_back(drop);
        } while (result->NextRow());

        // A mail holds MAX_MAIL_ITEMS, so a full chest needs more than one. The
        // gold goes with the first; a chest of gold alone is one mail with no
        // items at all.
        size_t start = 0;
        do
        {
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            MailDraft draft("Spoils of the Fallen",
                "No one came to claim what was taken from you. It is returned.");

            size_t const stop = std::min(start + MAX_MAIL_ITEMS, items.size());
            bool any = false;
            for (size_t i = start; i < stop; ++i)
            {
                Item* item = Item::CreateItem(items[i].entry, items[i].count);
                if (!item)
                    continue;

                if (items[i].randomPropertyId)
                    item->SetItemRandomProperties(items[i].randomPropertyId);

                for (uint32 slot = 0; slot < MAX_ENCHANTMENT_SLOT; ++slot)
                    if (items[i].enchants[slot])
                        item->SetEnchantment(EnchantmentSlot(slot), items[i].enchants[slot], 0, 0);

                item->SaveToDB(trans);
                draft.AddItem(item);
                any = true;
            }

            if (start == 0 && gold)
            {
                draft.AddMoney(gold);
                any = true;
            }

            if (any)
                draft.SendMailTo(trans, MailReceiver(victim),
                    MailSender(MAIL_NORMAL, 0, MAIL_STATIONERY_GM), MAIL_CHECK_MASK_COPIED);

            CharacterDatabase.CommitTransaction(trans);
            start = stop;
        } while (start < items.size());

        CharacterDatabase.Execute("DELETE FROM character_hardcore_pvp_chest WHERE chest = {}", chestId);

        LOG_INFO("module", "mod-madosa: Hardcore PvP - chest {} crumbled unclaimed, "
            "{} item(s) and {} copper mailed back.", chestId, uint32(items.size()), gold);
    }

    // Puts the chest into the world. The contents are already in the table by
    // the time this runs, so if the map refuses the object nothing is lost -
    // the caller mails the rows straight back.
    bool SpawnDeathChest(uint64 chestId, Player* killer, Player* victim, std::vector<DroppedItem> const& dropped,
        uint32 gold)
    {
        Map* map = victim->GetMap();
        if (!map)
            return false;

        GameObject* chest = new GameObject();
        G3D::Quat const rotation = G3D::Quat::fromAxisAngleRotation(G3D::Vector3::unitZ(), victim->GetOrientation());
        if (!chest->Create(map->GenerateLowGuid<HighGuid::GameObject>(), DEATH_CHEST_ENTRY, map, PHASEMASK_NORMAL,
            victim->GetPositionX(), victim->GetPositionY(), victim->GetPositionZ(), victim->GetOrientation(),
            rotation, 0, GO_STATE_READY))
        {
            delete chest;
            LOG_ERROR("module", "mod-madosa: could not create gameobject {} (is hardcore_pvp.sql applied?)",
                DEATH_CHEST_ENTRY);
            return false;
        }

        // The chest template carries no loot id, so nothing here is ever
        // regenerated or cleared out from under us - see the file header.
        chest->loot.clear();
        chest->loot.loot_type = LOOT_CORPSE;
        chest->loot.lootOwnerGUID = killer->GetGUID();
        chest->loot.gold = gold;
        for (DroppedItem const& drop : dropped)
        {
            LootStoreItem storeItem(drop.entry, 0, 100.0f, false, LOOT_MODE_DEFAULT, 0, drop.count, drop.count);
            LootItem item(storeItem);

            // See the note in mod_madosa_hardcore_pvp_loot.cpp: the constructor
            // leaves count at 0, and an entry with no count is visible in the
            // window but impossible to take. This is why the very first death
            // chest could not be looted by anyone - not the killer, not the
            // victim - and its contents were lost when it crumbled.
            item.count = drop.count;
            item.randomPropertyId = drop.randomPropertyId;
            item.randomSuffix = drop.suffixFactor;
            item.itemIndex = chest->loot.items.size();
            chest->loot.items.push_back(item);
            ++chest->loot.unlootedCount;
        }

        if (!map->AddToMap(chest))
        {
            delete chest;
            LOG_ERROR("module", "mod-madosa: map {} refused the death chest for {}", map->GetId(), victim->GetName());
            return false;
        }

        time_t const now = GameTime::GetGameTime().count();
        DeathChest record;
        record.id = chestId;
        record.mapId = map->GetId();
        record.victim = victim->GetGUID().GetCounter();
        record.owner = killer->GetGUID();
        record.ownerGroup = killer->GetGroup() ? killer->GetGroup()->GetGUID() : ObjectGuid::Empty;
        record.expiresAt = now + time_t(MadosaSettings::GetHardcorePvPChestLifetime()) * MINUTE;
        record.items = dropped;

        {
            std::lock_guard<std::mutex> lock(chestMutex);
            chests[chest->GetGUID()] = std::move(record);
        }

        LOG_INFO("module", "mod-madosa: Hardcore PvP - {} killed {}, {} item(s) and {} copper dropped.",
            killer->GetName(), victim->GetName(), dropped.size(), gold);
        return true;
    }

    // Bots have a session too, so "is this worth telling anyone" is a question
    // about the player, not about whether a session exists.
    void Tell(Player* player, std::string const& message)
    {
        if (player && player->GetSession() && !IsBotSession(player))
            ChatHandler(player->GetSession()).PSendSysMessage("{}", message);
    }

    // Who may open a death chest:
    //
    //   the killer, the killer's group, and the victim - at once
    //   anyone else - only if they are in High-Risk themselves
    //
    // The victim was originally locked out for the first two minutes, and that
    // was wrong in a way only playing showed: on a realm where the killer is
    // almost always a bot that walks off without looting, the victim stood next
    // to their own belongings unable to touch them until the chest crumbled.
    // Their own things are theirs to race for.
    //
    // Everyone else has to be in High-Risk. A chest is what High-Risk players
    // stake against each other; someone who risks nothing does not get to
    // collect from it.
    //
    // Answered in two places for the same chest: the loot check, and the
    // sparkle the client draws on it - so a player only ever sees glitter on a
    // chest they can actually open. Returns false for anything that is not one
    // of our chests, so callers can tell "no opinion" from "no".
    bool IsDeathChest(ObjectGuid guid, DeathChest* out = nullptr)
    {
        std::lock_guard<std::mutex> lock(chestMutex);
        auto chest = chests.find(guid);
        if (chest == chests.end())
            return false;

        if (out)
        {
            out->id = chest->second.id;
            out->owner = chest->second.owner;
            out->ownerGroup = chest->second.ownerGroup;
            out->victim = chest->second.victim;
        }
        return true;
    }

    bool MayOpenChest(Player const* player, DeathChest const& chest)
    {
        if (player->GetGUID() == chest.owner || player->GetGUID().GetCounter() == chest.victim)
            return true;

        if (chest.ownerGroup && player->GetGroup() && player->GetGroup()->GetGUID() == chest.ownerGroup)
            return true;

        return MadosaHardcorePvP::IsHighRisk(player);
    }

    // The order here is the safety: the contents are written to the table
    // first, the items leave the bags second, the chest appears third. Whatever
    // fails after the first step can only ever delay the return, not lose it.
    // The first version did it the other way round - destroy, then spawn, then
    // record - and a chest the map refused would have taken the bags with it.
    void HandleHardcoreKill(Player* killer, Player* victim)
    {
        // Insurance pays out instead of the bags, and is spent doing it. The
        // gold is the premium the victim already paid, so nothing is minted
        // here - it changes hands.
        if (MadosaSettings::GetHardcorePvPInsuranceEnable() && GetState(victim).insured)
        {
            uint32 const gold = MadosaSettings::GetHardcorePvPInsuranceCost();

            ModeState state = GetState(victim);
            state.insured = false;
            {
                std::unique_lock<std::shared_mutex> lock(statesMutex);
                states[victim->GetGUID().GetCounter()] = state;
            }
            SaveState(victim->GetGUID().GetCounter(), state);

            uint64 const chestId = nextChestId++;
            RecordChestContents(chestId, victim, {}, gold * GOLD);
            if (!SpawnDeathChest(chestId, killer, victim, {}, gold * GOLD))
            {
                MailChestBack(chestId);
                return;
            }

            MadosaChronicle::Record("insurance", killer, victim, gold, "");
            Tell(victim, Acore::StringFormat("Your insurance paid out: {} gold instead of your belongings. "
                "You are no longer insured.", gold));
            Tell(killer, Acore::StringFormat("{} was insured - the chest holds gold, not gear.", victim->GetName()));
            return;
        }

        std::vector<Item*> candidates = CollectDroppable(victim);
        if (candidates.empty())
        {
            Tell(victim, "You were carrying nothing worth losing.");
            return;
        }

        uint32 wanted = uint32(candidates.size()) * MadosaSettings::GetHardcorePvPDropPercent() / 100;
        wanted = std::max<uint32>(1, wanted);
        wanted = std::min<uint32>(wanted, MadosaSettings::GetHardcorePvPDropMaxItems());
        wanted = std::min<uint32>(wanted, MAX_NR_LOOT_ITEMS);
        wanted = std::min<uint32>(wanted, uint32(candidates.size()));

        std::vector<Item*> taken;
        std::vector<DroppedItem> dropped;
        taken.reserve(wanted);
        dropped.reserve(wanted);
        for (uint32 i = 0; i < wanted; ++i)
        {
            uint32 const pick = urand(0, uint32(candidates.size()) - 1);
            Item* item = candidates[pick];
            candidates[pick] = candidates.back();
            candidates.pop_back();

            DroppedItem drop;
            drop.entry = item->GetEntry();
            drop.count = uint8(item->GetCount());
            drop.randomPropertyId = item->GetItemRandomPropertyId();
            drop.suffixFactor = item->GetItemSuffixFactor();
            for (uint8 slot = 0; slot < MAX_ENCHANTMENT_SLOT; ++slot)
                drop.enchants[slot] = item->GetEnchantmentId(EnchantmentSlot(slot));

            taken.push_back(item);
            dropped.push_back(drop);
        }

        uint64 const chestId = nextChestId++;
        RecordChestContents(chestId, victim, dropped, 0);

        for (Item* item : taken)
            victim->DestroyItem(item->GetBagSlot(), item->GetSlot(), true);

        if (!SpawnDeathChest(chestId, killer, victim, dropped, 0))
        {
            MailChestBack(chestId);
            Tell(victim, "Hardcore PvP: your belongings could not be laid down where you fell - "
                "they are on their way back to you by mail.");
            return;
        }

        MadosaChronicle::Record("chest", killer, victim, int64(dropped.size()), "");

        Tell(victim, Acore::StringFormat("Hardcore PvP: {} of your belongings spilled where you fell.",
            uint32(dropped.size())));
        Tell(killer, Acore::StringFormat("Hardcore PvP: {} left a chest behind.", victim->GetName()));
    }

    // Chests are deleted by us rather than by the core: the template is not
    // consumed on loot, so an emptied chest would otherwise stand there for the
    // rest of the uptime holding nothing.
    void ExpireChests()
    {
        time_t const now = GameTime::GetGameTime().count();

        std::vector<std::pair<uint32, ObjectGuid>> toDelete;
        std::vector<uint64> toMailBack;
        {
            std::lock_guard<std::mutex> lock(chestMutex);
            for (auto itr = chests.begin(); itr != chests.end();)
            {
                Map* map = sMapMgr->FindBaseNonInstanceMap(itr->second.mapId);
                GameObject* chest = map ? map->GetGameObject(itr->first) : nullptr;

                if (!chest || now >= itr->second.expiresAt || chest->loot.isLooted())
                {
                    if (chest)
                        toDelete.push_back({ itr->second.mapId, itr->first });

                    // Emptied chests have no rows left, so this is a no-op for
                    // them; it only does something when the chest went away
                    // with belongings still in it.
                    toMailBack.push_back(itr->second.id);
                    itr = chests.erase(itr);
                    continue;
                }

                ++itr;
            }
        }

        for (uint64 chestId : toMailBack)
            MailChestBack(chestId);

        for (auto const& [mapId, guid] : toDelete)
            if (Map* map = sMapMgr->FindBaseNonInstanceMap(mapId))
                if (GameObject* chest = map->GetGameObject(guid))
                    chest->Delete();
    }

    // Otherwise this grows for the whole uptime: one entry per pair of players
    // who have ever fought, kept long after the cooldown it records has run out.
    void PruneRecentKills()
    {
        time_t const now = GameTime::GetGameTime().count();
        std::lock_guard<std::mutex> lock(recentKillsMutex);
        for (auto itr = recentKills.begin(); itr != recentKills.end();)
            itr = now >= itr->second ? recentKills.erase(itr) : std::next(itr);
    }

    // Player::UpdateFFAPvPState() clears the flag on every area change; this is
    // where traitors get it back. Only traitors are visited, and only real ones
    // exist, so the loop is over a handful of players at most.
    void ReassertTraitorFlags()
    {
        std::vector<ObjectGuid::LowType> traitors;
        {
            std::shared_lock<std::shared_mutex> lock(statesMutex);
            for (auto const& [guid, state] : states)
                if (state.traitor)
                    traitors.push_back(guid);
        }

        for (ObjectGuid::LowType guid : traitors)
            if (Player* player = ObjectAccessor::FindPlayerByLowGUID(guid))
                if (!player->IsFFAPvP() && !player->pvpInfo.IsInNoPvPArea)
                    ApplyFFA(player, true);
    }
}

namespace MadosaHardcorePvP
{
    bool IsBot(Player const* player)
    {
        return IsBotSession(player);
    }

    RiskMode GetMode(Player const* player)
    {
        if (!MadosaSettings::GetHardcorePvPEnable())
            return RISK_MODE_PVE;

        return GetState(player).mode;
    }

    bool IsHighRisk(Player const* player)
    {
        return GetMode(player) == RISK_MODE_HIGH;
    }

    bool IsFlagged(Player const* player)
    {
        return GetMode(player) != RISK_MODE_PVE;
    }

    char const* ModeName(RiskMode mode)
    {
        switch (mode)
        {
            case RISK_MODE_WAR:  return "War Mode";
            case RISK_MODE_HIGH: return "High-Risk";
            default:             return "PvE";
        }
    }

    bool IsTraitor(Player const* player)
    {
        return MadosaSettings::GetHardcorePvPEnable() && GetState(player).traitor;
    }

    std::vector<std::string> Status()
    {
        uint32 war = 0;
        uint32 highRisk = 0;
        uint32 traitors = 0;
        {
            std::shared_lock<std::shared_mutex> lock(statesMutex);
            for (auto const& [guid, state] : states)
            {
                if (state.mode == RISK_MODE_WAR)
                    ++war;
                else if (state.mode == RISK_MODE_HIGH)
                    ++highRisk;
                if (state.traitor)
                    ++traitors;
            }
        }

        size_t standing = 0;
        {
            std::lock_guard<std::mutex> lock(chestMutex);
            standing = chests.size();
        }

        std::vector<std::string> out;
        out.push_back(Acore::StringFormat("Hardcore PvP is {}.",
            MadosaSettings::GetHardcorePvPEnable() ? "enabled" : "disabled"));
        out.push_back(Acore::StringFormat("{} online in War Mode, {} in High-Risk, {} of them traitors.",
            war, highRisk, traitors));
        out.push_back(Acore::StringFormat("{} death chest(s) standing.", uint32(standing)));
        return out;
    }

    bool SetMode(Player* player, RiskMode mode, std::string& outError)
    {
        if (IsBotSession(player))
        {
            outError = "Playerbots do not choose this for themselves.";
            return false;
        }

        if (mode == RISK_MODE_WAR && !MadosaSettings::GetHardcorePvPWarModeEnable())
        {
            outError = "War Mode is not enabled on this realm.";
            return false;
        }

        ModeState state = GetState(player);
        if (state.mode == mode)
        {
            outError = Acore::StringFormat("You are already in {}.", ModeName(mode));
            return false;
        }

        if (!CanToggle(player, mode != RISK_MODE_PVE, outError))
            return false;

        // Treason only means anything to someone who can be fought at all, and
        // leaving it on while dropping to PvE would be a flag with no way to
        // act on it. Stepping back to PvE renounces it in the same breath.
        if (mode == RISK_MODE_PVE)
            state.traitor = false;

        // Cover only means anything in High-Risk. Leaving it drops the cover
        // rather than banking it for a future return - otherwise the premium
        // could be bought cheaply now and cashed in much later.
        if (mode != RISK_MODE_HIGH)
            state.insured = false;

        time_t const now = GameTime::GetGameTime().count();
        state.mode = mode;
        state.since = mode != RISK_MODE_PVE ? now : 0;
        state.lastToggle = now;

        {
            std::unique_lock<std::shared_mutex> lock(statesMutex);
            states[player->GetGUID().GetCounter()] = state;
        }

        ApplyMarks(player, state);
        SaveState(player->GetGUID().GetCounter(), state);
        MadosaChronicle::Record("mode", player, nullptr, int64(mode), ModeName(mode));
        return true;
    }

    bool IsInsured(Player const* player)
    {
        return MadosaSettings::GetHardcorePvPInsuranceEnable() && GetState(player).insured;
    }

    bool BuyInsurance(Player* player, std::string& outError)
    {
        if (!MadosaSettings::GetHardcorePvPInsuranceEnable())
        {
            outError = "Insurance is not offered on this realm.";
            return false;
        }

        // Only High-Risk can lose anything, so only High-Risk has anything to
        // insure. Selling it to anyone else would be selling nothing.
        if (GetMode(player) != RISK_MODE_HIGH)
        {
            outError = "Only a High-Risk character has anything to insure.";
            return false;
        }

        ModeState state = GetState(player);
        if (state.insured)
        {
            outError = "You are already insured.";
            return false;
        }

        uint32 const cost = MadosaSettings::GetHardcorePvPInsuranceCost();
        if (!player->HasEnoughMoney(uint32(cost) * GOLD))
        {
            outError = Acore::StringFormat("That costs {} gold.", cost);
            return false;
        }

        player->ModifyMoney(-int32(cost * GOLD));

        state.insured = true;
        {
            std::unique_lock<std::shared_mutex> lock(statesMutex);
            states[player->GetGUID().GetCounter()] = state;
        }
        SaveState(player->GetGUID().GetCounter(), state);
        return true;
    }

    bool SetTraitor(Player* player, bool enable, std::string& outError)
    {
        if (IsBotSession(player))
        {
            outError = "Playerbots do not choose this for themselves.";
            return false;
        }

        if (enable && !MadosaSettings::GetHardcorePvPTraitorEnable())
        {
            outError = "Treason is not enabled on this realm.";
            return false;
        }

        ModeState state = GetState(player);

        // There is nothing to betray anyone with from PvE: treason opens
        // same-faction fighting, and a PvE character cannot fight at all.
        if (enable && state.mode == RISK_MODE_PVE)
        {
            outError = "Only War Mode or High-Risk can betray a faction.";
            return false;
        }
        if (state.traitor == enable)
        {
            outError = enable ? "You are already a traitor." : "You are already loyal.";
            return false;
        }

        if (!CanToggle(player, enable, outError))
            return false;

        time_t const now = GameTime::GetGameTime().count();
        state.traitor = enable;
        state.lastToggle = now;

        {
            std::unique_lock<std::shared_mutex> lock(statesMutex);
            states[player->GetGUID().GetCounter()] = state;
        }

        ApplyMarks(player, state);
        SaveState(player->GetGUID().GetCounter(), state);
        MadosaChronicle::Record(enable ? "treason" : "loyalty", player, nullptr, 0,
            player->GetTeamId() == TEAM_ALLIANCE ? "Alliance" : "Horde");
        return true;
    }
}

class mod_madosa_hardcore_pvp_player : public PlayerScript
{
public:
    mod_madosa_hardcore_pvp_player() : PlayerScript("mod_madosa_hardcore_pvp_player",
        {
            PLAYERHOOK_ON_LOGIN,
            PLAYERHOOK_ON_LOGOUT,
            PLAYERHOOK_ON_GIVE_EXP,
            PLAYERHOOK_ON_PVP_KILL,
            PLAYERHOOK_ON_LOOT_ITEM,
            PLAYERHOOK_ON_PLAYER_RESURRECT,
            PLAYERHOOK_ON_BEFORE_LOOT_MONEY,
        }) { }

    void OnPlayerLogin(Player* player) override
    {
        ModeState state;
        bool known = false;

        if (IsBotSession(player))
        {
            // Bots go straight to High-Risk or stay in PvE - never War Mode,
            // which would be a bot that can be fought but carries nothing, and
            // never traitors, because treason changes who may attack whom and
            // 3000 bots deciding that among themselves is a different realm
            // from the one this feature is for.
            known = BotParticipates(player->GetGUID().GetCounter());
            state.mode = known ? MadosaHardcorePvP::RISK_MODE_HIGH : MadosaHardcorePvP::RISK_MODE_PVE;
        }
        else if (QueryResult result = CharacterDatabase.Query(
            "SELECT mode, traitor, insured, mode_since, last_toggle FROM character_hardcore_pvp WHERE guid = {}",
            player->GetGUID().GetCounter()))
        {
            Field* fields = result->Fetch();
            state.mode = MadosaHardcorePvP::RiskMode(std::min<uint8>(fields[0].Get<uint8>(),
                MadosaHardcorePvP::RISK_MODE_HIGH));
            state.traitor = fields[1].Get<uint8>() != 0;
            state.insured = fields[2].Get<uint8>() != 0;
            state.since = time_t(fields[3].Get<int64>());
            state.lastToggle = time_t(fields[4].Get<int64>());

            // Remembered even when both modes are off, because the row still
            // carries when they were last changed - drop it here and logging
            // out would be a way around the toggle cooldown.
            known = true;
        }

        if (!known)
            return;

        {
            std::unique_lock<std::shared_mutex> lock(statesMutex);
            states[player->GetGUID().GetCounter()] = state;
        }

        if (state.mode != MadosaHardcorePvP::RISK_MODE_PVE || state.traitor)
            ApplyMarks(player, state);
    }

    void OnPlayerLogout(Player* player) override
    {
        std::unique_lock<std::shared_mutex> lock(statesMutex);
        states.erase(player->GetGUID().GetCounter());
    }

    // Auras survive death (SPELL_ATTR3_ALLOW_AURA_WHILE_DEAD), but a resurrect
    // is the one moment worth re-asserting them: a spirit healer, a battleground
    // exit or a GM revive can all strip a player down first.
    void OnPlayerResurrect(Player* player, float /*restorePercent*/, bool& /*applySickness*/) override
    {
        ModeState const state = GetState(player);
        if (state.mode != MadosaHardcorePvP::RISK_MODE_PVE || state.traitor)
            ApplyMarks(player, state);
    }

    void OnPlayerGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 /*xpSource*/) override
    {
        // Both flagged modes force the PvP flag on, so an unflagged player
        // cannot be in either - and that is a bit test on the unit rather than
        // a lock on the shared mode table. Called on every experience gain of
        // every bot, so it is worth the two lines.
        if (!player->IsPvP())
            return;

        // Two rates, because the two modes stake different things: War Mode
        // risks only being attackable, High-Risk risks the bags as well.
        uint32 percent = 0;
        switch (MadosaHardcorePvP::GetMode(player))
        {
            case MadosaHardcorePvP::RISK_MODE_WAR:
                percent = MadosaSettings::GetHardcorePvPWarModeXPPercent();
                break;
            case MadosaHardcorePvP::RISK_MODE_HIGH:
                percent = MadosaSettings::GetHardcorePvPXPPercent();
                break;
            default:
                return;
        }

        if (!percent)
            return;

        amount = uint32(amount * (1.0f + percent / 100.0f));
    }

    void OnPlayerPVPKill(Player* killer, Player* victim) override
    {
        if (!MadosaSettings::GetHardcorePvPEnable() || killer == victim)
            return;

        // The rule the whole mode rests on: a chest is what two hardcore
        // players stake against each other, and nothing a hardcore player can
        // take from anyone else.
        if (!MadosaHardcorePvP::IsHighRisk(killer) || !MadosaHardcorePvP::IsHighRisk(victim))
            return;

        if (killer->InBattleground() || killer->InArena() || killer->duel || victim->duel)
            return;

        if (victim->GetLevel() < MadosaSettings::GetHardcorePvPMinLevel())
            return;

        // Not worth honour means not worth loot either - which is also what
        // stops a player farming their own low-level alt.
        if (!killer->isHonorOrXPTarget(victim))
            return;

        Map* map = victim->GetMap();
        if (!map || map->Instanceable())
            return;

        time_t const now = GameTime::GetGameTime().count();
        uint32 const cooldown = MadosaSettings::GetHardcorePvPRepeatKillCooldown();
        if (cooldown)
        {
            std::lock_guard<std::mutex> lock(recentKillsMutex);
            uint64 const key = KillPairKey(killer, victim);
            auto itr = recentKills.find(key);
            if (itr != recentKills.end() && now < itr->second)
                return;

            recentKills[key] = now + time_t(cooldown) * MINUTE;
        }

        HandleHardcoreKill(killer, victim);
    }

    // The gold's counterpart to OnPlayerLootItem below: taking it out of the
    // chest takes its row out of the table, so it is not also mailed back.
    // Runs before the core zeroes loot->gold, which is the only reason the
    // amount is still readable here.
    void OnPlayerBeforeLootMoney(Player* player, Loot* loot) override
    {
        if (!loot || !loot->gold)
            return;

        ObjectGuid const lootguid = player->GetLootGUID();
        if (!lootguid.IsGameObject())
            return;

        uint64 chestId = 0;
        {
            std::lock_guard<std::mutex> lock(chestMutex);
            auto chest = chests.find(lootguid);
            if (chest == chests.end())
                return;

            chestId = chest->second.id;
        }

        CharacterDatabase.Execute(
            "DELETE FROM character_hardcore_pvp_chest WHERE chest = {} AND slot = {}", chestId, GOLD_SLOT);
    }

    // Loot cannot express an enchantment, so the ones recorded when the item
    // was taken off the victim are put back on the item the looter just got.
    void OnPlayerLootItem(Player* /*player*/, Item* item, uint32 /*count*/, ObjectGuid lootguid) override
    {
        if (!item)
            return;

        // Before the lock, and that is the whole point: this fires for every
        // item every one of three thousand bots ever loots, and taking a global
        // mutex that often serialises the map threads against each other. A
        // death chest is a gameobject; creature corpses are not, and they are
        // effectively all of the traffic.
        if (!lootguid.IsGameObject())
            return;

        DroppedItem source;
        uint64 chestId = 0;
        {
            std::lock_guard<std::mutex> lock(chestMutex);
            auto chest = chests.find(lootguid);
            if (chest == chests.end())
                return;

            auto entry = std::find_if(chest->second.items.begin(), chest->second.items.end(),
                [item](DroppedItem const& drop) { return drop.entry == item->GetEntry(); });
            if (entry == chest->second.items.end())
                return;

            source = *entry;
            chest->second.items.erase(entry);
            chestId = chest->second.id;
        }

        // Claimed, so it must not also come back by mail.
        if (chestId)
            CharacterDatabase.Execute(
                "DELETE FROM character_hardcore_pvp_chest WHERE chest = {} AND item = {} LIMIT 1",
                chestId, source.entry);

        bool changed = false;
        for (uint8 slot = 0; slot < MAX_ENCHANTMENT_SLOT; ++slot)
        {
            if (!source.enchants[slot])
                continue;

            item->SetEnchantment(EnchantmentSlot(slot), source.enchants[slot], 0, 0);
            changed = true;
        }

        if (changed)
            item->SetState(ITEM_CHANGED, item->GetOwner());
    }
};

class mod_madosa_hardcore_pvp_global : public GlobalScript
{
public:
    mod_madosa_hardcore_pvp_global() : GlobalScript("mod_madosa_hardcore_pvp_global",
        { GLOBALHOOK_ON_ALLOWED_TO_LOOT_CONTAINER_CHECK }) { }

    // Careful with the polarity: CALL_ENABLED_BOOLEAN_HOOKS turns a `true` here
    // into a `false` at the call site, so returning true is what *denies* the
    // loot. Everything that is not one of our chests returns false, i.e. "no
    // opinion". The rule itself is MayOpenChest(), shared with the sparkle.
    bool OnAllowedToLootContainerCheck(Player const* player, ObjectGuid source) override
    {
        DeathChest chest;
        if (!IsDeathChest(source, &chest))
            return false;

        return !MayOpenChest(player, chest);
    }
};

// The chest's own script, for one thing only: the sparkle. The client draws
// the quest glitter on a gameobject when the server flags it activatable for
// that player, and the core decides that from the quest log - which knows
// nothing about a chest full of somebody's bags. This answers the question
// instead, with the same rule the loot check uses, so the chest glitters for
// exactly the people who may open it and for nobody else. It is the one core
// hook this feature needed: GameObjectScript::OnActivateToQuest.
class go_madosa_death_chest : public GameObjectScript
{
public:
    go_madosa_death_chest() : GameObjectScript("go_madosa_death_chest") { }

    bool OnActivateToQuest(Player* player, GameObject const* go) override
    {
        DeathChest chest;
        if (!IsDeathChest(go->GetGUID(), &chest))
            return false;

        return MayOpenChest(player, chest);
    }
};

class mod_madosa_hardcore_pvp_support : public UnitScript
{
public:
    mod_madosa_hardcore_pvp_support() : UnitScript("mod_madosa_hardcore_pvp_support", true,
        { UNITHOOK_MODIFY_HEAL_RECEIVED, UNITHOOK_ON_AURA_APPLY }) { }

    // Refuses when `helper` is in PvE and `target` is flagged, both are real
    // players, and this is the open world.
    static bool Refuses(Unit const* helper, Unit const* target)
    {
        if (!MadosaSettings::GetHardcorePvPEnable() || !helper || !target || helper == target)
            return false;

        Player const* giver = helper->ToPlayer();
        Player const* taker = target->ToPlayer();
        if (!giver || !taker)
            return false;

        // Lock-free gate first. Only a flagged player can be in War Mode or
        // High-Risk, so an unflagged target rules the whole rule out with a bit
        // test. This runs on every positive aura applied anywhere in the world,
        // which on this realm is a torrent.
        //
        // The byte flag rather than IsPvP(): Player declares its own non-const
        // IsPvP() (Player.h:2480) which hides Unit's const one, and everything
        // reaching this function is const.
        if (!taker->HasByteFlag(UNIT_FIELD_BYTES_2, 1, UNIT_BYTE2_FLAG_PVP))
            return false;

        if (MadosaHardcorePvP::GetMode(giver) != MadosaHardcorePvP::RISK_MODE_PVE)
            return false;

        if (!MadosaHardcorePvP::IsFlagged(taker))
            return false;

        // "in the open world": a battleground or an arena has its own rules
        // about who may help whom, and they are not ours to override.
        Map const* map = giver->GetMap();
        return map && !map->Instanceable();
    }

    // Careful with the parameter names: Unit.cpp:8409 calls this as
    // ModifyHealReceived(this, healInfo.GetTarget(), ...) from
    // Unit::HealBySpell, which callers invoke as caster->HealBySpell(...). So
    // the argument the hook declares as "target" is the *healer*, and the one
    // it calls "healer" is the target. Taking the names at face value would
    // point this rule the wrong way round.
    void ModifyHealReceived(Unit* healer, Unit* target, uint32& heal, SpellInfo const* /*spellInfo*/) override
    {
        if (Refuses(healer, target))
            heal = 0;
    }

    void OnAuraApply(Unit* target, Aura* aura) override
    {
        if (!aura || !aura->GetSpellInfo()->IsPositive())
            return;

        // Only a timed aura can be told to end; see the note above.
        if (aura->GetDuration() <= 0)
            return;

        if (Refuses(aura->GetCaster(), target))
            aura->SetDuration(0);
    }
};

class mod_madosa_hardcore_pvp_world : public WorldScript
{
    uint32 _timer = 0;

public:
    mod_madosa_hardcore_pvp_world() : WorldScript("mod_madosa_hardcore_pvp_world") { }

    void OnStartup() override
    {
        // Ids continue where the last run left off. Restarting at 1 would let a
        // fresh chest adopt the rows of an old one that is still being cleaned
        // up here.
        if (QueryResult result = CharacterDatabase.Query(
            "SELECT IFNULL(MAX(chest), 0) + 1 FROM character_hardcore_pvp_chest"))
            nextChestId = result->Fetch()[0].Get<uint64>();

        // Anything still in the table belongs to a chest that no longer exists -
        // the server went down while it was standing. Its owner gets it back.
        QueryResult leftovers = CharacterDatabase.Query(
            "SELECT DISTINCT chest FROM character_hardcore_pvp_chest");

        if (!leftovers)
            return;

        std::vector<uint64> ids;
        do
        {
            ids.push_back(leftovers->Fetch()[0].Get<uint64>());
        } while (leftovers->NextRow());

        for (uint64 chestId : ids)
            MailChestBack(chestId);

        LOG_INFO("module", "mod-madosa: Hardcore PvP returned {} chest(s) left over from the last run.",
            uint32(ids.size()));
    }

    void OnUpdate(uint32 diff) override
    {
        _timer += diff;
        if (_timer < TICK_INTERVAL_MS)
            return;

        _timer = 0;

        if (!MadosaSettings::GetHardcorePvPEnable())
            return;

        ExpireChests();
        ReassertTraitorFlags();
        PruneRecentKills();
    }
};

enum HeraldGossip
{
    GOSSIP_ACTION_MODE_PVE = GOSSIP_ACTION_INFO_DEF + 1,
    GOSSIP_ACTION_MODE_WAR,
    GOSSIP_ACTION_MODE_HIGH,
    GOSSIP_ACTION_INSURE,
    GOSSIP_ACTION_TRAITOR_ON,
    GOSSIP_ACTION_TRAITOR_OFF,
    GOSSIP_ACTION_EXPLAIN,
};

// Deliberately faction-neutral and also standing in the neutral towns: a
// traitor's own capital is hostile ground, and the one NPC that can take the
// flag back off must not be behind its guards.
class npc_madosa_hardcore_herald : public CreatureScript
{
public:
    npc_madosa_hardcore_herald() : CreatureScript("npc_madosa_hardcore_herald") { }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        if (!MadosaSettings::GetHardcorePvPEnable())
        {
            ChatHandler(player->GetSession()).PSendSysMessage("Hardcore PvP is not enabled on this realm.");
            CloseGossipMenuFor(player);
            return true;
        }

        ClearGossipMenuFor(player);

        using namespace MadosaHardcorePvP;

        ModeState const state = GetState(player);

        // Only the modes the player is not already in - a menu that offers you
        // what you have is a menu you have to read twice.
        if (state.mode != RISK_MODE_PVE)
            AddGossipItemFor(player, GOSSIP_ICON_CHAT, "Return to PvE. I want no part of this.",
                GOSSIP_SENDER_MAIN, GOSSIP_ACTION_MODE_PVE);

        if (state.mode != RISK_MODE_WAR && MadosaSettings::GetHardcorePvPWarModeEnable())
            AddGossipItemFor(player, GOSSIP_ICON_BATTLE,
                Acore::StringFormat("Enter War Mode. (+{}% experience, nothing at stake.)",
                    MadosaSettings::GetHardcorePvPWarModeXPPercent()),
                GOSSIP_SENDER_MAIN, GOSSIP_ACTION_MODE_WAR);

        if (state.mode != RISK_MODE_HIGH)
            AddGossipItemFor(player, GOSSIP_ICON_BATTLE,
                Acore::StringFormat("Enter High-Risk. (+{}% experience, dungeon drops - and your bags.)",
                    MadosaSettings::GetHardcorePvPXPPercent()),
                GOSSIP_SENDER_MAIN, GOSSIP_ACTION_MODE_HIGH);

        if (MadosaSettings::GetHardcorePvPInsuranceEnable() && state.mode == RISK_MODE_HIGH)
        {
            if (state.insured)
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG,
                    "My belongings are insured. (One death is covered.)",
                    GOSSIP_SENDER_MAIN, GOSSIP_ACTION_EXPLAIN);
            else
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG,
                    Acore::StringFormat("Insure my belongings. ({} gold, covers one death.)",
                        MadosaSettings::GetHardcorePvPInsuranceCost()),
                    GOSSIP_SENDER_MAIN, GOSSIP_ACTION_INSURE);
        }

        if (MadosaSettings::GetHardcorePvPTraitorEnable() && state.mode != RISK_MODE_PVE)
        {
            std::string const side = player->GetTeamId() == TEAM_ALLIANCE ? "Alliance" : "Horde";
            if (state.traitor)
                AddGossipItemFor(player, GOSSIP_ICON_TALK,
                    Acore::StringFormat("Renounce my treason against the {}.", side),
                    GOSSIP_SENDER_MAIN, GOSSIP_ACTION_TRAITOR_OFF);
            else
                AddGossipItemFor(player, GOSSIP_ICON_TALK,
                    Acore::StringFormat("Betray the {}.", side),
                    GOSSIP_SENDER_MAIN, GOSSIP_ACTION_TRAITOR_ON);
        }

        AddGossipItemFor(player, GOSSIP_ICON_CHAT, "What does any of this mean?",
            GOSSIP_SENDER_MAIN, GOSSIP_ACTION_EXPLAIN);

        SendGossipMenuFor(player, HERALD_GOSSIP_TEXT, creature->GetGUID());
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* /*creature*/, uint32 /*sender*/, uint32 action) override
    {
        ChatHandler handler(player->GetSession());
        std::string error;

        switch (action)
        {
            case GOSSIP_ACTION_MODE_PVE:
                if (MadosaHardcorePvP::SetMode(player, MadosaHardcorePvP::RISK_MODE_PVE, error))
                    handler.PSendSysMessage("You are back in PvE. No one can touch you out there - "
                        "and you can no longer heal or buff anyone who can be touched.");
                else
                    handler.PSendSysMessage("{}", error);
                break;
            case GOSSIP_ACTION_MODE_WAR:
                if (MadosaHardcorePvP::SetMode(player, MadosaHardcorePvP::RISK_MODE_WAR, error))
                    handler.PSendSysMessage("War Mode. You are open to the world now, but it cannot take "
                        "anything off you.");
                else
                    handler.PSendSysMessage("{}", error);
                break;
            case GOSSIP_ACTION_MODE_HIGH:
                if (MadosaHardcorePvP::SetMode(player, MadosaHardcorePvP::RISK_MODE_HIGH, error))
                    handler.PSendSysMessage("High-Risk. More experience, richer world drops - and what you "
                        "carry is now worth taking.");
                else
                    handler.PSendSysMessage("{}", error);
                break;
            case GOSSIP_ACTION_INSURE:
                if (MadosaHardcorePvP::BuyInsurance(player, error))
                    handler.PSendSysMessage("Insured. The next High-Risk player to kill you finds your premium in "
                        "gold where your belongings would have been - once.");
                else
                    handler.PSendSysMessage("{}", error);
                break;
            case GOSSIP_ACTION_TRAITOR_ON:
                if (MadosaHardcorePvP::SetTraitor(player, true, error))
                    handler.PSendSysMessage("Your own cities will not have you now. Other traitors are fair game, "
                        "whatever banner they were born under.");
                else
                    handler.PSendSysMessage("{}", error);
                break;
            case GOSSIP_ACTION_TRAITOR_OFF:
                if (MadosaHardcorePvP::SetTraitor(player, false, error))
                    handler.PSendSysMessage("Your treason is forgiven. Your cities will have you back.");
                else
                    handler.PSendSysMessage("{}", error);
                break;
            case GOSSIP_ACTION_EXPLAIN:
                handler.PSendSysMessage("Three ways to be out there. PvE is the default: nobody can attack you, "
                    "and you cannot heal or buff anyone who can be attacked.");
                handler.PSendSysMessage("War Mode: +{}% experience and you are open to any other flagged player. "
                    "Nothing of yours is ever taken.",
                    MadosaSettings::GetHardcorePvPWarModeXPPercent());
                handler.PSendSysMessage("High-Risk: +{}% experience, and world mobs may drop dungeon and raid gear "
                    "for your level. But killed by another High-Risk player, you drop part of what your bags hold - "
                    "and only ever to another High-Risk player.",
                    MadosaSettings::GetHardcorePvPXPPercent());
                handler.PSendSysMessage("Treason lets you fight your own kind: traitors are hostile to each other "
                    "whatever their faction. Your own cities turn on you while it lasts.");
                handler.PSendSysMessage("All of it is changed here, or with \".hardcore\", in any inn or city.");
                break;
            default:
                break;
        }

        CloseGossipMenuFor(player);
        return true;
    }
};

void AddSC_madosa_hardcore_pvp()
{
    new mod_madosa_hardcore_pvp_player();
    new mod_madosa_hardcore_pvp_global();
    new go_madosa_death_chest();
    new mod_madosa_hardcore_pvp_support();
    new mod_madosa_hardcore_pvp_world();
    new npc_madosa_hardcore_herald();
}
