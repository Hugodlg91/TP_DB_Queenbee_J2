# Captures d'écran du jour 2 - Groupe Praveen, Ugo, Hugo, Corentin

Une capture par question de l'énoncé. En haut, **le code** : l'extrait de nos fichiers, avec ses vrais numéros de ligne, ou les commandes tapées quand il n'y a pas de fichier. En bas, **le résultat** : ce que psql, PowerShell ou Python ont répondu en exécutant ce code.

Elles ont été produites en rejouant toute la journée sur une base reconstruite à partir de nos fichiers (PostgreSQL 18), dans l'ordre du README : la base du jour 1, les fichiers du jour 2, puis `tests_audit.sql` et `tests_contournement.sql`, puis chaque question. Les résultats commentés dans nos fichiers ont été obtenus de la même façon.

Les poids sont tirés au hasard par `volume.sql`, et les pseudonymes dépendent de la clé secrète : ces valeurs, comme les temps d'exécution, changent d'une reconstruction à l'autre.

- Lab 6 · Décomposer sans rien perdre : 11 captures
- Lab 7 · Dénormaliser, en connaissance de cause : 8 captures
- Lab 8 · Contraintes, trigger d'audit et rôles : 11 captures
- Lab 9 · Transactions : 14 captures
- Lab 10 · Revue de sécurité : 15 captures
- Section 11 · Rendu : 2 captures

## Lab 6 · Décomposer sans rien perdre

### Étape 6.1 · Questions 1 et 2 : créer formation_plat et la remplir

*Attendu : CREATE TABLE, puis INSERT 0 8*

![Étape 6.1 · Questions 1 et 2 : créer formation_plat et la remplir](6-01_formation_creer_et_remplir.png)

### Étape 6.1 · Question 3 : les trois tests des dépendances

*Attendu : 0 ligne pour chacun*

![Étape 6.1 · Question 3 : les trois tests des dépendances](6-02_trois_tests.png)

### Étape 6.1 · Provoquer l'anomalie (Moussa Sarr passe en capteurs)

*Attendu : Moussa Sarr | {capteurs,varroa}*

![Étape 6.1 · Provoquer l'anomalie (Moussa Sarr passe en capteurs)](6-03_anomalie.png)

### Étape 6.2 · Le mauvais découpage : p1(telephone, theme) et p2(theme, formateur)

*Attendu : 16 lignes au lieu de 8, dont 8 inventées*

![Étape 6.2 · Le mauvais découpage : p1(telephone, theme) et p2(theme, formateur)](6-04_mauvais_decoupage.png)

### Étape 6.2 · Questions 1 à 3 : les tables formateur et suivi_formation

*Attendu : INSERT 0 5 (cinq formateurs), puis INSERT 0 8 (huit suivis)*

![Étape 6.2 · Questions 1 à 3 : les tables formateur et suivi_formation](6-05_bon_decoupage_tables.png)

### Étape 6.2 · Question 4 : la double comparaison EXCEPT

*Attendu : 0 ligne (rien de perdu, rien d'inventé)*

![Étape 6.2 · Question 4 : la double comparaison EXCEPT](6-06_preuve_sans_perte.png)

### Étape 6.3 · Montrer la règle perdue (trigger désactivé, transaction annulée)

*Attendu : INSERT 0 1, puis Awa Diop | varroa | {"Moussa Sarr","Ibrahima Fall"}*

![Étape 6.3 · Montrer la règle perdue (trigger désactivé, transaction annulée)](6-07_regle_perdue.png)

### Étape 6.3 · Le trigger suivi_formation_df et ses deux tests

*Attendu : chez Ibrahima Fall refusé (DF violée), chez Khady Ndiaye accepté (INSERT 0 1)*

![Étape 6.3 · Le trigger suivi_formation_df et ses deux tests](6-08_trigger.png)

### Étape 6.3 (suite) · La règle contournée par la table formateur, et son trigger

*Sans le trigger : Aminata Diop a deux formateurs varroa ; avec : refus, et un changement légitime accepté*

![Étape 6.3 (suite) · La règle contournée par la table formateur, et son trigger](6-09_trigger_formateur.png)

### Étape 6.3 · Pour aller plus loin : la même règle par des contraintes

*Attendu : les deux fraudes refusées par l'UNIQUE et par la clé étrangère composée*

![Étape 6.3 · Pour aller plus loin : la même règle par des contraintes](6-10_pour_aller_plus_loin.png)

### Étape 6.4 · Question 2 : le site de l'apicultrice et celui de ses ruches

*Attendu : chaque apicultrice n'a de ruches que sur son site*

![Étape 6.4 · Question 2 : le site de l'apicultrice et celui de ses ruches](6-11_revue_sites.png)

## Lab 7 · Dénormaliser, en connaissance de cause

### Étape 7.1 · Question 1 : 90 jours de mesures (volume.sql, lancé une seule fois)

*Attendu : INSERT 0 47520*

![Étape 7.1 · Question 1 : 90 jours de mesures (volume.sql, lancé une seule fois)](7-01_volume.png)

### Étape 7.1 · Question 2 : le tableau de bord sur les mesures brutes, avec EXPLAIN ANALYZE

*Attendu : 144 mesures par jour (3 ruches × 48 chez nous), Execution Time de l'ordre de 10 ms*

![Étape 7.1 · Question 2 : le tableau de bord sur les mesures brutes, avec EXPLAIN ANALYZE](7-02_tableau_de_bord.png)

### Étape 7.2 · Question 1 : la vue matérialisée synthese_site_jour (denormalisation.sql)

*Attendu : la vue et son index unique créés, sans erreur*

![Étape 7.2 · Question 1 : la vue matérialisée synthese_site_jour (denormalisation.sql)](7-03_synthese_creer.png)

### Étape 7.2 · Question 2 : le tableau de bord lu dans la synthèse

*Attendu : les mêmes chiffres qu'en 7.1, en moins de 0,2 ms*

![Étape 7.2 · Question 2 : le tableau de bord lu dans la synthèse](7-04_synthese_lire.png)

### Étape 7.2 · Question 3 : le vol du 15 mars, avant et après le REFRESH

*Attendu : le 15 mars n'apparaît qu'après le REFRESH, avec poids_min = 8.40*

![Étape 7.2 · Question 3 : le vol du 15 mars, avant et après le REFRESH](7-05_vol_et_refresh.png)

### Étape 7.3 · Casser le pseudonyme d'Awa Diop (notre « Fatou Ba »)

*Attendu : +221 77 100 00 02 retrouvé en un peu plus d'une seconde*

![Étape 7.3 · Casser le pseudonyme d'Awa Diop (notre « Fatou Ba »)](7-06_casser_le_hache.png)

### Étape 7.3 · Questions 1 et 2 : l'export du bailleur (code de la vue, puis lecture)

*Attendu : 8 lignes pour 11 ruches, sans nom ni téléphone ; la vérification de la clé renvoie f*

![Étape 7.3 · Questions 1 et 2 : l'export du bailleur (code de la vue, puis lecture)](7-07_export_bailleur.png)

### Étape 7.4 · Le journal d'audit, et denormalisation.sql relancé (rejouable)

*Attendu : la seconde exécution passe sans erreur (INSERT 0 0 : la clé n'est pas recréée)*

![Étape 7.4 · Le journal d'audit, et denormalisation.sql relancé (rejouable)](7-08_journal_et_relance.png)

## Lab 8 · Contraintes, trigger d'audit et rôles

### Étape 8.1 · Questions 1 et 2 : supprimer une ruche (défaut, puis CASCADE annulé)

*Attendu : refus par mesure_ruche_fk ; avec CASCADE, DELETE 1 et 4 368 mesures de moins ; tout revient*

![Étape 8.1 · Questions 1 et 2 : supprimer une ruche (défaut, puis CASCADE annulé)](8-01_suppression.png)

### Étape 8.1 · Question 3 : references.sql, puis la vérification

*Attendu : 2 CASCADE, 4 RESTRICT*

![Étape 8.1 · Question 3 : references.sql, puis la vérification](8-02_references.png)

### Étape 8.2 : check.sql (contraintes nommées)

*Attendu : les ALTER TABLE passent*

![Étape 8.2 : check.sql (contraintes nommées)](8-03_check.png)

### Étape 8.2 : les deux tests (batterie à 150, statut d'alerte invalide)

*Attendu : les deux refusés*

![Étape 8.2 : les deux tests (batterie à 150, statut d'alerte invalide)](8-04_check_tests.png)

### Étape 8.3 · Question 1 : audit.sql (qui(), audit_ligne(), journal en ajout seul)

*Attendu : les fonctions et les triggers créés*

![Étape 8.3 · Question 1 : audit.sql (qui(), audit_ligne(), journal en ajout seul)](8-05_audit.png)

### Étape 8.3 · Questions 2 à 4 : la trace, les trois refus, la limite

*Attendu : postgres | recolte | UPDATE | 12.40 | 14.00 ; trois refus ; DISABLE passe en postgres*

![Étape 8.3 · Questions 2 à 4 : la trace, les trois refus, la limite](8-06_tests_audit.png)

### Étape 8.4 · Questions 2 et 3 : roles.sql (groupes, personnes, fermeture)

*Attendu : cinq lignes, une par personne*

![Étape 8.4 · Questions 2 et 3 : roles.sql (groupes, personnes, fermeture)](8-07_roles.png)

### Étape 8.4 · Les vues de moindre privilège et les GRANT (roles.sql)

*Vérification : les droits réels de chaque personne sur chaque vue*

![Étape 8.4 · Les vues de moindre privilège et les GRANT (roles.sql)](8-08_vues.png)

### Étape 8.5 : la fonction valider_recolte(p_recolte uuid)

*Vérification : SECURITY DEFINER, search_path fixé, exécutable par qb_coordinateur seulement*

![Étape 8.5 : la fonction valider_recolte(p_recolte uuid)](8-09_valider_recolte.png)

### Étape 8.6 · Tests de contournement 1 à 9 (a.diop, notre f.ba)

*Attendu : refusé, ses ruches seulement, accepté, puis six refus*

![Étape 8.6 · Tests de contournement 1 à 9 (a.diop, notre f.ba)](8-10_contournement_1_a_9.png)

### Étape 8.6 · Tests de contournement 10 à 12 (coord.casa, admin), même session

*Attendu : accepté puis refusé ; refusé ; journal lu (vrais acteurs) et suppression refusée*

![Étape 8.6 · Tests de contournement 10 à 12 (coord.casa, admin), même session](8-11_contournement_10_a_12.png)

## Lab 9 · Transactions

### Étape 9.1 · Question 1 : la trace qui ment

*Attendu : l'UPDATE refusé par recolte_validation_tracee, mais le journal de l'application affirme la validation*

![Étape 9.1 · Question 1 : la trace qui ment](9-01_trace_qui_ment.png)

### Étape 9.1 · Question 2 : l'action et sa trace, dans une transaction

*Attendu : +1 dans la transaction, « current transaction is aborted » après l'erreur, tout revenu après le ROLLBACK*

![Étape 9.1 · Question 2 : l'action et sa trace, dans une transaction](9-02_transaction.png)

### Étape 9.2 · Question 1 : jeton.sql

*Attendu : INSERT 0 30*

![Étape 9.2 · Question 1 : jeton.sql](9-03_jeton_sql.png)

### Étape 9.2 · Questions 2 et 3 : la course au jeton dans deux terminaux (RT-a.diop-1)

*Attendu : 2 sessions avec ce jeton (contrainte session_jeton_unique pas encore posée, comme avant l'étape 9.4)*

![Étape 9.2 · Questions 2 et 3 : la course au jeton dans deux terminaux (RT-a.diop-1)](9-04_course_deux_terminaux.png)

### Étape 9.3 · Question 1 : course_jeton.py (vulnérable), deux fois

*Attendu : sessions ouvertes avec ce jeton : 2, à chaque fois*

![Étape 9.3 · Question 1 : course_jeton.py (vulnérable), deux fois](9-05_course_programme.png)

### Étape 9.3 · Question 2 : course_jeton_corrige.py (UPDATE ... RETURNING), deux fois

*Attendu : un accepté, un refusé, et 1 session, à chaque fois*

![Étape 9.3 · Question 2 : course_jeton_corrige.py (UPDATE ... RETURNING), deux fois](9-06_course_corrigee.png)

### Étape 9.4 · Correction 1 : SELECT ... FOR UPDATE (RT-a.diop-2)

*Attendu : B se fige ; dès que A fait COMMIT, B voit utilise_le rempli*

![Étape 9.4 · Correction 1 : SELECT ... FOR UPDATE (RT-a.diop-2)](9-07_for_update.png)

### Étape 9.4 · Correction 2 : une seule instruction UPDATE ... RETURNING (RT-a.diop-3)

*Attendu : A reçoit un id, B attend puis reçoit 0 ligne*

![Étape 9.4 · Correction 2 : une seule instruction UPDATE ... RETURNING (RT-a.diop-3)](9-08_update_returning.png)

### Étape 9.4 · Correction 3 : UNIQUE (jeton_id), puis le programme vulnérable relancé

*Attendu : d'abord un refus, puis la contrainte posée ; course_jeton.py RT-a.diop-14 : 1 session et duplicate key*

![Étape 9.4 · Correction 3 : UNIQUE (jeton_id), puis le programme vulnérable relancé](9-09_unique.png)

### Étape 9.4 · Correction 4 : REPEATABLE READ (RT-a.diop-4)

*Attendu : l'UPDATE de B échoue avec could not serialize access due to concurrent update*

![Étape 9.4 · Correction 4 : REPEATABLE READ (RT-a.diop-4)](9-10_repeatable_read.png)

### Étape 9.4 · Question : le trigger du lab 6 face à deux inscriptions simultanées

*Avec la fonction d'origine (formation.sql) : les deux passent, Mariama Ba a deux formateurs varroa (constat R2)*

![Étape 9.4 · Question : le trigger du lab 6 face à deux inscriptions simultanées](9-11_trigger_lab6_course.png)

### Étape 9.4 · Question (suite) : la même course après corrections.sql (constat R2)

*Attendu : B attend, puis reçoit « DF violée » ; Mariama Ba garde un seul formateur varroa*

![Étape 9.4 · Question (suite) : la même course après corrections.sql (constat R2)](9-12_trigger_lab6_corrige.png)

### Étape 9.5 · Question 1 : les réglages de durabilité

*Attendu : on, on, replica*

![Étape 9.5 · Question 1 : les réglages de durabilité](9-13_durabilite_reglages.png)

### Étape 9.5 · Question 2 : sauvegarde, empreinte, restauration, vérification

*Attendu : le même nombre de lignes de journal, le DELETE refusé dans la copie, et queenbee_j2.dump: OK*

![Étape 9.5 · Question 2 : sauvegarde, empreinte, restauration, vérification](9-14_sauvegarde.png)

## Lab 10 · Revue de sécurité

### Étape 10.1 · Questions 1 et 2 : recherche_vuln.py, recherche normale puis attaque par erreur

*Attendu : les ruches de SN-CASA ; puis invalid input syntax for type integer: "+221 77 100 00 02"*

![Étape 10.1 · Questions 1 et 2 : recherche_vuln.py, recherche normale puis attaque par erreur](10-01_tri_normal_et_par_erreur.png)

### Étape 10.1 · Question 2 : attaques à l'aveugle ('77' puis '78') et empilée

*Attendu : l'ordre des lignes change ; puis cannot insert multiple commands into a prepared statement*

![Étape 10.1 · Question 2 : attaques à l'aveugle ('77' puis '78') et empilée](10-02_tri_aveugle_et_empile.png)

### Étape 10.1 · Question 3 : recherche.py (liste blanche, sql.Identifier)

*Attendu : Tri refusé : choisissez code ou date_installation ; un tri autorisé fonctionne*

![Étape 10.1 · Question 3 : recherche.py (liste blanche, sql.Identifier)](10-03_recherche_corrigee.png)

### Étape 10.2 · Questions 1 et 2 : la vue trop large (P2) et la fonction espion (P3)

*Attendu : table refusée mais 11 téléphones par la vue ; 1 ligne de résultat mais 11 NOTICE (toutes les positions)*

![Étape 10.2 · Questions 1 et 2 : la vue trop large (P2) et la fonction espion (P3)](10-04_failles_P2_P3.png)

### Étape 10.2 · Question 3 : corrections.sql, lancé en postgres

*Attendu : la vue réécrite, security_barrier sur les vues filtrées, REVOKE TEMPORARY*

![Étape 10.2 · Question 3 : corrections.sql, lancé en postgres](10-05_corrections.png)

### Étape 10.2 · Question 4 : retest « dans la même session » (barrière seule)

*Attendu : l'espion ne voit plus que SN-CASA-021*

![Étape 10.2 · Question 4 : retest « dans la même session » (barrière seule)](10-06_retest_meme_session.png)

### Étape 10.2 · Question 4 : retest dans une nouvelle session (après corrections.sql)

*Attendu : une seule ligne sans téléphone ; permission denied to create temporary tables*

![Étape 10.2 · Question 4 : retest dans une nouvelle session (après corrections.sql)](10-07_retest_nouvelle_session.png)

### Étape 10.3 · Constat R1 : les hachés des mots de passe (preuve, puis retest)

*Preuve : le haché lisible dans le journal ; retest : f, et SELECT mot_de_passe_hash refusé à l'admin*

![Étape 10.3 · Constat R1 : les hachés des mots de passe (preuve, puis retest)](10-08_R1_haches.png)

### Étape 10.3 · Constat R5 : récoltes impossibles (retest, tests_8_1_8_2.sql)

*Attendu : NaN, 9999.99 kg, l'an 3027 et 'infinity' refusés ; aucune ligne existante hors règles*

![Étape 10.3 · Constat R5 : récoltes impossibles (retest, tests_8_1_8_2.sql)](10-09_R5_recoltes_impossibles.png)

### Étape 10.3 · Constat R6 : agir sous le nom de son groupe (preuve, puis retest)

*Preuve : le journal nomme qb_admin ; retest : permission denied to set role, et l'héritage marche toujours*

![Étape 10.3 · Constat R6 : agir sous le nom de son groupe (preuve, puis retest)](10-10_R6_role_de_groupe.png)

### Étape 10.3 · Constat R2 (suite) : remplacer un formateur par un autre du même thème

*Attendu après corrections.sql : UPDATE 1 (la ligne modifiée n'est plus prise pour « un autre formateur »)*

![Étape 10.3 · Constat R2 (suite) : remplacer un formateur par un autre du même thème](10-11_E1_remplacement.png)

### Étape 10.3 · Grille : C1 (PUBLIC), C2 (search_path), C3 (barrières)

*Attendu : 0 ligne ; search_path=... partout ; security_barrier=true sur les 7 vues filtrées*

![Étape 10.3 · Grille : C1 (PUBLIC), C2 (search_path), C3 (barrières)](10-12_grille_C1_C2_C3.png)

### Étape 10.3 · Grille : C4, chaque vue lue par chaque rôle

*Attendu : chacun ses lignes seulement ; les vues des autres rôles refusées*

![Étape 10.3 · Grille : C4, chaque vue lue par chaque rôle](10-13_grille_C4.png)

### Étape 10.3 · Grille : C5, C6, C7 et C10

*Attendu : trois refus ; admin | utilisateur | UPDATE ; check option ; preuves en r (RESTRICT)*

![Étape 10.3 · Grille : C5, C6, C7 et C10](10-14_grille_C5_C6_C7_C10.png)

### Étape 10.3 · Grille : C8 (jeton neuf), C9 (requêtes construites par +), C11 (mot de passe)

*Attendu : 1 session ; seulement les deux démonstrations vulnérables ; aucun mot de passe dans les scripts*

![Étape 10.3 · Grille : C8 (jeton neuf), C9 (requêtes construites par +), C11 (mot de passe)](10-15_grille_C8_C9_C11.png)

## Section 11 · Rendu

### Étape 11.1 : le schéma exporté contient le trigger, les barrières et les droits

*Attendu : CREATE TRIGGER recolte_audit, security_barrier et GRANT SELECT ON TABLE public.v_mes_ruches*

![Étape 11.1 : le schéma exporté contient le trigger, les barrières et les droits](11-01_schema_j2.png)

### Étape 11.5 : reconstruire toute la base dans une base vide (contrôle C12)

*Attendu : aucune ERROR hors des tests ; extrait : les titres d'étape, le bilan du jour 1 et les ERROR (voulues) des tests*

Capture obtenue avec notre script de reconstruction (il enchaîne les étapes 0 à 8 du README), qui n'est pas joint au rendu.

![Étape 11.5 : reconstruire toute la base dans une base vide (contrôle C12)](11-02_reconstruction.png)
