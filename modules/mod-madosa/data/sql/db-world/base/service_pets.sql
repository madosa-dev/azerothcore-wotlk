-- Repairbot and Mailbot companions: two more 2000g convenience pets sold by the
-- same "Special Vendor" NPCs as Lootbot, Classtrainer, Craftbot, Bankbot,
-- Auctionbot and Questbot.
--
-- Unlike Bankbot/Auctionbot these are NOT pure data: the core has no gossip option
-- type that opens a mailbox, and its repair option (GOSSIP_OPTION_ARMORER) is never
-- rendered as a menu entry - see the header comment in
-- src/mod_madosa_service_pets.cpp for the full reasoning. Hence the ScriptName on
-- each creature below.
--
-- Like every other companion here, this repurposes an existing but genuinely
-- unobtainable companion pet rather than inventing one, because WotLK summon
-- effects are baked into the shipped Spell.dbc. Both were picked by elimination:
-- sold by no vendor, in no loot table, no quest reward, not craftable by any spell,
-- carrying no existing ScriptName and spawned nowhere in the world.
--
--   Repairbot = item 44972 "Alarming Clockbot (NOT IN USE)" -> spell 62514 -> creature 33199
--   Mailbot   = item 23713 "Hippogryph Hatchling"           -> spell 30156 -> creature 17255

-- ---------------------------------------------------------------------------
-- Repairbot
-- ---------------------------------------------------------------------------

-- Quality 6 = the module's "Vanity" quality, which also makes
-- mod_madosa_account_companions.cpp pick the learn-spell up as account-wide.
UPDATE `item_template` SET `name` = 'Repairbot', `Description` = 'While summoned, this companion repairs your equipment - anywhere, anytime. Normal repair costs apply.', `BuyPrice` = 20000000, `Quality` = 6 WHERE `entry` = 44972;

-- npcflag 1 = GOSSIP only. Repairing is done by the script off the gossip
-- selection, so unlike a real repair vendor this needs neither VENDOR (128) nor
-- REPAIR (4096) - and deliberately so, since an empty vendor inventory makes
-- SendListInventory answer "Vendor has no inventory" instead of opening a window.
UPDATE `creature_template` SET `name` = 'Repairbot', `npcflag` = 1, `gossip_menu_id` = 900360, `ScriptName` = 'npc_madosa_repairbot' WHERE `entry` = 33199;

DELETE FROM `npc_text` WHERE `ID` = 900360;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900360,'Dents, scratches, cracks - hand it here.','Dents, scratches, cracks - hand it here.',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900360;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900360,900360);

-- No gossip_menu_option row on purpose: the CreatureScript builds the menu itself
-- (AddGossipItemFor), so a static option here would show up twice.
DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900360;

-- ---------------------------------------------------------------------------
-- Mailbot
-- ---------------------------------------------------------------------------

UPDATE `item_template` SET `name` = 'Mailbot', `Description` = 'While summoned, this companion gives you access to your mailbox - anywhere, anytime.', `BuyPrice` = 20000000, `Quality` = 6 WHERE `entry` = 23713;

-- npcflag 67108865 = GOSSIP(1) | MAILBOX(0x04000000). The MAILBOX bit is what
-- MailHandler's GetNPCIfCanInteractWith() check requires; without it the mail
-- window opens and then refuses every operation.
UPDATE `creature_template` SET `name` = 'Mailbot', `npcflag` = 67108865, `gossip_menu_id` = 900370, `ScriptName` = 'npc_madosa_mailbot' WHERE `entry` = 17255;

DELETE FROM `npc_text` WHERE `ID` = 900370;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900370,'You have mail!','You have mail!',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900370;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900370,900370);

DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900370;

-- ---------------------------------------------------------------------------
-- Vendor stock: slots 8 and 9, after the six existing companions and the scroll.
-- ---------------------------------------------------------------------------

DELETE FROM `npc_vendor` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307) AND `item` IN (44972,23713);
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900300,8,44972,0,0,0),
(900301,8,44972,0,0,0),
(900302,8,44972,0,0,0),
(900303,8,44972,0,0,0),
(900304,8,44972,0,0,0),
(900305,8,44972,0,0,0),
(900306,8,44972,0,0,0),
(900307,8,44972,0,0,0),
(900300,9,23713,0,0,0),
(900301,9,23713,0,0,0),
(900302,9,23713,0,0,0),
(900303,9,23713,0,0,0),
(900304,9,23713,0,0,0),
(900305,9,23713,0,0,0),
(900306,9,23713,0,0,0),
(900307,9,23713,0,0,0);
