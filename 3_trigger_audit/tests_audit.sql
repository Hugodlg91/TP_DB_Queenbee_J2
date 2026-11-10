-- tests_audit.sql : tests du trigger d'audit (TP Jour 2, étape 8.3, points 2 à 4 ; section 11.2)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement SANS ON_ERROR_STOP (les refus sont voulus), en postgres, après audit.sql :
--   psql -U postgres -d queenbee -f tests_audit.sql
-- Adaptation : l'énoncé modifie la récolte de SN-CASA-011 (volume_kg 12.5 -> 14.0) ;
-- chez nous, c'est la récolte validée de SN-CASA-014 (quantite_kg 12.40 -> 14.00).

-- Point 2 · une modification, et sa trace
UPDATE recolte SET quantite_kg = 14.0
WHERE ruche_id = (SELECT id FROM ruche WHERE code = 'SN-CASA-014');
-- Obtenu : UPDATE 1

SELECT acteur, table_cible, operation,
       avant ->> 'quantite_kg' AS avant, apres ->> 'quantite_kg' AS apres
FROM journal_audit
WHERE table_cible = 'recolte' AND operation = 'UPDATE'
ORDER BY id DESC LIMIT 1;
-- Obtenu :
--   acteur  | table_cible | operation | avant | apres
--  postgres | recolte     | UPDATE    | 12.40 | 14.00
-- (1 ligne)  -> attendu
-- (si le fichier est relancé, la ligne affiche 14.00 | 14.00 : l'UPDATE a eu lieu,
--  même sans changement de valeur, et il est tracé lui aussi)

-- Point 3 · effacer ses traces : trois refus, le nombre de lignes ne bouge pas
SELECT count(*) AS lignes_avant FROM journal_audit \gset
UPDATE journal_audit SET acteur = 'personne';
-- Obtenu : ERROR:  journal_audit est en ajout seul : UPDATE interdit
DELETE FROM journal_audit;
-- Obtenu : ERROR:  journal_audit est en ajout seul : DELETE interdit
TRUNCATE journal_audit;
-- Obtenu : ERROR:  journal_audit est en ajout seul : TRUNCATE interdit
SELECT :lignes_avant AS lignes_avant, count(*) AS lignes_apres FROM journal_audit;
-- Obtenu : lignes_avant = lignes_apres  -> attendu
-- (1 | 1 lors de notre premier passage ; 2 | 2 dans une base reconstruite en suivant
--  le README, où roles.sql a déjà journalisé la création de gest.beeafrica)

-- Point 4 · la limite : le propriétaire peut désactiver le trigger
ALTER TABLE journal_audit DISABLE TRIGGER journal_ajout_seul;
-- Obtenu : ALTER TABLE  -> la protection tombe pour postgres (propriétaire de la table)
ALTER TABLE journal_audit ENABLE TRIGGER journal_ajout_seul;
-- Obtenu : ALTER TABLE  -> réactivé aussitôt
SELECT tgname, tgenabled FROM pg_trigger
WHERE tgrelid = 'journal_audit'::regclass ORDER BY tgname;
-- Obtenu :
--         tgname         | tgenabled
--  journal_ajout_seul    | O
--  journal_sans_truncate | O
-- (2 lignes)  -> les deux triggers sont actifs (O = origin, activé)
-- Conséquence (matrice_droits.md) : le journal doit aussi être copié hors de
-- la base, vers le SIEM du cahier des charges.
