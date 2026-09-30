#!/usr/bin/env python3
"""Sert `site/public/` en local comme Vercel le servira : `cleanUrls`, page 404, et les
en-têtes de `site/vercel.json` (CSP comprise). Sert à relire le site et à y lancer
Lighthouse sans rien déployer.

    python3 site/scripts/servir.py [--port 8080]

Les motifs `source` de vercel.json sont traduits en expressions régulières au plus simple
(`(.*)` et groupes) ; c'est suffisant pour les quatre règles du fichier, pas un moteur
complet. La compression n'est pas imitée : Lighthouse la note à part, Vercel la fait.
"""

from __future__ import annotations

import argparse
import json
import re
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

SITE = Path(__file__).resolve().parent.parent
PUBLIC = SITE / "public"


def regles() -> list[tuple[re.Pattern[str], list[dict]]]:
    config = json.loads((SITE / "vercel.json").read_text(encoding="utf-8"))
    return [
        (re.compile("^" + bloc["source"] + "$"), bloc["headers"])
        for bloc in config.get("headers", [])
    ]


class Gestionnaire(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".avif": "image/avif",
        ".webp": "image/webp",
        ".woff2": "font/woff2",
        ".svg": "image/svg+xml",
        ".xml": "application/xml",
    }
    _regles = regles()
    _statut = 200

    def _resoudre(self) -> tuple[str, int]:
        chemin = urlsplit(self.path).path
        if chemin == "/":
            return "/index.html", 200
        if chemin.endswith(".html"):
            return "/404.html", 404  # cleanUrls : l'extension n'est pas une adresse publique
        fichier = PUBLIC / chemin.lstrip("/")
        if fichier.is_file():
            return chemin, 200
        if (PUBLIC / (chemin.lstrip("/") + ".html")).is_file():
            return chemin + ".html", 200
        return "/404.html", 404

    def send_head(self):  # noqa: N802 — nom imposé par http.server
        chemin, self._statut = self._resoudre()
        self._chemin_public = urlsplit(self.path).path
        self.path = chemin
        return super().send_head()

    def send_response(self, code, message=None):  # noqa: N802
        super().send_response(self._statut if code == 200 else code, message)

    def end_headers(self) -> None:
        public = getattr(self, "_chemin_public", self.path)
        valeurs: dict[str, str] = {}
        for motif, entetes in self._regles:
            if motif.match(public):
                for entete in entetes:
                    valeurs[entete["key"]] = entete["value"]
        for cle, valeur in valeurs.items():
            if cle.lower() != "strict-transport-security":  # sans objet en HTTP local
                self.send_header(cle, valeur)
        super().end_headers()

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        pass


def main() -> None:
    analyseur = argparse.ArgumentParser(description="Sert site/public/ comme Vercel.")
    analyseur.add_argument("--port", type=int, default=8080)
    options = analyseur.parse_args()
    serveur = ThreadingHTTPServer(
        ("127.0.0.1", options.port), partial(Gestionnaire, directory=str(PUBLIC))
    )
    print(f"http://127.0.0.1:{options.port}/")
    serveur.serve_forever()


if __name__ == "__main__":
    main()
