-- Persistent per-character XP boost granted via the .xpboost GM command
DROP TABLE IF EXISTS `character_xp_boost`;
CREATE TABLE `character_xp_boost` (
  `guid` INT UNSIGNED NOT NULL,
  `pct` SMALLINT UNSIGNED NOT NULL DEFAULT '0',
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
