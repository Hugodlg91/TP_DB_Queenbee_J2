-- tests_contournement.sql : essayer de contourner les droits (TP Jour 2, Lab 8, étape 8.6)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement SANS ON_ERROR_STOP (les refus sont voulus), en postgres :
--   psql -U postgres -d queenbee -f tests_contournement.sql
-- Rôles de notre base (voir roles.sql) : "a.diop" joue f.ba, "coord.casa"
-- joue coord.sn, "admin" joue admin.beeafrica.
-- Les UUID changent à chaque reconstruction de la base.

-- En postgres, on range d'abord les identifiants utiles (a.diop n'a pas le
-- droit de les lire)
RESET ROLE;
SELECT id AS ruche_autre FROM ruche WHERE code = 'SN-KOLD-011' \gset
SELECT id AS ma_ruche    FROM ruche WHERE code = 'SN-CASA-021' \gset
SELECT rc.id AS recolte_autre_site FROM recolte rc JOIN ruche r ON r.id = rc.ruche_id
WHERE r.code = 'CI-YAMO-002' AND rc.statut = 'declaree' \gset

SET ROLE "a.diop";
SELECT qui();

-- Test 1 · a.diop · lire apicultrice directement. Attendu : refusé
SELECT nom, telephone FROM apicultrice;
-- Obtenu : ERROR:  permission denied for table apicultrice  -> attendu

-- Test 2 · a.diop · lire v_mes_ruches. Attendu : ses ruches seulement
SELECT code, site_id FROM v_mes_ruches;
-- Obtenu :
--     code     | site_id
--  SN-CASA-021 | SN-CASA
-- (1 ligne)  -> attendu : sa seule ruche, aucune des 10 autres

-- Test 3 · a.diop · déclarer une récolte sur sa ruche, par v_mes_recoltes. Attendu : accepté
INSERT INTO v_mes_recoltes (ruche_id, date_recolte, quantite_kg)
VALUES (:'ma_ruche', DATE '2027-03-15', 7.50)
RETURNING id AS recolte_test3 \gset
-- Obtenu : INSERT 0 1  -> attendu (statut par défaut : declaree)

-- Test 4 · a.diop · déclarer une récolte sur la ruche d'une autre. Attendu : refusé (check option)
INSERT INTO v_mes_recoltes (ruche_id, date_recolte, quantite_kg)
VALUES (:'ruche_autre', DATE '2027-03-15', 50.00);
-- Obtenu : ERROR:  new row violates check option for view "v_mes_recoltes"  -> attendu

-- Test 5 · a.diop · déclarer une récolte directement « validee ». Attendu : refusé
INSERT INTO v_mes_recoltes (ruche_id, date_recolte, quantite_kg, statut)
VALUES (:'ma_ruche', DATE '2027-03-15', 7.50, 'validee');
-- Obtenu : ERROR:  permission denied for view v_mes_recoltes  -> attendu
-- (INSERT n'est accordé que sur ruche_id, date_recolte et quantite_kg : la colonne statut est interdite)

-- Test 6 · a.diop · UPDATE recolte SET quantite_kg = 99. Attendu : refusé
UPDATE recolte SET quantite_kg = 99;
-- Obtenu : ERROR:  permission denied for table recolte  -> attendu

-- Test 7 · a.diop · appeler valider_recolte(...). Attendu : refusé
SELECT valider_recolte(:'recolte_test3');
-- Obtenu : ERROR:  permission denied for function valider_recolte  -> attendu

-- Test 8 · a.diop · écrire une fausse ligne dans journal_audit. Attendu : refusé
INSERT INTO journal_audit (acteur, table_cible, operation) VALUES ('coord.casa', 'recolte', 'UPDATE');
-- Obtenu : ERROR:  permission denied for table journal_audit  -> attendu

-- Test 9 · a.diop · désactiver le trigger d'audit. Attendu : refusé
ALTER TABLE recolte DISABLE TRIGGER recolte_audit;
-- Obtenu : ERROR:  must be owner of table recolte  -> attendu

RESET ROLE;
SET ROLE "coord.casa";

-- Test 10 · coord.casa · valider la récolte du test 3, puis la revalider. Attendu : accepté, puis refusé
SELECT valider_recolte(:'recolte_test3');
-- Obtenu : la fonction répond (une ligne vide) : récolte validée  -> attendu
SELECT valider_recolte(:'recolte_test3');
-- Obtenu : ERROR:  récolte introuvable, déjà traitée ou hors de votre site  -> attendu
SELECT ruche_code, quantite_kg, statut FROM v_recoltes_site ORDER BY ruche_code, date_recolte;
-- Obtenu :
--  ruche_code  | quantite_kg | statut
--  SN-CASA-014 |       14.00 | validee
--  SN-CASA-021 |        7.50 | validee
--  SN-CASA-099 |       25.00 | ecart
-- (3 lignes)  -> attendu : son site seulement (pas CI-YAMO-002)

-- Test 11 · coord.casa · valider une récolte d'un autre site (CI-YAMO-002). Attendu : refusé
SELECT valider_recolte(:'recolte_autre_site');
-- Obtenu : ERROR:  récolte introuvable, déjà traitée ou hors de votre site  -> attendu

RESET ROLE;
SET ROLE "admin";

-- Test 12 · admin · lire le journal ; supprimer un utilisateur. Attendu : lu ; refusé
SELECT acteur, table_cible, operation, apres ->> 'statut' AS statut
FROM journal_audit WHERE table_cible = 'recolte' ORDER BY id;
-- Obtenu :
--    acteur   | table_cible | operation |  statut
--  postgres   | recolte     | UPDATE    | validee     <- test de l'étape 8.3 (audit)
--  a.diop     | recolte     | INSERT    | declaree    <- test 3
--  coord.casa | recolte     | UPDATE    | validee     <- test 10
-- (3 lignes)  -> attendu : les VRAIS acteurs, même quand la validation passe
-- par valider_recolte(), exécutée avec les droits de postgres
DELETE FROM utilisateur WHERE login = 'm.ba';
-- Obtenu : ERROR:  permission denied for table utilisateur  -> attendu

RESET ROLE;

-- ---------------------------------------------------------------------------
-- Bilan : 12 tests, 12 résultats attendus, aucun « problème ».
-- Refus obtenus : permission denied (tests 1, 5, 6, 7, 8, 12), new row violates
-- check option (test 4), must be owner of table recolte (test 9), et le
-- message de valider_recolte (test 10, second appel, et test 11).
-- ---------------------------------------------------------------------------
