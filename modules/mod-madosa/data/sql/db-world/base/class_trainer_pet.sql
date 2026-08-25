-- Classtrainer companion: a "Special Vendor" in every capital city (the same
-- ones selling Lootbot) also sells a companion pet for 2000g that acts as a
-- class trainer for whoever summons it. There is only one pet/creature - the
-- trainer window it opens is filled with every class's trainer spells, and
-- Trainer::SendSpells()/GetSpellState() already filter each spell against the
-- viewing player's own class (Player::IsSpellFitByClassAndRace) before it's
-- ever shown, so each player only ever sees (and can only ever buy) the
-- spells for their own class - no per-class creature needed.
--
-- Like auto_loot_pet.sql, this repurposes an existing, currently-unsold
-- companion pet item/creature (Mojo, teaches spell 43918 via the standard
-- ITEM_SPELLTRIGGER_LEARN_SPELL_ID convention, summons creature 24480)
-- instead of inventing a new one - client-side summon effects for WotLK are
-- baked into the shipped Spell.dbc and can't be created from scratch without
-- a client patch.

-- 1) Repurpose the (currently unsold) Mojo item and the critter it summons,
--    both renamed to "Classtrainer". npcflag 49 = GOSSIP(1) | TRAINER(16) |
--    TRAINER_CLASS(32) - the same combination real class trainer NPCs use.
UPDATE `item_template` SET `name` = 'Classtrainer', `Description` = 'While summoned, this companion offers class training for your class - anywhere, anytime.', `BuyPrice` = 20000000, `Quality` = 6 WHERE `entry` = 33993;
UPDATE `creature_template` SET `name` = 'Classtrainer', `npcflag` = 49, `gossip_menu_id` = 900310 WHERE `entry` = 24480;

-- 2) Gossip: a single "I require training." option (OptionType 5 =
--    GOSSIP_OPTION_TRAINER, OptionNpcFlag 16 = UNIT_NPC_FLAG_TRAINER) is what
--    actually opens the trainer window - same reasoning as the Lootbot
--    vendor's explicit gossip option.
DELETE FROM `npc_text` WHERE `ID` = 900310;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900310,'Ready to further your training?','Ready to further your training?',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900310;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900310,900310);

DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900310;
INSERT INTO `gossip_menu_option` (`MenuID`,`OptionID`,`OptionIcon`,`OptionText`,`OptionBroadcastTextID`,`OptionType`,`OptionNpcFlag`,`ActionMenuID`,`ActionPoiID`,`BoxCoded`,`BoxMoney`,`BoxText`,`BoxBroadcastTextID`) VALUES
(900310,0,3,'I require training.',0,5,16,0,0,0,0,'',0);

-- 3) One synthetic "every class" trainer. Type 0 = Class, Requirement 0 means
--    Trainer::IsTrainerValidForPlayer() lets every class open the window (the
--    normal per-class gate only applies when Requirement is a real class id).
DELETE FROM `trainer` WHERE `Id` = 90001;
INSERT INTO `trainer` (`Id`,`Type`,`Requirement`,`Greeting`) VALUES
(90001,0,0,'Let''s see what I can teach you.');

DELETE FROM `creature_default_trainer` WHERE `CreatureId` = 24480;
INSERT INTO `creature_default_trainer` (`CreatureId`,`TrainerId`) VALUES (24480,90001);

-- 4) Trainer spells: the union of every class's own canonical trainer
--    (picked as the trainer_id with the most spells for each class - the
--    "teaches everything" trainer every class already has, as opposed to the
--    handful of narrow alternate-spec trainers), deduplicated by SpellId.
--    Kept as a SELECT off the existing data instead of literal values so it
--    stays correct if the base trainer_spell data ever changes.
DELETE FROM `trainer_spell` WHERE `TrainerId` = 90001;
INSERT INTO `trainer_spell` (`TrainerId`,`SpellId`,`MoneyCost`,`ReqSkillLine`,`ReqSkillRank`,`ReqAbility1`,`ReqAbility2`,`ReqAbility3`,`ReqLevel`)
SELECT 90001, `SpellId`, MIN(`MoneyCost`), MIN(`ReqSkillLine`), MIN(`ReqSkillRank`), MIN(`ReqAbility1`), MIN(`ReqAbility2`), MIN(`ReqAbility3`), MIN(`ReqLevel`)
FROM `trainer_spell`
WHERE `TrainerId` IN (
    SELECT `Id` FROM (
        SELECT t.`Id`, t.`Requirement`,
               ROW_NUMBER() OVER (PARTITION BY t.`Requirement` ORDER BY COUNT(ts.`SpellId`) DESC, t.`Id`) AS rn
        FROM `trainer` t
        JOIN `trainer_spell` ts ON ts.`TrainerId` = t.`Id`
        WHERE t.`Type` = 0 AND t.`Requirement` > 0 AND t.`Id` <> 90001
        GROUP BY t.`Id`
    ) ranked
    WHERE rn = 1
)
GROUP BY `SpellId`;

-- 5) Vendor stock: the companion, 2000g (BuyPrice above), at the same eight
--    Special Vendor NPCs Lootbot uses (see auto_loot_pet.sql).
DELETE FROM `npc_vendor` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307) AND `item` = 33993;
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900300,2,33993,0,0,0),
(900301,2,33993,0,0,0),
(900302,2,33993,0,0,0),
(900303,2,33993,0,0,0),
(900304,2,33993,0,0,0),
(900305,2,33993,0,0,0),
(900306,2,33993,0,0,0),
(900307,2,33993,0,0,0);
