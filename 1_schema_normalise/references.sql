-- references.sql : que se passe-t-il quand on supprime ? (TP Jour 2, Lab 8, étape 8.1)
-- Groupe : Praveen, Ugo, Hugo, Corentin
-- Lancement : psql -U postgres -d queenbee -v ON_ERROR_STOP=1 -f references.sql
-- Rejouable : chaque clé est supprimée puis recréée, sous le même nom.
--
-- Règle : une ligne liée qui est une PREUVE (mesure, inspection, récolte,
-- alerte) ne part jamais avec sa ruche : RESTRICT. Un lien sans valeur propre
-- (l'adhésion) part avec l'apicultrice ou la coopérative : CASCADE.

BEGIN;

-- Adhésion : simple lien n,n, sans valeur de preuve. Si l'apicultrice ou la
-- coopérative est supprimée (droit à l'effacement, coopérative dissoute),
-- garder l'adhésion n'aurait aucun sens : elle part avec.
ALTER TABLE adhesion
  DROP CONSTRAINT adhesion_apicultrice_fk,
  ADD  CONSTRAINT adhesion_apicultrice_fk FOREIGN KEY (apicultrice_id)
       REFERENCES apicultrice (id) ON DELETE CASCADE,
  DROP CONSTRAINT adhesion_cooperative_fk,
  ADD  CONSTRAINT adhesion_cooperative_fk FOREIGN KEY (cooperative_id)
       REFERENCES cooperative (id) ON DELETE CASCADE;

-- Mesures : historique des capteurs, preuve d'un vol ou d'une récolte
-- (UC-CY04, UC-C02). Supprimer une ruche ne doit jamais les effacer.
ALTER TABLE mesure
  DROP CONSTRAINT mesure_ruche_fk,
  ADD  CONSTRAINT mesure_ruche_fk FOREIGN KEY (ruche_id)
       REFERENCES ruche (id) ON DELETE RESTRICT;

-- Inspections : constats signés par une apicultrice (état de la colonie,
-- reine) ; les perdre permettrait de nier une observation (R de STRIDE).
ALTER TABLE inspection
  DROP CONSTRAINT inspection_ruche_fk,
  ADD  CONSTRAINT inspection_ruche_fk FOREIGN KEY (ruche_id)
       REFERENCES ruche (id) ON DELETE RESTRICT;

-- Récoltes : production et revenus, validées par un coordinateur (UC-C02).
-- Une suppression en cascade effacerait une validation sans trace.
ALTER TABLE recolte
  DROP CONSTRAINT recolte_ruche_fk,
  ADD  CONSTRAINT recolte_ruche_fk FOREIGN KEY (ruche_id)
       REFERENCES ruche (id) ON DELETE RESTRICT;

-- Alertes : trace d'un vol, d'un essaimage ou d'un capteur silencieux.
-- Supprimer la ruche volée ne doit pas effacer l'alerte de vol.
ALTER TABLE alerte
  DROP CONSTRAINT alerte_ruche_fk,
  ADD  CONSTRAINT alerte_ruche_fk FOREIGN KEY (ruche_id)
       REFERENCES ruche (id) ON DELETE RESTRICT;

COMMIT;

-- Vérification : 2 CASCADE, 4 RESTRICT ; les autres clés gardent le défaut
-- (a = NO ACTION, qui refuse lui aussi)
SELECT conrelid::regclass AS table_, conname,
       CASE confdeltype WHEN 'c' THEN 'CASCADE' WHEN 'r' THEN 'RESTRICT'
                        WHEN 'n' THEN 'SET NULL' ELSE 'NO ACTION (défaut)' END AS on_delete
FROM pg_constraint
WHERE contype = 'f' AND confdeltype IN ('c', 'r')
ORDER BY on_delete, table_;
