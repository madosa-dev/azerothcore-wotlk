-- Dragonmaw Bonewarder (1057, Wetlands): despawn its summoned Skeleton companion
-- when the Bonewarder dies, instead of leaving it behind as an orphaned mob.
DELETE FROM `smart_scripts` WHERE `entryorguid`=1057 AND `source_type`=0;
INSERT INTO `smart_scripts` (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`, `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`, `event_param6`, `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`, `target_type`, `target_param1`, `target_param2`, `target_param3`, `target_param4`, `target_x`, `target_y`, `target_z`, `target_o`, `comment`) VALUES
(1057, 0, 0, 0, 1, 0, 100, 1, 1000, 1000, 0, 0, 0, 0, 11, 8853, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 'Dragonmaw Bonewarder - Out of Combat - Cast Summon Skeleton (No Repeat)'),
(1057, 0, 1, 0, 0, 0, 100, 0, 8000, 14000, 8000, 14000, 0, 0, 11, 6205, 32, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 'Dragonmaw Bonewarder - In Combat - Cast Curse of Weakness'),
(1057, 0, 2, 0, 0, 0, 100, 0, 1000, 9000, 15000, 27000, 0, 0, 11, 707, 32, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 'Dragonmaw Bonewarder - In Combat - Cast Immolate'),
(1057, 0, 3, 0, 2, 0, 100, 1, 0, 15, 0, 0, 0, 0, 25, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 'Dragonmaw Bonewarder - Between 0-15% Health - Flee For Assist (No Repeat)'),
(1057, 0, 4, 0, 17, 0, 100, 0, 0, 0, 0, 0, 0, 0, 64, 1, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 'Dragonmaw Bonewarder - On Summoned Unit - Store Skeleton'),
(1057, 0, 5, 0, 6, 0, 100, 0, 0, 0, 0, 0, 0, 0, 41, 0, 0, 0, 0, 0, 0, 12, 1, 0, 0, 0, 0, 0, 0, 0, 'Dragonmaw Bonewarder - On Death - Despawn Skeleton');
