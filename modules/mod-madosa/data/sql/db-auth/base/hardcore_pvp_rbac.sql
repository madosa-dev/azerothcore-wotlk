-- Custom permission for the ".hardcore" player command
-- (modules/mod-madosa/src/mod_madosa_command.cpp).
--
-- Linked to 199 "Role: Player Commands" rather than a GM role: choosing to
-- enter Hardcore PvP, or to betray your faction, is something every player
-- does for themselves. The command enforces the same "in an inn or a city,
-- out of combat" rules the Hardcore Herald does, so it is not a way around
-- anything - just a way to do it without walking to the NPC.
DELETE FROM `rbac_permissions` WHERE `id` = 1002;
INSERT INTO `rbac_permissions` (`id`, `name`) VALUES
(1002, 'Command: hardcore');

DELETE FROM `rbac_linked_permissions` WHERE `linkedId` = 1002;
INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
(199, 1002);
