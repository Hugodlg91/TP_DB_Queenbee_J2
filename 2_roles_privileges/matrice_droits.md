# matrice_droits.md · TP Jour 2, Lab 8

Groupe : Praveen, Ugo, Hugo, Corentin

La matrice a été remplie avant d'écrire le moindre `GRANT`. `roles.sql` la traduit ligne par ligne : la dernière colonne donne le droit qui la met en œuvre.

## Les personnes de notre base

Chaque rôle PostgreSQL porte exactement le login de son compte dans `utilisateur` : c'est ce qui relie `qui()` au compte.

| Énoncé | Notre rôle | Qui | Groupe |
|---|---|---|---|
| `f.ba` | `a.diop` | Awa Diop, SN-CASA, 1 ruche (SN-CASA-021), même téléphone que « Fatou Ba » | `qb_apicultrice` |
| `awa.diop` | `aminata.diop.casa` | Aminata Diop, SN-CASA, 2 ruches | `qb_apicultrice` |
| `coord.sn` | `coord.casa` | coordinateur de SN-CASA | `qb_coordinateur` |
| `gest.beeafrica` | `gest.beeafrica` | gestionnaire (compte ajouté dans `utilisateur` par `roles.sql`) | `qb_gestionnaire` |
| `admin.beeafrica` | `admin` | le compte administrateur du jour 1 | `qb_admin` |

## La matrice

| Objet | apicultrice | coordinateur | gestionnaire | admin | Mise en œuvre (`roles.sql`) |
|---|---|---|---|---|---|
| ses ruches et leurs mesures | lire (les siennes) | lire les ruches de son site ; mesures : non accordé au jour 2 (voir limite 3) | non (agrégats seulement, ligne « synthèse ») | non (aucun besoin métier) | `v_mes_ruches`, `v_mes_mesures` et, depuis le lab 10, `v_carte_ruches` (ses ruches, sans téléphone ; `corrections.sql`) → `qb_apicultrice` ; `v_ruches_site` → `qb_coordinateur` |
| déclarer une récolte | sur ses ruches, statut `declaree` seulement | non | non | non | `INSERT (ruche_id, date_recolte, quantite_kg)` sur `v_mes_recoltes` (`WITH CHECK OPTION`) |
| valider une récolte (UC-C02) | non | sur son site, une récolte encore déclarée, par la fonction seulement | non | non | `EXECUTE` sur `valider_recolte(uuid)` → `qb_coordinateur` ; aucun `UPDATE` sur `recolte` |
| ruches et téléphones de son site | non (ses ruches seulement, aucun téléphone) | lire | non | non | `v_ruches_site` (nom et téléphone de l'apicultrice, pour la joindre en cas d'alerte) |
| synthèse et export (UC-G01, UC-G02) | non | non | lire | non | `SELECT` sur `synthese_site_jour` et `v_export_bailleur` ; `EXECUTE` sur `hmac()` |
| comptes utilisateurs (UC-AD01) | son compte, en lecture | son compte, en lecture | son compte, en lecture | lire, créer, modifier, **sans le haché du mot de passe** ; **pas supprimer** | `v_moi` → tous ; droits par colonne sur `utilisateur` → `qb_admin` : `SELECT (id, login, role, site_id, apicultrice_id)`, `INSERT` et `UPDATE (login, role, site_id, apicultrice_id)`, jamais `mot_de_passe_hash` (le haché est posé par l'application, par un rôle de service ou une fonction `SECURITY DEFINER` de réinitialisation : l'admin ne le lit ni ne l'écrit) |
| journal d'audit | non | non | non | lire | `SELECT` sur `journal_audit` → `qb_admin` ; personne n'a `INSERT` (seul le trigger écrit, en `SECURITY DEFINER`) |

Principes appliqués :
- **tout fermer, puis ouvrir le minimum** : `REVOKE` sur la base, le schéma, les tables, les séquences et les fonctions pour `PUBLIC`. Les fonctions créées plus tard par `postgres` sont aussi fermées par défaut (`ALTER DEFAULT PRIVILEGES FOR ROLE postgres`, sans `IN SCHEMA` : un défaut limité à un schéma ne peut pas retirer le droit `EXECUTE` que `PUBLIC` reçoit globalement ; notre première version, `IN SCHEMA public`, ne faisait rien) ;
- **les droits vont aux groupes**, jamais aux personnes. Les personnes héritent des droits de leur groupe sans pouvoir devenir ce groupe (`WITH INHERIT TRUE, SET FALSE`) ;
- **aucun droit sur les tables pour les personnes** : elles lisent des vues filtrées par `qui()`, qui s'exécutent avec les droits de leur propriétaire ;
- **pas de suppression de compte par l'admin** : supprimer un compte effacerait le responsable d'actions passées (`validee_par`). On le désactive (rôle retiré, connexion fermée).

## Vérification de la matrice par les tests

Les 12 tests de `tests_contournement.sql` vérifient chaque case « non » qui compte : lire `apicultrice`, écrire chez une autre, valider soi-même, modifier un volume, écrire dans le journal, désactiver le trigger, valider hors de son site, supprimer un compte. Les **12 résultats sont ceux attendus**.

## Limites

1. **Le superutilisateur peut désactiver le journal.** En `postgres`, `ALTER TABLE journal_audit DISABLE TRIGGER journal_ajout_seul;` passe (test du point 4 de `tests_audit.sql`). Le propriétaire de la table n'est pas lié par ses propres triggers. Le journal ne prouve donc rien contre un administrateur de la base ; il doit **aussi être copié hors de la base, au fil de l'eau, vers le SIEM du cahier des charges**, où ce même administrateur n'a pas la main. En plus : un compte `postgres` réservé aux urgences, et des tables qui appartiennent à un rôle sans connexion.
2. **`qui()` repose sur le paramètre `role`** (ou sur l'utilisateur connecté). Un rôle personnel ne peut faire `SET ROLE` que vers un rôle dont il est membre avec l'option `SET`. Dans notre première version, il pouvait devenir son groupe : connecté en `admin`, `SET ROLE qb_admin` passait, et le journal nommait `qb_admin` au lieu de `admin` (constat R6 de `rapport_revue.md`). Les appartenances sont maintenant données `WITH INHERIT TRUE, SET FALSE` (PostgreSQL 16 et plus) : la personne garde les droits du groupe, mais `SET ROLE` vers le groupe est refusé (`permission denied to set role "qb_admin"`). On ne peut donc se faire passer ni pour quelqu'un d'autre, ni pour un groupe. Il ne faut jamais ajouter une personne dans le rôle d'une autre personne. Le superutilisateur `postgres` peut toujours faire `SET ROLE "a.diop"` : c'est ce qu'utilisent les tests.
3. **Le coordinateur n'a pas encore de vue sur les mesures de son site.** Pour valider une récolte (UC-C02), il compare la déclaration aux pesées. À ajouter : une vue `v_mesures_site`, filtrée comme `v_ruches_site`, avec `security_barrier`.
4. **Pas encore de mot de passe** pour les rôles personnels (`LOGIN` sans secret). C'est voulu, pour qu'aucun secret ne soit dans le dépôt ; l'administrateur les pose hors du dépôt.

## Testez-vous · Lab 8

1. **Pourquoi `ON DELETE CASCADE` sur `mesure.ruche_id` est-il un risque pour la preuve ?** Supprimer une ruche, par erreur ou pour couvrir un vol, effacerait **sans aucun message** tout son historique : la chute de poids et la position GPS qui prouvent le vol. Le test de l'étape 8.1 le montre : `DELETE 1` sur la ruche, et **4 368 mesures** de moins, sans un mot. Avec `RESTRICT`, la suppression est refusée.
2. **Que vaut `current_user` dans une fonction `SECURITY DEFINER` qui appartient à `postgres` ?** Il vaut `postgres`, le propriétaire, pendant toute l'exécution. Un journal écrit avec `current_user` accuserait toujours `postgres` et ne prouverait plus rien (R de STRIDE). C'est pourquoi `qui()` lit le paramètre `role` (le `SET ROLE`), sinon `session_user`. Résultat dans `tests_contournement.sql` : le journal nomme `a.diop` et `coord.casa`, même pour une validation faite par `valider_recolte()`.
3. **Pourquoi `INSERT` sur la vue `v_mes_recoltes` plutôt que sur la table `recolte` ?** Sur la table, l'apicultrice pourrait déclarer une récolte sur **n'importe quelle ruche**, et renseigner `statut = 'validee'`, `validee_par` ou `date_validation`. Par la vue :
   - `WITH CHECK OPTION` refuse une ruche qui n'est pas à elle (test 4) ;
   - le droit `INSERT` porte sur trois colonnes seulement, donc le statut est refusé (test 5) et prend sa valeur par défaut, `declaree`.
4. **Que risque-t-on si l'on oublie `REVOKE ALL ON FUNCTION valider_recolte(uuid) FROM PUBLIC` ?** Une fonction est exécutable par `PUBLIC` par défaut. Tout le monde, une apicultrice comprise, pourrait appeler une fonction qui s'exécute **avec les droits de `postgres`**. Il ne resterait qu'une seule barrière, le contrôle `role = 'coordinateur'` dans le code : la moindre erreur dans ce code, ou un compte mal rattaché, devient une élévation de privilège. Avec le `REVOKE`, une apicultrice est refusée avant même d'entrer dans la fonction (test 7 : `permission denied for function valider_recolte`).
