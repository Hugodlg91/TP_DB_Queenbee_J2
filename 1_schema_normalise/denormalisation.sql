-- denormalisation.sql : synthèse, export pseudonymisé, journal d'audit (TP Jour 2, Lab 7)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement (après volume.sql) :
--   psql -U postgres -d queenbee -v ON_ERROR_STOP=1 -f denormalisation.sql
-- Le fichier se relance sans perte :
--   - la vue matérialisée et la vue d'export sont recréées ;
--   - la clé de pseudonymisation n'est créée qu'une fois (sinon tous les
--     pseudonymes changeraient à chaque relance, et les exports ne se
--     recouperaient plus d'une fois sur l'autre) ;
--   - le journal d'audit n'est JAMAIS supprimé (CREATE TABLE IF NOT EXISTS) :
--     le modèle de l'énoncé commence par DROP TABLE journal_audit, ce qui
--     effacerait toute la preuve à chaque relance, une fois le lab 8 en place.
-- Attention : les deux vues recréées perdent leurs droits. Si roles.sql a déjà
-- été lancé, relancez-le ensuite (le gestionnaire perdrait sinon la synthèse
-- et l'export).

-- ===========================================================================
-- 7.2 · La synthèse : une copie voulue, pour aller vite
-- Son prix : elle est en retard jusqu'au prochain REFRESH.
-- ===========================================================================
DROP MATERIALIZED VIEW IF EXISTS synthese_site_jour;

CREATE MATERIALIZED VIEW synthese_site_jour AS
SELECT r.site_id,
       (m.horodatage AT TIME ZONE 'UTC')::date AS jour,
       count(*)                  AS nb_mesures,
       round(avg(m.poids_kg), 2) AS poids_moyen,
       min(m.poids_kg)           AS poids_min,
       min(m.batterie_pct)       AS batterie_min
FROM mesure m
JOIN ruche r ON r.id = m.ruche_id
GROUP BY r.site_id, (m.horodatage AT TIME ZONE 'UTC')::date;

-- Index unique : lecture directe, et REFRESH ... CONCURRENTLY possible
-- (rafraîchir sans bloquer les lecteurs du tableau de bord)
CREATE UNIQUE INDEX synthese_site_jour_pk ON synthese_site_jour (site_id, jour);

-- Qui rafraîchit, et quand ? Rien ne le fait tout seul : PostgreSQL ne
-- rafraîchit jamais une vue matérialisée de lui-même. On prévoit un
-- rafraîchissement chaque nuit à 2 h (UTC), au choix :
--   - avec l'extension pg_cron (à installer, à lancer en superutilisateur) :
--       SELECT cron.schedule_in_database('synthese-nuit', '0 2 * * *',
--              'REFRESH MATERIALIZED VIEW CONCURRENTLY synthese_site_jour', 'queenbee');
--   - ou un timer système (cron ou systemd) sur le serveur, qui lance :
--       psql -U postgres -d queenbee -c "REFRESH MATERIALIZED VIEW CONCURRENTLY synthese_site_jour"
-- Le coût : CONCURRENTLY ne lit pas seulement les nouvelles mesures. Il
-- recalcule toute l'agrégation sur TOUTE la table mesure, puis compare le
-- résultat à l'ancienne version pour n'écrire que les différences. Le temps
-- grandit donc avec l'historique complet (« historique complet », CDC § 7.2).
-- Si le volume explose, piste : une synthèse incrémentale (une vraie table,
-- mise à jour seulement pour les jours qui ont reçu des mesures).

-- ===========================================================================
-- 7.3 · L'export pour le bailleur : minimiser, puis pseudonymiser
-- ===========================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;          -- fournit hmac() et gen_random_bytes()

-- La clé secrète : une seule ligne, dans une table fermée à tous
CREATE TABLE IF NOT EXISTS cle_pseudonymisation (
  id   int PRIMARY KEY CHECK (id = 1),             -- une seule ligne
  cle  text NOT NULL
);
INSERT INTO cle_pseudonymisation VALUES (1, encode(gen_random_bytes(32), 'hex'))
ON CONFLICT (id) DO NOTHING;                      -- la clé ne change pas à la relance
REVOKE ALL ON cle_pseudonymisation FROM PUBLIC;

-- Une ligne par apicultrice et par emplacement arrondi (deux ruches voisines
-- d'une même apicultrice tombent dans la même case de 0,1 degré).
-- Retiré : nom, téléphone (identifient la personne), id et code de ruche
-- (permettent de recouper avec d'autres données), position précise (mène à
-- la ruche : vol), dates et détail des récoltes (inutiles au bailleur).
-- Gardé : nb_ruches, car le bailleur finance des ruches et suit leur nombre.
-- C'est un agrégat, mais sur un petit site, avec le site et la position
-- approchée, c'est un quasi-identifiant (sur SN-CASA, une seule apicultrice
-- a 2 ruches dans sa case : qui connaît le village la reconnaît). On
-- l'accepte en le sachant.
-- Pseudonyme stable d'un export à l'autre (la clé ne change pas) : voulu,
-- pour suivre une apicultrice dans le temps. Mais le bailleur peut lui aussi
-- la suivre d'un export à l'autre et recouper : c'est un choix, pas un oubli.
-- Pour l'empêcher, il faudrait changer de clé à chaque export.
DROP VIEW IF EXISTS v_export_bailleur;

CREATE VIEW v_export_bailleur AS
SELECT left(encode(hmac(r.apicultrice_id::text, k.cle, 'sha256'), 'hex'), 12) AS apicultrice_pseudo,
       s.pays,
       s.id                    AS site,
       round(r.latitude, 1)    AS latitude_approx,      -- 0,1 degré, environ 11 km
       round(r.longitude, 1)   AS longitude_approx,
       count(DISTINCT r.id)    AS nb_ruches,
       coalesce(sum(rc.quantite_kg) FILTER (WHERE rc.statut = 'validee'), 0) AS recolte_validee_kg
FROM ruche r
JOIN site s ON s.id = r.site_id
LEFT JOIN recolte rc ON rc.ruche_id = r.id
CROSS JOIN cle_pseudonymisation k
GROUP BY 1, 2, 3, 4, 5;

-- ===========================================================================
-- 7.4 · Le journal d'audit : une copie voulue, qui ne doit jamais changer
-- (rempli par les triggers de audit.sql, lab 8)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS journal_audit (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  horodatage   timestamptz NOT NULL DEFAULT clock_timestamp(),
  acteur       text NOT NULL,                     -- qui
  table_cible  text NOT NULL,                     -- sur quoi
  operation    text NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
  ligne_id     text,                              -- quelle ligne (pas de clé étrangère : voir normalisation_j2.md)
  avant        jsonb,                             -- la ligne avant
  apres        jsonb                              -- la ligne après
);

REVOKE ALL ON journal_audit FROM PUBLIC;
