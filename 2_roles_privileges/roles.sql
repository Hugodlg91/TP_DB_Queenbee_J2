-- roles.sql : rôles, vues de moindre privilège et validation des récoltes
-- TP Jour 2, Lab 8 (étapes 8.4 et 8.5) · Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement (après audit.sql, qui crée qui()) :
--   psql -U postgres -d queenbee -v ON_ERROR_STOP=1 -f roles.sql
-- Rejouable : rôles créés seulement s'ils manquent, vues recréées, droits
-- reposés. Conforme à matrice_droits.md.
--
-- Adaptation à notre jeu d'essai : un rôle PostgreSQL porte EXACTEMENT le
-- login de son compte dans utilisateur (qui() relie les deux) :
--   énoncé            -> notre base
--   f.ba              -> "a.diop"            Awa Diop, SN-CASA, 1 ruche (SN-CASA-021),
--                                            même téléphone que Fatou Ba (+221 77 100 00 02)
--   awa.diop          -> "aminata.diop.casa" Aminata Diop, SN-CASA, 2 ruches
--   coord.sn          -> "coord.casa"        coordinateur de SN-CASA
--   gest.beeafrica    -> "gest.beeafrica"    ajouté dans utilisateur ci-dessous
--   admin.beeafrica   -> "admin"             le compte admin du jour 1
--
-- Aucun mot de passe ici : les rôles personnels sont LOGIN sans secret (ils ne
-- peuvent pas encore se connecter par mot de passe). L'administrateur pose les
-- secrets hors du dépôt (méta-commande de psql prévue pour cela). Les tests passent par
-- SET ROLE depuis postgres.

-- ===========================================================================
-- 1. Les groupes, puis les personnes (les rôles sont communs à tout le serveur)
-- ===========================================================================
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['qb_apicultrice', 'qb_coordinateur', 'qb_gestionnaire', 'qb_admin'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END IF;
  END LOOP;
  FOREACH r IN ARRAY ARRAY['a.diop', 'aminata.diop.casa', 'coord.casa', 'gest.beeafrica', 'admin'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I LOGIN', r);
    END IF;
  END LOOP;
END $$;

-- Chaque personne hérite des droits de son groupe (INHERIT TRUE), mais ne peut
-- pas faire SET ROLE vers ce groupe (SET FALSE, PostgreSQL 16 et plus) : sinon
-- qui() renverrait « qb_admin » au lieu de son login, et le journal ne
-- nommerait plus personne (revue, constat R6). Les tests passent toujours par
-- SET ROLE "a.diop" depuis postgres, qui reste permis au superutilisateur.
-- Relance : un GRANT sur une appartenance qui existe déjà repose ses options.
GRANT qb_apicultrice  TO "a.diop", "aminata.diop.casa" WITH INHERIT TRUE, SET FALSE;
GRANT qb_coordinateur TO "coord.casa"                  WITH INHERIT TRUE, SET FALSE;
GRANT qb_gestionnaire TO "gest.beeafrica"              WITH INHERIT TRUE, SET FALSE;
GRANT qb_admin        TO "admin"                       WITH INHERIT TRUE, SET FALSE;

-- Le gestionnaire n'avait pas de compte dans notre jeu d'essai
INSERT INTO utilisateur (login, role)
SELECT 'gest.beeafrica', 'gestionnaire'
WHERE NOT EXISTS (SELECT 1 FROM utilisateur WHERE login = 'gest.beeafrica');

-- ===========================================================================
-- 2. Tout fermer, puis ouvrir le minimum
--    (CONNECT seulement : le droit TEMPORARY reste à PUBLIC jusqu'au lab 10)
-- ===========================================================================
DO $$
BEGIN
  EXECUTE format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', current_database());
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO qb_apicultrice, qb_coordinateur, qb_gestionnaire, qb_admin',
                 current_database());
END $$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
-- Les fonctions créées PLUS TARD par postgres ne seront pas non plus ouvertes
-- à PUBLIC. Sans IN SCHEMA : le droit EXECUTE de PUBLIC est un défaut global,
-- et un défaut limité à un schéma ne peut pas le retirer (notre première
-- version, IN SCHEMA public, ne faisait rien : pg_default_acl restait vide).
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO qb_apicultrice, qb_coordinateur, qb_gestionnaire, qb_admin;
-- qui() est appelée dans les vues : une fonction d'une vue s'exécute avec les
-- droits de celui qui lit la vue, il faut donc le droit EXECUTE
GRANT EXECUTE ON FUNCTION qui() TO qb_apicultrice, qb_coordinateur, qb_gestionnaire, qb_admin;

-- ===========================================================================
-- 3. Chacun ne voit que ses lignes, et les colonnes utiles
--    (une vue s'exécute avec les droits de son propriétaire : aucun droit
--     n'est donné sur les tables elles-mêmes)
-- ===========================================================================
DROP VIEW IF EXISTS v_moi, v_mes_recoltes, v_mes_mesures, v_mes_ruches,
                    v_recoltes_site, v_ruches_site CASCADE;

-- Son propre compte (tous les rôles) ; jamais le hash du mot de passe
CREATE VIEW v_moi AS
SELECT id, login, role, site_id, apicultrice_id
FROM utilisateur
WHERE login = qui();

-- --- Apicultrice --------------------------------------------------------------
CREATE VIEW v_mes_ruches AS
SELECT r.id, r.code, r.site_id, r.latitude, r.longitude, r.date_installation
FROM ruche r
JOIN utilisateur u ON u.apicultrice_id = r.apicultrice_id
WHERE u.login = qui();

-- Pas la position reçue : elle sert à la détection de vol, côté coordinateur
CREATE VIEW v_mes_mesures AS
SELECT m.ruche_id, m.horodatage, m.poids_kg, m.temp_int_c, m.temp_ext_c,
       m.humidite_pct, m.activite_sonore, m.batterie_pct
FROM mesure m
WHERE m.ruche_id IN (SELECT id FROM v_mes_ruches);

-- WITH CHECK OPTION : on ne peut pas écrire, par la vue, une récolte que la vue
-- ne montrerait pas (sur la ruche d'une autre)
CREATE VIEW v_mes_recoltes AS
SELECT rc.id, rc.ruche_id, rc.date_recolte, rc.quantite_kg, rc.statut, rc.date_validation
FROM recolte rc
WHERE rc.ruche_id IN (SELECT id FROM v_mes_ruches)
WITH CHECK OPTION;

-- --- Coordinateur : son site seulement ---------------------------------------------
CREATE VIEW v_ruches_site AS
SELECT r.id, r.code, r.latitude, r.longitude, r.date_installation,
       a.nom AS apicultrice, a.telephone          -- pour joindre l'apicultrice (alerte, récolte)
FROM ruche r
JOIN apicultrice a ON a.id = r.apicultrice_id
WHERE r.site_id = (SELECT site_id FROM utilisateur
                   WHERE login = qui() AND role = 'coordinateur');

CREATE VIEW v_recoltes_site AS
SELECT rc.id, r.code AS ruche_code, rc.date_recolte, rc.quantite_kg, rc.statut,
       rc.validee_par, rc.date_validation
FROM recolte rc
JOIN ruche r ON r.id = rc.ruche_id
WHERE r.site_id = (SELECT site_id FROM utilisateur
                   WHERE login = qui() AND role = 'coordinateur');

-- ===========================================================================
-- 4. Validation d'une récolte (étape 8.5)
--    Le coordinateur n'a AUCUN droit UPDATE sur recolte (il pourrait changer
--    les volumes) : il passe par cette fonction, qui ne fait qu'une chose.
-- ===========================================================================
CREATE OR REPLACE FUNCTION valider_recolte(p_recolte uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_coord uuid;
  v_site  text;
  n       int;
BEGIN
  SELECT id, site_id INTO v_coord, v_site
  FROM utilisateur
  WHERE login = qui() AND role = 'coordinateur';

  IF v_coord IS NULL THEN
    RAISE EXCEPTION 'valider_recolte : réservé aux coordinateurs';
  END IF;

  UPDATE recolte rc
  SET statut = 'validee', validee_par = v_coord, date_validation = now()
  WHERE rc.id = p_recolte
    AND rc.statut = 'declaree'
    AND rc.ruche_id IN (SELECT id FROM ruche WHERE site_id = v_site);

  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RAISE EXCEPTION 'récolte introuvable, déjà traitée ou hors de votre site';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION valider_recolte(uuid) FROM PUBLIC;

-- ===========================================================================
-- 5. Les droits, conformes à matrice_droits.md
-- ===========================================================================
GRANT SELECT ON v_moi TO qb_apicultrice, qb_coordinateur, qb_gestionnaire, qb_admin;

-- Apicultrice : ses ruches, ses mesures, déclarer une récolte sur ses ruches
GRANT SELECT ON v_mes_ruches, v_mes_mesures TO qb_apicultrice;
GRANT SELECT, INSERT (ruche_id, date_recolte, quantite_kg) ON v_mes_recoltes TO qb_apicultrice;

-- Coordinateur : son site, et la validation par la fonction seulement
GRANT SELECT ON v_ruches_site, v_recoltes_site TO qb_coordinateur;
GRANT EXECUTE ON FUNCTION valider_recolte(uuid) TO qb_coordinateur;

-- Gestionnaire : la synthèse (UC-G01) et l'export pseudonymisé (UC-G02).
-- hmac() est appelée dans la vue d'export : comme qui(), il faut EXECUTE.
GRANT SELECT ON synthese_site_jour, v_export_bailleur TO qb_gestionnaire;
GRANT EXECUTE ON FUNCTION hmac(text, text, text) TO qb_gestionnaire;

-- Administrateur : les comptes (sans DELETE : on désactive, on ne supprime pas
-- une trace) et la lecture du journal.
-- Droits par colonne, sans mot_de_passe_hash : l'admin ne lit pas les hachés
-- (à casser hors ligne, constat R1). L'id n'est pas dans INSERT : il prend
-- sa valeur par défaut, gen_random_uuid(), sans droit sur la colonne.
-- REVOKE d'abord : à la relance, l'ancien droit sur toute la table disparaît.
REVOKE ALL ON utilisateur FROM qb_admin;
GRANT SELECT (id, login, role, site_id, apicultrice_id),
      INSERT (login, role, site_id, apicultrice_id),
      UPDATE (login, role, site_id, apicultrice_id) ON utilisateur TO qb_admin;
GRANT SELECT ON journal_audit TO qb_admin;

-- Vérification : une ligne par personne, héritage oui, SET ROLE vers le groupe non
SELECT m.rolname AS personne, g.rolname AS groupe,
       am.inherit_option AS herite, am.set_option AS set_role
FROM pg_auth_members am
JOIN pg_roles g ON g.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE g.rolname LIKE 'qb\_%'
ORDER BY groupe, personne;
