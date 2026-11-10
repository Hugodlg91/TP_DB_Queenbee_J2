-- requetes_j2.sql : les requêtes des labs 6 et 7, avec leurs résultats (TP Jour 2, Labs 6 et 7)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement SANS ON_ERROR_STOP (certains refus sont voulus), en postgres,
-- après toute la reconstruction du README :
--   psql -U postgres -d queenbee -f requetes_j2.sql
-- Ce fichier ne laisse RIEN dans la base : chaque écriture est faite dans une
-- transaction annulée (ROLLBACK), p1 et p2 sont des tables temporaires. On le
-- relance autant de fois qu'on veut. Le bilan du début et celui de la fin
-- doivent être identiques.
-- (Seul effet : le compteur d'identité de mesure.id avance d'un cran à chaque
--  lancement, à cause de l'INSERT annulé de l'étape 7.2. Ce n'est pas une donnée.)
--
-- Les résultats en commentaire ont été obtenus sur une base reconstruite
-- (PostgreSQL 16). Les poids sont tirés au hasard par volume.sql et le
-- pseudonyme dépend de la clé secrète : ces valeurs changent à chaque
-- reconstruction. Les temps aussi.

-- ===========================================================================
-- Bilan AVANT
-- ===========================================================================
SELECT (SELECT count(*) FROM mesure)             AS mesures,
       (SELECT count(*) FROM formation_plat)     AS plat,
       (SELECT count(*) FROM formateur)          AS formateurs,
       (SELECT count(*) FROM suivi_formation)    AS suivis,
       (SELECT count(*) FROM synthese_site_jour) AS synthese,
       (SELECT max(jour) FROM synthese_site_jour) AS dernier_jour,
       (SELECT count(*) FROM journal_audit)      AS journal,
       (SELECT string_agg(nom || ':' || theme, ', ' ORDER BY nom) FROM formateur) AS themes,
       to_regclass('suivi_formation_v2') IS NULL AS sans_v2,
       (SELECT string_agg(tgname::text || '=' || tgenabled::text, ', ' ORDER BY tgname)
          FROM pg_trigger WHERE tgname IN ('suivi_formation_df', 'formateur_theme_df')) AS triggers;
-- Obtenu (base reconstruite, après tests_audit.sql et tests_contournement.sql) :
--   48048 | 8 | 5 | 8 | 364 | 2027-03-14 | 4
--   | Ibrahima Fall:varroa, Khady Ndiaye:recolte, Kouassi Yao:varroa, Moussa Sarr:varroa, Oumar Diallo:capteurs
--   | t | formateur_theme_df=O, suivi_formation_df=O
-- (O : trigger actif)

-- ===========================================================================
-- Étape 6.1 · Les trois tests sur les données (GROUP BY ... HAVING)
-- ===========================================================================
-- (telephone, theme) -> formateur : un couple avec deux formateurs ?
SELECT telephone, theme, array_agg(formateur)
FROM formation_plat
GROUP BY telephone, theme
HAVING count(DISTINCT formateur) > 1;
-- Obtenu : (0 rows)

-- formateur -> theme : un formateur avec deux thèmes ?
SELECT formateur, array_agg(DISTINCT theme)
FROM formation_plat
GROUP BY formateur
HAVING count(DISTINCT theme) > 1;
-- Obtenu : (0 rows)

-- (telephone, formateur) est une clé : un doublon ?
SELECT telephone, formateur, count(*)
FROM formation_plat
GROUP BY telephone, formateur
HAVING count(*) > 1;
-- Obtenu : (0 rows)

-- L'anomalie : Moussa Sarr passe en capteurs sur UNE ligne (transaction annulée)
BEGIN;
UPDATE formation_plat SET theme = 'capteurs'
WHERE telephone = '+221 77 100 00 02' AND formateur = 'Moussa Sarr';
-- Obtenu : UPDATE 1 (aucun message)
SELECT formateur, array_agg(DISTINCT theme)
FROM formation_plat
GROUP BY formateur
HAVING count(DISTINCT theme) > 1;
-- Obtenu :
--   formateur  |     array_agg
-- -------------+-------------------
--  Moussa Sarr | {capteurs,varroa}
ROLLBACK;

-- ===========================================================================
-- Étape 6.2 · Le mauvais découpage : p1(telephone, theme) et p2(theme, formateur)
-- ===========================================================================
-- (tables temporaires : supprimées plus bas, et de toute façon en quittant psql)
CREATE TEMP TABLE p1 AS SELECT DISTINCT telephone, theme FROM formation_plat;
CREATE TEMP TABLE p2 AS SELECT DISTINCT theme, formateur FROM formation_plat;

SELECT count(*) FROM p1 JOIN p2 USING (theme);
-- Obtenu : 16 (au lieu de 8)

-- Les lignes inventées
SELECT telephone, theme, formateur FROM p1 JOIN p2 USING (theme)
EXCEPT
SELECT telephone, theme, formateur FROM formation_plat
ORDER BY telephone, formateur;
-- Obtenu (8 lignes inventées) :
--      telephone     | theme  |   formateur
-- -------------------+--------+---------------
--  +221 77 100 00 01 | varroa | Ibrahima Fall
--  +221 77 100 00 01 | varroa | Kouassi Yao
--  +221 77 100 00 02 | varroa | Ibrahima Fall
--  +221 77 100 00 02 | varroa | Kouassi Yao
--  +221 77 200 00 03 | varroa | Kouassi Yao
--  +221 77 200 00 03 | varroa | Moussa Sarr
--  +225 07 300 00 05 | varroa | Ibrahima Fall
--  +225 07 300 00 05 | varroa | Moussa Sarr
-- Awa Diop (+221 77 100 00 02) serait suivie par trois formateurs varroa.

DROP TABLE pg_temp.p1, pg_temp.p2;

-- Le bon découpage : double comparaison EXCEPT (rien de perdu, rien d'inventé)
(SELECT telephone, theme, formateur FROM formation_plat
 EXCEPT
 SELECT a.telephone, f.theme, f.nom
 FROM suivi_formation s
 JOIN apicultrice a ON a.id = s.apicultrice_id
 JOIN formateur f   ON f.id = s.formateur_id)
UNION ALL
(SELECT a.telephone, f.theme, f.nom
 FROM suivi_formation s
 JOIN apicultrice a ON a.id = s.apicultrice_id
 JOIN formateur f   ON f.id = s.formateur_id
 EXCEPT
 SELECT telephone, theme, formateur FROM formation_plat);
-- Obtenu : (0 rows)

-- ===========================================================================
-- Étape 6.3 · La règle perdue (trigger désactivé, transaction annulée)
-- ===========================================================================
BEGIN;
ALTER TABLE suivi_formation DISABLE TRIGGER suivi_formation_df;
-- Awa Diop (notre « Fatou Ba ») chez Ibrahima Fall (varroa), alors qu'elle a Moussa Sarr
INSERT INTO suivi_formation (apicultrice_id, formateur_id)
SELECT a.id, f.id FROM apicultrice a, formateur f
WHERE a.telephone = '+221 77 100 00 02' AND f.nom = 'Ibrahima Fall';
-- Obtenu : INSERT 0 1
SELECT a.nom, f.theme, array_agg(f.nom)
FROM suivi_formation s
JOIN apicultrice a ON a.id = s.apicultrice_id
JOIN formateur f   ON f.id = s.formateur_id
GROUP BY a.id, a.nom, f.theme
HAVING count(*) > 1;
-- Obtenu :
--    nom    | theme  |            array_agg
-- ----------+--------+---------------------------------
--  Awa Diop | varroa | {"Moussa Sarr","Ibrahima Fall"}
ROLLBACK;
-- (le ROLLBACK supprime la ligne fautive et réactive le trigger)

-- Les deux tests du trigger suivi_formation_df (une transaction chacun)
BEGIN;
INSERT INTO suivi_formation (apicultrice_id, formateur_id)
SELECT a.id, f.id FROM apicultrice a, formateur f
WHERE a.telephone = '+221 77 100 00 02' AND f.nom = 'Ibrahima Fall';
-- Obtenu : ERROR:  DF violée : cette apicultrice a déjà un formateur pour ce thème
ROLLBACK;

BEGIN;
INSERT INTO suivi_formation (apicultrice_id, formateur_id)
SELECT a.id, f.id FROM apicultrice a, formateur f
WHERE a.telephone = '+221 77 100 00 02' AND f.nom = 'Khady Ndiaye';
-- Obtenu : INSERT 0 1 (récolte : thème nouveau pour elle)
ROLLBACK;

-- Remplacer Moussa Sarr par Ibrahima Fall (même thème) pour Awa Diop : un
-- changement légitime (elle garde UN formateur varroa).
BEGIN;
UPDATE suivi_formation SET formateur_id = (SELECT id FROM formateur WHERE nom = 'Ibrahima Fall')
WHERE apicultrice_id = (SELECT id FROM apicultrice WHERE telephone = '+221 77 100 00 02')
  AND formateur_id   = (SELECT id FROM formateur WHERE nom = 'Moussa Sarr');
-- Obtenu après la reconstruction complète (fonction de corrections.sql, qui
-- exclut la ligne modifiée) : UPDATE 1
-- Obtenu avec la fonction de formation.sql (modèle GreenFarm, avant
-- corrections.sql, ou si formation.sql est relancé après) :
--   ERROR:  DF violée : cette apicultrice a déjà un formateur pour ce thème
-- Refus à tort : l'ancienne version de la ligne (Awa Diop, Moussa Sarr) est
-- encore visible, et son formateur est bien différent du nouveau. La condition
-- s.formateur_id <> NEW.formateur_id ne l'exclut donc pas.
ROLLBACK;

-- La règle contournée par la table formateur (trigger formateur_theme_df
-- désactivé, transaction annulée) : Khady Ndiaye passe en varroa
BEGIN;
ALTER TABLE formateur DISABLE TRIGGER formateur_theme_df;
UPDATE formateur SET theme = 'varroa' WHERE nom = 'Khady Ndiaye';
-- Obtenu : UPDATE 1
SELECT a.nom, a.telephone, f.theme, array_agg(f.nom ORDER BY f.nom)
FROM suivi_formation s
JOIN apicultrice a ON a.id = s.apicultrice_id
JOIN formateur f   ON f.id = s.formateur_id
GROUP BY a.id, a.nom, a.telephone, f.theme
HAVING count(*) > 1;
-- Obtenu :
--      nom      |     telephone     | theme  |           array_agg
-- --------------+-------------------+--------+--------------------------------
--  Aminata Diop | +221 77 100 00 01 | varroa | {"Khady Ndiaye","Moussa Sarr"}
-- Aminata Diop (SN-CASA) a deux formateurs varroa, sans aucun message.
ROLLBACK;

-- Les deux tests du trigger formateur_theme_df
BEGIN;
UPDATE formateur SET theme = 'varroa' WHERE nom = 'Khady Ndiaye';
-- Obtenu : ERROR:  DF violée : Khady Ndiaye ne peut pas passer en varroa, une de ses apicultrices a déjà un formateur pour ce thème
ROLLBACK;

BEGIN;
UPDATE formateur SET theme = 'capteurs' WHERE nom = 'Kouassi Yao';
-- Obtenu : UPDATE 1 (Adjoua Kouassi n'a pas d'autre formateur capteurs)
ROLLBACK;

-- ===========================================================================
-- Étape 6.3 · Pour aller plus loin : suivi_formation_v2, la règle portée par
-- des contraintes (DDL dans une transaction annulée)
-- ===========================================================================
BEGIN;
ALTER TABLE formateur ADD CONSTRAINT formateur_id_theme_uq UNIQUE (id, theme);
CREATE TABLE suivi_formation_v2 (
  apicultrice_id uuid NOT NULL REFERENCES apicultrice (id),
  formateur_id   uuid NOT NULL,
  theme          text NOT NULL,                       -- copie contrôlée du thème
  PRIMARY KEY (apicultrice_id, formateur_id),
  UNIQUE (apicultrice_id, theme),                     -- un formateur par thème
  FOREIGN KEY (formateur_id, theme) REFERENCES formateur (id, theme)
);
INSERT INTO suivi_formation_v2
SELECT s.apicultrice_id, s.formateur_id, f.theme
FROM suivi_formation s JOIN formateur f ON f.id = s.formateur_id;
-- Obtenu : INSERT 0 8

SAVEPOINT avant_tests;
-- Awa Diop + Ibrahima Fall (varroa) : elle a déjà Moussa Sarr en varroa
INSERT INTO suivi_formation_v2
SELECT a.id, f.id, f.theme FROM apicultrice a, formateur f
WHERE a.telephone = '+221 77 100 00 02' AND f.nom = 'Ibrahima Fall';
-- Obtenu : ERROR:  duplicate key value violates unique constraint "suivi_formation_v2_apicultrice_id_theme_key"
ROLLBACK TO SAVEPOINT avant_tests;

-- Moussa Sarr déclaré « capteurs » pour tricher sur le thème (Mariama Ba,
-- qui n'a aucun suivi : ni la clé primaire ni l'UNIQUE ne gênent)
INSERT INTO suivi_formation_v2
SELECT a.id, f.id, 'capteurs' FROM apicultrice a, formateur f
WHERE a.telephone = '+221 77 200 00 04' AND f.nom = 'Moussa Sarr';
-- Obtenu : ERROR:  insert or update on table "suivi_formation_v2" violates foreign key constraint "suivi_formation_v2_formateur_id_theme_fkey"
ROLLBACK TO SAVEPOINT avant_tests;

-- Le contournement par la table formateur, sans le trigger formateur_theme_df :
-- la clé étrangère composée le refuse toute seule
ALTER TABLE formateur DISABLE TRIGGER formateur_theme_df;
UPDATE formateur SET theme = 'varroa' WHERE nom = 'Khady Ndiaye';
-- Obtenu : ERROR:  update or delete on table "formateur" violates foreign key constraint "suivi_formation_v2_formateur_id_theme_fkey" on table "suivi_formation_v2"
-- (DETAIL : la clé (id, recolte) de Khady Ndiaye est encore référencée)
ROLLBACK TO SAVEPOINT avant_tests;
ROLLBACK;
-- (la table v2 et la contrainte formateur_id_theme_uq disparaissent)

-- ===========================================================================
-- Étape 6.4 · Le site de l'apicultrice et le site de ses ruches
-- ===========================================================================
SELECT a.nom, a.site_id AS site_apicultrice, array_agg(DISTINCT r.site_id) AS sites_ruches
FROM apicultrice a
JOIN ruche r ON r.apicultrice_id = a.id
GROUP BY a.id, a.nom, a.site_id
ORDER BY a.site_id, a.nom;
-- Obtenu :
--       nom       | site_apicultrice | sites_ruches
-- ----------------+------------------+--------------
--  Adjoua Kouassi | CI-YAMO          | {CI-YAMO}
--  Aya Kone       | CI-YAMO          | {CI-YAMO}
--  Brigitte Ngono | CM-BAFO          | {CM-BAFO}
--  Esther Fotso   | CM-BAFO          | {CM-BAFO}
--  Aminata Diop   | SN-CASA          | {SN-CASA}
--  Awa Diop       | SN-CASA          | {SN-CASA}
--  Aminata Diop   | SN-KOLD          | {SN-KOLD}
--  Mariama Ba     | SN-KOLD          | {SN-KOLD}
-- (8 rows)

-- La copie utilisateur.site_id : un compte apicultrice rattaché à un autre
-- site que son apicultrice ?
SELECT u.login, u.site_id AS site_compte, a.site_id AS site_apicultrice
FROM utilisateur u
JOIN apicultrice a ON a.id = u.apicultrice_id
WHERE u.site_id IS DISTINCT FROM a.site_id;
-- Obtenu : (0 rows). Cohérent aujourd'hui, mais rien ne l'impose
-- (voir normalisation_j2.md, étape 6.4).

-- ===========================================================================
-- Étape 7.1 · Le tableau de bord du gestionnaire (UC-G01) sur les mesures brutes
-- Même découpage des jours que la synthèse : AT TIME ZONE 'UTC'.
-- ===========================================================================
SELECT count(*) FROM mesure;
-- Obtenu : 48048 (47 520 de volume.sql + 528 de donnees.sql)

SELECT (m.horodatage AT TIME ZONE 'UTC')::date AS jour,
       count(*)                  AS nb_mesures,
       round(avg(m.poids_kg), 2) AS poids_moyen,
       min(m.poids_kg)           AS poids_min,
       min(m.batterie_pct)       AS batterie_min
FROM mesure m
JOIN ruche r ON r.id = m.ruche_id
WHERE r.site_id = 'SN-CASA'
GROUP BY 1
ORDER BY jour DESC
LIMIT 3;
-- Obtenu (base reconstruite ; les poids changent à chaque reconstruction) :
--     jour    | nb_mesures | poids_moyen | poids_min | batterie_min
-- ------------+------------+-------------+-----------+--------------
--  2027-03-14 |        144 |       37.49 |     30.06 |           73
--  2027-03-13 |        144 |       32.31 |     30.01 |           90
--  2027-03-12 |        144 |       32.44 |     30.03 |           90

EXPLAIN ANALYZE
SELECT (m.horodatage AT TIME ZONE 'UTC')::date AS jour,
       count(*)                  AS nb_mesures,
       round(avg(m.poids_kg), 2) AS poids_moyen,
       min(m.poids_kg)           AS poids_min,
       min(m.batterie_pct)       AS batterie_min
FROM mesure m
JOIN ruche r ON r.id = m.ruche_id
WHERE r.site_id = 'SN-CASA'
GROUP BY 1
ORDER BY jour DESC
LIMIT 3;
-- Obtenu (lignes principales) :
--   ->  Seq Scan on mesure m  (...) (actual time=0.006..4.094 rows=48048 loops=1)
--   Execution Time: 11.396 ms
-- Toute la table mesure est lue, puis jointe, triée et regroupée.

-- ===========================================================================
-- Étape 7.2 · La même lecture dans la synthèse
-- ===========================================================================
SELECT jour, nb_mesures, poids_moyen, poids_min, batterie_min
FROM synthese_site_jour
WHERE site_id = 'SN-CASA'
ORDER BY jour DESC
LIMIT 3;
-- Obtenu : les mêmes chiffres qu'en 7.1

EXPLAIN ANALYZE
SELECT jour, nb_mesures, poids_moyen, poids_min, batterie_min
FROM synthese_site_jour
WHERE site_id = 'SN-CASA'
ORDER BY jour DESC
LIMIT 3;
-- Obtenu (lignes principales) :
--   ->  Bitmap Index Scan on synthese_site_jour_pk  (...) (actual time=0.006..0.006 rows=91 loops=1)
--   Execution Time: 0.039 ms
-- Au lancement suivant (l'autovacuum avait calculé les statistiques de la vue) :
--   ->  Index Scan Backward using synthese_site_jour_pk on synthese_site_jour  (...)
--   Execution Time: 0.011 ms
-- Le plan change avec les statistiques, mais c'est toujours l'index unique de
-- la synthèse : la table mesure n'est plus lue.

-- Le vol : le 15 mars à 6 h, SN-CASA-014 (notre SN-CASA-011) tombe à 8,4 kg.
-- Tout est dans une transaction annulée : la mesure et le rafraîchissement
-- disparaissent au ROLLBACK. Avec PostgreSQL 16, REFRESH ... CONCURRENTLY
-- passe dans un bloc BEGIN (c'est CREATE INDEX CONCURRENTLY qui est interdit).
BEGIN;
INSERT INTO mesure (ruche_id, horodatage, poids_kg, temp_int_c, batterie_pct, latitude, longitude)
SELECT id, TIMESTAMPTZ '2027-03-15 06:00:00+00', 8.40, 34.0, 90, latitude, longitude
FROM ruche WHERE code = 'SN-CASA-014';
-- Obtenu : INSERT 0 1

SELECT jour, nb_mesures, poids_moyen, poids_min, batterie_min
FROM synthese_site_jour WHERE site_id = 'SN-CASA' ORDER BY jour DESC LIMIT 2;
-- Obtenu : la synthèse s'arrête au 14 mars, rien d'anormal
--     jour    | nb_mesures | poids_moyen | poids_min | batterie_min
-- ------------+------------+-------------+-----------+--------------
--  2027-03-14 |        144 |       37.49 |     30.06 |           73
--  2027-03-13 |        144 |       32.31 |     30.01 |           90

REFRESH MATERIALIZED VIEW CONCURRENTLY synthese_site_jour;
-- Obtenu : REFRESH MATERIALIZED VIEW

SELECT jour, nb_mesures, poids_moyen, poids_min, batterie_min
FROM synthese_site_jour WHERE site_id = 'SN-CASA' ORDER BY jour DESC LIMIT 2;
-- Obtenu : le 15 mars apparaît, avec poids_min = 8.40
--     jour    | nb_mesures | poids_moyen | poids_min | batterie_min
-- ------------+------------+-------------+-----------+--------------
--  2027-03-15 |          1 |        8.40 |      8.40 |           90
--  2027-03-14 |        144 |       37.49 |     30.06 |           73
ROLLBACK;
-- (la mesure du vol et le rafraîchissement sont annulés : la synthèse
--  s'arrête de nouveau au 14 mars)

-- ===========================================================================
-- Étape 7.3 · Casser un haché simple (sha256 du téléphone, sans clé)
-- ===========================================================================
SELECT encode(sha256(convert_to(telephone, 'UTF8')), 'hex') AS hache
FROM apicultrice WHERE telephone = '+221 77 100 00 02';
-- Obtenu : ef9a4fc1992b103c9ba32f3987851d1e17d7c95031fb7423593b37b274f83051

\timing on
-- Le million de numéros qui commencent par +221 77 1 (format « +221 77 1xx xx xx »)
SELECT candidat
FROM (SELECT '+221 77 1' || substr(c, 1, 2) || ' ' || substr(c, 3, 2) || ' ' || substr(c, 5, 2) AS candidat
      FROM (SELECT lpad(n::text, 6, '0') AS c FROM generate_series(0, 999999) AS n) AS chiffres) AS numeros
WHERE encode(sha256(convert_to(candidat, 'UTF8')), 'hex') = 'ef9a4fc1992b103c9ba32f3987851d1e17d7c95031fb7423593b37b274f83051';
-- Obtenu : +221 77 100 00 02, Time: 1314.089 ms (1 557 ms sur notre base de travail)
\timing off

-- La clé secrète n'est pas écrite dans la définition de la vue
SELECT position((SELECT cle FROM cle_pseudonymisation) IN pg_get_viewdef('v_export_bailleur')) > 0 AS cle_dans_la_vue;
-- Obtenu : f

-- L'export lui-même
SELECT * FROM v_export_bailleur ORDER BY site, nb_ruches;
-- Obtenu : 8 lignes pour 11 ruches, sans nom ni téléphone (pseudonymes
-- propres à chaque clé), par exemple pour SN-CASA :
--  9df00b5e2025 | Sénégal | SN-CASA | 12.6 | -16.3 | 2 | 14.00
-- 14.00 et non 12.40 : tests_audit.sql (lab 8) a modifié cette récolte.

-- ===========================================================================
-- Bilan APRÈS : identique au bilan AVANT
-- ===========================================================================
SELECT (SELECT count(*) FROM mesure)             AS mesures,
       (SELECT count(*) FROM formation_plat)     AS plat,
       (SELECT count(*) FROM formateur)          AS formateurs,
       (SELECT count(*) FROM suivi_formation)    AS suivis,
       (SELECT count(*) FROM synthese_site_jour) AS synthese,
       (SELECT max(jour) FROM synthese_site_jour) AS dernier_jour,
       (SELECT count(*) FROM journal_audit)      AS journal,
       (SELECT string_agg(nom || ':' || theme, ', ' ORDER BY nom) FROM formateur) AS themes,
       to_regclass('suivi_formation_v2') IS NULL AS sans_v2,
       (SELECT string_agg(tgname::text || '=' || tgenabled::text, ', ' ORDER BY tgname)
          FROM pg_trigger WHERE tgname IN ('suivi_formation_df', 'formateur_theme_df')) AS triggers;
-- Obtenu : le même bilan qu'au début
