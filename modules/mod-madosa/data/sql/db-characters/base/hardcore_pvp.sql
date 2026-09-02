-- Hardcore PvP: which risk mode each character has chosen.
--
-- Three modes, after Ascension's own three (PvE Mode 84422, War Mode 84420,
-- High-Risk 84421):
--
--   0  PvE       - the default. Not flagged, and cannot aid a flagged player.
--   1  War Mode  - permanently flagged, bonus XP, nothing at stake.
--   2  High-Risk - War Mode plus dungeon world drops, and a chest full of your
--                  bags when another High-Risk player kills you.
--
-- Per character rather than per account on purpose: the risk mode is a way to
-- play a character, and one account may well want a High-Risk main and a quiet
-- alt. Playerbots are never stored here - their participation is derived from
-- their guid and Madosa.HardcorePvP.BotParticipation, so changing that setting
-- leaves no stale rows behind.
--
-- `mode_since` is kept for its own sake (how long a character has held out),
-- `last_toggle` is what the toggle cooldown is measured against.
CREATE TABLE IF NOT EXISTS `character_hardcore_pvp` (
  `guid` INT UNSIGNED NOT NULL,
  `mode` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `traitor` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `insured` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `mode_since` BIGINT NOT NULL DEFAULT 0,
  `last_toggle` BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Migration from the first version of this table, which had a single
-- `hardcore` on/off column instead of a three-way mode. Each step is guarded by
-- information_schema rather than run blindly, because this file is re-applied
-- whenever its hash changes and ALTER TABLE is not idempotent on its own.

-- 1) add `mode` to a table that predates it
SET @stmt := IF((SELECT COUNT(*) FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'character_hardcore_pvp'
                   AND COLUMN_NAME = 'mode') = 0,
    'ALTER TABLE `character_hardcore_pvp` ADD COLUMN `mode` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `guid`',
    'DO 0');
PREPARE s FROM @stmt; EXECUTE s; DEALLOCATE PREPARE s;

-- 2) carry the old flag over: hardcore = 1 was what is now High-Risk
SET @stmt := IF((SELECT COUNT(*) FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'character_hardcore_pvp'
                   AND COLUMN_NAME = 'hardcore') > 0,
    'UPDATE `character_hardcore_pvp` SET `mode` = 2 WHERE `hardcore` = 1',
    'DO 0');
PREPARE s FROM @stmt; EXECUTE s; DEALLOCATE PREPARE s;

SET @stmt := IF((SELECT COUNT(*) FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'character_hardcore_pvp'
                   AND COLUMN_NAME = 'hardcore') > 0,
    'ALTER TABLE `character_hardcore_pvp` DROP COLUMN `hardcore`',
    'DO 0');
PREPARE s FROM @stmt; EXECUTE s; DEALLOCATE PREPARE s;

-- 3) gear insurance, added after the three modes were
SET @stmt := IF((SELECT COUNT(*) FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'character_hardcore_pvp'
                   AND COLUMN_NAME = 'insured') = 0,
    'ALTER TABLE `character_hardcore_pvp` ADD COLUMN `insured` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `traitor`',
    'DO 0');
PREPARE s FROM @stmt; EXECUTE s; DEALLOCATE PREPARE s;

-- 4) `hardcore_since` is now `mode_since`, since it times any mode
SET @stmt := IF((SELECT COUNT(*) FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'character_hardcore_pvp'
                   AND COLUMN_NAME = 'hardcore_since') > 0,
    'ALTER TABLE `character_hardcore_pvp` CHANGE `hardcore_since` `mode_since` BIGINT NOT NULL DEFAULT 0',
    'DO 0');
PREPARE s FROM @stmt; EXECUTE s; DEALLOCATE PREPARE s;

-- What a death chest is holding, so nothing can be lost to a crash, a restart,
-- or a killer who simply walked away.
--
-- The first version of this feature kept a chest's contents in memory only. If
-- nobody looted it - and on a realm where the killer is usually a bot, that is
-- the normal case - the items were destroyed on the victim and then quietly
-- ceased to exist when the chest crumbled. The victim lost, and nobody won.
--
-- Now every dropped stack - and the gold of an insurance chest - is written
-- here *before* it leaves the victim, removed again as it is looted, and
-- whatever is left when the chest expires is mailed back to the victim. Rows
-- surviving a restart are mailed back at the next startup, which is what makes
-- this safe against a crash as well.
CREATE TABLE IF NOT EXISTS `character_hardcore_pvp_chest` (
  `chest` BIGINT UNSIGNED NOT NULL,
  `slot` TINYINT UNSIGNED NOT NULL,
  `victim` INT UNSIGNED NOT NULL,
  `created_at` INT UNSIGNED NOT NULL,
  `item` INT UNSIGNED NOT NULL,
  `count` INT UNSIGNED NOT NULL DEFAULT 1,
  `random_property` INT NOT NULL DEFAULT 0,
  `suffix_factor` INT UNSIGNED NOT NULL DEFAULT 0,
  `enchants` VARCHAR(255) NOT NULL DEFAULT '',
  `gold` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`chest`, `slot`),
  KEY `victim` (`victim`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- The chest's gold is one row of its own (slot 255, item 0), so an insurance
-- payout nobody collected goes back the same way an item does. Guarded like
-- the migrations above, for tables created before the column existed.
SET @stmt := IF((SELECT COUNT(*) FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'character_hardcore_pvp_chest'
                   AND COLUMN_NAME = 'gold') = 0,
    'ALTER TABLE `character_hardcore_pvp_chest` ADD COLUMN `gold` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `enchants`',
    'DO 0');
PREPARE s FROM @stmt; EXECUTE s; DEALLOCATE PREPARE s;
