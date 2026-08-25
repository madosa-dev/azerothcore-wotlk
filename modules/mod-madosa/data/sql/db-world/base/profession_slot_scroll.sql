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

DELETE FROM `item_template` WHERE `entry` = 90001;
INSERT INTO `item_template`
  (`entry`,`class`,`subclass`,`name`,`displayid`,`Quality`,`Flags`,`BuyCount`,
   `BuyPrice`,`SellPrice`,`InventoryType`,`AllowableClass`,`AllowableRace`,
   `ItemLevel`,`RequiredLevel`,`maxcount`,`stackable`,`bonding`,
   `spellid_1`,`spelltrigger_1`,`spellcharges_1`,`spellcooldown_1`,
   `description`,`ScriptName`)
VALUES
  (90001,0,0,'Scroll of Professions',3331,4,0,1,
   5000000,0,0,-1,-1,
   80,1,0,5,0,
   36177,0,0,-1,
   'Grants one additional primary profession slot. Bound to the character that reads it.',
   'item_madosa_profession_scroll');
