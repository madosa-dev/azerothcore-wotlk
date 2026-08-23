-- Questbot companion: a "Special Vendor" in every capital city (the same
-- ones selling the other companions) also sells a companion pet for 2000g
-- that acts as a one-stop quest giver for whatever instance you're standing
-- in - offers every quest that instance has while you're inside it, and
-- takes back completed instance quests from anywhere (inspired by a similar
-- Ascension WoW pet).
--
-- Unlike the other companions this needs a little C++
-- (src/mod_madosa_instance_quest_pet.cpp) - which instance quests exist for
-- which map is computed at startup from creature_queststarter/
-- gameobject_queststarter cross-referenced with where those NPCs/objects are
-- actually spawned (map_dbc isn't populated in this database, so "is this
-- map actually an instance" is checked against the real loaded Map.dbc data
-- in C++ instead of in SQL), and the accept-vs-turn-in list shown depends on
-- the player's current map, which only C++ can see.
--
-- That C++ startup step also writes the resulting instance-quest set into
-- `creature_queststarter`/`creature_questender` for this creature entry -
-- deliberately not done here, since a static migration can't know which
-- quests are "instance quests" without the same map-type check. That table
-- is only what makes Creature::hasQuest()/hasInvolvedQuest() accept them
-- once offered; what's actually *shown* in the gossip window is filtered to
-- the current map's quests by the C++ script.
--
-- This migration only sets up the static half: renaming the item/creature,
-- npcflag/gossip wiring, and vendor stock.
--
-- Like the other companions, this repurposes an existing, currently-unsold
-- companion pet item/creature (Toothy's Bucket, teaches spell 43697 via the
-- standard ITEM_SPELLTRIGGER_LEARN_SPELL_ID convention, summons creature
-- 24388) instead of inventing a new one - client-side summon effects for
-- WotLK are baked into the shipped Spell.dbc and can't be created from
-- scratch without a client patch.

-- 1) Repurpose the (currently unsold) Toothy's Bucket item and the critter
--    it summons, both renamed to "Questbot". npcflag 2 = QUESTGIVER only (no
--    GOSSIP) - matches how a pure questgiver-with-no-flavor-text NPC is set
--    up, so the client goes straight to the quest list instead of a generic
--    gossip window.
UPDATE `item_template` SET `name` = 'Questbot', `Description` = 'While summoned, this companion offers every quest for the instance you are in, and takes back finished instance quests from anywhere.', `BuyPrice` = 20000000 WHERE `entry` = 33816;
UPDATE `creature_template` SET `name` = 'Questbot', `npcflag` = 2, `gossip_menu_id` = 900350 WHERE `entry` = 24388;

-- 2) Fallback text for when there's nothing to offer right now (not inside
--    an instance, and not carrying any instance quest to turn in) - no
--    gossip_menu_option rows, purely informational.
DELETE FROM `npc_text` WHERE `ID` = 900350;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900350,'Nothing for you right now - find me inside a dungeon or raid, or bring me a finished instance quest.','Nothing for you right now - find me inside a dungeon or raid, or bring me a finished instance quest.',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900350;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900350,900350);

-- 3) Vendor stock: the companion, 2000g (BuyPrice above), at the same eight
--    Special Vendor NPCs the other companions use.
DELETE FROM `npc_vendor` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307) AND `item` = 33816;
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900300,6,33816,0,0,0),
(900301,6,33816,0,0,0),
(900302,6,33816,0,0,0),
(900303,6,33816,0,0,0),
(900304,6,33816,0,0,0),
(900305,6,33816,0,0,0),
(900306,6,33816,0,0,0),
(900307,6,33816,0,0,0);
