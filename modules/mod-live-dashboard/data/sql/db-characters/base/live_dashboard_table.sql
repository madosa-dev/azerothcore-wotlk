-- Live snapshot of every online player/bot position, refreshed every ~2s by
-- mod-live-dashboard. Read-only from the outside (webapp/server.py polls it).
DROP TABLE IF EXISTS `live_player_positions`;
CREATE TABLE `live_player_positions` (
  `guid` INT UNSIGNED NOT NULL,
  `name` VARCHAR(12) NOT NULL,
  `is_bot` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `level` TINYINT UNSIGNED NOT NULL,
  `class` TINYINT UNSIGNED NOT NULL,
  `race` TINYINT UNSIGNED NOT NULL,
  `map_id` INT UNSIGNED NOT NULL,
  `zone_id` INT UNSIGNED NOT NULL,
  `area_id` INT UNSIGNED NOT NULL,
  `area_name` VARCHAR(100) NOT NULL DEFAULT '',
  `pos_x` FLOAT NOT NULL,
  `pos_y` FLOAT NOT NULL,
  `pos_z` FLOAT NOT NULL,
  `pct_x` FLOAT NOT NULL DEFAULT 0,
  `pct_y` FLOAT NOT NULL DEFAULT 0,
  `hp_pct` TINYINT UNSIGNED NOT NULL,
  `guild_name` VARCHAR(24) NOT NULL DEFAULT '',
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
