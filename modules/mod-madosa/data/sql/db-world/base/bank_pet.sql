-- Bankbot companion: a "Special Vendor" in every capital city (the same
-- ones selling Lootbot, Classtrainer and Craftbot) also sells a companion
-- pet for 2000g that gives bank access anywhere - inspired by Ascension
-- WoW's "Personal Bank" quality-of-life item. Purely data-driven: the core
-- already opens the bank window off a single gossip option
-- (GOSSIP_OPTION_BANKER -> WorldSession::SendShowBank()) the same way any
-- stationary banker NPC works, so the companion pet just needs the right
-- npcflag/gossip wiring - no C++.
--
-- Like the other companions, this repurposes an existing, currently-unsold
-- companion pet item/creature (Golden Pig Coin, teaches spell 45174 via the
-- standard ITEM_SPELLTRIGGER_LEARN_SPELL_ID convention, summons creature
-- 25146) instead of inventing a new one - client-side summon effects for
-- WotLK are baked into the shipped Spell.dbc and can't be created from
-- scratch without a client patch.

-- 1) Repurpose the (currently unsold) Golden Pig Coin item and the critter
--    it summons, both renamed to "Bankbot". npcflag 131073 = GOSSIP(1) |
--    BANKER(131072) - the same combination real banker NPCs use.
UPDATE `item_template` SET `name` = 'Bankbot', `Description` = 'While summoned, this companion gives you access to your bank - anywhere, anytime.', `BuyPrice` = 20000000, `Quality` = 6 WHERE `entry` = 34518;
UPDATE `creature_template` SET `name` = 'Bankbot', `npcflag` = 131073, `gossip_menu_id` = 900330 WHERE `entry` = 25146;

-- 2) Gossip: a single "I would like to check my deposit box." option
--    (OptionType 9 = GOSSIP_OPTION_BANKER, OptionNpcFlag 131072 =
--    UNIT_NPC_FLAG_BANKER) opens the bank window - same reasoning as the
--    other companions' explicit gossip options.
DELETE FROM `npc_text` WHERE `ID` = 900330;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900330,'Your valuables are safe with me.','Your valuables are safe with me.',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900330;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900330,900330);

DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900330;
INSERT INTO `gossip_menu_option` (`MenuID`,`OptionID`,`OptionIcon`,`OptionText`,`OptionBroadcastTextID`,`OptionType`,`OptionNpcFlag`,`ActionMenuID`,`ActionPoiID`,`BoxCoded`,`BoxMoney`,`BoxText`,`BoxBroadcastTextID`) VALUES
(900330,0,6,'I would like to check my deposit box.',0,9,131072,0,0,0,0,'',0);

-- 3) Vendor stock: the companion, 2000g (BuyPrice above), at the same eight
--    Special Vendor NPCs the other companions use.
DELETE FROM `npc_vendor` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307) AND `item` = 34518;
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900300,4,34518,0,0,0),
(900301,4,34518,0,0,0),
(900302,4,34518,0,0,0),
(900303,4,34518,0,0,0),
(900304,4,34518,0,0,0),
(900305,4,34518,0,0,0),
(900306,4,34518,0,0,0),
(900307,4,34518,0,0,0);
