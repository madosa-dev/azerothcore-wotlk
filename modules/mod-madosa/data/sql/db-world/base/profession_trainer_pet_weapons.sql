-- Craftbot also teaches every weapon skill the Weapon Masters do (Two-Handed
-- Axes, Polearms, Crossbows, ...), so a capital-city trip is not needed for
-- those either. Same union trick as profession_trainer_pet.sql, over the
-- eleven creatures with subname "Weapon Master" - 14 distinct skills.
--
-- Class and race gating is the core's: Trainer::SendSpells() and
-- GetSpellState() both run IsSpellFitByClassAndRace(), so a priest never sees
-- Two-Handed Axes in the list, exactly as at the real Weapon Master. Free,
-- like the recipes in profession_trainer_pet_recipes.sql.
--
-- INSERT IGNORE and a name that sorts after profession_trainer_pet.sql, which
-- opens with DELETE FROM trainer_spell WHERE TrainerId = 90002.

INSERT IGNORE INTO `trainer_spell` (`TrainerId`,`SpellId`,`MoneyCost`,`ReqSkillLine`,`ReqSkillRank`,`ReqAbility1`,`ReqAbility2`,`ReqAbility3`,`ReqLevel`)
SELECT 90002, `SpellId`, 0, MIN(`ReqSkillLine`), MIN(`ReqSkillRank`), MIN(`ReqAbility1`), MIN(`ReqAbility2`), MIN(`ReqAbility3`), MIN(`ReqLevel`)
FROM `trainer_spell`
WHERE `TrainerId` IN (
    SELECT DISTINCT cdt.`TrainerId`
    FROM `creature_template` ct
    JOIN `creature_default_trainer` cdt ON cdt.`CreatureId` = ct.`entry`
    WHERE ct.`subname` = 'Weapon Master'
)
GROUP BY `SpellId`;
