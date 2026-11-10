# concurrence.md · TP Jour 2, Lab 9

Groupe : Praveen, Ugo, Hugo, Corentin

Adaptation : les jetons sont ceux de `a.diop` (notre `f.ba`), donc `RT-a.diop-1` à `RT-a.diop-30`. Les « deux terminaux » sont deux sessions PostgreSQL distinctes (A et B), jouées dans l'ordre des temps T1, T2… Les réponses ci-dessous sont celles de PostgreSQL 18.

## Étape 9.1 · L'action et sa trace ensemble

**La trace qui ment.** On crée une table temporaire `journal_appli` et on y écrit `récolte SN-CASA-099 validée par coord.casa`. Puis `UPDATE recolte SET statut = 'validee'` sur cette ruche, **sans `validee_par`** :

```
ERROR:  new row for relation "recolte" violates check constraint "recolte_validation_tracee"
```

Le journal de l'application affirme pourtant la validation (`récolte SN-CASA-099 validée par coord.casa`), alors que la récolte est toujours `ecart` : **la trace ment**.

**La transaction.** Dans notre base de travail (après `tests_audit.sql`), `journal_audit` compte 4 lignes. Sur une base reconstruite, le nombre de départ peut différer : l'important est le +1, puis le retour au nombre de départ. Entre `BEGIN` et `ROLLBACK` :

| Commande | Réponse |
|---|---|
| validation complète (`validee_par` = coord.casa, `date_validation = now()`) | `UPDATE 1` |
| comptage de `journal_audit` | **5** (+1 : l'action et sa trace, ensemble) |
| `SELECT 1 / 0;` | `ERROR: division by zero` |
| comptage | `ERROR: current transaction is aborted, commands ignored until end of transaction block` |
| `ROLLBACK;` | `ROLLBACK` |
| comptage | **4** (le nombre de départ) ; la récolte est revenue à `ecart` |

Avec le trigger d'audit dans la même transaction, l'action et sa trace sont validées ou annulées **ensemble** : la trace ne peut plus mentir.

## Étape 9.2 · La course au jeton (`RT-a.diop-1`)

`jeton.sql` : `INSERT 0 30`. La démonstration est faite **avant** la contrainte `session_jeton_unique` (correction 3).

| Temps | Session | Commande | Réponse |
|---|---|---|---|
| T1 | A | `BEGIN;` | BEGIN |
| T2 | B | `BEGIN;` | BEGIN |
| T3 | A | `SELECT id, utilise_le FROM jeton WHERE valeur = 'RT-a.diop-1';` | 1 ligne, `utilise_le` vide : jeton libre |
| T4 | B | même `SELECT` | 1 ligne, `utilise_le` vide : **jeton libre aussi pour B** |
| T5 | A | `UPDATE jeton SET utilise_le = now() WHERE valeur = 'RT-a.diop-1';` | UPDATE 1 |
| T6 | A | `INSERT INTO session_app ... SELECT utilisateur_id, id FROM jeton WHERE valeur = 'RT-a.diop-1';` | INSERT 0 1 |
| T7 | B | même `UPDATE` | bloqué : attend le verrou de A |
| T8 | A | `COMMIT;` | COMMIT ; B reçoit alors `UPDATE 1` |
| T9 | B | même `INSERT` | INSERT 0 1 |
| T10 | B | `COMMIT;` | COMMIT |

**Résultat : 2 sessions ouvertes avec le même jeton.** Les deux sessions ont vérifié (T3, T4) avant que l'une n'agisse. Le verrou de l'`UPDATE` fait attendre B, mais pas recontrôler : son `UPDATE` n'a aucune condition sur `utilise_le`.

## Étape 9.3 · La course par un programme

| Programme | Jeton | Réponses | Sessions avec ce jeton |
|---|---|---|---|
| `course_jeton.py` | RT-a.diop-10 | requête 1 : accepté ; requête 2 : accepté | **2** |
| `course_jeton.py` | RT-a.diop-11 | requête 1 : accepté ; requête 2 : accepté | **2** |
| `course_jeton_corrige.py` | RT-a.diop-12 | requête 1 : refusé (jeton déjà utilisé ou expiré) ; requête 2 : accepté | **1** |
| `course_jeton_corrige.py` | RT-a.diop-13 | requête 1 : refusé ; requête 2 : accepté | **1** |

Le `time.sleep(0.2)` de l'énoncé suffit : pas besoin de passer à 0,5 s.

## Étape 9.4 · Les quatre corrections

**1. `SELECT ... FOR UPDATE` (RT-a.diop-2).** T3 : A lit et verrouille. T4 : **B se fige**. A fait `UPDATE`, `INSERT` et `COMMIT` ; B reçoit alors la ligne **avec `utilise_le` rempli** et fait `ROLLBACK`. Résultat : 1 session.

**2. Une seule instruction `UPDATE ... WHERE utilise_le IS NULL AND expire_le > now() RETURNING id` (RT-a.diop-3).** A reçoit l'id. B attend, puis, après le `COMMIT` de A, reçoit **0 ligne**. Résultat : 1 session. Cette protection dépend du niveau d'isolation : en `READ COMMITTED`, PostgreSQL réévalue le `WHERE` ; en `REPEATABLE READ`, le même `UPDATE` échoue avec `could not serialize access due to concurrent update`.

**3. `UNIQUE (jeton_id)`.**
- Premier essai : `ERROR: could not create unique index "session_jeton_unique"`, car les tests ont laissé 3 jetons en double (RT-a.diop-1, -10, -11, deux sessions chacun).
- Nettoyage : on garde la plus ancienne session de chaque jeton (`DELETE 3`), puis `ALTER TABLE` passe.
- Relance du programme **vulnérable** sur RT-a.diop-14 : requête 1 acceptée ; requête 2 `erreur de la base : duplicate key value violates unique constraint "session_jeton_unique"`. **1 session**. La contrainte est dans `jeton.sql`.

**Rejouer la démonstration vulnérable.** Après une reconstruction, `jeton.sql` pose déjà `session_jeton_unique` : `course_jeton.py` ne donne plus « 2 sessions », mais 1 session et l'erreur `duplicate key`. Pour revoir la course, on retire la contrainte, on lance le programme sur un jeton non utilisé, puis on nettoie et on remet la contrainte :

```
ALTER TABLE session_app DROP CONSTRAINT session_jeton_unique;
python course_jeton.py RT-a.diop-N
```

Résultat : requête 1 et requête 2 acceptées, 2 sessions. Pour remettre la contrainte, il faut d'abord supprimer le doublon, en gardant la plus ancienne session de chaque jeton (comme au point 3) :

```
DELETE FROM session_app s USING session_app t
 WHERE s.jeton_id = t.jeton_id AND (s.ouverte_le, s.id) > (t.ouverte_le, t.id);
ALTER TABLE session_app ADD CONSTRAINT session_jeton_unique UNIQUE (jeton_id);
```

Relancer `jeton.sql` repart aussi de zéro : il fait `DROP TABLE IF EXISTS session_app, jeton CASCADE`, recrée les 30 jetons et repose la contrainte.

**4. `REPEATABLE READ` (RT-a.diop-4).** Les deux sessions lisent le jeton libre ; A fait son `UPDATE` ; l'`UPDATE` de B attend, puis, après le `COMMIT` de A, échoue : `ERROR: could not serialize access due to concurrent update`. Résultat : 1 session ; B doit annuler et réessayer, et verra alors le jeton utilisé.

| Correction | Où agit-elle ? | Que voit la seconde requête ? | Avantage | Limite |
|---|---|---|---|---|
| `SELECT ... FOR UPDATE` | dans le code de l'application (verrou de ligne posé à la lecture) | elle attend, puis lit le jeton déjà utilisé | simple ; garde la logique « vérifier, puis agir » lisible | chaque développeur doit y penser, dans chaque code ; un oubli suffit ; les verrous peuvent créer des attentes ou des interblocages |
| `UPDATE ... WHERE ... RETURNING` | dans la requête : vérifier et agir en une instruction atomique | elle attend, puis 0 ligne (condition réévaluée sur la version validée) | sûr sans verrou explicite, une seule requête, rapide | ne protège que ce code ; un autre programme qui fait « vérifier, puis agir » reste vulnérable |
| `UNIQUE (jeton_id)` | dans la base, quel que soit le programme | `duplicate key value violates unique constraint` | **garantie au niveau des données**, même pour du code vulnérable ou un accès direct | il faut d'abord nettoyer les doublons ; l'application doit traiter l'erreur proprement |
| `REPEATABLE READ` | dans la transaction (niveau d'isolation) | `could not serialize access due to concurrent update` | détecte le conflit sans verrou explicite | l'application doit savoir réessayer ; plus d'échecs sous forte charge |

**Le trigger du lab 6 est-il, lui aussi, contournable par deux insertions simultanées ?** **Oui, et nous l'avons démontré.** Deux sessions inscrivent Mariama Ba (+221 77 200 00 04), l'une chez Moussa Sarr, l'autre chez Ibrahima Fall, deux formateurs varroa :

| Temps | Session | Commande | Réponse |
|---|---|---|---|
| T1, T2 | A, B | `BEGIN;` | BEGIN |
| T3 | A | inscription chez Moussa Sarr | INSERT 0 1 |
| T4 | B | inscription chez Ibrahima Fall | **INSERT 0 1** (le trigger ne voit pas la ligne de A, non validée) |
| T5, T6 | A, B | `COMMIT;` | COMMIT, COMMIT |

Résultat : `varroa | {Ibrahima Fall, Moussa Sarr}`, et la règle est violée.

**Ce qui le protège** :
- la **contrainte** de « Pour aller plus loin » (`UNIQUE (apicultrice_id, theme)`), qui est la meilleure garantie ;
- ou un **verrou** : c'est la correction appliquée dans `corrections.sql` (constat R2). Le trigger verrouille d'abord la ligne de l'apicultrice (`FOR NO KEY UPDATE`). Retest : B attend, puis reçoit `DF violée : cette apicultrice a déjà un formateur pour ce thème`, et Mariama Ba garde un seul formateur varroa.

## Testez-vous · Lab 9

1. **Pourquoi l'invite devient-elle `queenbee=!#` après une erreur dans une transaction ?** La transaction est **avortée**. Le `!` de l'invite `=!#` signale cette transaction en échec. PostgreSQL refuse toute commande (`current transaction is aborted, commands ignored until end of transaction block`) pour ne pas valider un état à moitié fait. Il faut taper **`ROLLBACK;`** (ou `ROLLBACK TO SAVEPOINT ...` si un point de sauvegarde existe).
2. **Pourquoi `READ COMMITTED` ne protège-t-il pas de la course au jeton ?** Chaque instruction voit les données validées **au moment où elle commence**. Les deux `SELECT` voient le jeton libre, puisque aucune des deux sessions n'a encore validé. Ensuite, l'`UPDATE` de B attend le verrou de A, puis s'applique quand même : il n'a aucune condition sur `utilise_le`. Rien n'oblige B à revérifier.
3. **Pourquoi `UPDATE ... WHERE utilise_le IS NULL RETURNING id` est-il sûr, sans verrou explicite ?** La vérification et l'action sont **une seule instruction**. L'`UPDATE` pose lui-même un verrou sur la ligne. Quand B obtient ce verrou après le `COMMIT` de A, PostgreSQL **réévalue la condition `WHERE`** sur la nouvelle version de la ligne : `utilise_le` n'est plus vide, donc B touche 0 ligne.
4. **Un rançongiciel chiffre le serveur. ACID vous protège-t-il ?** Non. La durabilité protège les transactions validées contre une **panne** (coupure de courant, arrêt brutal), sur le même disque. Un rançongiciel chiffre ce disque, journal WAL compris. Ce qui protège :
   - des **sauvegardes hors du serveur**, dont une hors ligne ou immuable (règle 3-2-1) ;
   - des restaurations **testées** et des **empreintes** vérifiées (`durabilite.md`) ;
   - des identifiants de sauvegarde séparés de ceux du serveur.
