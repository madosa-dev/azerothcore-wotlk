-- Free starter mount + earlier riding: level 7 apprentice riding, racial mount NPC in every starting zone

-- 1) Allow training Apprentice Riding (spell 33388) starting at level 7 instead of the current requirement
UPDATE `trainer_spell` SET `ReqLevel` = 7 WHERE `SpellID` = 33388;

-- 2) The mount items themselves also carry a level requirement - lower it to match
UPDATE `item_template` SET `RequiredLevel` = 7 WHERE `entry` IN (5656,5668,5872,8591,8629,13321,13333,15290,28481,29220);

-- 3) Creature templates for the racial mount NPC (one per starting-zone location/model)
DELETE FROM `creature_template` WHERE `entry` IN (900000,900001,900002,900003,900004,900005,900006,900007);
INSERT INTO `creature_template` (`entry`,`difficulty_entry_1`,`difficulty_entry_2`,`difficulty_entry_3`,`KillCredit1`,`KillCredit2`,`name`,`subname`,`gossip_menu_id`,`minlevel`,`maxlevel`,`exp`,`faction`,`npcflag`,`speed_walk`,`speed_run`,`speed_swim`,`speed_flight`,`detection_range`,`rank`,`dmgschool`,`DamageModifier`,`BaseAttackTime`,`RangeAttackTime`,`BaseVariance`,`RangeVariance`,`unit_class`,`unit_flags`,`unit_flags2`,`dynamicflags`,`family`,`type`,`type_flags`,`lootid`,`pickpocketloot`,`skinloot`,`PetSpellDataId`,`VehicleId`,`mingold`,`maxgold`,`AIName`,`MovementType`,`HoverHeight`,`HealthModifier`,`ManaModifier`,`ArmorModifier`,`ExperienceModifier`,`RacialLeader`,`movementId`,`RegenHealth`,`CreatureImmunitiesId`,`flags_extra`,`ScriptName`) VALUES
(900000,0,0,0,0,0,'Riding Instructor','Free Mount',900000,1,1,0,12,1,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'SmartAI',0,1,1,1,1,1,0,0,1,0,0,''),
(900001,0,0,0,0,0,'Riding Instructor','Free Mount',900000,1,1,0,29,1,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'SmartAI',0,1,1,1,1,1,0,0,1,0,0,''),
(900002,0,0,0,0,0,'Riding Instructor','Free Mount',900000,1,1,0,55,1,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'SmartAI',0,1,1,1,1,1,0,0,1,0,0,''),
(900003,0,0,0,0,0,'Riding Instructor','Free Mount',900000,1,1,0,80,1,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'SmartAI',0,1,1,1,1,1,0,0,1,0,0,''),
(900004,0,0,0,0,0,'Riding Instructor','Free Mount',900000,1,1,0,68,1,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'SmartAI',0,1,1,1,1,1,0,0,1,0,0,''),
(900005,0,0,0,0,0,'Riding Instructor','Free Mount',900000,1,1,0,104,1,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'SmartAI',0,1,1,1,1,1,0,0,1,0,0,''),
(900006,0,0,0,0,0,'Riding Instructor','Free Mount',900000,1,1,0,1604,1,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'SmartAI',0,1,1,1,1,1,0,0,1,0,0,''),
(900007,0,0,0,0,0,'Riding Instructor','Free Mount',900000,1,1,0,1638,1,1,1.14286,1,1,20,0,0,1,0,0,1,1,1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'SmartAI',0,1,1,1,1,1,0,0,1,0,0,'');

-- 4) Model per template
DELETE FROM `creature_template_model` WHERE `CreatureID` IN (900000,900001,900002,900003,900004,900005,900006,900007);
INSERT INTO `creature_template_model` (`CreatureID`,`Idx`,`CreatureDisplayID`,`DisplayScale`,`Probability`) VALUES
(900000,0,2072,1,1),
(900001,0,9470,1,1),
(900002,0,1362,1,1),
(900003,0,1285,1,1),
(900004,0,1582,1,1),
(900005,0,3808,1,1),
(900006,0,15516,1,1),
(900007,0,16203,1,1);

-- 5) Gossip text + menu + one option per race (only the matching race sees its own option)
DELETE FROM `npc_text` WHERE `ID` = 900000;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900000,'Looking for a mount to get around faster? I can help with that.','Looking for a mount to get around faster? I can help with that.',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900000;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900000,900000);

DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900000;
INSERT INTO `gossip_menu_option` (`MenuID`,`OptionID`,`OptionIcon`,`OptionText`,`OptionBroadcastTextID`,`OptionType`,`OptionNpcFlag`,`ActionMenuID`,`ActionPoiID`,`BoxCoded`,`BoxMoney`,`BoxText`,`BoxBroadcastTextID`) VALUES
(900000,0,0,'I would like a free Brown Horse.',0,0,1,0,0,0,0,'',0),
(900000,1,0,'I would like a free Brown Wolf.',0,0,1,0,0,0,0,'',0),
(900000,2,0,'I would like a free Brown Ram.',0,0,1,0,0,0,0,'',0),
(900000,3,0,'I would like a free Striped Nightsaber.',0,0,1,0,0,0,0,'',0),
(900000,4,0,'I would like a free Brown Skeletal Horse.',0,0,1,0,0,0,0,'',0),
(900000,5,0,'I would like a free Brown Kodo.',0,0,1,0,0,0,0,'',0),
(900000,6,0,'I would like a free Green Mechanostrider.',0,0,1,0,0,0,0,'',0),
(900000,7,0,'I would like a free Turquoise Raptor.',0,0,1,0,0,0,0,'',0),
(900000,8,0,'I would like a free Blue Hawkstrider.',0,0,1,0,0,0,0,'',0),
(900000,9,0,'I would like a free Brown Elekk.',0,0,1,0,0,0,0,'',0);

-- 6) Race-gate each option so only the matching race can see/select it
DELETE FROM `conditions` WHERE `SourceTypeOrReferenceId` = 15 AND `SourceGroup` = 900000;
INSERT INTO `conditions` (`SourceTypeOrReferenceId`,`SourceGroup`,`SourceEntry`,`SourceId`,`ElseGroup`,`ConditionTypeOrReference`,`ConditionTarget`,`ConditionValue1`,`ConditionValue2`,`ConditionValue3`,`NegativeCondition`,`ErrorType`,`ErrorTextId`,`ScriptName`,`Comment`) VALUES
(15,900000,0,0,0,16,0,1,0,0,0,0,0,'','Riding instructor - Human only'),
(15,900000,1,0,0,16,0,2,0,0,0,0,0,'','Riding instructor - Orc only'),
(15,900000,2,0,0,16,0,4,0,0,0,0,0,'','Riding instructor - Dwarf only'),
(15,900000,3,0,0,16,0,8,0,0,0,0,0,'','Riding instructor - NightElf only'),
(15,900000,4,0,0,16,0,16,0,0,0,0,0,'','Riding instructor - Undead only'),
(15,900000,5,0,0,16,0,32,0,0,0,0,0,'','Riding instructor - Tauren only'),
(15,900000,6,0,0,16,0,64,0,0,0,0,0,'','Riding instructor - Gnome only'),
(15,900000,7,0,0,16,0,128,0,0,0,0,0,'','Riding instructor - Troll only'),
(15,900000,8,0,0,16,0,512,0,0,0,0,0,'','Riding instructor - BloodElf only'),
(15,900000,9,0,0,16,0,1024,0,0,0,0,0,'','Riding instructor - Draenei only');

-- 7) SmartAI: selecting an option grants the corresponding mount item to the player who clicked it
DELETE FROM `smart_scripts` WHERE `entryorguid` IN (900000,900001,900002,900003,900004,900005,900006,900007) AND `source_type` = 0;
INSERT INTO `smart_scripts` (`entryorguid`,`source_type`,`id`,`link`,`event_type`,`event_phase_mask`,`event_chance`,`event_flags`,`event_param1`,`event_param2`,`event_param3`,`event_param4`,`event_param5`,`event_param6`,`action_type`,`action_param1`,`action_param2`,`action_param3`,`action_param4`,`action_param5`,`action_param6`,`target_type`,`target_param1`,`target_param2`,`target_param3`,`target_param4`,`target_x`,`target_y`,`target_z`,`target_o`,`comment`) VALUES
(900000,0,0,0,62,1,100,0,900000,0,0,0,0,0,56,5656,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Horse on gossip select'),
(900000,0,1,0,62,1,100,0,900000,1,0,0,0,0,56,5668,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Wolf on gossip select'),
(900000,0,2,0,62,1,100,0,900000,2,0,0,0,0,56,5872,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Ram on gossip select'),
(900000,0,3,0,62,1,100,0,900000,3,0,0,0,0,56,8629,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Striped Nightsaber on gossip select'),
(900000,0,4,0,62,1,100,0,900000,4,0,0,0,0,56,13333,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Skeletal Horse on gossip select'),
(900000,0,5,0,62,1,100,0,900000,5,0,0,0,0,56,15290,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Kodo on gossip select'),
(900000,0,6,0,62,1,100,0,900000,6,0,0,0,0,56,13321,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Green Mechanostrider on gossip select'),
(900000,0,7,0,62,1,100,0,900000,7,0,0,0,0,56,8591,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Turquoise Raptor on gossip select'),
(900000,0,8,0,62,1,100,0,900000,8,0,0,0,0,56,29220,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Blue Hawkstrider on gossip select'),
(900000,0,9,0,62,1,100,0,900000,9,0,0,0,0,56,28481,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Elekk on gossip select'),
(900001,0,0,0,62,1,100,0,900000,0,0,0,0,0,56,5656,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Horse on gossip select'),
(900001,0,1,0,62,1,100,0,900000,1,0,0,0,0,56,5668,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Wolf on gossip select'),
(900001,0,2,0,62,1,100,0,900000,2,0,0,0,0,56,5872,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Ram on gossip select'),
(900001,0,3,0,62,1,100,0,900000,3,0,0,0,0,56,8629,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Striped Nightsaber on gossip select'),
(900001,0,4,0,62,1,100,0,900000,4,0,0,0,0,56,13333,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Skeletal Horse on gossip select'),
(900001,0,5,0,62,1,100,0,900000,5,0,0,0,0,56,15290,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Kodo on gossip select'),
(900001,0,6,0,62,1,100,0,900000,6,0,0,0,0,56,13321,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Green Mechanostrider on gossip select'),
(900001,0,7,0,62,1,100,0,900000,7,0,0,0,0,56,8591,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Turquoise Raptor on gossip select'),
(900001,0,8,0,62,1,100,0,900000,8,0,0,0,0,56,29220,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Blue Hawkstrider on gossip select'),
(900001,0,9,0,62,1,100,0,900000,9,0,0,0,0,56,28481,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Elekk on gossip select'),
(900002,0,0,0,62,1,100,0,900000,0,0,0,0,0,56,5656,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Horse on gossip select'),
(900002,0,1,0,62,1,100,0,900000,1,0,0,0,0,56,5668,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Wolf on gossip select'),
(900002,0,2,0,62,1,100,0,900000,2,0,0,0,0,56,5872,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Ram on gossip select'),
(900002,0,3,0,62,1,100,0,900000,3,0,0,0,0,56,8629,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Striped Nightsaber on gossip select'),
(900002,0,4,0,62,1,100,0,900000,4,0,0,0,0,56,13333,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Skeletal Horse on gossip select'),
(900002,0,5,0,62,1,100,0,900000,5,0,0,0,0,56,15290,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Kodo on gossip select'),
(900002,0,6,0,62,1,100,0,900000,6,0,0,0,0,56,13321,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Green Mechanostrider on gossip select'),
(900002,0,7,0,62,1,100,0,900000,7,0,0,0,0,56,8591,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Turquoise Raptor on gossip select'),
(900002,0,8,0,62,1,100,0,900000,8,0,0,0,0,56,29220,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Blue Hawkstrider on gossip select'),
(900002,0,9,0,62,1,100,0,900000,9,0,0,0,0,56,28481,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Elekk on gossip select'),
(900003,0,0,0,62,1,100,0,900000,0,0,0,0,0,56,5656,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Horse on gossip select'),
(900003,0,1,0,62,1,100,0,900000,1,0,0,0,0,56,5668,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Wolf on gossip select'),
(900003,0,2,0,62,1,100,0,900000,2,0,0,0,0,56,5872,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Ram on gossip select'),
(900003,0,3,0,62,1,100,0,900000,3,0,0,0,0,56,8629,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Striped Nightsaber on gossip select'),
(900003,0,4,0,62,1,100,0,900000,4,0,0,0,0,56,13333,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Skeletal Horse on gossip select'),
(900003,0,5,0,62,1,100,0,900000,5,0,0,0,0,56,15290,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Kodo on gossip select'),
(900003,0,6,0,62,1,100,0,900000,6,0,0,0,0,56,13321,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Green Mechanostrider on gossip select'),
(900003,0,7,0,62,1,100,0,900000,7,0,0,0,0,56,8591,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Turquoise Raptor on gossip select'),
(900003,0,8,0,62,1,100,0,900000,8,0,0,0,0,56,29220,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Blue Hawkstrider on gossip select'),
(900003,0,9,0,62,1,100,0,900000,9,0,0,0,0,56,28481,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Elekk on gossip select'),
(900004,0,0,0,62,1,100,0,900000,0,0,0,0,0,56,5656,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Horse on gossip select'),
(900004,0,1,0,62,1,100,0,900000,1,0,0,0,0,56,5668,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Wolf on gossip select'),
(900004,0,2,0,62,1,100,0,900000,2,0,0,0,0,56,5872,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Ram on gossip select'),
(900004,0,3,0,62,1,100,0,900000,3,0,0,0,0,56,8629,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Striped Nightsaber on gossip select'),
(900004,0,4,0,62,1,100,0,900000,4,0,0,0,0,56,13333,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Skeletal Horse on gossip select'),
(900004,0,5,0,62,1,100,0,900000,5,0,0,0,0,56,15290,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Kodo on gossip select'),
(900004,0,6,0,62,1,100,0,900000,6,0,0,0,0,56,13321,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Green Mechanostrider on gossip select'),
(900004,0,7,0,62,1,100,0,900000,7,0,0,0,0,56,8591,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Turquoise Raptor on gossip select'),
(900004,0,8,0,62,1,100,0,900000,8,0,0,0,0,56,29220,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Blue Hawkstrider on gossip select'),
(900004,0,9,0,62,1,100,0,900000,9,0,0,0,0,56,28481,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Elekk on gossip select'),
(900005,0,0,0,62,1,100,0,900000,0,0,0,0,0,56,5656,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Horse on gossip select'),
(900005,0,1,0,62,1,100,0,900000,1,0,0,0,0,56,5668,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Wolf on gossip select'),
(900005,0,2,0,62,1,100,0,900000,2,0,0,0,0,56,5872,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Ram on gossip select'),
(900005,0,3,0,62,1,100,0,900000,3,0,0,0,0,56,8629,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Striped Nightsaber on gossip select'),
(900005,0,4,0,62,1,100,0,900000,4,0,0,0,0,56,13333,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Skeletal Horse on gossip select'),
(900005,0,5,0,62,1,100,0,900000,5,0,0,0,0,56,15290,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Kodo on gossip select'),
(900005,0,6,0,62,1,100,0,900000,6,0,0,0,0,56,13321,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Green Mechanostrider on gossip select'),
(900005,0,7,0,62,1,100,0,900000,7,0,0,0,0,56,8591,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Turquoise Raptor on gossip select'),
(900005,0,8,0,62,1,100,0,900000,8,0,0,0,0,56,29220,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Blue Hawkstrider on gossip select'),
(900005,0,9,0,62,1,100,0,900000,9,0,0,0,0,56,28481,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Elekk on gossip select'),
(900006,0,0,0,62,1,100,0,900000,0,0,0,0,0,56,5656,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Horse on gossip select'),
(900006,0,1,0,62,1,100,0,900000,1,0,0,0,0,56,5668,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Wolf on gossip select'),
(900006,0,2,0,62,1,100,0,900000,2,0,0,0,0,56,5872,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Ram on gossip select'),
(900006,0,3,0,62,1,100,0,900000,3,0,0,0,0,56,8629,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Striped Nightsaber on gossip select'),
(900006,0,4,0,62,1,100,0,900000,4,0,0,0,0,56,13333,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Skeletal Horse on gossip select'),
(900006,0,5,0,62,1,100,0,900000,5,0,0,0,0,56,15290,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Kodo on gossip select'),
(900006,0,6,0,62,1,100,0,900000,6,0,0,0,0,56,13321,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Green Mechanostrider on gossip select'),
(900006,0,7,0,62,1,100,0,900000,7,0,0,0,0,56,8591,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Turquoise Raptor on gossip select'),
(900006,0,8,0,62,1,100,0,900000,8,0,0,0,0,56,29220,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Blue Hawkstrider on gossip select'),
(900006,0,9,0,62,1,100,0,900000,9,0,0,0,0,56,28481,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Elekk on gossip select'),
(900007,0,0,0,62,1,100,0,900000,0,0,0,0,0,56,5656,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Horse on gossip select'),
(900007,0,1,0,62,1,100,0,900000,1,0,0,0,0,56,5668,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Wolf on gossip select'),
(900007,0,2,0,62,1,100,0,900000,2,0,0,0,0,56,5872,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Ram on gossip select'),
(900007,0,3,0,62,1,100,0,900000,3,0,0,0,0,56,8629,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Striped Nightsaber on gossip select'),
(900007,0,4,0,62,1,100,0,900000,4,0,0,0,0,56,13333,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Skeletal Horse on gossip select'),
(900007,0,5,0,62,1,100,0,900000,5,0,0,0,0,56,15290,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Kodo on gossip select'),
(900007,0,6,0,62,1,100,0,900000,6,0,0,0,0,56,13321,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Green Mechanostrider on gossip select'),
(900007,0,7,0,62,1,100,0,900000,7,0,0,0,0,56,8591,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Turquoise Raptor on gossip select'),
(900007,0,8,0,62,1,100,0,900000,8,0,0,0,0,56,29220,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Blue Hawkstrider on gossip select'),
(900007,0,9,0,62,1,100,0,900000,9,0,0,0,0,56,28481,1,0,0,0,0,7,0,0,0,0,0,0,0,0,'Riding Instructor - grant Brown Elekk on gossip select');

-- 8) Spawn one riding instructor at each starting zone
DELETE FROM `creature` WHERE `guid` BETWEEN 5390001 AND 5390008;
INSERT INTO `creature` (`guid`,`id`,`map`,`zoneId`,`areaId`,`spawnMask`,`phaseMask`,`equipment_id`,`position_x`,`position_y`,`position_z`,`orientation`,`spawntimesecs`,`wander_distance`,`currentwaypoint`,`curhealth`,`curmana`,`MovementType`,`npcflag`,`unit_flags`,`dynamicflags`,`CreateObject`) VALUES
(5390001,900000,0,0,0,1,1,0,-8944.64,-132.319,83.7199,3.33358,120,0,0,1,0,0,1,0,0,1),
(5390002,900001,1,0,0,1,1,0,-607.073,-4253.52,39.0393,3.28122,120,0,0,1,0,0,1,0,0,1),
(5390003,900002,0,0,0,1,1,0,-6233.74,331.113,382.911,3.00197,120,0,0,1,0,0,1,0,0,1),
(5390004,900003,1,0,0,1,1,0,10317.0,829.83,1326.48,2.54818,120,0,0,1,0,0,1,0,0,1),
(5390005,900004,0,0,0,1,1,0,1681.99,1667.86,135.855,3.76991,120,0,0,1,0,0,1,0,0,1),
(5390006,900005,1,0,0,1,1,0,-2909.7,-257.54,53.0241,3.1765,120,0,0,1,0,0,1,0,0,1),
(5390007,900006,530,0,0,1,1,0,10355.0,-6359.93,34.1146,2.07694,120,0,0,1,0,0,1,0,0,1),
(5390008,900007,530,0,0,1,1,0,-3959.0,-13926.3,101.238,4.1889,120,0,0,1,0,0,1,0,0,1);
