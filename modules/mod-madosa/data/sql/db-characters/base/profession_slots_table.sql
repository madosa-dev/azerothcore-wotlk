-- How many "Scroll of Professions" each character has consumed.
--
-- This has to be stored per character because WotLK does not keep the free
-- primary-profession counter anywhere: Player::LoadFromDB calls
-- InitPrimaryProfessions() on every login, which resets
-- PLAYER_CHARACTER_POINTS2 to CONFIG_MAX_PRIMARY_TRADE_SKILL, and each primary
-- profession spell loaded afterwards decrements it again. mod-madosa adds the
-- rows below back on top in OnPlayerLogin (mod_madosa_profession_slots.cpp).
CREATE TABLE IF NOT EXISTS `mod_madosa_profession_slots` (
  `guid` INT UNSIGNED NOT NULL,
  `extra_slots` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
