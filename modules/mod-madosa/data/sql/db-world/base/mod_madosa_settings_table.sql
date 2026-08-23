-- Runtime overrides for MadosaSettings (mod_madosa_settings.h). Absence of a
-- row for a given setting_key just means "use the mod_madosa.conf.dist value".
CREATE TABLE IF NOT EXISTS `mod_madosa_settings` (
  `setting_key` VARCHAR(64) NOT NULL,
  `setting_value` VARCHAR(64) NOT NULL,
  PRIMARY KEY (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
