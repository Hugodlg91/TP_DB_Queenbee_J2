"""course_jeton.py (Queen Bee) : deux requêtes simultanées avec le même jeton.

TP Jour 2, Lab 9, étape 9.3 · Groupe : Praveen, Ugo, Hugo, Corentin
VERSION VULNÉRABLE : « vérifier, puis agir » en deux instructions.

Lancement : python course_jeton.py RT-a.diop-10
Connexion : PGUSER, PGHOST et le secret de connexion viennent des variables
d'environnement du terminal (comme au jour 1), jamais de ce fichier. La base
est lue dans PGDATABASE, « queenbee » par défaut.
"""
import os
import sys
import threading
import time

import psycopg

BASE = os.environ.get("PGDATABASE", "queenbee")
JETON = sys.argv[1]
depart = threading.Barrier(2)          # les deux fils attendent d'être prêts
resultats = {}


def rafraichir(nom):
    try:
        with psycopg.connect(dbname=BASE) as conn:
            depart.wait()              # partez !
            row = conn.execute(
                "SELECT id, utilisateur_id, utilise_le, expire_le > now() FROM jeton WHERE valeur = %s",
                (JETON,)).fetchone()
            if row is None or row[2] is not None or not row[3]:     # 1. vérifier
                resultats[nom] = "refusé : jeton déjà utilisé ou expiré"
                return
            time.sleep(0.2)            # le temps de préparer la session...
            conn.execute("UPDATE jeton SET utilise_le = now() WHERE id = %s", (row[0],))
            conn.execute("INSERT INTO session_app (utilisateur_id, jeton_id) VALUES (%s, %s)",
                         (row[1], row[0]))                          # 2. agir
            resultats[nom] = "accepté : session ouverte"
    except psycopg.Error as e:
        resultats[nom] = "erreur de la base : " + e.diag.message_primary


fils = [threading.Thread(target=rafraichir, args=(n,)) for n in ("requête 1", "requête 2")]
for f in fils:
    f.start()
for f in fils:
    f.join()
for nom in sorted(resultats):
    print(nom, "->", resultats[nom])

with psycopg.connect(dbname=BASE) as conn:
    n = conn.execute("""SELECT count(*) FROM session_app s
                        JOIN jeton j ON j.id = s.jeton_id
                        WHERE j.valeur = %s""", (JETON,)).fetchone()[0]
print("sessions ouvertes avec ce jeton :", n)
