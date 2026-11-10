"""course_jeton_corrige.py (Queen Bee) : la même course, corrigée.

TP Jour 2, Lab 9, étape 9.3 · Groupe : Praveen, Ugo, Hugo, Corentin
Correction : « vérifier et agir » en UNE seule instruction. L'UPDATE ne
touche le jeton que s'il est encore libre et valide ; il verrouille la ligne,
et la seconde requête, après l'attente, ne trouve plus rien (0 ligne).

Lancement : python course_jeton_corrige.py RT-a.diop-12
Connexion : comme course_jeton.py (variables d'environnement du terminal).
"""
import os
import sys
import threading
import time

import psycopg

BASE = os.environ.get("PGDATABASE", "queenbee")
JETON = sys.argv[1]
depart = threading.Barrier(2)
resultats = {}


def rafraichir(nom):
    try:
        with psycopg.connect(dbname=BASE) as conn:
            depart.wait()
            row = conn.execute(
                """UPDATE jeton SET utilise_le = now()
                   WHERE valeur = %s AND utilise_le IS NULL AND expire_le > now()
                   RETURNING id, utilisateur_id""", (JETON,)).fetchone()
            if row is None:            # vérifié ET consommé en une instruction
                resultats[nom] = "refusé : jeton déjà utilisé ou expiré"
                return
            time.sleep(0.2)            # même attente que la version vulnérable
            conn.execute("INSERT INTO session_app (utilisateur_id, jeton_id) VALUES (%s, %s)",
                         (row[1], row[0]))
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
