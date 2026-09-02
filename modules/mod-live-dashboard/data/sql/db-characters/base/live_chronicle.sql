-- The Chronicle: what actually happened on this realm.
--
-- One row per notable event, written by whichever module saw it. The table is
-- the whole contract between them - no module includes another's headers, they
-- just agree on this shape, the same way server.py and the C++ module already
-- agree on `live_player_positions`. mod-live-dashboard captures the generic
-- events (kills, milestones, boss kills, rare finds); mod-madosa writes its own
-- (Worldforged claims, risk-mode changes, death chests), guarded by a startup
-- check so it stays silent if this table is not installed.
--
-- Zone is stored as its name rather than its id: area names live in Map/Area
-- DBCs that the Python server has no reader for, and the server-side lookup is
-- free at the moment the event happens.
CREATE TABLE IF NOT EXISTS `live_chronicle` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `at` INT UNSIGNED NOT NULL,
  `kind` VARCHAR(32) NOT NULL,
  `actor` VARCHAR(64) NOT NULL DEFAULT '',
  `actor_bot` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `actor_class` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `actor_level` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `target` VARCHAR(64) NOT NULL DEFAULT '',
  `target_bot` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `zone` VARCHAR(64) NOT NULL DEFAULT '',
  `map` INT UNSIGNED NOT NULL DEFAULT 0,
  `value` BIGINT NOT NULL DEFAULT 0,
  `detail` VARCHAR(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `at` (`at`),
  KEY `kind_at` (`kind`, `at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- The admin command queue.
--
-- The dashboard never talks to the game process over a socket - it writes a row
-- here and the module picks it up on its next tick, runs it through the same
-- CliHandler the server console uses, and writes the output back. That keeps
-- mod-live-dashboard's founding promise (no sockets opened from inside
-- worldserver) and means an admin action survives the web server restarting
-- mid-command.
--
-- Every command runs with console rights. The gate is in server.py: a token,
-- and localhost-only binding by default. See the module README.
CREATE TABLE IF NOT EXISTS `live_dashboard_commands` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `created_at` INT UNSIGNED NOT NULL,
  `command` VARCHAR(512) NOT NULL,
  `status` ENUM('pending','done','failed') NOT NULL DEFAULT 'pending',
  `output` MEDIUMTEXT,
  `executed_at` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `status_id` (`status`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
