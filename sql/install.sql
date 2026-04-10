-- ═══════════════════════════════════════════════════════════
--  WebCom Elevators – Database Schema (MySQL / MariaDB)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS `webcom_elevator_groups` (
    `id`                INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    `name`              VARCHAR(64)     NOT NULL UNIQUE,
    `label`             VARCHAR(128)    NOT NULL,
    `description`       VARCHAR(255)    DEFAULT NULL,
    `color`             VARCHAR(9)      NOT NULL DEFAULT '#3B82F6',
    `created_by`        VARCHAR(64)     DEFAULT NULL,
    `created_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `webcom_elevators` (
    `id`                INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    `group_id`          INT UNSIGNED    NOT NULL,
    `name`              VARCHAR(64)     NOT NULL UNIQUE,
    `label`             VARCHAR(128)    NOT NULL,
    `navigation_mode`   ENUM('list','updown') NOT NULL DEFAULT 'list',
    `interaction_type`  ENUM('target','dui') NOT NULL DEFAULT 'target',
    `cooldown_ms`       INT UNSIGNED    NOT NULL DEFAULT 5000,
    `is_active`         TINYINT(1)      NOT NULL DEFAULT 1,
    `created_by`        VARCHAR(64)     DEFAULT NULL,
    `created_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_elev_group`  (`group_id`),
    INDEX `idx_elev_active` (`is_active`),
    CONSTRAINT `fk_elev_group` FOREIGN KEY (`group_id`) REFERENCES `webcom_elevator_groups`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `webcom_elevator_floors` (
    `id`                INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    `elevator_id`       INT UNSIGNED    NOT NULL,
    `floor_number`      INT             NOT NULL DEFAULT 0,
    `label`             VARCHAR(128)    NOT NULL,
    `position`          JSON            NOT NULL,
    `interaction_point` JSON            DEFAULT NULL,
    `protection_type`   ENUM('none','pin','password','job','item') NOT NULL DEFAULT 'none',
    `protection_data`   JSON            DEFAULT NULL,
    `is_active`         TINYINT(1)      NOT NULL DEFAULT 1,
    `created_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_floor_elevator` (`elevator_id`),
    UNIQUE INDEX `idx_floor_unique` (`elevator_id`, `floor_number`),
    CONSTRAINT `fk_floor_elevator` FOREIGN KEY (`elevator_id`) REFERENCES `webcom_elevators`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
