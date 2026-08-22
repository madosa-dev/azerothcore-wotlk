-- Free starter mount + earlier riding: level 7 apprentice riding, racial mount NPC in every starting zone
--
-- Two separate NPCs per location, using plain vendor/trainer mechanics instead of custom
-- gossip/SmartAI wiring (which turned out fragile - the client always echoes back an option's
-- real, DB-stored OptionID, but a menu shared across all 10 races only ever shows one option
-- at a time, which made per-race SmartAI action matching easy to get wrong):
--   - a Riding Trainer (npcflag TRAINER only) that teaches Apprentice Riding (60% speed) at
--     level 7 for 20 silver
--   - a Mount Vendor (npcflag VENDOR only) that "sells" the matching racial mount for free,
--     via ExtendedCost id 2 (the one entry in ItemExtendedCost.dbc that requires nothing at
--     all), which makes the core skip the normal gold price entirely (see IsGoldRequired())

-- 1) Also lower the requirement at every existing trainer that already teaches it, so this
--    isn't the only place in the world where riding is available at level 7
UPDATE `trainer_spell` SET `ReqLevel` = 7 WHERE `SpellID` = 33388;

-- 2) The mount items themselves also carry a level requirement - lower it to match
UPDATE `item_template` SET `RequiredLevel` = 7 WHERE `entry` IN (5656,5668,5872,8591,8629,13321,13333,15290,28481,29220);

-- 3) Dedicated trainer entry: Apprentice Riding only, 20 silver, level 7
DELETE FROM `trainer` WHERE `Id` = 90000;
INSERT INTO `trainer` (`Id`,`Type`,`Requirement`,`Greeting`) VALUES
(90000,1,0,'Ready to learn to ride?');

DELETE FROM `trainer_spell` WHERE `TrainerId` = 90000;
INSERT INTO `trainer_spell` (`TrainerId`,`SpellId`,`MoneyCost`,`ReqSkillLine`,`ReqSkillRank`,`ReqAbility1`,`ReqAbility2`,`ReqAbility3`,`ReqLevel`) VALUES
(90000,33388,2000,762,0,0,0,0,7);

-- 4) Riding Trainer creature templates (one per starting-zone location/model)
DELETE FROM `creature_template` WHERE `entry` IN (900100,900101,900102,900103,900104,900105,900106,900107);
INSERT INTO `creature_template` (`entry`,`difficulty_entry_1`,`difficulty_entry_2`,`difficulty_entry_3`,`KillCredit1`,`KillCredit2`,`name`,`subname`,`gossip_menu_id`,`minlevel`,`maxlevel`,`exp`,`faction`,`npcflag`,`speed_walk`,`speed_run`,`speed_swim`,`speed_flight`,`detection_range`,`rank`,`dmgschool`,`DamageModifier`,`BaseAttackTime`,`RangeAttackTime`,`BaseVariance`,`RangeVariance`,`unit_class`,`unit_flags`,`unit_flags2`,`dynamicflags`,`family`,`type`,`type_flags`,`lootid`,`pickpocketloot`,`skinloot`,`PetSpellDataId`,`VehicleId`,`mingold`,`maxgold`,`AIName`,`MovementType`,`HoverHeight`,`HealthModifier`,`ManaModifier`,`ArmorModifier`,`ExperienceModifier`,`RacialLeader`,`movementId`,`RegenHealth`,`CreatureImmunitiesId`,`flags_extra`,`ScriptName`) VALUES
(900100,0,0,0,0,0,'Riding Trainer','',900100,1,1,0,12,17,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900101,0,0,0,0,0,'Riding Trainer','',900100,1,1,0,29,17,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900102,0,0,0,0,0,'Riding Trainer','',900100,1,1,0,55,17,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900103,0,0,0,0,0,'Riding Trainer','',900100,1,1,0,80,17,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900104,0,0,0,0,0,'Riding Trainer','',900100,1,1,0,68,17,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900105,0,0,0,0,0,'Riding Trainer','',900100,1,1,0,104,17,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900106,0,0,0,0,0,'Riding Trainer','',900100,1,1,0,1604,17,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900107,0,0,0,0,0,'Riding Trainer','',900100,1,1,0,1638,17,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,'');

DELETE FROM `creature_template_model` WHERE `CreatureID` IN (900100,900101,900102,900103,900104,900105,900106,900107);
INSERT INTO `creature_template_model` (`CreatureID`,`Idx`,`CreatureDisplayID`,`DisplayScale`,`Probability`) VALUES
(900100,0,2072,1,1),
(900101,0,9470,1,1),
(900102,0,1362,1,1),
(900103,0,1285,1,1),
(900104,0,1582,1,1),
(900105,0,3808,1,1),
(900106,0,15516,1,1),
(900107,0,16203,1,1);

DELETE FROM `creature_default_trainer` WHERE `CreatureId` IN (900100,900101,900102,900103,900104,900105,900106,900107);
INSERT INTO `creature_default_trainer` (`CreatureId`,`TrainerId`) VALUES
(900100,90000),(900101,90000),(900102,90000),(900103,90000),(900104,90000),(900105,90000),(900106,90000),(900107,90000);

-- 4b) Explicit gossip menu for the trainer, instead of relying on the implicit MenuID=0
--     fallback options - a real greeting plus one unmistakably clickable "Train me!" line
DELETE FROM `npc_text` WHERE `ID` = 900100;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900100,'Ready to learn to ride?','Ready to learn to ride?',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900100;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900100,900100);

DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900100;
INSERT INTO `gossip_menu_option` (`MenuID`,`OptionID`,`OptionIcon`,`OptionText`,`OptionBroadcastTextID`,`OptionType`,`OptionNpcFlag`,`ActionMenuID`,`ActionPoiID`,`BoxCoded`,`BoxMoney`,`BoxText`,`BoxBroadcastTextID`) VALUES
(900100,0,3,'Train me!',0,5,16,0,0,0,0,'',0);

-- 5) Mount Vendor creature templates (same locations/models, standing next to the trainer)
DELETE FROM `creature_template` WHERE `entry` IN (900200,900201,900202,900203,900204,900205,900206,900207);
INSERT INTO `creature_template` (`entry`,`difficulty_entry_1`,`difficulty_entry_2`,`difficulty_entry_3`,`KillCredit1`,`KillCredit2`,`name`,`subname`,`gossip_menu_id`,`minlevel`,`maxlevel`,`exp`,`faction`,`npcflag`,`speed_walk`,`speed_run`,`speed_swim`,`speed_flight`,`detection_range`,`rank`,`dmgschool`,`DamageModifier`,`BaseAttackTime`,`RangeAttackTime`,`BaseVariance`,`RangeVariance`,`unit_class`,`unit_flags`,`unit_flags2`,`dynamicflags`,`family`,`type`,`type_flags`,`lootid`,`pickpocketloot`,`skinloot`,`PetSpellDataId`,`VehicleId`,`mingold`,`maxgold`,`AIName`,`MovementType`,`HoverHeight`,`HealthModifier`,`ManaModifier`,`ArmorModifier`,`ExperienceModifier`,`RacialLeader`,`movementId`,`RegenHealth`,`CreatureImmunitiesId`,`flags_extra`,`ScriptName`) VALUES
(900200,0,0,0,0,0,'Mount Vendor','Free Mount',900200,1,1,0,12,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900201,0,0,0,0,0,'Mount Vendor','Free Mount',900200,1,1,0,29,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900202,0,0,0,0,0,'Mount Vendor','Free Mount',900200,1,1,0,55,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900203,0,0,0,0,0,'Mount Vendor','Free Mount',900200,1,1,0,80,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900204,0,0,0,0,0,'Mount Vendor','Free Mount',900200,1,1,0,68,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900205,0,0,0,0,0,'Mount Vendor','Free Mount',900200,1,1,0,104,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900206,0,0,0,0,0,'Mount Vendor','Free Mount',900200,1,1,0,1604,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,''),
(900207,0,0,0,0,0,'Mount Vendor','Free Mount',900200,1,1,0,1638,129,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,'');

DELETE FROM `creature_template_model` WHERE `CreatureID` IN (900200,900201,900202,900203,900204,900205,900206,900207);
INSERT INTO `creature_template_model` (`CreatureID`,`Idx`,`CreatureDisplayID`,`DisplayScale`,`Probability`) VALUES
(900200,0,2072,1,1),
(900201,0,9470,1,1),
(900202,0,1362,1,1),
(900203,0,1285,1,1),
(900204,0,1582,1,1),
(900205,0,3808,1,1),
(900206,0,15516,1,1),
(900207,0,16203,1,1);

-- 6) Vendor stock: every vendor sells all 10 racial mounts, race-gated per viewer just like the
--    old gossip menu was, and free via ExtendedCost 2 (the all-zero-requirement DBC entry)
DELETE FROM `npc_vendor` WHERE `entry` IN (900200,900201,900202,900203,900204,900205,900206,900207);
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900200,1,5656,0,0,2),(900200,2,5668,0,0,2),(900200,3,5872,0,0,2),(900200,4,8629,0,0,2),(900200,5,13333,0,0,2),
(900200,6,15290,0,0,2),(900200,7,13321,0,0,2),(900200,8,8591,0,0,2),(900200,9,29220,0,0,2),(900200,10,28481,0,0,2),
(900201,1,5656,0,0,2),(900201,2,5668,0,0,2),(900201,3,5872,0,0,2),(900201,4,8629,0,0,2),(900201,5,13333,0,0,2),
(900201,6,15290,0,0,2),(900201,7,13321,0,0,2),(900201,8,8591,0,0,2),(900201,9,29220,0,0,2),(900201,10,28481,0,0,2),
(900202,1,5656,0,0,2),(900202,2,5668,0,0,2),(900202,3,5872,0,0,2),(900202,4,8629,0,0,2),(900202,5,13333,0,0,2),
(900202,6,15290,0,0,2),(900202,7,13321,0,0,2),(900202,8,8591,0,0,2),(900202,9,29220,0,0,2),(900202,10,28481,0,0,2),
(900203,1,5656,0,0,2),(900203,2,5668,0,0,2),(900203,3,5872,0,0,2),(900203,4,8629,0,0,2),(900203,5,13333,0,0,2),
(900203,6,15290,0,0,2),(900203,7,13321,0,0,2),(900203,8,8591,0,0,2),(900203,9,29220,0,0,2),(900203,10,28481,0,0,2),
(900204,1,5656,0,0,2),(900204,2,5668,0,0,2),(900204,3,5872,0,0,2),(900204,4,8629,0,0,2),(900204,5,13333,0,0,2),
(900204,6,15290,0,0,2),(900204,7,13321,0,0,2),(900204,8,8591,0,0,2),(900204,9,29220,0,0,2),(900204,10,28481,0,0,2),
(900205,1,5656,0,0,2),(900205,2,5668,0,0,2),(900205,3,5872,0,0,2),(900205,4,8629,0,0,2),(900205,5,13333,0,0,2),
(900205,6,15290,0,0,2),(900205,7,13321,0,0,2),(900205,8,8591,0,0,2),(900205,9,29220,0,0,2),(900205,10,28481,0,0,2),
(900206,1,5656,0,0,2),(900206,2,5668,0,0,2),(900206,3,5872,0,0,2),(900206,4,8629,0,0,2),(900206,5,13333,0,0,2),
(900206,6,15290,0,0,2),(900206,7,13321,0,0,2),(900206,8,8591,0,0,2),(900206,9,29220,0,0,2),(900206,10,28481,0,0,2),
(900207,1,5656,0,0,2),(900207,2,5668,0,0,2),(900207,3,5872,0,0,2),(900207,4,8629,0,0,2),(900207,5,13333,0,0,2),
(900207,6,15290,0,0,2),(900207,7,13321,0,0,2),(900207,8,8591,0,0,2),(900207,9,29220,0,0,2),(900207,10,28481,0,0,2);

DELETE FROM `conditions` WHERE `SourceTypeOrReferenceId` = 23 AND `SourceGroup` IN (900200,900201,900202,900203,900204,900205,900206,900207);
INSERT INTO `conditions` (`SourceTypeOrReferenceId`,`SourceGroup`,`SourceEntry`,`SourceId`,`ElseGroup`,`ConditionTypeOrReference`,`ConditionTarget`,`ConditionValue1`,`ConditionValue2`,`ConditionValue3`,`NegativeCondition`,`ErrorType`,`ErrorTextId`,`ScriptName`,`Comment`) VALUES
(23,900200,5656,0,0,16,0,1,0,0,0,0,0,'','Human only'),(23,900200,5668,0,0,16,0,2,0,0,0,0,0,'','Orc only'),(23,900200,5872,0,0,16,0,4,0,0,0,0,0,'','Dwarf only'),(23,900200,8629,0,0,16,0,8,0,0,0,0,0,'','NightElf only'),(23,900200,13333,0,0,16,0,16,0,0,0,0,0,'','Undead only'),(23,900200,15290,0,0,16,0,32,0,0,0,0,0,'','Tauren only'),(23,900200,13321,0,0,16,0,64,0,0,0,0,0,'','Gnome only'),(23,900200,8591,0,0,16,0,128,0,0,0,0,0,'','Troll only'),(23,900200,29220,0,0,16,0,512,0,0,0,0,0,'','BloodElf only'),(23,900200,28481,0,0,16,0,1024,0,0,0,0,0,'','Draenei only'),
(23,900201,5656,0,0,16,0,1,0,0,0,0,0,'','Human only'),(23,900201,5668,0,0,16,0,2,0,0,0,0,0,'','Orc only'),(23,900201,5872,0,0,16,0,4,0,0,0,0,0,'','Dwarf only'),(23,900201,8629,0,0,16,0,8,0,0,0,0,0,'','NightElf only'),(23,900201,13333,0,0,16,0,16,0,0,0,0,0,'','Undead only'),(23,900201,15290,0,0,16,0,32,0,0,0,0,0,'','Tauren only'),(23,900201,13321,0,0,16,0,64,0,0,0,0,0,'','Gnome only'),(23,900201,8591,0,0,16,0,128,0,0,0,0,0,'','Troll only'),(23,900201,29220,0,0,16,0,512,0,0,0,0,0,'','BloodElf only'),(23,900201,28481,0,0,16,0,1024,0,0,0,0,0,'','Draenei only'),
(23,900202,5656,0,0,16,0,1,0,0,0,0,0,'','Human only'),(23,900202,5668,0,0,16,0,2,0,0,0,0,0,'','Orc only'),(23,900202,5872,0,0,16,0,4,0,0,0,0,0,'','Dwarf only'),(23,900202,8629,0,0,16,0,8,0,0,0,0,0,'','NightElf only'),(23,900202,13333,0,0,16,0,16,0,0,0,0,0,'','Undead only'),(23,900202,15290,0,0,16,0,32,0,0,0,0,0,'','Tauren only'),(23,900202,13321,0,0,16,0,64,0,0,0,0,0,'','Gnome only'),(23,900202,8591,0,0,16,0,128,0,0,0,0,0,'','Troll only'),(23,900202,29220,0,0,16,0,512,0,0,0,0,0,'','BloodElf only'),(23,900202,28481,0,0,16,0,1024,0,0,0,0,0,'','Draenei only'),
(23,900203,5656,0,0,16,0,1,0,0,0,0,0,'','Human only'),(23,900203,5668,0,0,16,0,2,0,0,0,0,0,'','Orc only'),(23,900203,5872,0,0,16,0,4,0,0,0,0,0,'','Dwarf only'),(23,900203,8629,0,0,16,0,8,0,0,0,0,0,'','NightElf only'),(23,900203,13333,0,0,16,0,16,0,0,0,0,0,'','Undead only'),(23,900203,15290,0,0,16,0,32,0,0,0,0,0,'','Tauren only'),(23,900203,13321,0,0,16,0,64,0,0,0,0,0,'','Gnome only'),(23,900203,8591,0,0,16,0,128,0,0,0,0,0,'','Troll only'),(23,900203,29220,0,0,16,0,512,0,0,0,0,0,'','BloodElf only'),(23,900203,28481,0,0,16,0,1024,0,0,0,0,0,'','Draenei only'),
(23,900204,5656,0,0,16,0,1,0,0,0,0,0,'','Human only'),(23,900204,5668,0,0,16,0,2,0,0,0,0,0,'','Orc only'),(23,900204,5872,0,0,16,0,4,0,0,0,0,0,'','Dwarf only'),(23,900204,8629,0,0,16,0,8,0,0,0,0,0,'','NightElf only'),(23,900204,13333,0,0,16,0,16,0,0,0,0,0,'','Undead only'),(23,900204,15290,0,0,16,0,32,0,0,0,0,0,'','Tauren only'),(23,900204,13321,0,0,16,0,64,0,0,0,0,0,'','Gnome only'),(23,900204,8591,0,0,16,0,128,0,0,0,0,0,'','Troll only'),(23,900204,29220,0,0,16,0,512,0,0,0,0,0,'','BloodElf only'),(23,900204,28481,0,0,16,0,1024,0,0,0,0,0,'','Draenei only'),
(23,900205,5656,0,0,16,0,1,0,0,0,0,0,'','Human only'),(23,900205,5668,0,0,16,0,2,0,0,0,0,0,'','Orc only'),(23,900205,5872,0,0,16,0,4,0,0,0,0,0,'','Dwarf only'),(23,900205,8629,0,0,16,0,8,0,0,0,0,0,'','NightElf only'),(23,900205,13333,0,0,16,0,16,0,0,0,0,0,'','Undead only'),(23,900205,15290,0,0,16,0,32,0,0,0,0,0,'','Tauren only'),(23,900205,13321,0,0,16,0,64,0,0,0,0,0,'','Gnome only'),(23,900205,8591,0,0,16,0,128,0,0,0,0,0,'','Troll only'),(23,900205,29220,0,0,16,0,512,0,0,0,0,0,'','BloodElf only'),(23,900205,28481,0,0,16,0,1024,0,0,0,0,0,'','Draenei only'),
(23,900206,5656,0,0,16,0,1,0,0,0,0,0,'','Human only'),(23,900206,5668,0,0,16,0,2,0,0,0,0,0,'','Orc only'),(23,900206,5872,0,0,16,0,4,0,0,0,0,0,'','Dwarf only'),(23,900206,8629,0,0,16,0,8,0,0,0,0,0,'','NightElf only'),(23,900206,13333,0,0,16,0,16,0,0,0,0,0,'','Undead only'),(23,900206,15290,0,0,16,0,32,0,0,0,0,0,'','Tauren only'),(23,900206,13321,0,0,16,0,64,0,0,0,0,0,'','Gnome only'),(23,900206,8591,0,0,16,0,128,0,0,0,0,0,'','Troll only'),(23,900206,29220,0,0,16,0,512,0,0,0,0,0,'','BloodElf only'),(23,900206,28481,0,0,16,0,1024,0,0,0,0,0,'','Draenei only'),
(23,900207,5656,0,0,16,0,1,0,0,0,0,0,'','Human only'),(23,900207,5668,0,0,16,0,2,0,0,0,0,0,'','Orc only'),(23,900207,5872,0,0,16,0,4,0,0,0,0,0,'','Dwarf only'),(23,900207,8629,0,0,16,0,8,0,0,0,0,0,'','NightElf only'),(23,900207,13333,0,0,16,0,16,0,0,0,0,0,'','Undead only'),(23,900207,15290,0,0,16,0,32,0,0,0,0,0,'','Tauren only'),(23,900207,13321,0,0,16,0,64,0,0,0,0,0,'','Gnome only'),(23,900207,8591,0,0,16,0,128,0,0,0,0,0,'','Troll only'),(23,900207,29220,0,0,16,0,512,0,0,0,0,0,'','BloodElf only'),(23,900207,28481,0,0,16,0,1024,0,0,0,0,0,'','Draenei only');

-- 6b) Explicit gossip menu for the vendor, instead of relying on the implicit MenuID=0
--     fallback options - a real greeting plus one unmistakably clickable "browse your goods" line
DELETE FROM `npc_text` WHERE `ID` = 900200;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900200,'Looking for a mount to get around faster? I can help with that.','Looking for a mount to get around faster? I can help with that.',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900200;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900200,900200);

DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900200;
INSERT INTO `gossip_menu_option` (`MenuID`,`OptionID`,`OptionIcon`,`OptionText`,`OptionBroadcastTextID`,`OptionType`,`OptionNpcFlag`,`ActionMenuID`,`ActionPoiID`,`BoxCoded`,`BoxMoney`,`BoxText`,`BoxBroadcastTextID`) VALUES
(900200,0,1,'I want to browse your goods.',0,3,128,0,0,0,0,'',0);

-- 7) Clean up the old combined gossip/SmartAI NPC (900000-900007) from the previous design
DELETE FROM `creature` WHERE `guid` BETWEEN 5390001 AND 5390008;
DELETE FROM `smart_scripts` WHERE `entryorguid` IN (900000,900001,900002,900003,900004,900005,900006,900007) AND `source_type` = 0;
DELETE FROM `conditions` WHERE `SourceTypeOrReferenceId` = 15 AND `SourceGroup` = 900000;
DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900000;
DELETE FROM `gossip_menu` WHERE `MenuID` = 900000;
DELETE FROM `npc_text` WHERE `ID` = 900000;
DELETE FROM `creature_template_model` WHERE `CreatureID` IN (900000,900001,900002,900003,900004,900005,900006,900007);
DELETE FROM `creature_default_trainer` WHERE `CreatureId` IN (900000,900001,900002,900003,900004,900005,900006,900007);
DELETE FROM `creature_template` WHERE `entry` IN (900000,900001,900002,900003,900004,900005,900006,900007);

-- 8) Spawn trainer + vendor side by side at each starting-zone location
DELETE FROM `creature` WHERE `guid` BETWEEN 5391001 AND 5391016;
INSERT INTO `creature` (`guid`,`id`,`map`,`zoneId`,`areaId`,`spawnMask`,`phaseMask`,`equipment_id`,`position_x`,`position_y`,`position_z`,`orientation`,`spawntimesecs`,`wander_distance`,`currentwaypoint`,`curhealth`,`curmana`,`MovementType`,`npcflag`,`unit_flags`,`dynamicflags`,`CreateObject`) VALUES
(5391001,900100,0,0,0,1,1,0,-8944.64,-132.319,83.7199,3.33358,120,0,0,1,0,0,0,0,0,1),
(5391002,900200,0,0,0,1,1,0,-8942.9,-130.6,83.7199,3.33358,120,0,0,1,0,0,0,0,0,1),
(5391003,900101,1,0,0,1,1,0,-607.073,-4253.52,39.0393,3.28122,120,0,0,1,0,0,0,0,0,1),
(5391004,900201,1,0,0,1,1,0,-605.3,-4251.8,39.0393,3.28122,120,0,0,1,0,0,0,0,0,1),
(5391005,900102,0,0,0,1,1,0,-6233.74,331.113,382.911,3.00197,120,0,0,1,0,0,0,0,0,1),
(5391006,900202,0,0,0,1,1,0,-6232.0,332.9,382.911,3.00197,120,0,0,1,0,0,0,0,0,1),
(5391007,900103,1,0,0,1,1,0,10317.0,829.83,1326.48,2.54818,120,0,0,1,0,0,0,0,0,1),
(5391008,900203,1,0,0,1,1,0,10318.7,831.6,1326.48,2.54818,120,0,0,1,0,0,0,0,0,1),
(5391009,900104,0,0,0,1,1,0,1681.99,1667.86,135.855,3.76991,120,0,0,1,0,0,0,0,0,1),
(5391010,900204,0,0,0,1,1,0,1683.7,1669.6,135.855,3.76991,120,0,0,1,0,0,0,0,0,1),
(5391011,900105,1,0,0,1,1,0,-2909.7,-257.54,53.0241,3.1765,120,0,0,1,0,0,0,0,0,1),
(5391012,900205,1,0,0,1,1,0,-2907.9,-255.8,53.0241,3.1765,120,0,0,1,0,0,0,0,0,1),
(5391013,900106,530,0,0,1,1,0,10355.0,-6359.93,34.1146,2.07694,120,0,0,1,0,0,0,0,0,1),
(5391014,900206,530,0,0,1,1,0,10356.7,-6358.2,34.1146,2.07694,120,0,0,1,0,0,0,0,0,1),
(5391015,900107,530,0,0,1,1,0,-3959.0,-13926.3,101.238,4.1889,120,0,0,1,0,0,0,0,0,1),
(5391016,900207,530,0,0,1,1,0,-3957.3,-13924.6,101.238,4.1889,120,0,0,1,0,0,0,0,0,1);
