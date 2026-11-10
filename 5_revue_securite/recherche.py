"""recherche.py (Queen Bee) : recherche de ruches par site, triée. Version corrigée.

TP Jour 2, Lab 10, étape 10.1 · Groupe : Praveen, Ugo, Hugo, Corentin
Corrections par rapport à recherche_vuln.py :
  1. le tri est choisi dans une LISTE BLANCHE de colonnes connues ; tout le
     reste est refusé avant même d'interroger la base ;
  2. la colonne est insérée avec sql.Identifier (jamais par concaténation) ;
  3. l'erreur de la base n'est jamais montrée à l'utilisateur (elle peut
     contenir des données : c'est l'attaque « par erreur »).

Lancement : python recherche.py
Connexion : variables d'environnement du terminal (comme au jour 1).
"""
import os

import psycopg
from psycopg import sql

TRIS = {"code": sql.Identifier("code"),
        "date_installation": sql.Identifier("date_installation")}

site = input("Site (ex. SN-CASA) : ")
tri = input("Trier par (code ou date_installation) : ")
if tri not in TRIS:
    print("Tri refusé : choisissez code ou date_installation")
    raise SystemExit(1)

requete = sql.SQL("SELECT code, site_id, date_installation FROM ruche "
                  "WHERE site_id = %s ORDER BY {}").format(TRIS[tri])
try:
    with psycopg.connect(dbname=os.environ.get("PGDATABASE", "queenbee")) as conn:
        for row in conn.execute(requete, (site,)):
            print(row)
except psycopg.Error:
    print("Erreur : la recherche n'a pas abouti.")     # pas de détail de la base
    raise SystemExit(1)
