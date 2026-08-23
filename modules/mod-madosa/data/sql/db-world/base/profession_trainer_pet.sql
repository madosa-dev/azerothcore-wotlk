-- Craftbot companion: a "Special Vendor" in every capital city (the same
-- ones selling Lootbot and Classtrainer) also sells a companion pet for
-- 2000g that opens a single trainer window teaching every profession at
-- once - deliberately not a "pick a profession" menu, just one flat spell
-- list with everything in it (mining, herbalism, all the crafting
-- professions, cooking, first aid, fishing - primary and secondary alike).
--
-- Same trick as Classtrainer (see class_trainer_pet.sql): Trainer::Type is
-- Tradeskill here, but profession trainers already ship with Requirement = 0
-- (nothing to "already know" to see the list - unlike class trainers,
-- there's no per-player filtering step to lean on here, so every player
-- really does see every profession's full recipe list together, exactly as
-- asked for). The existing 2-primary-profession limit still applies as
-- normal - Trainer::CanTeachSpell() blocks buying a further primary
-- profession's starting recipe once both primary slots are full, same as
-- any other profession trainer.
--
-- Like the other two companions, this repurposes an existing, currently-
-- unsold companion pet item/creature (Frosty, teaches spell 52615 via the
-- standard ITEM_SPELLTRIGGER_LEARN_SPELL_ID convention, summons creature
-- 28883) instead of inventing a new one - client-side summon effects for
-- WotLK are baked into the shipped Spell.dbc and can't be created from
-- scratch without a client patch.

-- 1) Repurpose the (currently unsold) Frosty's Collar item and the critter
--    it summons, both renamed to "Craftbot". npcflag 81 = GOSSIP(1) |
--    TRAINER(16) | TRAINER_PROFESSION(64) - the same combination real
--    profession trainer NPCs use.
UPDATE `item_template` SET `name` = 'Craftbot', `Description` = 'While summoned, this companion offers training in every profession - anywhere, anytime.', `BuyPrice` = 20000000 WHERE `entry` = 39286;
UPDATE `creature_template` SET `name` = 'Craftbot', `npcflag` = 81, `gossip_menu_id` = 900320 WHERE `entry` = 28883;

-- 2) Gossip: a single "Train me." option (OptionType 5 = GOSSIP_OPTION_TRAINER,
--    OptionNpcFlag 16 = UNIT_NPC_FLAG_TRAINER) opens the trainer window -
--    same reasoning as Lootbot's vendor option and Classtrainer's own.
DELETE FROM `npc_text` WHERE `ID` = 900320;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900320,'Every trade has its secrets. Let me share them with you.','Every trade has its secrets. Let me share them with you.',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900320;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900320,900320);

DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900320;
INSERT INTO `gossip_menu_option` (`MenuID`,`OptionID`,`OptionIcon`,`OptionText`,`OptionBroadcastTextID`,`OptionType`,`OptionNpcFlag`,`ActionMenuID`,`ActionPoiID`,`BoxCoded`,`BoxMoney`,`BoxText`,`BoxBroadcastTextID`) VALUES
(900320,0,3,'Train me.',0,5,16,0,0,0,0,'',0);

-- 3) One synthetic "every profession" trainer. Type 2 = Tradeskill,
--    Requirement 0 matches how every real profession trainer is already set
--    up (there's no trainer-level "must already know profession X" gate to
--    work around here, unlike class trainers).
DELETE FROM `trainer` WHERE `Id` = 90002;
INSERT INTO `trainer` (`Id`,`Type`,`Requirement`,`Greeting`) VALUES
(90002,2,0,'Every trade has its secrets. Let me share them with you.');

DELETE FROM `creature_default_trainer` WHERE `CreatureId` = 28883;
INSERT INTO `creature_default_trainer` (`CreatureId`,`TrainerId`) VALUES (28883,90002);

-- 4) Trainer spells: the union of every profession's own canonical trainer
--    (picked as the "Grand Master" trainer for each profession - already
--    the complete Apprentice-through-Grand-Master recipe list on this
--    dataset, exactly like the class trainers, so no need to also pull in
--    the lower-tier trainers separately), deduplicated by SpellId. Kept as a
--    SELECT off the existing data instead of literal values so it stays
--    correct if the base trainer_spell data ever changes.
DELETE FROM `trainer_spell` WHERE `TrainerId` = 90002;
INSERT INTO `trainer_spell` (`TrainerId`,`SpellId`,`MoneyCost`,`ReqSkillLine`,`ReqSkillRank`,`ReqAbility1`,`ReqAbility2`,`ReqAbility3`,`ReqLevel`)
SELECT 90002, `SpellId`, MIN(`MoneyCost`), MIN(`ReqSkillLine`), MIN(`ReqSkillRank`), MIN(`ReqAbility1`), MIN(`ReqAbility2`), MIN(`ReqAbility3`), MIN(`ReqLevel`)
FROM `trainer_spell`
WHERE `TrainerId` IN (
    SELECT DISTINCT cdt.`TrainerId`
    FROM `creature_template` ct
    JOIN `creature_default_trainer` cdt ON cdt.`CreatureId` = ct.`entry`
    WHERE ct.`subname` IN (
        'Grand Master Alchemy Trainer','Grand Master Blacksmithing Trainer','Grand Master Cooking Trainer',
        'Grand Master Enchanting Trainer','Grand Master Engineering Trainer','Grand Master First Aid Trainer',
        'Grand Master Fishing Trainer','Grand Master Fishing Trainer & Supplies','Grand Master Herbalism Trainer',
        'Grand Master Inscription Trainer','Grand Master Jewelcrafting Trainer','Grand Master Leatherworking Trainer',
        'Grand Master Mining Trainer','Grand Master Skinning Trainer','Grand Master Tailoring Trainer'
    )
)
GROUP BY `SpellId`;

-- 5) Vendor stock: the companion, 2000g (BuyPrice above), at the same eight
--    Special Vendor NPCs Lootbot and Classtrainer use.
DELETE FROM `npc_vendor` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307) AND `item` = 39286;
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900300,3,39286,0,0,0),
(900301,3,39286,0,0,0),
(900302,3,39286,0,0,0),
(900303,3,39286,0,0,0),
(900304,3,39286,0,0,0),
(900305,3,39286,0,0,0),
(900306,3,39286,0,0,0),
(900307,3,39286,0,0,0);
