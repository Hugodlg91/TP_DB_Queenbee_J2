-- jeton.sql : jetons de rafraîchissement à usage unique (TP Jour 2, Lab 9, étape 9.2)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement : psql -U postgres -d queenbee -v ON_ERROR_STOP=1 -f jeton.sql
-- Rejouable : les deux tables sont supprimées puis recréées (jetons de test).
--
-- Adaptation : les jetons sont ceux de "a.diop" (notre f.ba), donc
-- RT-a.diop-1 à RT-a.diop-30 au lieu de RT-f.ba-1 à RT-f.ba-30.

DROP TABLE IF EXISTS session_app, jeton CASCADE;

CREATE TABLE jeton (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  utilisateur_id  uuid NOT NULL CONSTRAINT jeton_utilisateur_fk REFERENCES utilisateur (id),
  valeur          text NOT NULL UNIQUE,
  expire_le       timestamptz NOT NULL,
  utilise_le      timestamptz            -- vide tant que le jeton n'a pas servi
);

CREATE TABLE session_app (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  utilisateur_id  uuid NOT NULL CONSTRAINT session_app_utilisateur_fk REFERENCES utilisateur (id),
  jeton_id        uuid NOT NULL CONSTRAINT session_app_jeton_fk REFERENCES jeton (id),
  ouverte_le      timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Trente jetons pour a.diop, valables un jour
INSERT INTO jeton (utilisateur_id, valeur, expire_le)
SELECT id, 'RT-' || login || '-' || n, now() + INTERVAL '1 day'
FROM utilisateur CROSS JOIN generate_series(1, 30) AS n
WHERE login = 'a.diop';
-- Attendu : INSERT 0 30

-- Correction 3 (étape 9.4) : la base refuse deux sessions pour un même jeton,
-- quel que soit le code de l'application. Posée APRÈS la démonstration de la
-- course (voir concurrence.md) : avec elle, la course ne peut plus réussir.
ALTER TABLE session_app ADD CONSTRAINT session_jeton_unique UNIQUE (jeton_id);
