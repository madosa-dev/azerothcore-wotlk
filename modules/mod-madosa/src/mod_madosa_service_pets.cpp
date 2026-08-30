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

// Repairbot and Mailbot: two more convenience companions in the same spirit as
// Bankbot and Auctionbot, but the two that could NOT be done as pure gossip data.
//
// Bankbot/Auctionbot get away with SQL alone because the core exposes a gossip
// option type for those services (GOSSIP_OPTION_BANKER / _AUCTIONEER) that opens
// the window on its own. Neither of these has that:
//
//   Mail   - there is simply no GOSSIP_OPTION_MAILBOX in Gossip_Option. A creature
//            *can* serve as a mailbox (MailHandler checks GetNPCIfCanInteractWith
//            with UNIT_NPC_FLAG_MAILBOX), it just has to be opened from script.
//            The Argent Pony does exactly this in scripts/Pet/pet_generic.cpp.
//
//   Repair - GOSSIP_OPTION_ARMORER exists but PlayerGossip.cpp sets canTalk = false
//            for it ("added in special mode"), so it is never shown as a menu entry:
//            repairing normally happens through the *merchant* frame, off the
//            UNIT_NPC_FLAG_REPAIR flag. Going that route would mean giving the pet
//            a vendor inventory it has no business having - an empty one makes
//            SendListInventory answer "Vendor has no inventory" and the window
//            never opens properly. Repairing straight from gossip is both simpler
//            and better UX, and is what .gear repair does internally anyway.
//
// Both charge the player normally (Repairbot through the standard durability cost),
// so neither shortcuts a gold sink - they only remove the walk back to town.

#include "Chat.h"
#include "Creature.h"
#include "CreatureScript.h"
#include "GossipDef.h"
#include "Item.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "ScriptedGossip.h"
#include "UnitDefines.h"
#include "WorldSession.h"
#include "mod_madosa_settings.h"

#include <string>

namespace
{
    // Same slot range DurabilityRepairAll() itself walks: equipped items, the
    // backpack and the bags, plus the contents of those bags. Kept in sync with
    // Player::DurabilityRepairAll - if that ever grows a slot, this must too, or
    // the pet would claim "nothing to repair" while the repair call still charges.
    bool HasDamagedItems(Player* player)
    {
        auto damaged = [](Item* item)
        {
            if (!item)
                return false;

            uint32 maxDurability = item->GetUInt32Value(ITEM_FIELD_MAXDURABILITY);
            return maxDurability && item->GetUInt32Value(ITEM_FIELD_DURABILITY) < maxDurability;
        };

        for (uint8 i = EQUIPMENT_SLOT_START; i < INVENTORY_SLOT_ITEM_END; ++i)
            if (damaged(player->GetItemByPos(INVENTORY_SLOT_BAG_0, i)))
                return true;

        for (uint8 bag = INVENTORY_SLOT_BAG_START; bag < INVENTORY_SLOT_BAG_END; ++bag)
            for (uint8 i = 0; i < MAX_BAG_SIZE; ++i)
                if (damaged(player->GetItemByPos(bag, i)))
                    return true;

        return false;
    }

    // Copper -> "12g 34s 56c", skipping the units that would read as zero.
    std::string FormatMoney(uint32 copper)
    {
        uint32 gold = copper / GOLD;
        uint32 silver = (copper % GOLD) / SILVER;
        uint32 rest = copper % SILVER;

        std::string out;
        if (gold)
            out += std::to_string(gold) + "g ";
        if (gold || silver)
            out += std::to_string(silver) + "s ";
        out += std::to_string(rest) + "c";
        return out;
    }

    // Shared by Repairbot and Omnibot so the two can never drift apart.
    void RepairFor(Player* player)
    {
        ChatHandler handler(player->GetSession());

        if (!HasDamagedItems(player))
        {
            handler.PSendSysMessage("Your equipment is already in perfect condition.");
            return;
        }

        // The money actually spent has to be measured, NOT taken from the return
        // value: Player::DurabilityRepair() only assigns TotalCost in its guild-bank
        // branch, so a normal repair paid from the player's own purse always reports
        // 0 - which is indistinguishable from "could not afford a thing" and made
        // this claim the player was broke right after charging them.
        uint32 moneyBefore = player->GetMoney();

        // discountMod 1.0f = no reputation discount (the pet has no faction to like
        // you), guildBank false = always the player's own money.
        player->DurabilityRepairAll(true, 1.0f, false);

        uint32 moneyAfter = player->GetMoney();
        uint32 spent = moneyBefore > moneyAfter ? moneyBefore - moneyAfter : 0;
        bool stillDamaged = HasDamagedItems(player);

        if (!spent && stillDamaged)
        {
            handler.PSendSysMessage("You cannot afford the repairs.");
            return;
        }

        // DurabilityRepairAll skips (rather than fails on) any single item the player
        // ran out of money for, so spending something does not prove everything got fixed.
        if (stillDamaged)
            handler.PSendSysMessage("Repaired what you could afford, for {} - some items are still damaged.",
                                    FormatMoney(spent));
        else
            handler.PSendSysMessage("Equipment fully repaired for {}.", FormatMoney(spent));
    }
}

// "Repairbot" - repairs everything the player is carrying, for the normal cost.
class npc_madosa_repairbot : public CreatureScript
{
public:
    npc_madosa_repairbot() : CreatureScript("npc_madosa_repairbot") { }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        if (!MadosaSettings::GetRepairPetEnable())
            return false;

        ClearGossipMenuFor(player);
        AddGossipItemFor(player, GOSSIP_ICON_INTERACT_1, "Repair all my equipment.",
                         GOSSIP_SENDER_MAIN, GOSSIP_ACTION_INFO_DEF);
        SendGossipMenuFor(player, player->GetGossipTextId(creature), creature);
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* /*creature*/, uint32 /*sender*/, uint32 action) override
    {
        CloseGossipMenuFor(player);

        if (!MadosaSettings::GetRepairPetEnable() || action != GOSSIP_ACTION_INFO_DEF)
            return true;

        RepairFor(player);
        return true;
    }
};

// "Mailbot" - opens the player's mailbox from anywhere.
class npc_madosa_mailbot : public CreatureScript
{
public:
    npc_madosa_mailbot() : CreatureScript("npc_madosa_mailbot") { }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        if (!MadosaSettings::GetMailPetEnable())
            return false;

        ClearGossipMenuFor(player);
        AddGossipItemFor(player, GOSSIP_ICON_INTERACT_1, "I would like to check my mail.",
                         GOSSIP_SENDER_MAIN, GOSSIP_ACTION_INFO_DEF);
        SendGossipMenuFor(player, player->GetGossipTextId(creature), creature);
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* creature, uint32 /*sender*/, uint32 action) override
    {
        if (!MadosaSettings::GetMailPetEnable() || action != GOSSIP_ACTION_INFO_DEF)
        {
            CloseGossipMenuFor(player);
            return true;
        }

        // Deliberately NOT closing the gossip menu first: the core never does for an
        // option that opens a window of its own (see the comment in Omnibot's
        // OnGossipSelect - doing it there is what stopped the trainer from opening).
        // Mail happens to tolerate the close, but keeping one rule for both pets
        // means nobody copies the broken half later.
        //
        // The creature template already carries GOSSIP|MAILBOX, which is what
        // MailHandler's GetNPCIfCanInteractWith() check needs - so unlike the Argent
        // Pony (which is a vendor/banker/mailbox in turn and has to swap flags for
        // whichever role was picked) there is nothing to replace here.
        player->GetSession()->SendShowMailBox(creature->GetGUID());
        return true;
    }
};

// "Omnibot" - every service the individual companions offer, from one pet.
//
// The point is a hard client limit rather than convenience: WotLK allows exactly
// one summoned companion, so owning eight service pets means constantly swapping
// them. Each companion we add makes that worse, not better. Omnibot is the answer
// to that, and the Argent Pony (scripts/Pet/pet_generic.cpp) is the same idea in
// the core - one pet, several services behind a gossip menu.
//
// Training is the one service that could not simply be forwarded: both
// WorldSession::SendTrainerList() and the buy handler resolve the trainer from
// npc->GetEntry(), so showing another creature's trainer list would display the
// spells but fail every purchase. Omnibot therefore has its own trainer (90003),
// built in SQL as the union of the Classtrainer (90001) and Craftbot (90002)
// lists. That is safe because neither the class/race filtering nor the
// two-primary-profession limit depends on the trainer's Type: Trainer::
// GetSpellState() filters per spell via Player::IsSpellFitByClassAndRace(), and
// Trainer::CanTeachSpell() enforces the profession limit via
// GetFreePrimaryProfessionPoints(). Requirement = 0 makes the window open for
// everyone (and produces the same harmless "invalid class requirement" startup
// warning that trainer 90001 already does).
class npc_madosa_omnibot : public CreatureScript
{
    enum Action : uint32
    {
        ACTION_BANK = GOSSIP_ACTION_INFO_DEF + 1,
        ACTION_AUCTION,
        ACTION_MAIL,
        ACTION_REPAIR,
        ACTION_TRAIN,
    };

public:
    npc_madosa_omnibot() : CreatureScript("npc_madosa_omnibot") { }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        if (!MadosaSettings::GetOmniPetEnable())
            return false;

        ClearGossipMenuFor(player);
        AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "I would like to check my deposit box.",
                         GOSSIP_SENDER_MAIN, ACTION_BANK);
        AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, "I would like to browse the auction house.",
                         GOSSIP_SENDER_MAIN, ACTION_AUCTION);
        AddGossipItemFor(player, GOSSIP_ICON_INTERACT_1, "I would like to check my mail.",
                         GOSSIP_SENDER_MAIN, ACTION_MAIL);
        AddGossipItemFor(player, GOSSIP_ICON_INTERACT_1, "Repair all my equipment.",
                         GOSSIP_SENDER_MAIN, ACTION_REPAIR);
        AddGossipItemFor(player, GOSSIP_ICON_TRAINER, "Train me.",
                         GOSSIP_SENDER_MAIN, ACTION_TRAIN);
        SendGossipMenuFor(player, player->GetGossipTextId(creature), creature);
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* creature, uint32 /*sender*/, uint32 action) override
    {
        if (!MadosaSettings::GetOmniPetEnable())
        {
            CloseGossipMenuFor(player);
            return true;
        }

        // Closing the gossip menu first breaks the trainer: PlayerGossip.cpp calls
        // SendCloseGossip() only for options that just perform an action (INNKEEPER,
        // PETITIONER, TABARDDESIGNER...) and deliberately NOT for the ones that open
        // a window of their own - BANKER, AUCTIONEER, VENDOR and TRAINER all leave
        // the menu alone and let the client swap frames. Sending GOSSIP_COMPLETE
        // ahead of SMSG_TRAINER_LIST made the client drop the trainer window
        // entirely, which is why "Train me" appeared to do nothing while bank,
        // auction and mail survived it. So mirror the core: only the repair option,
        // which opens nothing, closes the menu.
        //
        // Every npcflag these need (BANKER, AUCTIONEER, MAILBOX, TRAINER) is set
        // permanently on the creature template, so unlike the Argent Pony - which is
        // a real world NPC swapping roles - there are no flags to replace here.
        switch (action)
        {
            case ACTION_BANK:
                player->GetSession()->SendShowBank(creature->GetGUID());
                break;
            case ACTION_AUCTION:
                player->GetSession()->SendAuctionHello(creature->GetGUID(), creature);
                break;
            case ACTION_MAIL:
                player->GetSession()->SendShowMailBox(creature->GetGUID());
                break;
            case ACTION_REPAIR:
                CloseGossipMenuFor(player);
                RepairFor(player);
                break;
            case ACTION_TRAIN:
                player->GetSession()->SendTrainerList(creature);
                break;
            default:
                CloseGossipMenuFor(player);
                break;
        }

        return true;
    }
};

void AddSC_madosa_service_pets()
{
    new npc_madosa_repairbot();
    new npc_madosa_mailbot();
    new npc_madosa_omnibot();
}
