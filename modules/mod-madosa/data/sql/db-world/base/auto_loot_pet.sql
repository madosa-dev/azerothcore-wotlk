-- Auto-loot companion: a "Special Vendor" in every capital city sells a
-- companion pet for 1000g. While that companion is summoned, the player's
-- kills auto-loot anything they'd be allowed to take themselves (see
-- mod_madosa_autoloot_pet.cpp) - items still under a pending need/greed roll,
-- or restricted by master loot, are left for the player to handle normally.
--
-- Client-side spell/summon effects for WotLK are baked into the shipped
-- Spell.dbc and can't be created from scratch without a client patch, so
-- this repurposes an existing, currently-unsold companion pet item (Rat
-- Cage, teaches spell 28740, summons creature 16549 "Whiskers the Rat" -
-- confirmed in-game, not by name-matching) rather than inventing a new one.

-- 1) Repurpose the (currently unsold) Rat Cage and the critter it summons as
--    our companion, both renamed to "Lootbot"
UPDATE `item_template` SET `name` = 'Lootbot', `Description` = 'While summoned, this companion automatically loots anything you could loot yourself.', `BuyPrice` = 10000000, `Quality` = 6 WHERE `entry` = 23015;
UPDATE `creature_template` SET `name` = 'Lootbot' WHERE `entry` = 16549;

-- 2) Special Vendor creature templates (one per capital city)
DELETE FROM `creature_template` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307);
INSERT INTO `creature_template` (`entry`,`difficulty_entry_1`,`difficulty_entry_2`,`difficulty_entry_3`,`KillCredit1`,`KillCredit2`,`name`,`subname`,`gossip_menu_id`,`minlevel`,`maxlevel`,`exp`,`faction`,`npcflag`,`speed_walk`,`speed_run`,`speed_swim`,`speed_flight`,`detection_range`,`rank`,`dmgschool`,`DamageModifier`,`BaseAttackTime`,`RangeAttackTime`,`BaseVariance`,`RangeVariance`,`unit_class`,`unit_flags`,`unit_flags2`,`dynamicflags`,`family`,`type`,`type_flags`,`lootid`,`pickpocketloot`,`skinloot`,`PetSpellDataId`,`VehicleId`,`mingold`,`maxgold`,`AIName`,`MovementType`,`HoverHeight`,`HealthModifier`,`ManaModifier`,`ArmorModifier`,`ExperienceModifier`,`RacialLeader`,`movementId`,`RegenHealth`,`CreatureImmunitiesId`,`flags_extra`,`ScriptName`) VALUES
(900300,0,0,0,0,0,'Special Vendor','Black Market Dealer',900300,1,1,0,12,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900301,0,0,0,0,0,'Special Vendor','Black Market Dealer',900300,1,1,0,29,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900302,0,0,0,0,0,'Special Vendor','Black Market Dealer',900300,1,1,0,55,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900303,0,0,0,0,0,'Special Vendor','Black Market Dealer',900300,1,1,0,80,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900304,0,0,0,0,0,'Special Vendor','Black Market Dealer',900300,1,1,0,68,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900305,0,0,0,0,0,'Special Vendor','Black Market Dealer',900300,1,1,0,104,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900306,0,0,0,0,0,'Special Vendor','Black Market Dealer',900300,1,1,0,1604,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900307,0,0,0,0,0,'Special Vendor','Black Market Dealer',900300,1,1,0,1638,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,'');

-- Same model at every location: display 26779 is Shifty Vickers' (Dalaran's
-- own black-market dealer, entry 30137) - an existing, already-rendered
-- WotLK model, so this needs no client patch and carries none of the risk a
-- custom Ascension model does.
DELETE FROM `creature_template_model` WHERE `CreatureID` IN (900300,900301,900302,900303,900304,900305,900306,900307);
INSERT INTO `creature_template_model` (`CreatureID`,`Idx`,`CreatureDisplayID`,`DisplayScale`,`Probability`) VALUES
(900300,0,26779,1,1),
(900301,0,26779,1,1),
(900302,0,26779,1,1),
(900303,0,26779,1,1),
(900304,0,26779,1,1),
(900305,0,26779,1,1),
(900306,0,26779,1,1),
(900307,0,26779,1,1);

-- 3) Explicit gossip menu (see mod-madosa's mount vendor for why: an
--    OptionType this specific, matched to OptionNpcFlag = VENDOR, is what
--    actually opens the vendor window - not relying on the implicit
--    MenuID=0 fallback keeps this unambiguous)
DELETE FROM `npc_text` WHERE `ID` = 900300;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900300,'Looking for something a little... special?','Looking for something a little... special?',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900300;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900300,900300);

DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900300;
INSERT INTO `gossip_menu_option` (`MenuID`,`OptionID`,`OptionIcon`,`OptionText`,`OptionBroadcastTextID`,`OptionType`,`OptionNpcFlag`,`ActionMenuID`,`ActionPoiID`,`BoxCoded`,`BoxMoney`,`BoxText`,`BoxBroadcastTextID`) VALUES
(900300,0,1,'I want to browse your goods.',0,3,128,0,0,0,0,'',0);

-- 4) Vendor stock: the companion, 1000g (BuyPrice above), same at every location.
--    Scoped to this item - class_trainer_pet.sql and friends add their own
--    slots to these same 8 NPCs, and an unscoped DELETE here would wipe those
--    out every time this file alone gets re-applied.
DELETE FROM `npc_vendor` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307) AND `item` = 23015;
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900300,1,23015,0,0,0),
(900301,1,23015,0,0,0),
(900302,1,23015,0,0,0),
(900303,1,23015,0,0,0),
(900304,1,23015,0,0,0),
(900305,1,23015,0,0,0),
(900306,1,23015,0,0,0),
(900307,1,23015,0,0,0);

-- 5) Spawn at each capital city (coordinates match the .tele command's own
--    destinations, offset by a couple yards so the vendor isn't standing
--    exactly on the teleport landing spot). npcflag = 0: the `creature`
--    table's own npcflag column overrides creature_template's whenever
--    non-zero (see the free_starter_mounts.sql fix) - 0 means "no override".
DELETE FROM `creature` WHERE `guid` BETWEEN 5392001 AND 5392008;
INSERT INTO `creature` (`guid`,`id`,`map`,`zoneId`,`areaId`,`spawnMask`,`phaseMask`,`equipment_id`,`position_x`,`position_y`,`position_z`,`orientation`,`spawntimesecs`,`wander_distance`,`currentwaypoint`,`curhealth`,`curmana`,`MovementType`,`npcflag`,`unit_flags`,`dynamicflags`,`CreateObject`) VALUES
(5392001,900300,0,0,0,1,1,0,-8831.38,626.628,94.0066,1.06535,120,0,0,1,0,0,0,0,0,1),
(5392002,900301,1,0,0,1,1,0,1631.85,-4375.64,31.5573,3.69762,120,0,0,1,0,0,0,0,0,1),
(5392003,900302,0,0,0,1,1,0,-4916.88,-942.406,501.564,5.42347,120,0,0,1,0,0,0,0,0,1),
(5392004,900303,1,0,0,1,1,0,9951.56,2286.21,1341.4,1.59587,120,0,0,1,0,0,0,0,0,1),
(5392005,900304,0,0,0,1,1,0,1586.14,242.308,-52.1534,0.041793,120,0,0,1,0,0,0,0,0,1),
(5392006,900305,1,0,0,1,1,0,-1275.37,126.804,131.287,5.22274,120,0,0,1,0,0,0,0,0,1),
(5392007,900306,530,0,0,1,1,0,9489.69,-7277.2,14.2866,6.16478,120,0,0,1,0,0,0,0,0,1),
(5392008,900307,530,0,0,1,1,0,-3963.7,-11651.6,-138.844,0.852154,120,0,0,1,0,0,0,0,0,1);
