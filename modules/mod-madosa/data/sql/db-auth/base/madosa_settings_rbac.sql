-- Custom permission for the ".madosa" GM commands and the MadosaControl addon bridge
DELETE FROM `rbac_permissions` WHERE `id` = 1001;
INSERT INTO `rbac_permissions` (`id`, `name`) VALUES
(1001, 'Command: madosa');

DELETE FROM `rbac_linked_permissions` WHERE `linkedId` = 1001;
INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
(197, 1001);
