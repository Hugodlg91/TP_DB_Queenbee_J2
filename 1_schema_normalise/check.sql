-- check.sql : refuser les valeurs impossibles (TP Jour 2, Lab 8, étape 8.2)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement : psql -U postgres -d queenbee -v ON_ERROR_STOP=1 -f check.sql
--
-- Notre schema.sql du jour 1 avait déjà ces règles, mais sous des noms
-- générés par PostgreSQL (mesure_batterie_pct_check...), et deux CHECK de
-- utilisateur sans nom du tout (limite 6 de tests_schema.sql). On les remplace
-- par des contraintes NOMMÉES : les messages d'erreur disent quelle règle
-- refuse. Rejouable : DROP ... IF EXISTS sur l'ancien ET sur le nouveau nom.
--
-- Adaptation : nos statuts d'alerte sont ouverte, en_cours, fermee (choix du
-- jour 1) ; l'énoncé écrit « traitee » pour « fermee ».

BEGIN;

ALTER TABLE mesure
  DROP CONSTRAINT IF EXISTS mesure_batterie_pct_check,
  DROP CONSTRAINT IF EXISTS mesure_batterie_0_100,
  ADD  CONSTRAINT mesure_batterie_0_100 CHECK (batterie_pct BETWEEN 0 AND 100),
  DROP CONSTRAINT IF EXISTS mesure_humidite_pct_check,
  DROP CONSTRAINT IF EXISTS mesure_humidite_0_100,
  ADD  CONSTRAINT mesure_humidite_0_100 CHECK (humidite_pct BETWEEN 0 AND 100),
  DROP CONSTRAINT IF EXISTS mesure_poids_kg_check,
  DROP CONSTRAINT IF EXISTS mesure_poids_positif,
  -- positif ou nul ; on garde aussi la borne haute du jour 1 (200 kg) : un
  -- poids de 5 tonnes est une trame forgée, pas une ruche
  ADD  CONSTRAINT mesure_poids_positif CHECK (poids_kg >= 0 AND poids_kg <= 200);

ALTER TABLE utilisateur
  DROP CONSTRAINT IF EXISTS utilisateur_role_check,
  DROP CONSTRAINT IF EXISTS utilisateur_role_valide,
  ADD  CONSTRAINT utilisateur_role_valide
       CHECK (role IN ('apicultrice', 'coordinateur', 'gestionnaire', 'admin')),
  -- les deux CHECK sans nom du jour 1, enfin nommés
  DROP CONSTRAINT IF EXISTS utilisateur_check,
  DROP CONSTRAINT IF EXISTS utilisateur_apicultrice_si_role,
  ADD  CONSTRAINT utilisateur_apicultrice_si_role
       CHECK ((role = 'apicultrice') = (apicultrice_id IS NOT NULL)),
  DROP CONSTRAINT IF EXISTS utilisateur_check1,
  DROP CONSTRAINT IF EXISTS utilisateur_site_si_terrain,
  ADD  CONSTRAINT utilisateur_site_si_terrain
       CHECK (role NOT IN ('apicultrice', 'coordinateur') OR site_id IS NOT NULL);

ALTER TABLE alerte
  DROP CONSTRAINT IF EXISTS alerte_statut_check,
  DROP CONSTRAINT IF EXISTS alerte_statut_valide,
  ADD  CONSTRAINT alerte_statut_valide CHECK (statut IN ('ouverte', 'en_cours', 'fermee'));

ALTER TABLE recolte
  DROP CONSTRAINT IF EXISTS recolte_statut_check,
  DROP CONSTRAINT IF EXISTS recolte_statut_valide,
  ADD  CONSTRAINT recolte_statut_valide CHECK (statut IN ('declaree', 'validee', 'ecart')),
  -- Ajout de la revue (constat R5) : recolte_quantite_positive (jour 1, gardée)
  -- laisse passer 'NaN' (pour PostgreSQL, NaN est plus grand que tout nombre,
  -- donc NaN > 0 est vrai) et 9999.99 kg ; la date acceptait l'an 3027 ou
  -- 'infinity'. NaN <= 200 est faux : la borne haute refuse aussi NaN.
  -- ('infinity' en kg est déjà refusé par le type numeric(6,2).)
  DROP CONSTRAINT IF EXISTS recolte_quantite_plausible,
  ADD  CONSTRAINT recolte_quantite_plausible CHECK (quantite_kg > 0 AND quantite_kg <= 200),
  DROP CONSTRAINT IF EXISTS recolte_date_plausible,
  ADD  CONSTRAINT recolte_date_plausible
       CHECK (date_recolte BETWEEN DATE '2020-01-01' AND DATE '2100-01-01');

COMMIT;
