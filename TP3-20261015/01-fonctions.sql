USE mediatheque;

DROP FUNCTION IF EXISTS f_nb_emprunts_en_cours;
DROP FUNCTION IF EXISTS f_penalites_dues;
DROP FUNCTION IF EXISTS f_jours_de_retard;

DELIMITER $$

CREATE FUNCTION f_nb_emprunts_en_cours(p_adherent_id INT UNSIGNED)
RETURNS INT
READS SQL DATA
BEGIN
  DECLARE v_nb INT DEFAULT 0;

  SELECT COUNT(*)
    INTO v_nb
    FROM emprunt
   WHERE adherent_id = p_adherent_id
     AND date_retour_reelle IS NULL;

  RETURN v_nb;
END$$

CREATE FUNCTION f_penalites_dues(p_adherent_id INT UNSIGNED)
RETURNS DECIMAL(8,2)
READS SQL DATA
BEGIN
  DECLARE v_total DECIMAL(8,2) DEFAULT 0.00;

  SELECT COALESCE(SUM(montant), 0.00)
    INTO v_total
    FROM penalite
   WHERE adherent_id = p_adherent_id
     AND payee = 0;

  RETURN COALESCE(v_total, 0.00);
END$$

CREATE FUNCTION f_jours_de_retard(p_emprunt_id INT UNSIGNED)
RETURNS INT
READS SQL DATA
BEGIN
  DECLARE v_prevue    DATE DEFAULT NULL;
  DECLARE v_reelle    DATE DEFAULT NULL;
  DECLARE v_reference DATE DEFAULT NULL;

  SELECT date_retour_prevue, date_retour_reelle
    INTO v_prevue, v_reelle
    FROM emprunt
   WHERE id = p_emprunt_id;

  IF v_prevue IS NULL THEN
    RETURN 0;
  END IF;

  SET v_reference = COALESCE(v_reelle, CURDATE());

  IF v_reference <= v_prevue THEN
    RETURN 0;
  END IF;

  RETURN DATEDIFF(v_reference, v_prevue);
END$$

DELIMITER ;

SELECT a.id,
       a.nom,
       a.prenom,
       a.actif,
       f_nb_emprunts_en_cours(a.id) AS emprunts_en_cours,
       f_penalites_dues(a.id)       AS penalites_dues
  FROM adherent a
 WHERE f_nb_emprunts_en_cours(a.id) > 0
 ORDER BY emprunts_en_cours DESC, penalites_dues DESC, a.id;
