-- Omnibot: one companion offering every service the individual ones do -
-- bank, auction house, mail, repair and training - plus Lootbot's auto-looting
-- (that part lives in mod_madosa_autoloot_pet.cpp, keyed on creature 40703).
--
-- The reason this exists is a hard client limit, not convenience: WotLK allows
-- exactly ONE summoned companion, so owning eight service pets means constantly
-- swapping them, and every companion added makes that worse. The core has the
-- same idea in the Argent Pony (scripts/Pet/pet_generic.cpp): one pet, several
-- services behind a gossip menu.
--
-- Repurposes item 54847 "Lil' XT" -> spell 75906 -> creature 40703, picked by the
-- same elimination as Repairbot/Mailbot: sold by no vendor, in no loot table, no
-- quest reward, not craftable by any spell, no existing ScriptName, spawned
-- nowhere in the world.

-- 1) The item. Quality 6 = the module's "Vanity" quality, which also makes
--    mod_madosa_account_companions.cpp pick the learn-spell up as account-wide.
--    10000g: five times a single companion, for something that replaces all of them.
UPDATE `item_template` SET `name` = 'Omnibot', `Description` = 'While summoned, this companion offers your bank, the auction house, your mailbox, repairs and training - and loots your kills. Everything, from one bot.', `BuyPrice` = 100000000, `Quality` = 6 WHERE `entry` = 54847;

-- 2) The creature. npcflag 69337201 = GOSSIP(1) | TRAINER(16) | TRAINER_CLASS(32)
--    | TRAINER_PROFESSION(64) | BANKER(0x20000) | AUCTIONEER(0x200000)
--    | MAILBOX(0x4000000). All of them permanently, because each service's
--    GetNPCIfCanInteractWith() check tests the creature's *current* flags - unlike
--    the Argent Pony (a real world NPC) there is no reason to swap them per use.
--    Repair needs no flag: it is done directly by the script.
--    Faction 188 matches the other companions and carries no Alliance/Horde mask,
--    so AuctionHouseMgr falls back to the neutral auction house.
UPDATE `creature_template` SET `name` = 'Omnibot', `npcflag` = 69337201, `gossip_menu_id` = 900380, `ScriptName` = 'npc_madosa_omnibot' WHERE `entry` = 40703;

DELETE FROM `npc_text` WHERE `ID` = 900380;
INSERT INTO `npc_text` (`ID`,`text0_0`,`text0_1`,`lang0`,`Probability0`) VALUES
(900380,'All systems nominal. What do you need?','All systems nominal. What do you need?',0,1);

DELETE FROM `gossip_menu` WHERE `MenuID` = 900380;
INSERT INTO `gossip_menu` (`MenuID`,`TextID`) VALUES (900380,900380);

-- No gossip_menu_option rows: the CreatureScript builds the whole menu itself.
DELETE FROM `gossip_menu_option` WHERE `MenuID` = 900380;

-- 3) Trainer 90003 - the union of Classtrainer's (90001) and Craftbot's (90002)
--    spell lists.
--
--    A merged trainer is necessary rather than merely convenient: both
--    WorldSession::SendTrainerList() and the buy handler resolve the trainer from
--    npc->GetEntry(), so a creature can only ever have ONE trainer - showing
--    another one's list would display spells that then fail to purchase.
--
--    Merging is safe because nothing that protects the player depends on the
--    trainer's Type: Trainer::GetSpellState() filters per spell through
--    Player::IsSpellFitByClassAndRace() (so you only ever see your own class's
--    spells), and Trainer::CanTeachSpell() enforces the two-primary-profession
--    limit through GetFreePrimaryProfessionPoints(). Requirement = 0 makes
--    IsTrainerValidForPlayer() return true for everyone, which is what lets one
--    trainer serve every class - and is why startup logs one harmless
--    "invalid class requirement" warning for it, exactly as it already does for 90001.
DELETE FROM `trainer` WHERE `Id` = 90003;
INSERT INTO `trainer` (`Id`,`Type`,`Requirement`,`Greeting`) VALUES
(90003,0,0,'Class or trade - I have the schematics for both.');

-- Built with a SELECT rather than a literal list so it cannot drift out of sync
-- with the two source trainers. DISTINCT because a spell present in both would
-- otherwise violate the (TrainerId, SpellId) primary key; MIN() picks one row's
-- requirements for such a spell, which is fine as they are identical in practice.
DELETE FROM `trainer_spell` WHERE `TrainerId` = 90003;
INSERT INTO `trainer_spell` (`TrainerId`,`SpellId`,`MoneyCost`,`ReqSkillLine`,`ReqSkillRank`,`ReqAbility1`,`ReqAbility2`,`ReqAbility3`,`ReqLevel`)
SELECT 90003, `SpellId`, MIN(`MoneyCost`), MIN(`ReqSkillLine`), MIN(`ReqSkillRank`),
       MIN(`ReqAbility1`), MIN(`ReqAbility2`), MIN(`ReqAbility3`), MIN(`ReqLevel`)
FROM `trainer_spell`
WHERE `TrainerId` IN (90001, 90002)
GROUP BY `SpellId`;

DELETE FROM `creature_default_trainer` WHERE `CreatureId` = 40703;
INSERT INTO `creature_default_trainer` (`CreatureId`,`TrainerId`) VALUES (40703,90003);

-- 4) Vendor stock: slot 10, after the eight companions and the scroll.
DELETE FROM `npc_vendor` WHERE `entry` IN (900300,900301,900302,900303,900304,900305,900306,900307) AND `item` = 54847;
INSERT INTO `npc_vendor` (`entry`,`slot`,`item`,`maxcount`,`incrtime`,`ExtendedCost`) VALUES
(900300,10,54847,0,0,0),
(900301,10,54847,0,0,0),
(900302,10,54847,0,0,0),
(900303,10,54847,0,0,0),
(900304,10,54847,0,0,0),
(900305,10,54847,0,0,0),
(900306,10,54847,0,0,0),
(900307,10,54847,0,0,0);
