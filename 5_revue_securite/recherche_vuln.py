"""recherche_vuln.py (Queen Bee) : recherche de ruches par site, triée.

TP Jour 2, Lab 10, étape 10.1 · Groupe : Praveen, Ugo, Hugo, Corentin
VERSION VULNÉRABLE, pour la démonstration : à ne jamais déployer.
Le site est bien paramétré (%s), mais le tri est RECOPIÉ dans la requête
(un %s ne peut pas remplacer un nom de colonne), et l'erreur de la base est
affichée à l'utilisateur.

Lancement : python recherche_vuln.py
Connexion : variables d'environnement du terminal (comme au jour 1) ; base lue
dans PGDATABASE, « queenbee » par défaut.
"""
import os

import psycopg

conn = psycopg.connect(dbname=os.environ.get("PGDATABASE", "queenbee"))
site = input("Site (ex. SN-CASA) : ")
tri = input("Trier par (code ou date_installation) : ")

sql = ("SELECT code, site_id, date_installation FROM ruche "
       "WHERE site_id = %s ORDER BY " + tri)          # valeur paramétrée, tri recopié
try:                                                   # affiche l'erreur de la base
    for row in conn.execute(sql, (site,)):
        print(row)
except psycopg.Error as e:
    print("Erreur :", e)
