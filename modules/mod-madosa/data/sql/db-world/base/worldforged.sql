-- Worldforged: a recurring world event. Every so often the server forges a
-- "Worldforged Cache" at one of the spots in mod_madosa_worldforged_spawns,
-- announces the zone to everyone online, and whoever gets there first opens it
-- for a randomly enchanted piece of gear scaled to their own level.
--
-- Everything the event does at runtime lives in src/mod_madosa_worldforged.cpp;
-- the spawn points themselves are generated into worldforged_spawns.sql by
-- tools/worldforged/build_spawns.py.

-- ---------------------------------------------------------------------------
-- The cache object
-- ---------------------------------------------------------------------------

-- type 10 = GAMEOBJECT_TYPE_GOOBER, NOT 3 = CHEST, even though it looks like a
-- chest. A chest is looted through CMSG_LOOT -> Player::SendLoot(), a path with
-- no script hook at all - GameObject::Use() does not even have a chest case. A
-- goober goes through CMSG_GAMEOBJ_USE -> GameObject::Use(), whose first
-- statement is sScriptMgr->OnGossipHello(player, go); returning true there
-- suppresses all default handling, which is what lets the script hand out a
-- reward computed for the player who opened it. Type and appearance are
-- independent, so this is purely about which code path the client takes.
--
-- displayId 1387 is the big raid-style treasure chest shared by "Massive
-- Treasure Chest" and the Four Horsemen Chest - a cache worth crossing the map
-- for should not look like a crate.
--
-- IconName 'LootAll' gives the loot-bag cursor, so it reads as treasure rather
-- than as a lever.
--
-- Data13 (goober.large) = 1 raises the object to VisibilityDistanceType::Large,
-- so it can be spotted from a distance instead of only once you are on top of
-- it. That is the difference between searching and stumbling.
-- Data16 (losOK) = 1 and Data17 (allowMounted) = 1: usable without line of
-- sight fuss and without being dismounted on arrival.
-- Data18 (floatingTooltip) = 1 shows the name on hover.
-- Everything else is deliberately 0: no lock, no quest, no spell, no
-- auto-close, and no 'consumable' - the script controls when the cache goes
-- away, not the template.

DELETE FROM `gameobject_template` WHERE `entry` = 900400;
INSERT INTO `gameobject_template`
  (`entry`,`type`,`displayId`,`name`,`IconName`,`castBarCaption`,`unk1`,`size`,
   `Data0`,`Data1`,`Data2`,`Data3`,`Data4`,`Data5`,`Data6`,`Data7`,`Data8`,`Data9`,`Data10`,`Data11`,
   `Data12`,`Data13`,`Data14`,`Data15`,`Data16`,`Data17`,`Data18`,`Data19`,`Data20`,`Data21`,`Data22`,`Data23`,
   `AIName`,`ScriptName`) VALUES
(900400,10,1387,'Worldforged Cache','LootAll','','',1,
 0,0,0,0,0,0,0,0,0,0,0,0,
 0,1,0,0,1,1,1,0,0,0,0,0,
 '','go_madosa_worldforged_cache');

-- ---------------------------------------------------------------------------
-- Where a cache can appear
-- ---------------------------------------------------------------------------

-- min_level/max_level describe the spot, not the reward: the forge matches them
-- against the levels of the real players currently online so a cache lands
-- somewhere they can actually reach. What is inside is always scaled to
-- whoever opens it, so any player can use any cache they can get to.
--
-- Rows below id 10000 are regenerated wholesale by
-- tools/worldforged/build_spawns.py. Add hand-picked spots of your own with ids
-- from 10000 up and regeneration will leave them alone.
CREATE TABLE IF NOT EXISTS `mod_madosa_worldforged_spawns` (
  `id` INT UNSIGNED NOT NULL,
  `map` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `position_x` FLOAT NOT NULL DEFAULT 0,
  `position_y` FLOAT NOT NULL DEFAULT 0,
  `position_z` FLOAT NOT NULL DEFAULT 0,
  `orientation` FLOAT NOT NULL DEFAULT 0,
  `min_level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `max_level` TINYINT UNSIGNED NOT NULL DEFAULT 80,
  `comment` VARCHAR(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='mod-madosa: Worldforged Cache spawn points';
