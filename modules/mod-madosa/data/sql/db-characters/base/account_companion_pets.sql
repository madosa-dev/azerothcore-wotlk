-- Tracks which mod-madosa companion pets (Lootbot, Classtrainer, Craftbot,
-- Bankbot, Auctionbot) each account has unlocked - see
-- mod_madosa_account_companions.cpp. spell_id is the companion's real
-- teach-spell (item_template.spellid_2 with spelltrigger_2 = 6), not the
-- item id, since that's what Player::HasSpell()/learnSpell() key off.
CREATE TABLE IF NOT EXISTS `account_companion_pets` (
  `account_id` INT UNSIGNED NOT NULL,
  `spell_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`account_id`, `spell_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
