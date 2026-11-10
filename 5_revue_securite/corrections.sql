-- corrections.sql : corrections de la revue de sécurité (TP Jour 2, Lab 10)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement, en postgres, en DERNIER (après jeton.sql) :
--   psql -U postgres -d queenbee -v ON_ERROR_STOP=1 -f corrections.sql
-- Rejouable. Chaque bloc renvoie à son constat dans rapport_revue.md.

-- ===========================================================================
-- P2 · La vue « pour la carte » donnait le nom et le téléphone de TOUTES les
-- apicultrices au groupe qb_apicultrice (une vue lit avec les droits de son
-- propriétaire : élévation de privilège). Réécrite : ses ruches seulement,
-- sans nom ni téléphone, et barrière de sécurité.
-- ===========================================================================
DROP VIEW IF EXISTS v_carte_ruches;

CREATE VIEW v_carte_ruches WITH (security_barrier = true) AS
SELECT r.code, r.latitude, r.longitude
FROM ruche r
JOIN utilisateur u ON u.apicultrice_id = r.apicultrice_id
WHERE u.login = qui();

GRANT SELECT ON v_carte_ruches TO qb_apicultrice;

-- ===========================================================================
-- P3 · La fonction espion : sans barrière, PostgreSQL peut évaluer une
-- fonction de l'utilisateur AVANT le filtre de la vue, et elle voit toutes
-- les lignes. security_barrier sur toutes les vues filtrées par qui().
-- ===========================================================================
ALTER VIEW v_moi           SET (security_barrier = true);
ALTER VIEW v_mes_ruches    SET (security_barrier = true);
ALTER VIEW v_mes_mesures   SET (security_barrier = true);
ALTER VIEW v_mes_recoltes  SET (security_barrier = true);
ALTER VIEW v_ruches_site   SET (security_barrier = true);
ALTER VIEW v_recoltes_site SET (security_barrier = true);

-- Plus de fonction (ni de table) temporaire pour les comptes : pg_temp.espion
-- ne peut plus être créée. postgres garde le droit (superutilisateur).
DO $$
BEGIN
  EXECUTE format('REVOKE TEMPORARY ON DATABASE %I FROM PUBLIC', current_database());
END $$;

-- ===========================================================================
-- R1 · Le journal recopiait mot_de_passe_hash à chaque création ou
-- modification de compte : l'administrateur, qui lit le journal, aurait les
-- hachés de tous les mots de passe (à casser hors ligne). Le trigger retire
-- désormais cette colonne ; le reste de la ligne est gardé comme preuve.
-- ===========================================================================
CREATE OR REPLACE FUNCTION audit_ligne() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  INSERT INTO journal_audit (acteur, table_cible, operation, ligne_id, avant, apres)
  VALUES (qui(), TG_TABLE_NAME, TG_OP,
          CASE WHEN TG_OP = 'DELETE' THEN OLD.id::text ELSE NEW.id::text END,
          CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) - 'mot_de_passe_hash' END,
          CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) - 'mot_de_passe_hash' END);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION audit_ligne() FROM PUBLIC;

-- ===========================================================================
-- R2 · Le trigger du lab 6 est un « vérifier, puis agir » : deux inscriptions
-- simultanées (même apicultrice, même thème, deux formateurs) passaient toutes
-- les deux. Correction : le trigger verrouille d'abord la ligne de
-- l'apicultrice. La seconde inscription attend la fin de la première, puis
-- sa vérification voit la ligne validée et refuse.
-- (FOR NO KEY UPDATE et non FOR UPDATE : ne bloque pas les clés étrangères
--  qui pointent vers l'apicultrice, par exemple un nouveau suivi d'un autre thème.)
-- Limite : ce verrou ne protège qu'en READ COMMITTED (le niveau par défaut).
-- En REPEATABLE READ, la seconde inscription attend bien le verrou, mais sa
-- vérification lit l'image prise au début de sa transaction : elle ne voit
-- pas la première, et les deux passent. Une contrainte UNIQUE garantit la règle
-- à tout niveau d'isolation (SERIALIZABLE la protège aussi, mais par une erreur
-- de sérialisation qu'il faut réessayer).
--
-- Revue (E1) : la condition d'origine, reprise du modèle GreenFarm du sujet,
-- refusait à tort un UPDATE qui remplace le formateur par un autre du même
-- thème : dans un trigger BEFORE, l'ancienne ligne est encore visible, et elle
-- passait pour « un autre formateur ». On exclut donc cette ancienne ligne.
-- (Pour un INSERT, TG_OP vaut 'INSERT' : la condition ajoutée est toujours vraie.)
-- ===========================================================================
CREATE OR REPLACE FUNCTION suivi_un_formateur_par_theme() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM apicultrice WHERE id = NEW.apicultrice_id FOR NO KEY UPDATE;
  IF EXISTS (
    SELECT 1
    FROM suivi_formation s
    JOIN formateur f ON f.id = s.formateur_id
    WHERE s.apicultrice_id = NEW.apicultrice_id     -- même apicultrice
      AND s.formateur_id <> NEW.formateur_id        -- un autre formateur
      AND NOT (TG_OP = 'UPDATE'                     -- sauf la ligne modifiée
               AND s.apicultrice_id = OLD.apicultrice_id
               AND s.formateur_id = OLD.formateur_id)
      AND f.theme = (SELECT theme FROM formateur WHERE id = NEW.formateur_id)
  ) THEN                                            -- ... pour le même thème
    RAISE EXCEPTION 'DF violée : cette apicultrice a déjà un formateur pour ce thème';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION suivi_un_formateur_par_theme() FROM PUBLIC;
