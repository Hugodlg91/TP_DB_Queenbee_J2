-- volume.sql : 90 jours de mesures pour mesurer le tableau de bord (TP Jour 2, Lab 7, étape 7.1)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement, UNE SEULE FOIS (une seconde fois serait refusée par mesure_anti_rejeu) :
--   psql -U postgres -d queenbee -v ON_ERROR_STOP=1 -f volume.sql
--
-- Une mesure toutes les 30 minutes pour chaque ruche, du 2026-12-14 00:00 UTC
-- au 2027-03-13 23:30 UTC : 90 x 48 = 4 320 mesures par ruche, 11 ruches.
-- Les mesures du jour d'essai (2027-03-14, donnees.sql) suivent juste après :
-- aucun conflit avec la contrainte anti-rejeu (ruche_id, horodatage).
-- Attendu : INSERT 0 47520.

INSERT INTO mesure (ruche_id, horodatage, poids_kg, temp_int_c, temp_ext_c,
                    humidite_pct, activite_sonore, batterie_pct, latitude, longitude)
SELECT r.id,
       TIMESTAMPTZ '2026-12-14 00:00:00+00' + n * INTERVAL '30 minutes',
       round((30 + random() * 5)::numeric, 2),          -- 30 à 35 kg
       round((33.5 + random())::numeric, 1),            -- vers 34 °C (couvain)
       round((22 + random() * 12)::numeric, 1),         -- 22 à 34 °C
       50 + floor(random() * 30)::int,                  -- 50 à 79 %
       round(random()::numeric, 2),                     -- 0 à 1
       90,                                              -- batterie à 90 %
       r.latitude, r.longitude                          -- la ruche n'a pas bougé
FROM ruche r
CROSS JOIN generate_series(0, 90 * 48 - 1) AS n;

-- Statistiques à jour pour le planificateur (EXPLAIN ANALYZE de l'étape 7.1)
ANALYZE mesure;
