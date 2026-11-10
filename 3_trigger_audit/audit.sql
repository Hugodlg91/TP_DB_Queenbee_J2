-- audit.sql : le trigger d'audit, qui a fait quoi (TP Jour 2, Lab 8, étape 8.3)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement (après denormalisation.sql, qui crée journal_audit) :
--   psql -U postgres -d queenbee -v ON_ERROR_STOP=1 -f audit.sql
-- Rejouable : CREATE OR REPLACE pour les fonctions, DROP TRIGGER IF EXISTS
-- avant chaque CREATE TRIGGER. Si corrections.sql a déjà été lancé, relancez-le
-- ensuite : il remplace audit_ligne() par sa version qui ne recopie pas le
-- haché des mots de passe (constat R1).
--
-- Un journal n'est une preuve (UC-AD01) que s'il est écrit par la base, s'il
-- nomme le vrai acteur, et s'il est en ajout seul.

-- ---------------------------------------------------------------------------
-- 1. Qui agit ? Le rôle choisi par SET ROLE, sinon l'utilisateur connecté.
--    (current_user ne convient pas : dans une fonction SECURITY DEFINER, il
--    vaut le propriétaire de la fonction, et le journal accuserait postgres.)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION qui() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN current_setting('role') = 'none'
              THEN session_user::text
              ELSE current_setting('role') END
$$;

-- ---------------------------------------------------------------------------
-- 2. Une ligne de journal par ligne touchée.
--    SECURITY DEFINER : la fonction écrit dans le journal avec les droits de
--    son propriétaire ; personne d'autre n'a besoin du droit d'y écrire.
--    search_path fixé : un utilisateur ne peut pas glisser sa propre table
--    journal_audit ou sa propre fonction qui() devant les nôtres.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_ligne() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  INSERT INTO journal_audit (acteur, table_cible, operation, ligne_id, avant, apres)
  VALUES (qui(), TG_TABLE_NAME, TG_OP,
          CASE WHEN TG_OP = 'DELETE' THEN OLD.id::text ELSE NEW.id::text END,
          CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
          CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END);
  RETURN NULL;                      -- trigger AFTER : la valeur de retour est ignorée
END;
$$;

-- Récoltes : preuve de production, déclarée puis validée (UC-C02)
DROP TRIGGER IF EXISTS recolte_audit ON recolte;
CREATE TRIGGER recolte_audit
AFTER INSERT OR UPDATE OR DELETE ON recolte
FOR EACH ROW EXECUTE FUNCTION audit_ligne();

-- Comptes : création, changement de rôle ou de site, suppression (UC-AD01)
DROP TRIGGER IF EXISTS utilisateur_audit ON utilisateur;
CREATE TRIGGER utilisateur_audit
AFTER INSERT OR UPDATE OR DELETE ON utilisateur
FOR EACH ROW EXECUTE FUNCTION audit_ligne();

-- ---------------------------------------------------------------------------
-- 3. Le journal en ajout seul : ni modification, ni suppression, ni TRUNCATE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION journal_interdit() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'journal_audit est en ajout seul : % interdit', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS journal_ajout_seul ON journal_audit;
CREATE TRIGGER journal_ajout_seul
BEFORE UPDATE OR DELETE ON journal_audit
FOR EACH ROW EXECUTE FUNCTION journal_interdit();

DROP TRIGGER IF EXISTS journal_sans_truncate ON journal_audit;
CREATE TRIGGER journal_sans_truncate          -- TRUNCATE a besoin de son propre trigger
BEFORE TRUNCATE ON journal_audit
FOR EACH STATEMENT EXECUTE FUNCTION journal_interdit();

-- Limite : le propriétaire de la table (postgres) peut encore désactiver ces
-- triggers (ALTER TABLE journal_audit DISABLE TRIGGER ...). Le journal doit
-- donc aussi partir hors de la base, vers le SIEM du cahier des charges
-- (voir 2_roles_privileges/matrice_droits.md).
