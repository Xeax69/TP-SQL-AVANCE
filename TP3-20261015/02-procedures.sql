USE mediatheque;

DROP PROCEDURE IF EXISTS p_emprunter;
DROP PROCEDURE IF EXISTS p_rendre;
DROP PROCEDURE IF EXISTS p_bilan_adherent;

DELIMITER $$

CREATE PROCEDURE p_emprunter(
  IN  p_code_barre  VARCHAR(20),
  IN  p_adherent_id INT UNSIGNED,
  OUT p_emprunt_id  INT UNSIGNED
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_actif          TINYINT(1)   DEFAULT NULL;
  DECLARE v_exemplaire_id  INT UNSIGNED DEFAULT NULL;
  DECLARE v_disponible     TINYINT(1)   DEFAULT NULL;
  DECLARE v_etat           VARCHAR(20)  DEFAULT NULL;
  DECLARE v_nb_en_cours    INT          DEFAULT 0;
  DECLARE v_penalites      DECIMAL(8,2) DEFAULT 0.00;
  DECLARE v_message        VARCHAR(255) DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SET p_emprunt_id = NULL;

  START TRANSACTION;

  SELECT actif
    INTO v_actif
    FROM adherent
   WHERE id = p_adherent_id;

  IF v_actif IS NULL THEN
    SET v_message = CONCAT('Aucun adhérent ne porte le numéro ', p_adherent_id, '.');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
  END IF;

  IF v_actif = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'L''inscription de cet adhérent n''est plus active : aucun prêt n''est possible.';
  END IF;

  SELECT id, disponible, etat
    INTO v_exemplaire_id, v_disponible, v_etat
    FROM exemplaire
   WHERE code_barre = p_code_barre
   FOR UPDATE;

  IF v_exemplaire_id IS NULL THEN
    SET v_message = CONCAT('Aucun exemplaire ne porte le code-barres ', p_code_barre, '.');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
  END IF;

  IF v_etat = 'hors_service' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cet exemplaire est hors service : il ne peut pas être emprunté.';
  END IF;

  IF v_disponible = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cet exemplaire est déjà emprunté : il n''est pas disponible.';
  END IF;

  SET v_nb_en_cours = f_nb_emprunts_en_cours(p_adherent_id);

  IF v_nb_en_cours >= 5 THEN
    SET v_message = CONCAT('Cet adhérent a déjà ', v_nb_en_cours,
                           ' documents en cours : la limite est de 5.');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
  END IF;

  SET v_penalites = f_penalites_dues(p_adherent_id);

  IF v_penalites > 10 THEN
    SET v_message = CONCAT('Cet adhérent doit ', FORMAT(v_penalites, 2),
                           ' € de pénalités : le prêt est bloqué au-delà de 10,00 €.');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
  END IF;

  INSERT INTO emprunt (exemplaire_id, adherent_id, date_emprunt, date_retour_prevue)
       VALUES (v_exemplaire_id, p_adherent_id, NULL, NULL);

  SET p_emprunt_id = LAST_INSERT_ID();

  COMMIT;
END$$

CREATE PROCEDURE p_rendre(IN p_code_barre VARCHAR(20))
MODIFIES SQL DATA
BEGIN
  DECLARE v_emprunt_id  INT UNSIGNED DEFAULT NULL;
  DECLARE v_adherent_id INT UNSIGNED DEFAULT NULL;
  DECLARE v_retard      INT          DEFAULT 0;
  DECLARE v_montant     DECIMAL(6,2) DEFAULT 0.00;
  DECLARE v_motif       VARCHAR(120) DEFAULT NULL;
  DECLARE v_message     VARCHAR(255) DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT em.id, em.adherent_id
    INTO v_emprunt_id, v_adherent_id
    FROM emprunt em
    JOIN exemplaire ex ON ex.id = em.exemplaire_id
   WHERE ex.code_barre = p_code_barre
     AND em.date_retour_reelle IS NULL
   ORDER BY em.date_emprunt DESC
   LIMIT 1
   FOR UPDATE;

  IF v_emprunt_id IS NULL THEN
    SET v_message = CONCAT('Aucun emprunt en cours pour le code-barres ', p_code_barre, '.');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
  END IF;

  UPDATE emprunt
     SET date_retour_reelle = CURDATE()
   WHERE id = v_emprunt_id;

  SET v_retard = f_jours_de_retard(v_emprunt_id);

  IF v_retard > 0 THEN
    SET v_montant = v_retard * 0.20;
    SET v_motif   = CONCAT('Retour avec ', v_retard, ' jour(s) de retard');

    INSERT INTO penalite (adherent_id, emprunt_id, montant, motif, date_creation, payee)
         VALUES (v_adherent_id, v_emprunt_id, v_montant, v_motif, CURDATE(), 0);
  END IF;

  COMMIT;

  SELECT v_emprunt_id AS emprunt_id,
         v_retard     AS jours_de_retard,
         v_montant    AS montant_facture;
END$$

CREATE PROCEDURE p_bilan_adherent(IN p_adherent_id INT UNSIGNED)
READS SQL DATA
BEGIN
  DECLARE v_existe  INT          DEFAULT 0;
  DECLARE v_message VARCHAR(255) DEFAULT NULL;

  SELECT COUNT(*)
    INTO v_existe
    FROM adherent
   WHERE id = p_adherent_id;

  IF v_existe = 0 THEN
    SET v_message = CONCAT('Aucun adhérent ne porte le numéro ', p_adherent_id, '.');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
  END IF;

  SELECT a.id,
         a.nom,
         a.prenom,
         a.ville,
         a.date_inscription,
         a.actif,
         f_nb_emprunts_en_cours(a.id) AS emprunts_en_cours,
         f_penalites_dues(a.id)       AS penalites_dues
    FROM adherent a
   WHERE a.id = p_adherent_id;

  SELECT em.id AS emprunt_id,
         ex.code_barre,
         o.titre,
         o.auteur,
         em.date_emprunt,
         em.date_retour_prevue,
         f_jours_de_retard(em.id) AS jours_de_retard
    FROM emprunt em
    JOIN exemplaire ex ON ex.id = em.exemplaire_id
    JOIN ouvrage    o  ON o.id  = ex.ouvrage_id
   WHERE em.adherent_id = p_adherent_id
     AND em.date_retour_reelle IS NULL
   ORDER BY em.date_retour_prevue, em.id;

  SELECT COUNT(*)                                            AS emprunts_depuis_inscription,
         SUM(em.date_retour_reelle IS NULL)                   AS dont_en_cours,
         MIN(em.date_emprunt)                                 AS premier_emprunt,
         MAX(em.date_emprunt)                                 AS dernier_emprunt
    FROM emprunt em
   WHERE em.adherent_id = p_adherent_id;
END$$

DELIMITER ;
