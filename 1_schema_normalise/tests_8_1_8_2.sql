-- tests_8_1_8_2.sql : tests des étapes 8.1 (suppression) et 8.2 (valeurs impossibles)
-- TP Jour 2, Lab 8 · Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement SANS ON_ERROR_STOP (les refus sont voulus), en postgres, après toute la
-- reconstruction du README (le test 9 utilise a.diop et v_mes_recoltes de roles.sql) :
--   psql -U postgres -d queenbee -f tests_8_1_8_2.sql
-- Ne laisse rien dans la base : une commande refusée n'écrit rien, et le test
-- CASCADE est annulé par ROLLBACK. Le fichier se relance autant de fois qu'on veut.
--
-- Adaptations à notre jeu d'essai :
--   CI-MAN-012 de l'énoncé -> SN-KOLD-012 : une ruche qui n'a que des mesures
--   (aucune récolte, alerte ni inspection), pour que seule mesure_ruche_fk réponde.
--   Statut d'alerte : nos statuts sont ouverte, en_cours, fermee (pas de
--   « traitee ») ; la commande de l'énoncé ne touche donc aucune ligne chez nous.

-- ===========================================================================
-- Étape 8.1 · Que se passe-t-il quand on supprime ?
-- ===========================================================================

-- Test 1 · supprimer une ruche qui a des mesures. Attendu : refus par mesure_ruche_fk
DELETE FROM ruche WHERE code = 'SN-KOLD-012';
-- Obtenu : ERROR:  update or delete on table "ruche" violates foreign key constraint
--          "mesure_ruche_fk" on table "mesure"
--          DETAIL:  Key (id)=(...) is still referenced from table "mesure".  -> attendu

-- Test 2 · la même suppression avec CASCADE, dans une transaction annulée.
-- Attendu : DELETE 1 et 4 368 mesures de moins, sans un mot ; après le ROLLBACK, tout revient.
BEGIN;
ALTER TABLE mesure
  DROP CONSTRAINT mesure_ruche_fk,
  ADD  CONSTRAINT mesure_ruche_fk FOREIGN KEY (ruche_id)
       REFERENCES ruche (id) ON DELETE CASCADE;
SELECT count(*) AS mesures_avant FROM mesure;
DELETE FROM ruche WHERE code = 'SN-KOLD-012';
SELECT count(*) AS mesures_apres FROM mesure;
ROLLBACK;
SELECT count(*) AS mesures_apres_rollback FROM mesure;
SELECT conname, confdeltype FROM pg_constraint WHERE conname = 'mesure_ruche_fk';
-- Obtenu : ALTER TABLE ; mesures_avant = 48048 ; DELETE 1 ; mesures_apres = 43680
-- (4 368 mesures de moins, sans un mot) ; ROLLBACK ; mesures_apres_rollback = 48048 ;
-- mesure_ruche_fk | r (RESTRICT, la clé de references.sql est revenue)  -> attendu

-- ===========================================================================
-- Étape 8.2 · Refuser les valeurs impossibles
-- ===========================================================================

-- Test 3 · une mesure avec batterie_pct = 150. Attendu : refus par mesure_batterie_0_100
INSERT INTO mesure (ruche_id, horodatage, batterie_pct)
SELECT id, TIMESTAMPTZ '2027-03-20 12:00:00+00', 150 FROM ruche WHERE code = 'SN-CASA-021';
-- Obtenu : ERROR:  new row for relation "mesure" violates check constraint "mesure_batterie_0_100"  -> attendu

-- Test 4 · un statut d'alerte invalide.
-- La commande de l'énoncé ne touche aucune ligne chez nous : elle ne prouve rien.
UPDATE alerte SET statut = 'fermée' WHERE statut = 'traitee';
-- Obtenu : UPDATE 0  (aucune alerte « traitee » : pas un test)
-- Même valeur invalide, sur des lignes qui existent. Attendu : refus par alerte_statut_valide
UPDATE alerte SET statut = 'fermée' WHERE statut = 'ouverte';
-- Obtenu : ERROR:  new row for relation "alerte" violates check constraint "alerte_statut_valide"
--          (la ligne refusée : essaimage, ..., fermée)  -> attendu

-- ===========================================================================
-- Ajout de la revue (constat R5 de rapport_revue.md) : récoltes impossibles
-- ===========================================================================
SELECT id AS ma_ruche FROM ruche WHERE code = 'SN-CASA-021' \gset

-- Test 5 · une récolte de 'NaN' kg. Attendu : refus par recolte_quantite_plausible
INSERT INTO recolte (ruche_id, date_recolte, quantite_kg)
VALUES (:'ma_ruche', DATE '2027-03-15', 'NaN');
-- Obtenu : ERROR:  new row for relation "recolte" violates check constraint "recolte_quantite_plausible"  -> attendu
-- (avant la revue : INSERT 0 1, recolte_quantite_positive laissait passer NaN)

-- Test 6 · une récolte de 'infinity' kg. Attendu : refus (par le type numeric(6,2))
INSERT INTO recolte (ruche_id, date_recolte, quantite_kg)
VALUES (:'ma_ruche', DATE '2027-03-15', 'infinity');
-- Obtenu : ERROR:  numeric field overflow
--          DETAIL:  A field with precision 6, scale 2 cannot hold an infinite value.  -> attendu

-- Test 7 · une récolte de 9 999,99 kg. Attendu : refus par recolte_quantite_plausible
INSERT INTO recolte (ruche_id, date_recolte, quantite_kg)
VALUES (:'ma_ruche', DATE '2027-03-15', 9999.99);
-- Obtenu : ERROR:  new row for relation "recolte" violates check constraint "recolte_quantite_plausible"  -> attendu

-- Test 8 · des dates absurdes (an 3027, puis 'infinity'). Attendu : refus par recolte_date_plausible
INSERT INTO recolte (ruche_id, date_recolte, quantite_kg)
VALUES (:'ma_ruche', DATE '3027-03-15', 7.50);
INSERT INTO recolte (ruche_id, date_recolte, quantite_kg)
VALUES (:'ma_ruche', 'infinity', 7.50);
-- Obtenu, deux fois : ERROR:  new row for relation "recolte" violates check constraint
--          "recolte_date_plausible"  -> attendu

-- Test 9 · l'apicultrice déclare 'NaN' kg par sa vue. Attendu : refus
SET ROLE "a.diop";
INSERT INTO v_mes_recoltes (ruche_id, date_recolte, quantite_kg)
VALUES (:'ma_ruche', DATE '2027-03-15', 'NaN');
RESET ROLE;
-- Obtenu : ERROR:  new row for relation "recolte" violates check constraint "recolte_quantite_plausible"  -> attendu

-- Test 10 · aucune ligne existante ne viole les nouvelles règles, et rien n'a été ajouté
SELECT count(*) AS recoltes,
       count(*) FILTER (WHERE NOT (quantite_kg > 0 AND quantite_kg <= 200
                        AND date_recolte BETWEEN DATE '2020-01-01' AND DATE '2100-01-01')) AS hors_regles
FROM recolte;
-- Obtenu :
--  recoltes | hors_regles
--         4 |           0
-- (1 ligne)  -> attendu : hors_regles = 0. Les 4 récoltes sont les 3 du jour 1 et
-- celle du test 3 de tests_contournement.sql (3 si ce fichier n'a pas encore été lancé).
