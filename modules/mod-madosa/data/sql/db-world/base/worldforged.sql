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

-- ---------------------------------------------------------------------------
-- Ascension's own Worldforged: the real items, at the real places
-- ---------------------------------------------------------------------------

-- A second, separate system from the timed event above. Where that one forges a
-- randomly enchanted item somewhere, this reproduces Ascension's Worldforged as
-- it actually is: 3608 fixed spots across the world, each holding the specific
-- item Ascension players recorded finding there.
--
-- Both the items (worldforged_ascension_items.sql) and the locations
-- (worldforged_ascension_spawns.sql) are generated - see the tools under
-- tools/worldforged/ for where the data comes from and how it is verified.

-- The cache object. A GOOBER for the same reason as 900400 above: a chest is
-- looted through a path with no script hook, and the script has to decide who
-- may open it. displayId 2450 is the ornate treasure box carried by "Amani
-- Treasure Box" and "Ancient Drakkari Chest" - deliberately not 1387, so an
-- Ascension find is recognisably a different thing from the timed event's cache,
-- and picked from displays this database demonstrably spawns rather than from an
-- id that merely looks plausible.
DELETE FROM `gameobject_template` WHERE `entry` = 900401;
INSERT INTO `gameobject_template`
  (`entry`,`type`,`displayId`,`name`,`IconName`,`castBarCaption`,`unk1`,`size`,
   `Data0`,`Data1`,`Data2`,`Data3`,`Data4`,`Data5`,`Data6`,`Data7`,`Data8`,`Data9`,`Data10`,`Data11`,
   `Data12`,`Data13`,`Data14`,`Data15`,`Data16`,`Data17`,`Data18`,`Data19`,`Data20`,`Data21`,`Data22`,`Data23`,
   `AIName`,`ScriptName`) VALUES
(900401,10,2450,'Worldforged','LootAll','','',1,
 0,0,0,0,0,0,0,0,0,0,0,0,
 0,1,0,0,1,1,1,0,0,0,0,0,
 '','go_madosa_worldforged_ascension');

-- Where Ascension's Worldforged items are found. No position_z: ground height
-- needs the server's map data, so it is resolved with Map::GetHeight() the
-- moment a cache is streamed in near a player.
CREATE TABLE IF NOT EXISTS `mod_madosa_worldforged_ascension_spawns` (
  `id` INT UNSIGNED NOT NULL,
  `map` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `position_x` FLOAT NOT NULL DEFAULT 0,
  `position_y` FLOAT NOT NULL DEFAULT 0,
  `item` INT UNSIGNED NOT NULL DEFAULT 0,
  `zone` VARCHAR(64) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_map` (`map`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='mod-madosa: Ascension Worldforged find locations';

-- Which item_template rows this module owns, so regenerating the item file can
-- clean up after the previous run without touching anything else.
CREATE TABLE IF NOT EXISTS `mod_madosa_worldforged_ascension_items` (
  `item` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='mod-madosa: item_template rows owned by the Ascension Worldforged import';

-- The same idea for spell_dbc: the Worldforged item effects and everything they
-- cast in turn. That table already holds this core's own custom spells, so the
-- import has to be able to remove exactly its own rows and nothing else.
CREATE TABLE IF NOT EXISTS `mod_madosa_worldforged_ascension_spells` (
  `spell` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`spell`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='mod-madosa: spell_dbc rows owned by the Ascension Worldforged import';

DROP TABLE IF EXISTS `mod_madosa_worldforged_ascension_cooldowns`;
