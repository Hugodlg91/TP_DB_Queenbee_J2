# durabilite.md · TP Jour 2, Lab 9, étape 9.5

Groupe : Praveen, Ugo, Hugo, Corentin

## Les réglages

```
SHOW fsync;               -> on
SHOW synchronous_commit;  -> on
SHOW wal_level;           -> replica
```

Avec `fsync` et `synchronous_commit` à `on`, un `COMMIT` ne répond qu'une fois le journal d'écriture (WAL) enregistré sur le disque. `wal_level = replica` permet l'archivage du WAL et la réplication.

## La sauvegarde vérifiée

Commandes (depuis `jour2/4_test_concurrence`) :

```
pg_dump -U postgres -d queenbee -Fc -f queenbee_j2.dump
sha256sum queenbee_j2.dump > queenbee_j2.dump.sha256
createdb -U postgres queenbee_restore
pg_restore -U postgres -d queenbee_restore queenbee_j2.dump
sha256sum -c queenbee_j2.dump.sha256
```

Sous Windows sans `sha256sum`, on utilise `certutil -hashfile queenbee_j2.dump SHA256` et on compare à l'œil avec le fichier `.sha256`.

Résultats :

| Vérification | Résultat |
|---|---|
| empreinte (`sha256sum` et `certutil` donnent la même) | `3571bdefca04e3bda1e4d0140e47eb49b2116cf62661a8f907b2743b56488afc` |
| lignes de `journal_audit` dans `queenbee` (notre base de travail) | 4 |
| lignes de `journal_audit` dans `queenbee_restore` | **4** : le même nombre que dans la base d'origine (sur une base reconstruite, le nombre de départ peut différer ; l'important est qu'il soit identique après la restauration) |
| `DELETE FROM journal_audit;` dans la copie | `ERROR: journal_audit est en ajout seul : DELETE interdit` : le journal restauré reste protégé (ses triggers sont restaurés avec lui) |
| `sha256sum -c queenbee_j2.dump.sha256` | **`queenbee_j2.dump: OK`** |

Le fichier `queenbee_j2.dump` n'est **pas** dans le dépôt : il est gros et contient des données personnelles. Seule son empreinte, `queenbee_j2.dump.sha256`, est commitée.

Cette empreinte vaut pour **ce fichier de sauvegarde** et pour lui seul : elle prouve son intégrité, pas qu'un autre dump équivalent redonnera le même haché. Deux `pg_dump` de la même base peuvent différer (par exemple l'en-tête du format custom). Elle correspond à **notre** sauvegarde. Refaites la sauvegarde sur votre propre base : les mesures étant tirées au hasard, vous obtiendrez une autre empreinte, qu'il faudra commiter à la place.

## Les questions

**Ce qu'on perdrait avec `synchronous_commit = off`.** Le `COMMIT` répondrait **avant** que le WAL soit sur le disque. En cas de panne, les toutes dernières transactions « validées » seraient perdues : jusqu'à environ trois fois `wal_writer_delay`, soit à peu près 0,6 s par défaut. La base reste cohérente, sans corruption, mais l'application a été prévenue d'un succès qui n'existe plus : par exemple une récolte validée, ou une ligne de journal d'audit qui a disparu. Pour une preuve, c'est inacceptable.

**Pourquoi garder l'empreinte ailleurs que la sauvegarde.** Si l'empreinte est à côté du fichier, celui qui peut modifier la sauvegarde peut aussi recalculer et remplacer l'empreinte : la vérification passerait. Rangée ailleurs, elle prouve que la sauvegarde n'a pas été modifiée, à condition que l'empreinte elle-même soit protégée. Ici, l'empreinte est dans le dépôt git et la sauvegarde sur un autre support. Mais un historique git peut être réécrit : pour prouver aussi l'authenticité, il faudrait un dépôt protégé (branche protégée), ou signer l'empreinte (GPG) ou la calculer avec une clé (HMAC).

**Ce que `pg_dump` ne sauvegarde pas.** Les **objets globaux** du serveur : les **rôles** (`qb_apicultrice`, `a.diop`, `coord.casa`…), leurs appartenances et les tablespaces. Sans eux, `pg_restore` signale des erreurs sur les `GRANT`, les `REVOKE` (et sur `OWNER` si des objets appartiennent à des rôles absents). Les données sont restaurées, mais les droits sont perdus : il faut d'abord restaurer les rôles (`pg_dumpall --roles-only`). On les sauvegarde à part :

```
pg_dumpall -U postgres --roles-only -f roles_j2.sql
```

Le fichier `roles_j2.sql` ne doit pas être commité non plus, s'il contient des hachés de mots de passe.

**Durabilité ou sauvegarde.**
- La **durabilité** (le D d'ACID) garantit qu'une transaction validée **survit à une panne** du serveur, comme une coupure ou un arrêt brutal, grâce au WAL sur le disque.
- La **sauvegarde** permet de survivre à ce que la durabilité ne couvre pas : **la perte du disque**, **une erreur humaine** (un `DELETE` validé, donc durable, que l'on veut annuler), **un rançongiciel** qui chiffre le serveur.
- Il faut les deux, avec des sauvegardes hors du serveur et des restaurations testées, comme ici.
