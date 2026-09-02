-- Hardcore PvP: the Hardcore Herald and the chest a fallen player leaves.
-- See src/mod_madosa_hardcore_pvp.cpp for what any of it does.

-- ---------------------------------------------------------------------------
-- 1) The Hardcore Herald
-- ---------------------------------------------------------------------------
-- Faction 35 ("Friendly" to everyone) is not decoration: while the traitor
-- flag is on, the character's own city factions are forced hostile, so a
-- Herald wearing a city's colours would be the one NPC a traitor could not
-- reach - and it is the NPC that takes the flag back off. For the same reason
-- it stands in the neutral towns as well as the capitals.
--
-- No gossip_menu rows: the menu is built in C++ (npc_madosa_hardcore_herald),
-- because which options it offers depends on what the player has switched on.
-- npcflag 1 is UNIT_NPC_FLAG_GOSSIP, which is what makes the client offer the
-- talk cursor at all.
DELETE FROM `creature_template` WHERE `entry` = 900500;
INSERT INTO `creature_template`
  (`entry`,`difficulty_entry_1`,`difficulty_entry_2`,`difficulty_entry_3`,`KillCredit1`,`KillCredit2`,`name`,`subname`,
   `gossip_menu_id`,`minlevel`,`maxlevel`,`exp`,`faction`,`npcflag`,`speed_walk`,`speed_run`,`speed_swim`,`speed_flight`,
   `detection_range`,`rank`,`dmgschool`,`DamageModifier`,`BaseAttackTime`,`RangeAttackTime`,`BaseVariance`,`RangeVariance`,
   `unit_class`,`unit_flags`,`unit_flags2`,`dynamicflags`,`family`,`type`,`type_flags`,`lootid`,`pickpocketloot`,`skinloot`,
   `PetSpellDataId`,`VehicleId`,`mingold`,`maxgold`,`AIName`,`MovementType`,`HoverHeight`,`HealthModifier`,`ManaModifier`,
   `ArmorModifier`,`ExperienceModifier`,`RacialLeader`,`movementId`,`RegenHealth`,`CreatureImmunitiesId`,`flags_extra`,`ScriptName`)
VALUES
(900500,0,0,0,0,0,'Hardcore Herald','Oaths and Treason',0,80,80,0,35,1,1,1.14286,1,1,20,0,0,1,0,0,1,1,
 1,0,2048,0,0,7,0,0,0,0,0,0,0,0,'',0,1,1,1,1,1,0,0,1,0,0,'npc_madosa_hardcore_herald');

-- An ethereal: hooded, faceless, and the one thing in this world that has
-- never picked a side.
DELETE FROM `creature_template_model` WHERE `CreatureID` = 900500;
INSERT INTO `creature_template_model` (`CreatureID`,`Idx`,`CreatureDisplayID`,`DisplayScale`,`Probability`) VALUES
(900500,0,21113,1,1);

-- ---------------------------------------------------------------------------
-- 2) Where the Heralds stand
-- ---------------------------------------------------------------------------
-- The eight capitals, beside the Special Vendors the other mod-madosa features
-- use, plus six neutral towns - Booty Bay, Gadgetzan, Everlook, Ratchet,
-- Shattrath and Dalaran - so a traitor whose own cities have turned on them
-- still has somewhere to go.
DELETE FROM `creature` WHERE `guid` BETWEEN 5393001 AND 5393014;
INSERT INTO `creature`
  (`guid`,`id`,`map`,`zoneId`,`areaId`,`spawnMask`,`phaseMask`,`equipment_id`,`position_x`,`position_y`,`position_z`,
   `orientation`,`spawntimesecs`,`wander_distance`,`currentwaypoint`,`curhealth`,`curmana`,`MovementType`,`npcflag`,
   `unit_flags`,`dynamicflags`,`CreateObject`)
VALUES
-- Capitals
(5393001,900500,0,0,0,1,1,0,-8829.38,626.628,94.0066,1.06535,120,0,0,1,0,0,0,0,0,1),      -- Stormwind
(5393002,900500,1,0,0,1,1,0,1633.85,-4375.64,31.5573,3.69762,120,0,0,1,0,0,0,0,0,1),      -- Orgrimmar
(5393003,900500,0,0,0,1,1,0,-4914.88,-942.406,501.564,5.42347,120,0,0,1,0,0,0,0,0,1),     -- Ironforge
(5393004,900500,1,0,0,1,1,0,9953.56,2286.21,1341.4,1.59587,120,0,0,1,0,0,0,0,0,1),        -- Thunder Bluff
(5393005,900500,0,0,0,1,1,0,1588.14,242.308,-52.1534,0.041793,120,0,0,1,0,0,0,0,0,1),     -- Undercity
(5393006,900500,1,0,0,1,1,0,-1273.37,126.804,131.287,5.22274,120,0,0,1,0,0,0,0,0,1),      -- Darnassus
(5393007,900500,530,0,0,1,1,0,9491.69,-7277.2,14.2866,6.16478,120,0,0,1,0,0,0,0,0,1),     -- Exodar
(5393008,900500,530,0,0,1,1,0,-3961.7,-11651.6,-138.844,0.852154,120,0,0,1,0,0,0,0,0,1),  -- Silvermoon
-- Neutral towns
(5393009,900500,0,0,0,1,1,0,-14455.7,495.35,15.21,3.979,120,0,0,1,0,0,0,0,0,1),           -- Booty Bay
(5393010,900500,1,0,0,1,1,0,-7156.96,-3841.61,8.85,1.955,120,0,0,1,0,0,0,0,0,1),          -- Gadgetzan
(5393011,900500,1,0,0,1,1,0,6697.15,-4673.04,721.65,0.541,120,0,0,1,0,0,0,0,0,1),         -- Everlook
(5393012,900500,1,0,0,1,1,0,-1048.04,-3664.8,23.97,6.004,120,0,0,1,0,0,0,0,0,1),          -- Ratchet
(5393013,900500,530,0,0,1,1,0,-2182.04,5399.62,51.97,1.239,120,0,0,1,0,0,0,0,0,1),        -- Shattrath
(5393014,900500,571,0,0,1,1,0,5849.97,635.43,647.57,1.047,120,0,0,1,0,0,0,0,0,1);         -- Dalaran

-- ---------------------------------------------------------------------------
-- 3) What the Herald says
-- ---------------------------------------------------------------------------
DELETE FROM `npc_text` WHERE `ID` = 900500;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900500,'Everyone here wants something worth dying for. Some of them want it badly enough to be worth killing.',
        'Everyone here wants something worth dying for. Some of them want it badly enough to be worth killing.',0,1);

-- ---------------------------------------------------------------------------
-- 4) The chest a fallen Hardcore player leaves behind
-- ---------------------------------------------------------------------------
-- Type 3 (CHEST) with **no loot id**, and that combination is the whole trick:
-- Player::SendLoot() only calls loot->clear() and FillLoot() inside
-- `if (lootid)` (Player.cpp:8029), so a chest without one keeps whatever the
-- server put in it by hand - which is how the victim's own belongings, with
-- their own random properties, end up in an ordinary loot window.
--
-- Data3 (consumable) stays 0 so the core does not despawn it on loot; the
-- module deletes it itself once it is empty or its lifetime runs out, which is
-- the only way to be sure an emptied chest does not stand there for the rest
-- of the uptime. Data15 (groupLootRules) stays 0 as well: who may open it and
-- when is decided in C++, not by the group loot method.
DELETE FROM `gameobject_template` WHERE `entry` = 900402;
INSERT INTO `gameobject_template`
  (`entry`,`type`,`displayId`,`name`,`IconName`,`castBarCaption`,`unk1`,`size`,
   `Data0`,`Data1`,`Data2`,`Data3`,`Data4`,`Data5`,`Data6`,`Data7`,`Data8`,`Data9`,`Data10`,`Data11`,
   `Data12`,`Data13`,`Data14`,`Data15`,`Data16`,`Data17`,`Data18`,`Data19`,`Data20`,`Data21`,`Data22`,`Data23`,
   `AIName`,`ScriptName`) VALUES
(900402,3,5743,'Spoils of the Fallen','LootAll','','',1,
 0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,
 '','');
