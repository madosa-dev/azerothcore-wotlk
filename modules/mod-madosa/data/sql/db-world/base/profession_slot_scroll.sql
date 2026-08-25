-- "Scroll of Professions" - consuming one grants a further primary profession
-- slot, handled by ItemScript item_madosa_profession_scroll
-- (src/mod_madosa_profession_slots.cpp). The per-character count lives in
-- mod_madosa_profession_slots in the characters DB.
--
-- The item needs *some* on-use spell or the client never sends CMSG_USE_ITEM
-- and right-clicking does nothing. Spell 36177 ("Dummy") has all three effects
-- set to 0 and is referenced by nothing else in this database, so it is inert:
-- the script returns true from OnUse, which stops WorldSession from casting it
-- at all (see SpellHandler.cpp:197). Its name and tooltip are rewritten in the
-- client patch built by tools/clientpatch/build_patches.py.
--
-- displayid 3331 is Blizzard's plain scroll, so the item icon needs no patch.
--
-- Quality 6 ("Vanity" - see addon/VanityQuality) like the companion pets, even
-- though it doesn't teach a spell via ITEM_SPELLTRIGGER_LEARN_SPELL_ID and so
-- never becomes account-wide through mod_madosa_account_companions.cpp: that's
-- correct here, a profession slot is inherently per-character.

DELETE FROM `item_template` WHERE `entry` = 90001;
INSERT INTO `item_template`
  (`entry`,`class`,`subclass`,`name`,`displayid`,`Quality`,`Flags`,`BuyCount`,
   `BuyPrice`,`SellPrice`,`InventoryType`,`AllowableClass`,`AllowableRace`,
   `ItemLevel`,`RequiredLevel`,`maxcount`,`stackable`,`bonding`,
   `spellid_1`,`spelltrigger_1`,`spellcharges_1`,`spellcooldown_1`,
   `description`,`ScriptName`)
VALUES
  (90001,0,0,'Scroll of Professions',3331,6,0,1,
   5000000,0,0,-1,-1,
   80,1,0,5,0,
   36177,0,0,-1,
   'Grants one additional primary profession slot. Bound to the character that reads it.',
   'item_madosa_profession_scroll');

-- Sold at the same 8 "Special Vendor" NPCs as the companion pets (see
-- auto_loot_pet.sql), slot 7 - slots 1-6 are already taken by the pets.
DELETE FROM `npc_vendor` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307) AND `item` = 90001;
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900300,7,90001,0,0,0),
(900301,7,90001,0,0,0),
(900302,7,90001,0,0,0),
(900303,7,90001,0,0,0),
(900304,7,90001,0,0,0),
(900305,7,90001,0,0,0),
(900306,7,90001,0,0,0),
(900307,7,90001,0,0,0);
