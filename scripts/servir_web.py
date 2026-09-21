#!/usr/bin/env python3
"""Sert `build/web` comme le fera l'hébergeur, pour vérifier avant d'envoyer.

    scripts/build_web.sh env/prod.json
    scripts/servir_web.py            # puis http://127.0.0.1:8099

Un serveur statique ordinaire ne suffit pas pour cette vérification : les
polices **et le moteur CanvasKit** sont livrés déjà compressés
(`scripts/build_web.sh`) et ne sont lisibles qu'avec l'en-tête
`Content-Encoding: br` que pose `vercel.json`. Servi sans lui, CanvasKit ne
démarre pas du tout (« expected magic word ») ; les polices, elles, échouent au
décodage **en silence** et l'application retombe sur un Roboto téléchargé chez
Google — la panne que le ticket 037 a supprimée, et celle qu'on ne voit pas si
on ne la cherche pas.

Ce serveur rejoue donc `vercel.json` : redirections, en-têtes, réécriture de
toute adresse inconnue vers `index.html`. Il ajoute la compression à la volée
des types texte, que le CDN fait aussi — sans elle, `main.dart.js` partirait en
clair (3,6 Mo au lieu de 1,1) et toute mesure de temps de chargement serait
fausse.

Ce n'est **pas** un serveur de production : mono-processus, sans HTTPS, sans
ETag. Il sert à regarder, pas à servir.
"""

import gzip
import json
import mimetypes
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RACINE_PROJET = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORTIE = os.path.abspath(
    sys.argv[1] if len(sys.argv) > 1 else os.path.join(RACINE_PROJET, "build/web")
)
CONFIG = os.path.join(RACINE_PROJET, "vercel.json")
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8099

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("font/ttf", ".ttf")

with open(CONFIG, encoding="utf-8") as fichier:
    VERCEL = json.load(fichier)

TYPES_COMPRESSIBLES = (
    "text/",
    "application/javascript",
    "application/json",
    "application/manifest+json",
)

# Compresser `main.dart.js` (3,7 Mo) coûte plus d'une seconde de processeur.
# Un CDN le fait une fois ; sans ce cache, ce serveur le referait à chaque
# requête et toute mesure de temps de chargement mesurerait la machine de
# développement au lieu du réseau (ticket 037).
_CACHE: dict[str, bytes] = {}


def entetes_pour(chemin: str) -> dict[str, str]:
    """Les en-têtes de `vercel.json` qui s'appliquent : la dernière règle gagne."""
    trouves: dict[str, str] = {}
    for regle in VERCEL.get("headers", []):
        if re.fullmatch(regle["source"], chemin):
            for entete in regle["headers"]:
                trouves[entete["key"]] = entete["value"]
    return trouves


def redirection_pour(chemin: str):
    for regle in VERCEL.get("redirects", []):
        if re.fullmatch(regle["source"], chemin):
            return regle
    return None


class Serveur(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):  # noqa: A002
        pass

    def do_HEAD(self):  # noqa: N802
        self._repondre(corps=False)

    def do_GET(self):  # noqa: N802
        self._repondre(corps=True)

    def _repondre(self, *, corps: bool) -> None:
        chemin = self.path.split("?")[0].split("#")[0]

        # Chez Vercel, les redirections passent avant le système de fichiers.
        regle = redirection_pour(chemin)
        if regle is not None:
            self.send_response(308 if regle.get("permanent") else 307)
            self.send_header("Location", regle["destination"])
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        fichier = os.path.join(SORTIE, chemin.lstrip("/"))
        if not os.path.isfile(fichier):
            # Réécriture : go_router résout la route côté client.
            fichier = os.path.join(SORTIE, "index.html")

        type_mime = mimetypes.guess_type(fichier)[0] or "application/octet-stream"
        entetes = entetes_pour(chemin)

        compressible = type_mime.startswith(TYPES_COMPRESSIBLES)
        accepte_gzip = "gzip" in self.headers.get("Accept-Encoding", "")
        compresser = compressible and accepte_gzip and "Content-Encoding" not in entetes

        empreinte = f"{fichier}|{compresser}"
        if empreinte not in _CACHE:
            with open(fichier, "rb") as source:
                brut = source.read()
            _CACHE[empreinte] = gzip.compress(brut, 6) if compresser else brut
        octets = _CACHE[empreinte]

        if compresser:
            entetes["Content-Encoding"] = "gzip"
            entetes["Vary"] = "Accept-Encoding"

        self.send_response(200)
        self.send_header("Content-Type", type_mime)
        self.send_header("Content-Length", str(len(octets)))
        for cle, valeur in entetes.items():
            self.send_header(cle, valeur)
        self.end_headers()
        if corps:
            self.wfile.write(octets)


if __name__ == "__main__":
    if not os.path.isfile(os.path.join(SORTIE, "index.html")):
        print(
            f"erreur : {SORTIE} ne contient pas index.html. "
            "Lancer scripts/build_web.sh d'abord.",
            file=sys.stderr,
        )
        raise SystemExit(1)
    print(f"→ http://127.0.0.1:{PORT}  sert {SORTIE} avec les règles de vercel.json")
    print("  Ctrl-C pour arrêter.")
    try:
        ThreadingHTTPServer(("127.0.0.1", PORT), Serveur).serve_forever()
    except KeyboardInterrupt:
        print()
