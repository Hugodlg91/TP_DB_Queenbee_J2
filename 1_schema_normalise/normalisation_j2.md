# normalisation_j2.md · TP Jour 2, Labs 6 et 7

Groupe : Praveen, Ugo, Hugo, Corentin

Les résultats ci-dessous ont été obtenus sur notre base du jour 1 (PostgreSQL 18). Le tableau des formations de l'énoncé a été adapté aux téléphones de nos apicultrices (correspondance en tête de `formation.sql`) : **Awa Diop (+221 77 100 00 02) joue le rôle de « Fatou Ba »**, avec le même numéro.

Les requêtes tapées dans psql sont rassemblées dans `requetes_j2.sql`, étape par étape, avec le résultat obtenu sur une base reconstruite (PostgreSQL 16). Ce fichier ne laisse rien dans la base (transactions annulées). Les temps et les poids tirés au hasard y diffèrent un peu des nôtres, c'est normal.

---

## Lab 6 · Décomposer sans rien perdre

### Étape 6.1 · Analyser la table reçue

`formation.sql` : `CREATE TABLE`, puis `INSERT 0 8`.

**Dépendances fonctionnelles**

| DF | En français |
|---|---|
| (`telephone`, `theme`) → `formateur` | pour un thème, une apicultrice n'a qu'un formateur, celui qui signe son attestation |
| `formateur` → `theme` | un formateur n'enseigne qu'un thème |

**Clés candidates**

- (`telephone`, `theme`) : sa fermeture donne `formateur`, donc les 3 colonnes ;
- (`telephone`, `formateur`) : `formateur` → `theme`, donc les 3 colonnes aussi.

Aucune n'a de sous-ensemble strict qui soit une clé. Par les fermetures : `telephone`⁺ = {`telephone`}, `theme`⁺ = {`theme`}, `formateur`⁺ = {`formateur`, `theme`}. Aucune ne donne les 3 colonnes, donc aucun attribut seul n'est une clé, et les deux clés sont minimales. Les données l'illustrent : `telephone` seul a plusieurs thèmes, et `theme` comme `formateur` seuls ont plusieurs apicultrices.

**Les trois tests sur les données** (`GROUP BY ... HAVING`, requêtes dans `requetes_j2.sql`) : 0 ligne chacun.
- (`telephone`, `theme`) → `formateur` : 0 ligne.
- `formateur` → `theme` : 0 ligne.
- (`telephone`, `formateur`) est bien une clé (pas de doublon) : 0 ligne.

**3NF ? Oui.** Toute colonne qui est en partie droite d'une DF est *première* : elle fait partie d'une clé. C'est le cas de `formateur` (clé 2) et de `theme` (clé 1), et la 3NF tolère une partie gauche non clé quand la partie droite est première.

**BCNF ? Non.** `formateur` → `theme` a une partie gauche, `formateur`, qui n'est pas une super-clé.

**L'anomalie** (entre `BEGIN` et `ROLLBACK`, requête dans `requetes_j2.sql`) : Moussa Sarr passe en `capteurs` sur la ligne de +221 77 100 00 02. La table l'accepte sans un mot, puis la recherche des formateurs à plusieurs thèmes renvoie :

```
  formateur  |     array_agg
-------------+-------------------
 Moussa Sarr | {capteurs,varroa}
```

La règle `formateur` → `theme` est violée : le thème de Moussa Sarr est écrit sur plusieurs lignes, et une seule copie a changé.

### Étape 6.2 · Découper, et prouver qu'on n'a rien perdu

**Le mauvais découpage** : `p1(telephone, theme)` et `p2(theme, formateur)`. La jointure donne **16 lignes au lieu de 8**, dont **8 inventées** (`EXCEPT`, requêtes dans `requetes_j2.sql`) :

```
     telephone     | theme  |   formateur
-------------------+--------+---------------
 +221 77 100 00 01 | varroa | Ibrahima Fall
 +221 77 100 00 01 | varroa | Kouassi Yao
 +221 77 100 00 02 | varroa | Ibrahima Fall
 +221 77 100 00 02 | varroa | Kouassi Yao
 +221 77 200 00 03 | varroa | Kouassi Yao
 +221 77 200 00 03 | varroa | Moussa Sarr
 +225 07 300 00 05 | varroa | Ibrahima Fall
 +225 07 300 00 05 | varroa | Moussa Sarr
```

Awa Diop (+221 77 100 00 02, notre « Fatou Ba ») serait suivie par trois formateurs varroa. **Pourquoi :** la colonne commune, `theme`, n'est la clé d'aucun des deux morceaux. Un thème a plusieurs apicultrices dans `p1` et plusieurs formateurs dans `p2`, donc la jointure associe chaque apicultrice à tous les formateurs du thème.

**Le bon découpage** : `formateur(id, nom UNIQUE, theme)` et `suivi_formation(apicultrice_id, formateur_id)`. La colonne commune est le formateur, clé de son morceau.
- Remplissage : `INSERT 0 5` (formateurs), puis `INSERT 0 8` (suivis).
- Double comparaison `EXCEPT` (recomposition par `suivi_formation` ⋈ `apicultrice` ⋈ `formateur`, requête dans `requetes_j2.sql`) : **0 ligne**. Rien de perdu, rien d'inventé.

**Quelle contrainte garantit `formateur` → `theme` ?** Le `UNIQUE` sur `formateur.nom`, avec la colonne `theme NOT NULL` dans la même ligne. Il n'existe qu'une ligne par formateur, donc un seul thème. Le `CHECK (theme IN ('varroa', 'recolte', 'capteurs'))` limite en plus les valeurs possibles.

**Pourquoi `suivi_formation` pointe-t-elle vers `apicultrice(id)` au lieu de recopier le téléphone ?**
- **Une seule copie** du téléphone, une donnée personnelle (minimisation) : si l'apicultrice change de numéro, rien d'autre n'est à corriger.
- **La clé étrangère garantit** que l'apicultrice existe ; un téléphone recopié pourrait désigner personne.
- **L'`id` ne change jamais** et ne révèle rien par lui-même, alors qu'un téléphone peut être partagé ou réattribué (limite connue du jour 1). Il reste pourtant une donnée personnelle, pseudonymisée : il désigne une personne, et la base permet de la retrouver.

### Étape 6.3 · La règle perdue, et le trigger qui la rétablit

**La règle perdue.** Après le découpage, plus aucune table ne contient à la fois l'apicultrice et le thème. Le trigger étant déjà dans `formation.sql`, nous l'avons désactivé dans une transaction annulée pour montrer ce que la base accepterait sans lui (requêtes dans `requetes_j2.sql`) :
- inscription d'Awa Diop chez Ibrahima Fall (varroa) : `INSERT 0 1` ;
- recherche des apicultrices qui ont deux formateurs pour un même thème :

```
   nom    | theme  |            array_agg
----------+--------+---------------------------------
 Awa Diop | varroa | {"Moussa Sarr","Ibrahima Fall"}
```

Puis `ROLLBACK` : la ligne fautive est supprimée.

**Le trigger** (`suivi_un_formateur_par_theme()`, trigger `suivi_formation_df`) :

```
-- Awa Diop chez Ibrahima Fall (varroa, elle a déjà Moussa Sarr)
ERROR:  DF violée : cette apicultrice a déjà un formateur pour ce thème
-- Awa Diop chez Khady Ndiaye (récolte, thème nouveau pour elle)
INSERT 0 1
```

**Une limite du modèle repris de GreenFarm.** La condition `s.formateur_id <> NEW.formateur_id` refuse à tort un changement légitime : remplacer le formateur d'une apicultrice par un autre du même thème. Pour Awa Diop, avec la fonction de `formation.sql`, `UPDATE suivi_formation SET formateur_id = <Ibrahima Fall>` sur sa ligne Moussa Sarr répond `DF violée` (requête dans `requetes_j2.sql`). L'ancienne version de la ligne (Moussa Sarr, varroa) est encore visible, et son formateur est bien différent du nouveau. Il faut exclure la ligne elle-même (`OLD`), ce que fait la version de `corrections.sql` : après elle, le même remplacement répond `UPDATE 1`. Nous gardons dans `formation.sql` la version de l'énoncé.

**La règle était aussi contournable par la table `formateur`.** Le trigger ne surveille que `suivi_formation`, or le thème est lu dans `formateur`. Sans autre garde, `UPDATE formateur SET theme = 'varroa' WHERE nom = 'Khady Ndiaye'` passait sans message, et Aminata Diop (+221 77 100 00 01) se retrouvait avec deux formateurs varroa, Khady Ndiaye et Moussa Sarr. Nous avons ajouté à la fin de `formation.sql` un second trigger, `formateur_theme_df` (`BEFORE UPDATE OF theme ON formateur`), qui refuse ce changement :

```
ERROR:  DF violée : Khady Ndiaye ne peut pas passer en varroa, une de ses apicultrices a déjà un formateur pour ce thème
```

Un changement de thème sans conflit passe toujours (Kouassi Yao en capteurs : `UPDATE 1`). Une règle portée par trigger doit donc surveiller **toutes** les tables d'où elle lit ses données : c'est un argument de plus pour la variante à contrainte ci-dessous, où la clé étrangère composée fait ce travail toute seule.

**Pour aller plus loin : la même garantie sans trigger.** On recopie le thème dans le suivi, avec `UNIQUE (apicultrice_id, theme)` et une clé étrangère composée `(formateur_id, theme) REFERENCES formateur (id, theme)`, qui demande `UNIQUE (id, theme)` sur `formateur`. Testé dans une transaction annulée (requêtes dans `requetes_j2.sql`) :
- Awa Diop + Ibrahima Fall (varroa) : `duplicate key value violates unique constraint "suivi_formation_v2_apicultrice_id_theme_key"` ;
- Moussa Sarr déclaré « capteurs » pour tricher sur le thème : `violates foreign key constraint "suivi_formation_v2_formateur_id_theme_fkey"` ;
- Khady Ndiaye passée en varroa par la table `formateur` (second trigger désactivé) : refusé aussi par cette clé étrangère, car le thème est encore référencé dans `suivi_formation_v2`.

**Est-ce encore en BCNF ? Non.** Dans `suivi_formation_v2(apicultrice_id, formateur_id, theme)`, `formateur_id` → `theme` alors que `formateur_id` n'est pas une super-clé. Les clés sont (`apicultrice_id`, `formateur_id`) et (`apicultrice_id`, `theme`). La table est en **3NF** (`theme` est premier), comme `formation_plat`. Mais la copie du thème ne peut plus diverger, puisque la clé étrangère composée l'oblige à rester égale au thème du formateur. On accepte une redondance **contrôlée** pour que la règle soit portée par un index unique, qui résiste aux insertions simultanées, contrairement au trigger (lab 9, `concurrence.md`).

La correction du trigger dans `corrections.sql` (verrou sur la ligne de l'apicultrice) ne vaut qu'en `READ COMMITTED`, le niveau par défaut : la seconde inscription attend, puis relit les lignes validées. En `REPEATABLE READ`, elle garde sa photo du début de transaction et ne voit pas la première : essayé avec deux sessions sur Mariama Ba (Moussa Sarr, puis Ibrahima Fall), les deux inscriptions passent. En `SERIALIZABLE`, la seconde échoue, mais par le contrôle de sérialisation de PostgreSQL (`could not serialize access`), pas grâce au verrou. La contrainte `UNIQUE`, elle, tient à tout niveau d'isolation.

### Étape 6.4 · Revue BCNF de tout le schéma

Méthode : pour chaque table, la clé primaire détermine tout, et chaque `UNIQUE` aussi. On cherche ensuite une autre DF dont la partie gauche ne serait pas une super-clé.

| Table | Dépendances | Partie gauche = super-clé ? | BCNF ? |
|---|---|---|---|
| `site` | `id` → `nom`, `pays` | oui | oui |
| `cooperative` | `id` → `nom`, `site_id` | oui | oui |
| `apicultrice` | `id` → tout ; `telephone` (UNIQUE) → tout | oui (deux clés) | oui |
| `ruche` | `id` → tout ; `code` (UNIQUE) → tout | oui | oui (sur `site_id`, voir ci-dessous) |
| `adhesion` | (`apicultrice_id`, `cooperative_id`) → `date_adhesion` | oui | oui |
| `utilisateur` | `id` → tout ; `login` (UNIQUE) → tout ; `apicultrice_id` (UNIQUE, quand il est rempli) → tout | oui | oui (mais `site_id` recopie un fait d'une autre table, voir ci-dessous) |
| `mesure` | `id` → tout ; (`ruche_id`, `horodatage`) (UNIQUE anti-rejeu) → tout | oui | oui |
| `inspection` | `id` → tout | oui | oui (`apicultrice_id` n'est pas une copie, voir ci-dessous) |
| `recolte` | `id` → tout | oui | oui |
| `alerte` | `id` → tout | oui | oui |
| `formateur` | `id` → `nom`, `theme` ; `nom` (UNIQUE) → `id`, `theme` | oui | oui |
| `suivi_formation` | aucune DF non triviale (clé = les deux colonnes) | oui | oui |
| `jeton` (créée au lab 9, `jeton.sql`) | `id` → tout ; `valeur` (UNIQUE) → tout | oui | oui |
| `session_app` (créée au lab 9, `jeton.sql`) | `id` → tout ; `jeton_id` (UNIQUE, lab 9) → tout | oui | oui |
| `journal_audit` | `id` → tout | oui | oui |
| `cle_pseudonymisation` | `id` → `cle` (une seule ligne) | oui | oui |
| `synthese_site_jour` (vue matérialisée) | (`site_id`, `jour`) → agrégats | oui | oui, mais c'est une **copie voulue** (lab 7) |
| `formation_plat` | `formateur` → `theme` | **non** | **non** : gardée comme trace du fichier reçu ; la donnée de travail est dans `formateur` et `suivi_formation`. Elle garde une **seconde copie des téléphones** : il faudrait la vider après l'import, ou la fermer à tous avec une durée de conservation |
| `extrait_plat` (jour 1) | DF1 à DF3 du jour 1 | non | non : table d'exercice du jour 1 (1NF seulement) ; les tables `norm.*` sont en BCNF (lignes suivantes) |
| `norm.site` (jour 1) | `site_id` → `site_nom`, `pays` | oui | oui |
| `norm.apicultrice` (jour 1) | `telephone` → `apicultrice`, `cooperative` | oui (la clé est `telephone`) | oui, mais la clé est une donnée personnelle (limite du jour 1) |
| `norm.ruche` (jour 1) | `ruche_code` → `site_id`, `telephone` | oui | oui |
| `norm.mesure` (jour 1) | (`ruche_code`, `horodatage`) → `poids_kg`, `temp_int_c` | oui | oui |

Les tables `norm.*` et `extrait_plat` sont des tables d'exercice du jour 1 : chacune est en BCNF (ou pas) pour elle-même, mais ensemble elles recopient des données de `public` (dont les téléphones). Elles n'ont pas leur place dans une base de production.

**`apicultrice.site_id` et `ruche.site_id` : le même fait écrit deux fois ?** Pour chaque apicultrice, le site de ses ruches (requête dans `requetes_j2.sql`) :

```
      nom       | site_apicultrice | sites_ruches
----------------+------------------+--------------
 Adjoua Kouassi | CI-YAMO          | {CI-YAMO}
 Aya Kone       | CI-YAMO          | {CI-YAMO}
 Brigitte Ngono | CM-BAFO          | {CM-BAFO}
 Esther Fotso   | CM-BAFO          | {CM-BAFO}
 Aminata Diop   | SN-CASA          | {SN-CASA}
 Awa Diop       | SN-CASA          | {SN-CASA}
 Aminata Diop   | SN-KOLD          | {SN-KOLD}
 Mariama Ba     | SN-KOLD          | {SN-KOLD}
(8 lignes)
```

Chaque apicultrice n'a de ruches que sur son site.

**Règle métier ou coïncidence ?** Règle métier : une ruche est sur le site de son apicultrice. Mais avec une exception déclarée, la **transhumance planifiée** (UC-CY04) : une ruche peut être déplacée pour un temps vers un autre site. C'est l'hypothèse de notre `annotations.md` du jour 1 (question 4 : « Non, sauf pendant une transhumance déclarée »). Ce n'est donc pas une DF stricte : `ruche.site_id` (où est la ruche aujourd'hui) et `apicultrice.site_id` (où l'apicultrice est rattachée) sont égaux en temps normal, et peuvent différer pendant une transhumance. Pas de clé étrangère composée (`apicultrice_id`, `site_id`) vers `apicultrice (id, site_id)` : elle interdirait toute transhumance, ce qui contredit le métier.

**Ce qui garantit la cohérence dans notre schéma** : rien aujourd'hui, au niveau de la base. Le test 7 du jour 1 le constate (`tests_schema.sql`), et la détection d'un déplacement non déclaré repose sur la position GPS des mesures. Pour la garantir, il faudrait une entité TRANSHUMANCE (ruche, site de destination, période) et un trigger sur `ruche` qui refuse un site différent de celui de l'apicultrice hors d'une transhumance déclarée en cours.

**Une vraie copie : `utilisateur.site_id`.** Pour un compte du rôle `apicultrice`, `site_id` recopie `apicultrice.site_id` (le compte est rattaché au site de son apicultrice). Ici, pas d'exception métier : c'est une copie qui peut diverger. Aujourd'hui les deux sont égaux (0 ligne, requête dans `requetes_j2.sql`), mais rien ne l'impose. Les vues filtrées du lab 8 lisent `utilisateur.site_id` pour le coordinateur ; celles de l'apicultrice passent par `apicultrice_id`, donc un site faux sur son compte n'ouvre rien aujourd'hui. Mais `v_moi` l'affiche, et toute future vue ou règle de sécurité par site (RLS) le lirait : un compte rattaché au mauvais site verrait alors les données d'un autre site. Deux corrections possibles :
- imposer `site_id IS NULL` pour le rôle `apicultrice` (il faut alors modifier le `CHECK` `utilisateur_site_si_terrain`, qui l'exige aujourd'hui) et lire le site par la jointure avec `apicultrice` ;
- ou garder la colonne, avec une clé étrangère composée (`apicultrice_id`, `site_id`) → `apicultrice (id, site_id)`, qui demande `UNIQUE (id, site_id)` sur `apicultrice`. C'est la limite 2 de notre jour 1 (`RENDU.md`), déjà testée dans une transaction annulée.

**Pas une copie : `inspection.apicultrice_id`.** Elle désigne l'apicultrice qui a fait l'inspection, pas forcément la propriétaire de la ruche (entraide entre voisines, hypothèse du jour 1, `annotations.md` question 4). Ce n'est pas `ruche.apicultrice_id` écrit deux fois.

### Testez-vous · Lab 6

1. **R(A, B, C) avec A → B.** (A, B) + (A, C) est **sans perte** : la colonne commune A est la clé de (A, B), puisque A → B (théorème de Heath). (A, B) + (B, C) **peut inventer des lignes** : la colonne commune B n'est la clé d'aucun morceau. Rien ne dit B → A ni B → C, et un même B peut avoir plusieurs A et plusieurs C.
2. **Pourquoi `formation_plat` est-elle en 3NF ?** La 3NF accepte X → A quand X n'est pas une super-clé, à condition que A soit *premier*, c'est-à-dire membre d'une clé candidate. `theme` appartient à la clé (`telephone`, `theme`) : la 3NF est respectée. La BCNF, plus stricte, exige une super-clé à gauche, sans exception.
3. **Pourquoi `s.formateur_id <> NEW.formateur_id` ?** Le trigger est aussi `BEFORE UPDATE`. Lors d'un `UPDATE`, l'ancienne version de la ligne est encore visible. Sans cette condition, un `UPDATE` qui garde la même apicultrice et un formateur du même thème (le même formateur, ou un autre du même thème) trouverait sa propre ancienne version et serait refusé à tort. Un `UPDATE` vers un formateur d'un autre thème passerait, lui : ce n'est donc pas « tout `UPDATE` ». À l'insertion, le doublon exact (même formateur) relève de la clé primaire, pas de cette règle.
   Mais la condition ne suffit pas : pour un changement de formateur dans le même thème (Moussa Sarr remplacé par Ibrahima Fall), l'ancienne version a un autre `formateur_id`, elle est donc trouvée, et le remplacement est refusé à tort (étape 6.3). La bonne condition exclut la ligne elle-même (`OLD`) : c'est la version de `corrections.sql`.
4. **Rester en 3NF plutôt que BCNF.**
   - Avantage : la DF (`telephone`, `theme`) → `formateur` reste portée par la clé primaire, donc vérifiée par un index unique, sans trigger, y compris pour des insertions simultanées.
   - Inconvénient : `formateur` → `theme` est recopiée sur plusieurs lignes, d'où l'anomalie de mise à jour (Moussa Sarr avec deux thèmes, sans aucun message).

---

## Lab 7 · Dénormaliser, en connaissance de cause

### Étape 7.1 · Mesurer avant de copier

`volume.sql` : `INSERT 0 47520` (11 ruches × 90 jours × 48 mesures), puis `ANALYZE`.

Tableau de bord du gestionnaire (UC-G01) pour SN-CASA, sur les 3 derniers jours (requête dans `requetes_j2.sql`, avec les jours découpés en UTC comme dans la synthèse) :

```
    jour    | nb_mesures | poids_moyen | poids_min | batterie_min
------------+------------+-------------+-----------+--------------
 2027-03-14 |        144 |       37.27 |     30.19 |           73
 2027-03-13 |        144 |       32.63 |     30.09 |           90
 2027-03-12 |        144 |       32.36 |     30.04 |           90
```

Notre site SN-CASA a **3 ruches** (et non 4 comme dans l'énoncé), d'où **144 mesures par jour** (3 × 48) au lieu de 192. Les poids sont tirés au hasard : ils changent à chaque reconstruction.

**EXPLAIN ANALYZE sur les mesures brutes : Execution Time 9,785 ms.** La requête parcourt toute la table `mesure` (`Seq Scan`), puis joint, trie et regroupe. La table compte 48 048 lignes sur une base reconstruite (47 520 + 528 du jour 1) ; notre base de travail en comptait 48 049, avec une mesure de test en plus.

### Étape 7.2 · La synthèse, et son prix

`synthese_site_jour`, avec son index unique `synthese_site_jour_pk (site_id, jour)`.

**EXPLAIN ANALYZE sur la synthèse : Execution Time 0,071 ms**, avec les mêmes chiffres (144 | 37.27 | 30.19 | 73…). C'est environ **140 fois plus rapide** : un `Bitmap Index Scan` sur l'index unique (ou un `Index Scan Backward` sur ce même index, une fois les statistiques de la vue calculées), au lieu de relire toutes les mesures (requête dans `requetes_j2.sql`).

**Le prix : le retard.** Le 15 mars à 6 h, SN-CASA-014 (notre équivalent de SN-CASA-011) tombe à **8,40 kg** (vol, UC-CY04 ; scénario dans `requetes_j2.sql`, dans une transaction annulée) :
- après l'`INSERT`, la synthèse s'arrête au 14 mars : rien d'anormal ;
- après `REFRESH MATERIALIZED VIEW CONCURRENTLY synthese_site_jour`, la ligne `2027-03-15 | 1 | 8.40` apparaît, avec `poids_min = 8.40`.

**Si la vue n'est rafraîchie que la nuit**, le vol reste invisible jusqu'au rafraîchissement suivant : il n'apparaît que la nuit suivante. Le retard va jusqu'à **24 heures** dans le pire cas (vol juste après le rafraîchissement) ; dans notre scénario (vol à 6 h, rafraîchissement à 2 h), il est d'environ **20 heures**. C'est assez pour que les ruches soient loin. **Un vol se détecte donc sur les mesures brutes, à leur arrivée** (règle ou trigger sur l'insertion : chute de poids, position GPS qui s'écarte de la référence), jamais dans une synthèse. La synthèse sert au pilotage, pas à l'alerte.

**Qui lance le rafraîchissement ?** Personne, si on ne le prévoit pas : PostgreSQL ne rafraîchit jamais une vue matérialisée tout seul. Nous proposons une tâche planifiée chaque nuit à 2 h (extension `pg_cron`, ou un timer système qui lance `psql`). Le détail, et le coût de `CONCURRENTLY` (toute l'agrégation est recalculée sur toute la table `mesure`), sont en commentaire dans `denormalisation.sql`.

**Une autre limite : le site actuel de la ruche.** La synthèse regroupe les mesures par `ruche.site_id`, c'est-à-dire le site de la ruche **aujourd'hui**. Après une transhumance puis un `REFRESH`, toutes les anciennes mesures de la ruche passent au nouveau site : l'historique de l'ancien site change après coup. Pour l'éviter, il faudrait historiser l'affectation de site (l'entité TRANSHUMANCE, avec sa période, vue à l'étape 6.4) et regrouper chaque mesure par le site où était la ruche à son horodatage.

### Étape 7.3 · L'export pour le bailleur

**Casser un haché simple.** On calcule `sha256` du téléphone d'Awa Diop (notre « Fatou Ba »), puis on essaie le million de numéros qui commencent par `+221 77 1` (requêtes dans `requetes_j2.sql`) : **`+221 77 100 00 02` retrouvé en 1 557 ms** (`\timing on`). Un haché sans clé n'est pas un pseudonyme sûr : l'espace des téléphones est trop petit.

**La vue `v_export_bailleur`** : pseudonyme = `HMAC-SHA256(id de l'apicultrice, clé secrète)`, tronqué à 12 caractères. La clé est dans `cle_pseudonymisation`, fermée à PUBLIC.

- Résultat : **8 lignes pour 11 ruches** (deux ruches voisines d'une même apicultrice tombent dans la même case de 0,1 degré), par exemple `829747eb9152 | Sénégal | SN-CASA | 12.6 | -16.3 | 2 | 12.40` (14.00 après les tests du lab 8, qui modifient cette récolte).
- Vérification de la clé : `SELECT position((SELECT cle FROM cle_pseudonymisation) IN pg_get_viewdef('v_export_bailleur')) > 0;` donne **`f`** (requête dans `requetes_j2.sql`). `position` renvoie un entier (0 si la clé est absente) : c'est le `> 0` qui donne le booléen. La clé n'est pas écrite dans la définition de la vue : elle est lue dans la table à l'exécution.

**Colonnes retirées, et pourquoi chacune**

| Colonne retirée | Pourquoi |
|---|---|
| `nom` | identifie directement la personne ; deux « Aminata Diop » montrent en plus qu'un nom n'est même pas une clé |
| `telephone` | identifiant direct, et donnée exploitable pour l'hameçonnage |
| `apicultrice.id` en clair | permettrait de recouper avec la base ou un autre export : il est remplacé par son HMAC |
| `ruche.code` (`SN-CASA-014`) | identifiant stable, recoupable, qui révèle le site et le numéro de la ruche |
| `latitude`, `longitude` précises | mènent à la ruche, donc au vol : arrondies à 0,1 degré (environ 11 km) |
| dates et détail des récoltes, mesures, inspections | inutiles au bailleur (minimisation) : seul le total validé est exporté |

**Deux choix gardés, en le sachant** (commentés dans `denormalisation.sql`) :
- `nb_ruches` reste : le bailleur finance des ruches et suit leur nombre. C'est un agrégat, mais sur un petit site, avec le site et la position approchée, c'est un quasi-identifiant (sur SN-CASA, une seule apicultrice a 2 ruches dans sa case) ;
- le pseudonyme est stable d'un export à l'autre (la clé ne change pas) : c'est voulu, pour suivre une apicultrice dans le temps. Mais le bailleur peut lui aussi la suivre et recouper ses exports. Pour l'empêcher, il faudrait une clé par export.

### Étape 7.4 · Le journal d'audit

`denormalisation.sql` se relance sans erreur. Deux écarts volontaires avec le modèle de l'énoncé :
- **le journal n'est jamais supprimé** : `CREATE TABLE IF NOT EXISTS` au lieu de `DROP TABLE` ;
- **la clé de pseudonymisation n'est créée qu'une fois** : sinon tous les pseudonymes changeraient à chaque relance.

1. **Pourquoi `ligne_id` n'est-il pas une clé étrangère vers la récolte ?** Le journal doit survivre à la ligne qu'il décrit.
   - Avec une clé étrangère `NO ACTION` ou `RESTRICT`, une récolte journalisée ne pourrait plus jamais être supprimée.
   - Avec `CASCADE`, supprimer la récolte effacerait sa trace : c'est justement l'action à prouver.
   - Avec `SET NULL`, on perdrait le lien.
   - Enfin, le journal couvre plusieurs tables (`recolte`, `utilisateur`) : une seule colonne ne peut pas pointer vers toutes.
2. **`avant` et `apres` recopient des lignes entières : est-ce acceptable ?** Oui, c'est le rôle d'un journal de preuve : il doit montrer l'état exact avant et après, même si la ligne est modifiée ou supprimée ensuite. C'est une copie voulue, en ajout seul, lisible par l'admin seulement. Avec deux limites, au nom de la minimisation :
   - **ne pas recopier de secret** : le haché du mot de passe a été retiré du journal (constat R1 de `rapport_revue.md`) ;
   - **fixer une durée de conservation** (RGPD).
3. **Pourquoi `clock_timestamp()` et pas `now()` ?** `now()` renvoie l'heure du **début** de la transaction. Toutes les lignes d'une même transaction auraient la même heure, et on ne pourrait plus ordonner les actions. `clock_timestamp()` donne l'heure réelle de chaque écriture.

### Testez-vous · Lab 7

1. **Vue ou vue matérialisée ?** Une vue est une requête enregistrée, recalculée à chaque lecture : elle est toujours à jour. Une vue matérialisée stocke son résultat : sa lecture est immédiate, mais elle **est en retard** jusqu'au prochain `REFRESH`.
2. **Deux raisons de refuser `md5(nom)` comme pseudonyme.**
   - Sans clé secrète, le haché se casse en essayant une liste de noms (attaque par dictionnaire), comme le téléphone à l'étape 7.3, et MD5 est en plus très rapide à calculer.
   - Le nom n'est pas un identifiant : les deux « Aminata Diop » auraient le même pseudonyme et seraient fusionnées dans l'export. Un nom peut aussi changer.
3. **Les données de `v_export_bailleur` sont-elles soumises au RGPD ?** Oui. Ce sont des données **pseudonymisées**, pas anonymes : BeeAfrica, qui détient la clé, peut retrouver la personne. Un recoupement reste aussi possible : site, position approchée et nombre de ruches, sur des cases où vit parfois une seule apicultrice.
4. **Pourquoi le journal n'a-t-il pas de clé étrangère vers la table surveillée ?** Pour la même raison que la question 1 de l'étape 7.4 : il doit survivre aux suppressions, couvrir plusieurs tables, et ne jamais empêcher ni effacer quoi que ce soit.
