-- Which Ascension Worldforged items each character has already claimed - see
-- src/mod_madosa_worldforged_ascension.cpp.
--
-- Keyed by item rather than by find location on purpose: the 1509 distinct
-- Worldforged items are spread over 3599 spots, so several places hold the same
-- item. Recording the item is what makes "each item once per character" mean
-- what it says - claiming a Silverbound Dagger at one spot finishes every other
-- spot that holds one, instead of letting you farm duplicates a few hills apart.
--
-- Per character, not per account: an alt starts its own collection.
CREATE TABLE IF NOT EXISTS `character_worldforged_ascension_loot` (
  `guid` INT UNSIGNED NOT NULL,
  `item` INT UNSIGNED NOT NULL,
  `looted_at` BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='mod-madosa: Worldforged items already claimed, per character';
