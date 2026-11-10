# Queen Bee - Dossier de conception, jour 2 - Groupe Praveen, Ugo, Hugo, Corentin

## Les 5 parties

1. Schéma normalisé : `1_schema_normalise/` (formations en BCNF + trigger, volume, synthèse, export pseudonymisé, journal, `ON DELETE`, `CHECK` nommés, `schema_j2.sql`, `normalisation_j2.md`)
2. Rôles et privilèges : `2_roles_privileges/` (4 rôles, 7 vues filtrées par utilisateur, 1 fonction de validation)
3. Trigger d'audit : `3_trigger_audit/` (tables auditées : `recolte`, `utilisateur` ; journal en ajout seul)
4. Test de concurrence : `4_test_concurrence/` (2 sessions avant, 1 après)
5. Revue de sécurité : `5_revue_securite/` (9 constats, 7 corrigés ; grille : 11 contrôles passés sur 12)

Fichiers de tests rejouables en plus (facultatifs, ils ne laissent rien dans la base) : `1_schema_normalise/requetes_j2.sql` (les requêtes des labs 6 et 7 citées dans `normalisation_j2.md`), `1_schema_normalise/tests_8_1_8_2.sql` (tests de suppression et de `CHECK` des étapes 8.1 et 8.2) et `5_revue_securite/demo_failles.sql` (rejoue les failles P2 et P3 du lab 10.2).

**Captures d'écran** : `captures/` contient une capture par question de l'énoncé (le code en haut, le résultat de son exécution en bas), et `captures/README.md` les présente dans l'ordre des labs, avec ce qui était attendu.

Les 7 vues filtrées par utilisateur : `v_moi`, `v_mes_ruches`, `v_mes_mesures`, `v_mes_recoltes`, `v_ruches_site`, `v_recoltes_site`, et `v_carte_ruches` (réécrite au lab 10).

## Adaptation à notre base du jour 1

L'énoncé suppose une base de référence qui n'est pas la nôtre. Nous avons fait le jour 2 **sur notre propre base du jour 1** : mêmes exercices, mêmes contrôles, avec ces correspondances.

| Énoncé | Notre base |
|---|---|
| Fatou Ba, rôle `f.ba` (+221 77 100 00 02, 1 ruche SN-CASA-013) | Awa Diop, rôle `a.diop` (même téléphone, 1 ruche SN-CASA-021) |
| rôle `awa.diop` | `aminata.diop.casa` (Aminata Diop, SN-CASA, 2 ruches) |
| `coord.sn` / `admin.beeafrica` | `coord.casa` / `admin` (comptes du jour 1) |
| `gest.beeafrica` | identique, ajouté dans `utilisateur` par `roles.sql` |
| téléphones de `formation_plat` | ceux de nos apicultrices (correspondance en tête de `formation.sql`) |
| SN-CASA : 4 ruches, 192 mesures par jour | SN-CASA : 3 ruches, **144** mesures par jour |
| SN-CASA-011 (vol du 15 mars, récolte 12.5 → 14.0) | SN-CASA-014 (vol du 15 mars, récolte 12.40 → 14.00) |
| CI-MAN-012 (test de suppression) | SN-KOLD-012 |
| récolte d'un autre site « CM-BAF » | récolte déclarée de CI-YAMO-002 |
| colonnes `volume_kg`, `validee_le` | `quantite_kg`, `date_validation` (noms du jour 1) |
| statut d'alerte `traitee` | `fermee` (valeurs du jour 1) |
| jetons `RT-f.ba-1` à `-30` | `RT-a.diop-1` à `-30` |

Un rôle PostgreSQL porte toujours le login de son compte dans `utilisateur` : `qui()` relie les deux.

## Reconstruire (après la base du jour 1, avec -v ON_ERROR_STOP=1)

Versions : testé sous PostgreSQL 18 (base de travail) et reconstruit sous PostgreSQL 16 ; `schema_j2.sql` se recharge avec un psql 16.10 ou plus récent (il commence par `\restrict`).

La reconstruction se fait depuis `dossier-bdd`, dans une base **vide** : il faut la créer avant. Relancer toute la chaîne sur une base qui contient déjà le jour 2 échoue au contrôle 2 de `verif_rendu.sql` du jour 1 (16 clés étrangères au lieu de 14, car les tables `formateur` et `jeton` survivent au `schema.sql` du jour 1 et gardent `suivi_formation_formateur_fk` et `session_app_jeton_fk`). Pour repartir de zéro :

```powershell
dropdb -U postgres --if-exists queenbee_test
createdb -U postgres queenbee_test
```

(ou, dans `psql` : `DROP DATABASE queenbee_test;` puis `CREATE DATABASE queenbee_test;`)

Les étapes :

0. la base du jour 1 : `rejouer_tout.ps1` (labs 1 à 5, avec le contrôle `verif_rendu.sql`)
1. `jour2/1_schema_normalise/formation.sql`
2. `jour2/1_schema_normalise/volume.sql` (**une seule fois** : une seconde fois serait refusée par l'anti-rejeu)
3. `jour2/1_schema_normalise/denormalisation.sql`
4. `jour2/1_schema_normalise/references.sql` puis `jour2/1_schema_normalise/check.sql`
5. `jour2/3_trigger_audit/audit.sql`
6. `jour2/2_roles_privileges/roles.sql`
7. `jour2/4_test_concurrence/jeton.sql`
8. `jour2/5_revue_securite/corrections.sql` (**toujours en dernier** : il remplace des fonctions créées par `formation.sql` et `audit.sql`)

Puis les tests, **sans** `ON_ERROR_STOP` (les refus sont voulus), dans l'ordre de l'énoncé : `tests_audit.sql` (étape 8.3), puis `tests_contournement.sql` (étape 8.6). Dans l'autre ordre, les verdicts sont les mêmes, mais trois sorties diffèrent des commentaires : SN-CASA-014 affiche 12.40 au lieu de 14.00 (la récolte n'a pas encore été portée à 14.00), la ligne `postgres | recolte | UPDATE` du journal disparaît (3 lignes deviennent 2), et `lignes_avant | lignes_apres` vaut 4 | 4 au lieu de 2 | 2. Les tests ajoutent une récolte et des lignes de journal : pour retrouver exactement les sorties commentées, il faut une base fraîchement reconstruite.

Les rôles sont communs à tout le serveur : `roles.sql` ne les crée que s'ils manquent.

Restauration : `pg_dump --schema-only` (`schema_j2.sql`) ne contient pas les droits au niveau de la base (`REVOKE CONNECT`, `REVOKE TEMPORARY`). Après une restauration à partir de `schema_j2.sql`, il faut relancer `roles.sql` et `corrections.sql` (ou au moins leurs blocs `DO`).

Archive à rendre (étape 11.6) : `git add -A`, `git commit -m "Jour 2 : dossier de conception"`, puis `git archive --format=zip -o GROUPE_X_jour2.zip HEAD jour2` (X = numéro du groupe). Le `.gitignore` de `jour2/` exclut les `.dump`, mais la sauvegarde de l'étape 9.5 est créée à la racine de `dossier-bdd` : il faut aussi la ligne `*.dump` dans le `.gitignore` de la racine, sinon `git add -A` la commiterait (données personnelles dans l'historique).

## Nos choix principaux

- **BCNF + trigger pour les formations**, parce que la BCNF supprime la copie du thème de chaque formateur : plus d'anomalie « Moussa Sarr a deux thèmes ». Le trigger rétablit la règle perdue (un formateur par thème et par apicultrice). Le lab 9 a montré qu'il cédait à deux inscriptions simultanées : il verrouille désormais l'apicultrice avant de vérifier (`corrections.sql`, constat R2). La variante sans trigger, en 3NF avec `UNIQUE (apicultrice_id, theme)` et une clé étrangère composée, est testée et documentée.
- **La synthèse est rafraîchie toutes les nuits** (`REFRESH MATERIALIZED VIEW CONCURRENTLY`, lancé par `pg_cron` ou une tâche planifiée, voir `denormalisation.sql`), pour le tableau de bord (0,07 ms au lieu de 9,8 ms) ; le vol est **détecté sur les mesures brutes, à leur arrivée**, jamais dans la synthèse, qui peut avoir jusqu'à 24 h de retard.
- **Export du bailleur pseudonymisé par HMAC**, avec une clé fermée à tous, et une position arrondie à 0,1 degré. Un haché simple du téléphone se casse en 1,6 s.
- **Le journal d'audit est écrit par la base** (trigger `SECURITY DEFINER`), nomme le vrai acteur (`qui()`), est en ajout seul, et ne recopie pas les hachés de mots de passe. Contrairement au modèle de l'énoncé, `denormalisation.sql` ne le supprime jamais.
- **Aucun droit sur les tables pour les personnes** : des vues filtrées par `qui()`, avec `security_barrier`. L'apicultrice déclare par une vue `WITH CHECK OPTION`, avec un `INSERT` limité à trois colonnes. Le coordinateur valide par `valider_recolte()` seulement.
- **Un jeton ne sert qu'une fois, garanti par la base** (`UNIQUE (jeton_id)`), même avec le code vulnérable. Le code corrigé utilise en plus `UPDATE ... RETURNING`.
- **Preuves en `RESTRICT`, adhésions en `CASCADE`.**
- **Aucun mot de passe dans le dépôt** : rôles `LOGIN` sans secret, connexions par variables d'environnement.

## Limites connues

- Un superutilisateur peut désactiver les triggers du journal (`ALTER TABLE journal_audit DISABLE TRIGGER ...` passe en `postgres`). Le journal doit donc aussi être copié **hors de la base**, au fil de l'eau, vers le SIEM du cahier des charges, et le compte `postgres` réservé aux urgences.
- Le coordinateur n'a pas encore de vue sur les mesures de son site, pour comparer avant de valider (à ajouter : `v_mesures_site`).
- La transhumance n'est pas modélisée : la base n'impose pas que les ruches soient sur le site de leur apicultrice (`normalisation_j2.md`, étape 6.4).
- L'empreinte `queenbee_j2.dump.sha256` est celle de notre sauvegarde : les mesures sont aléatoires, donc une autre base donne une autre empreinte.
- `qui()` (fonction du sujet) nomme le rôle choisi par `SET ROLE`. Les personnes ne peuvent pas devenir leur groupe (`GRANT ... WITH INHERIT TRUE, SET FALSE`, `roles.sql`), mais cette option n'existe qu'à partir de PostgreSQL 16 : sur une version plus ancienne, le journal pourrait nommer `qb_admin` au lieu de la personne.
- Les rôles personnels n'ont pas encore de mot de passe : l'administrateur les pose hors du dépôt.

## Vérifications faites

- **Toute la chaîne a été reconstruite dans une base vide** (jour 1, puis les fichiers du jour 2 avec `ON_ERROR_STOP`) : aucune ERROR. Les tests de contournement donnent les mêmes 12 résultats que sur la base de travail.
- **Chaque attendu de l'énoncé a été comparé au résultat obtenu.** Les écarts viennent uniquement de notre jeu d'essai (tableau ci-dessus).
