-- formation.sql : décomposition BCNF des formations et trigger (TP Jour 2, Lab 6)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement (après la base du jour 1) :
--   psql -U postgres -d queenbee -v ON_ERROR_STOP=1 -f formation.sql
-- Le fichier se relance autant de fois qu'on veut (DROP ... IF EXISTS en tête).
-- Si corrections.sql a déjà été lancé, relancez-le ensuite : il remplace le
-- trigger ci-dessous par sa version qui résiste aux insertions simultanées.
--
-- Adaptation à NOTRE jeu d'essai du jour 1 : l'énoncé utilise des téléphones
-- qui n'existent pas chez nous. Chaque ligne garde la même structure (mêmes
-- formateurs, mêmes thèmes, mêmes résultats attendus), avec le téléphone d'une
-- de nos apicultrices :
--   énoncé               -> notre base
--   +221 77 100 00 01    -> +221 77 100 00 01  Aminata Diop (SN-CASA), identique
--   +221 77 100 00 02    -> +221 77 100 00 02  Awa Diop (SN-CASA), identique ;
--                           c'est elle qui joue le rôle de « Fatou Ba »
--   +221 77 200 00 01    -> +221 77 200 00 03  Aminata Diop (SN-KOLD)
--   +225 07 100 00 01    -> +225 07 300 00 05  Adjoua Kouassi (CI-YAMO)
--   +225 07 100 00 02    -> +225 07 300 00 06  Aya Kone (CI-YAMO)
--   +237 6 77 100 01     -> +237 6 400 00 07   Brigitte Ngono (CM-BAFO)

DROP TABLE IF EXISTS suivi_formation, formateur, formation_plat CASCADE;

-- ---------------------------------------------------------------------------
-- Étape 6.1 · Le tableau reçu du centre de formation, tel quel
-- DF : (telephone, theme) -> formateur ; formateur -> theme
-- ---------------------------------------------------------------------------
CREATE TABLE formation_plat (
  telephone  text NOT NULL,
  theme      text NOT NULL,
  formateur  text NOT NULL,
  PRIMARY KEY (telephone, theme)
);

INSERT INTO formation_plat (telephone, theme, formateur) VALUES
  ('+221 77 100 00 01', 'varroa',   'Moussa Sarr'),
  ('+221 77 100 00 01', 'recolte',  'Khady Ndiaye'),
  ('+221 77 100 00 02', 'varroa',   'Moussa Sarr'),
  ('+221 77 200 00 03', 'varroa',   'Ibrahima Fall'),
  ('+221 77 200 00 03', 'capteurs', 'Oumar Diallo'),
  ('+225 07 300 00 05', 'varroa',   'Kouassi Yao'),
  ('+225 07 300 00 06', 'capteurs', 'Oumar Diallo'),
  ('+237 6 400 00 07',  'recolte',  'Khady Ndiaye');

-- ---------------------------------------------------------------------------
-- Étape 6.2 · Le découpage BCNF : une table par déterminant
--   formateur -> theme                  => table formateur (nom UNIQUE)
--   (apicultrice, formateur) : le suivi => table suivi_formation
-- ---------------------------------------------------------------------------
CREATE TABLE formateur (
  id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nom    text NOT NULL UNIQUE,                       -- formateur -> theme
  theme  text NOT NULL CHECK (theme IN ('varroa', 'recolte', 'capteurs'))
);

-- L'apicultrice est référencée par son id (clé primaire), jamais par son
-- téléphone recopié : pas de donnée personnelle en double, et le lien suit
-- l'apicultrice si elle change de numéro.
CREATE TABLE suivi_formation (
  apicultrice_id uuid NOT NULL CONSTRAINT suivi_formation_apicultrice_fk REFERENCES apicultrice (id),
  formateur_id   uuid NOT NULL CONSTRAINT suivi_formation_formateur_fk   REFERENCES formateur (id),
  PRIMARY KEY (apicultrice_id, formateur_id)
);

INSERT INTO formateur (nom, theme)
SELECT DISTINCT formateur, theme FROM formation_plat;
-- Attendu : INSERT 0 5

-- L'apicultrice est retrouvée par son téléphone (UNIQUE dans apicultrice)
INSERT INTO suivi_formation (apicultrice_id, formateur_id)
SELECT a.id, f.id
FROM formation_plat fp
JOIN apicultrice a ON a.telephone = fp.telephone
JOIN formateur f   ON f.nom = fp.formateur;
-- Attendu : INSERT 0 8 (moins de 8 : un téléphone ne correspond à aucune apicultrice)

-- ---------------------------------------------------------------------------
-- Étape 6.3 · La règle perdue, rétablie par un trigger
-- Après découpage, plus aucune table ne contient à la fois l'apicultrice et le
-- thème : la DF (telephone, theme) -> formateur n'est plus vérifiée par une clé.
-- Le trigger refuse un second formateur du même thème pour une apicultrice.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION suivi_un_formateur_par_theme() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM suivi_formation s
    JOIN formateur f ON f.id = s.formateur_id
    WHERE s.apicultrice_id = NEW.apicultrice_id     -- même apicultrice
      AND s.formateur_id <> NEW.formateur_id        -- un autre formateur
      AND f.theme = (SELECT theme FROM formateur WHERE id = NEW.formateur_id)
  ) THEN                                            -- ... pour le même thème
    RAISE EXCEPTION 'DF violée : cette apicultrice a déjà un formateur pour ce thème';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER suivi_formation_df
BEFORE INSERT OR UPDATE ON suivi_formation
FOR EACH ROW EXECUTE FUNCTION suivi_un_formateur_par_theme();

-- Limite (lab 9) : c'est un « vérifier, puis agir ». Deux insertions
-- simultanées pour la même apicultrice et le même thème peuvent passer toutes
-- les deux (chacune ne voit pas l'autre, encore non validée). Voir
-- normalisation_j2.md, « Pour aller plus loin », et concurrence.md.

-- ---------------------------------------------------------------------------
-- Étape 6.3 (suite) · La même règle, contournée par la table formateur
-- Le trigger ci-dessus ne surveille que suivi_formation. Or le thème est lu
-- dans formateur : UPDATE formateur SET theme = 'varroa' WHERE nom = 'Khady
-- Ndiaye' passait sans message, et Aminata Diop (+221 77 100 00 01) se
-- retrouvait avec deux formateurs varroa (Khady Ndiaye et Moussa Sarr).
-- Ce trigger refuse le changement de thème d'un formateur si une apicultrice
-- qu'il suit a déjà un AUTRE formateur pour le nouveau thème.
-- Limite : ce trigger ne pose aucun verrou. Un changement de thème et une
-- inscription simultanés peuvent passer tous les deux (« vérifier, puis agir »,
-- lab 9). Seule la variante à clé étrangère composée l'empêche à coup sûr.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION formateur_theme_coherent() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM suivi_formation s                          -- les apicultrices de ce formateur
    JOIN suivi_formation autre ON autre.apicultrice_id = s.apicultrice_id
                              AND autre.formateur_id <> s.formateur_id
    JOIN formateur f ON f.id = autre.formateur_id   -- leurs autres formateurs
    WHERE s.formateur_id = NEW.id
      AND f.theme = NEW.theme                       -- ... du nouveau thème
  ) THEN
    RAISE EXCEPTION 'DF violée : % ne peut pas passer en %, une de ses apicultrices a déjà un formateur pour ce thème',
      NEW.nom, NEW.theme;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION formateur_theme_coherent() FROM PUBLIC;

DROP TRIGGER IF EXISTS formateur_theme_df ON formateur;
CREATE TRIGGER formateur_theme_df
BEFORE UPDATE OF theme ON formateur
FOR EACH ROW WHEN (NEW.theme IS DISTINCT FROM OLD.theme)
EXECUTE FUNCTION formateur_theme_coherent();

-- Testé (transactions annulées, requêtes dans requetes_j2.sql) :
--   UPDATE formateur SET theme = 'varroa' WHERE nom = 'Khady Ndiaye';
--   ERROR:  DF violée : Khady Ndiaye ne peut pas passer en varroa, une de ses apicultrices a déjà un formateur pour ce thème
--   UPDATE formateur SET theme = 'capteurs' WHERE nom = 'Kouassi Yao';
--   UPDATE 1   (Adjoua Kouassi n'a pas d'autre formateur capteurs)
