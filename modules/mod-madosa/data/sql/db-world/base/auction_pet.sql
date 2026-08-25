-- Auctionbot companion: a "Special Vendor" in every capital city (the same
-- ones selling Lootbot, Classtrainer, Craftbot and Bankbot) also sells a
-- companion pet for 2000g that gives auction house access anywhere -
-- inspired by Ascension WoW's travel-friction-removing philosophy (portable
-- bank/mail/auctioneer items). Purely data-driven, same reasoning as
-- Bankbot: the core already opens the auction window off a single gossip
-- option (GOSSIP_OPTION_AUCTIONEER -> AuctionHouseObject flow), so the
-- companion pet just needs the right npcflag/gossip wiring - no C++.
--
-- Like the other companions, this repurposes an existing, currently-unsold
-- companion pet item/creature (Silver Pig Coin, teaches spell 45175 via the
-- standard ITEM_SPELLTRIGGER_LEARN_SPELL_ID convention, summons creature
-- 25147) instead of inventing a new one - client-side summon effects for
-- WotLK are baked into the shipped Spell.dbc and can't be created from
-- scratch without a client patch.

-- 1) Repurpose the (currently unsold) Silver Pig Coin item and the critter
--    it summons, both renamed to "Auctionbot". npcflag 2097153 = GOSSIP(1) |
--    AUCTIONEER(2097152) - the same combination real auctioneer NPCs use.
UPDATE `item_template` SET `name` = 'Auctionbot', `Description` = 'While summoned, this companion gives you access to the auction house - anywhere, anytime.', `BuyPrice` = 20000000, `Quality` = 6 WHERE `entry` = 34519;
UPDATE `creature_template` SET `name` = 'Auctionbot', `npcflag` = 2097153, `gossip_menu_id` = 900340 WHERE `entry` = 25147;

-- 2) Gossip: a single "What's on the auction house today?" option
--    (OptionType 13 = GOSSIP_OPTION_AUCTIONEER, OptionNpcFlag 2097152 =
--    UNIT_NPC_FLAG_AUCTIONEER) opens the auction window - same reasoning as
--    the other companions' explicit gossip options.
DELETE FROM `npc_text` WHERE `ID` = 900340;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900340,'Buying or selling, I can help with either.','Buying or selling, I can help with either.',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900340;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900340,900340);

DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900340;
INSERT INTO `gossip_menu_option` (`MenuID`,`OptionID`,`OptionIcon`,`OptionText`,`OptionBroadcastTextID`,`OptionType`,`OptionNpcFlag`,`ActionMenuID`,`ActionPoiID`,`BoxCoded`,`BoxMoney`,`BoxText`,`BoxBroadcastTextID`) VALUES
(900340,0,6,'What''s on the auction house today?',0,13,2097152,0,0,0,0,'',0);

-- 3) Vendor stock: the companion, 2000g (BuyPrice above), at the same eight
--    Special Vendor NPCs the other companions use.
DELETE FROM `npc_vendor` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307) AND `item` = 34519;
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900300,5,34519,0,0,0),
(900301,5,34519,0,0,0),
(900302,5,34519,0,0,0),
(900303,5,34519,0,0,0),
(900304,5,34519,0,0,0),
(900305,5,34519,0,0,0),
(900306,5,34519,0,0,0),
(900307,5,34519,0,0,0);
