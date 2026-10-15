USE mediatheque;

CREATE TABLE IF NOT EXISTS journal_action (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  table_cible VARCHAR(40)     NOT NULL,
  operation   VARCHAR(10)     NOT NULL,
  cle         VARCHAR(40)     NOT NULL,
  auteur      VARCHAR(100)    NOT NULL,
  horodatage  DATETIME        NOT NULL,
  details     VARCHAR(255)        NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;

DROP TRIGGER IF EXISTS trg_emprunt_avant_insert;
DROP TRIGGER IF EXISTS trg_emprunt_apres_insert;
DROP TRIGGER IF EXISTS trg_emprunt_apres_update;

DELIMITER $$

CREATE TRIGGER trg_emprunt_avant_insert
BEFORE INSERT ON emprunt
FOR EACH ROW
BEGIN
  IF NEW.date_emprunt IS NULL THEN
    SET NEW.date_emprunt = CURDATE();
  END IF;

  IF NEW.date_retour_prevue IS NULL THEN
    SET NEW.date_retour_prevue = NEW.date_emprunt + INTERVAL 14 DAY;
  END IF;

  IF NEW.date_retour_prevue < NEW.date_emprunt THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'La date de retour prévue ne peut pas précéder la date d''emprunt.';
  END IF;
END$$

CREATE TRIGGER trg_emprunt_apres_insert
AFTER INSERT ON emprunt
FOR EACH ROW
BEGIN
  DECLARE v_details VARCHAR(255) DEFAULT NULL;

  UPDATE exemplaire
     SET disponible = 0
   WHERE id = NEW.exemplaire_id;

  SET v_details = CONCAT('adherent_id=', NEW.adherent_id,
                         ' exemplaire_id=', NEW.exemplaire_id,
                         ' emprunt=', NEW.date_emprunt,
                         ' retour_prevu=', NEW.date_retour_prevue);

  INSERT INTO journal_action (table_cible, operation, cle, auteur, horodatage, details)
       VALUES ('emprunt', 'INSERT', NEW.id, USER(), NOW(), v_details);
END$$

CREATE TRIGGER trg_emprunt_apres_update
AFTER UPDATE ON emprunt
FOR EACH ROW
BEGIN
  DECLARE v_details VARCHAR(255) DEFAULT NULL;
  DECLARE v_retard  INT          DEFAULT 0;

  IF OLD.date_retour_reelle IS NULL AND NEW.date_retour_reelle IS NOT NULL THEN
    UPDATE exemplaire
       SET disponible = 1
     WHERE id = NEW.exemplaire_id;

    SET v_retard = GREATEST(DATEDIFF(NEW.date_retour_reelle, NEW.date_retour_prevue), 0);

    SET v_details = CONCAT('adherent_id=', NEW.adherent_id,
                           ' exemplaire_id=', NEW.exemplaire_id,
                           ' retour_reel=', NEW.date_retour_reelle,
                           ' retard=', v_retard, 'j');

    INSERT INTO journal_action (table_cible, operation, cle, auteur, horodatage, details)
         VALUES ('emprunt', 'RETOUR', NEW.id, USER(), NOW(), v_details);
  END IF;
END$$

DELIMITER ;

UPDATE exemplaire ex
   SET ex.disponible = CASE
         WHEN EXISTS (SELECT 1
                        FROM emprunt em
                       WHERE em.exemplaire_id = ex.id
                         AND em.date_retour_reelle IS NULL)
         THEN 0 ELSE 1 END;

SELECT TRIGGER_NAME, ACTION_TIMING, EVENT_MANIPULATION, EVENT_OBJECT_TABLE
  FROM information_schema.TRIGGERS
 WHERE TRIGGER_SCHEMA = 'mediatheque'
 ORDER BY TRIGGER_NAME;
