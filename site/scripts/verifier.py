#!/usr/bin/env python3
"""Contrôles du site vitrine (ticket 075, brief § 9.3), sans dépendance ni réseau.

Ce que ce script vérifie sur `site/public/`, le répertoire servi tel quel :

1. liens internes : chaque lien, image, feuille de style, fonte ou ancre pointe vers un
   fichier ou un identifiant qui existe (`/mentions-legales` → `mentions-legales.html`,
   comme le fait `cleanUrls` chez Vercel) ;
2. aucun tiers : aucune ressource chargée hors du domaine (image, feuille, fonte, script),
   aucun `<script src>`, aucune `url(...)` distante dans le CSS ;
3. poids : chaque image sous son budget, fontes et feuilles de style sous le leur, et le
   total des images d'une visite complète à 390 px ;
4. pied de page identique sur toutes les pages ;
5. l'empreinte de chaque script en ligne figure dans la CSP de `site/vercel.json` —
   sinon le navigateur bloquerait le script en production sans que rien ne le dise ;
6. `robots.txt` et `sitemap.xml` présents, et chaque URL du plan de site servie.

La validité du HTML est vérifiée à part, par `html-validate` (voir `site/README.md`).

Avec `--marqueurs`, le script vérifie **en plus** qu'aucune marque `[À COMPLÉTER` ne
reste dans les fichiers publiés. Ce contrôle bloque la **mise en ligne** (deploy.yml),
pas la CI des PR : le site se construit et se relit pendant que le propriétaire complète
les mentions (décision du 30 septembre 2026).

Codes de sortie : 0 conforme, 1 au moins un écart (tous listés), 2 usage.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

SITE = Path(__file__).resolve().parent.parent
PUBLIC = SITE / "public"
CONFIG = SITE / "vercel.json"
DOMAINE = "astreinte-sp.fr"
MARQUE = "[À COMPLÉTER"

KO = 1024

# Budgets des images (brief § 7.4), par motif de nom. Une image sans budget est un écart :
# ajouter une image, c'est lui donner un budget ici.
BUDGETS_IMAGES: list[tuple[str, int]] = [
    (r"^(a-accueil|c-saisie|d-proposition)-(300|600)\.avif$", 60 * KO),
    (r"^(a-accueil|c-saisie|d-proposition)-(300|600)\.webp$", 90 * KO),
    (r"^b-matrice-(720|1440)\.avif$", 140 * KO),
    (r"^b-matrice-(720|1440)\.webp$", 180 * KO),
    (r"^b-recadrage-(360|720)\.avif$", 50 * KO),
    (r"^b-recadrage-(360|720)\.webp$", 80 * KO),
    (r"^partage\.png$", 120 * KO),
    (r"^icone\.svg$", 4 * KO),
]
BUDGET_FONTES = 90 * KO
BUDGET_CSS = 20 * KO
BUDGET_HTML = 48 * KO
BUDGET_VISITE_390 = 350 * KO
BUDGET_SCRIPT = 2 * KO

# Balises et attributs qui **chargent** une ressource : ceux-là doivent rester chez nous.
CHARGEMENTS = {
    ("img", "src"),
    ("img", "srcset"),
    ("source", "srcset"),
    ("script", "src"),
    ("iframe", "src"),
    ("video", "src"),
    ("audio", "src"),
    ("embed", "src"),
    ("object", "data"),
}
LIENS_CHARGES = {"stylesheet", "preload", "icon", "apple-touch-icon", "manifest", "modulepreload"}


class Page(HTMLParser):
    """Ce qu'une page déclare : identifiants, liens, ressources, scripts, pied de page."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.liens: list[tuple[str, str]] = []  # (balise.attribut, valeur)
        self.ressources: list[tuple[str, str]] = []
        self.scripts_src: list[str] = []
        self.scripts_en_ligne: list[str] = []
        self.pictures: list[dict] = []
        self._script: dict | None = None
        self._picture: dict | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        a = {k: (v or "") for k, v in attrs}
        if "id" in a:
            self.ids.add(a["id"])
        if tag == "a" and "href" in a:
            self.liens.append(("a.href", a["href"]))
        if tag == "use" and "href" in a:
            self.liens.append(("use.href", a["href"]))
        if tag == "link":
            rels = set(a.get("rel", "").lower().split())
            if rels & LIENS_CHARGES:
                self.ressources.append(("link.href", a.get("href", "")))
        for attribut in ("src", "srcset", "data"):
            if (tag, attribut) in CHARGEMENTS and attribut in a:
                valeurs = (
                    [c.strip().split()[0] for c in a[attribut].split(",") if c.strip()]
                    if attribut == "srcset"
                    else [a[attribut]]
                )
                for valeur in valeurs:
                    self.ressources.append((f"{tag}.{attribut}", valeur))
        if tag == "script":
            if "src" in a:
                self.scripts_src.append(a["src"])
            type_ = a.get("type", "").lower()
            executable = type_ in ("", "text/javascript", "module", "application/javascript")
            self._script = {"executable": executable, "texte": ""}
        if tag == "picture":
            self._picture = {"sources": [], "mobile": a.get("data-mobile", "") != "non"}
        if tag == "source" and self._picture is not None:
            self._picture["sources"].append(a)

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self._script is not None:
            if self._script["executable"] and self._script["texte"].strip():
                self.scripts_en_ligne.append(self._script["texte"])
            self._script = None
        if tag == "picture" and self._picture is not None:
            self.pictures.append(self._picture)
            self._picture = None

    def handle_data(self, data: str) -> None:
        if self._script is not None:
            self._script["texte"] += data


def pages() -> list[Path]:
    return sorted(PUBLIC.glob("*.html"))


def fichier_de(chemin: str) -> Path | None:
    """Le fichier servi pour un chemin, comme Vercel avec `cleanUrls: true`."""
    chemin = unquote(chemin)
    if chemin in ("", "/"):
        return PUBLIC / "index.html"
    relatif = chemin.lstrip("/")
    for candidat in (PUBLIC / relatif, PUBLIC / f"{relatif}.html", PUBLIC / relatif / "index.html"):
        if candidat.is_file():
            return candidat
    return None


def est_distant(url: str) -> bool:
    return bool(urlsplit(url).scheme) or url.startswith("//")


def verifier_liens(analyses: dict[Path, Page], ecarts: list[str]) -> None:
    for page, analyse in analyses.items():
        nom = page.name
        for origine, url in analyse.liens + analyse.ressources:
            if not url:
                ecarts.append(f"{nom} : {origine} vide")
                continue
            if est_distant(url):
                continue  # les liens sortants sont permis ; les chargements distants, non (plus bas)
            morceaux = urlsplit(url)
            if morceaux.scheme in ("mailto", "tel"):
                continue
            cible = page if not morceaux.path else fichier_de(morceaux.path)
            if cible is None:
                ecarts.append(f"{nom} : {origine} « {url} » ne mène à aucun fichier")
                continue
            if morceaux.fragment:
                ids = analyses[cible].ids if cible in analyses else set()
                if morceaux.fragment not in ids:
                    ecarts.append(f"{nom} : {origine} « {url} » vise une ancre absente de {cible.name}")


def verifier_tiers(analyses: dict[Path, Page], ecarts: list[str]) -> None:
    for page, analyse in analyses.items():
        for origine, url in analyse.ressources:
            if est_distant(url):
                ecarts.append(f"{page.name} : {origine} charge une ressource distante « {url} »")
        for src in analyse.scripts_src:
            ecarts.append(f"{page.name} : <script src=\"{src}\"> interdit (scripts en ligne seulement)")
    for css in PUBLIC.rglob("*.css"):
        for url in re.findall(r"url\(\s*['\"]?([^'\")]+)", css.read_text(encoding="utf-8")):
            if est_distant(url):
                ecarts.append(f"{css.name} : url() distante « {url} »")
            elif fichier_de(url) is None:
                ecarts.append(f"{css.name} : url() « {url} » ne mène à aucun fichier")


def verifier_poids(analyses: dict[Path, Page], ecarts: list[str], rapport: list[str]) -> None:
    for image in sorted((PUBLIC / "images").glob("*")):
        taille = image.stat().st_size
        budget = next((b for motif, b in BUDGETS_IMAGES if re.match(motif, image.name)), None)
        if budget is None:
            ecarts.append(f"images/{image.name} : aucun budget déclaré dans site/scripts/verifier.py")
        elif taille > budget:
            ecarts.append(f"images/{image.name} : {taille // KO} Ko, budget {budget // KO} Ko")
    fontes = sum(f.stat().st_size for f in (PUBLIC / "fonts").glob("*.woff2"))
    rapport.append(f"fontes : {fontes // KO} Ko (budget {BUDGET_FONTES // KO})")
    if fontes > BUDGET_FONTES:
        ecarts.append(f"fontes : {fontes // KO} Ko au total, budget {BUDGET_FONTES // KO} Ko")
    for css in PUBLIC.glob("*.css"):
        taille = css.stat().st_size
        rapport.append(f"{css.name} : {taille // KO} Ko (budget {BUDGET_CSS // KO})")
        if taille > BUDGET_CSS:
            ecarts.append(f"{css.name} : {taille // KO} Ko, budget {BUDGET_CSS // KO} Ko")
    for page, analyse in analyses.items():
        taille = page.stat().st_size
        if taille > BUDGET_HTML:
            ecarts.append(f"{page.name} : {taille // KO} Ko, budget {BUDGET_HTML // KO} Ko")
        for script in analyse.scripts_en_ligne:
            if len(script.encode()) > BUDGET_SCRIPT:
                ecarts.append(f"{page.name} : script en ligne de {len(script.encode())} o, budget {BUDGET_SCRIPT} o")

    # Visite complète à 390 px, au pire (écran 2x ou 3x : la plus grande variante AVIF).
    accueil = analyses.get(PUBLIC / "index.html")
    if accueil is not None:
        total = 0
        for picture in accueil.pictures:
            if not picture["mobile"]:
                continue
            for source in picture["sources"]:
                media = source.get("media", "")
                if source.get("type") != "image/avif" or "min-width: 840px" in media:
                    continue
                candidats = [c.strip().split()[0] for c in source.get("srcset", "").split(",") if c.strip()]
                total += max((fichier_de(c).stat().st_size for c in candidats if fichier_de(c)), default=0)
                break
        rapport.append(f"images d'une visite à 390 px : {total // KO} Ko (budget {BUDGET_VISITE_390 // KO})")
        if total > BUDGET_VISITE_390:
            ecarts.append(f"images d'une visite à 390 px : {total // KO} Ko, budget {BUDGET_VISITE_390 // KO} Ko")


def verifier_pied(ecarts: list[str]) -> None:
    pieds = {}
    for page in pages():
        trouve = re.findall(r"<footer\b.*?</footer>", page.read_text(encoding="utf-8"), re.S)
        if len(trouve) != 1:
            ecarts.append(f"{page.name} : {len(trouve)} pied(s) de page, un seul attendu")
            continue
        pieds[page.name] = trouve[0]
    if len(set(pieds.values())) > 1:
        reference = pieds.get("index.html")
        differents = [nom for nom, pied in pieds.items() if pied != reference]
        ecarts.append(f"pied de page différent de celui de index.html : {', '.join(differents)}")


def verifier_csp(analyses: dict[Path, Page], ecarts: list[str]) -> None:
    try:
        config = json.loads(CONFIG.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as erreur:
        ecarts.append(f"site/vercel.json illisible : {erreur}")
        return
    csp = ""
    for bloc in config.get("headers", []):
        for entete in bloc.get("headers", []):
            if entete.get("key", "").lower() == "content-security-policy":
                csp = entete.get("value", "")
    if not csp:
        ecarts.append("site/vercel.json : aucune Content-Security-Policy")
        return
    declares = set(re.findall(r"'(sha256-[A-Za-z0-9+/=]+)'", csp))
    utilises = set()
    for page, analyse in analyses.items():
        for script in analyse.scripts_en_ligne:
            empreinte = "sha256-" + base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
            utilises.add(empreinte)
            if empreinte not in declares:
                ecarts.append(
                    f"{page.name} : script en ligne d'empreinte '{empreinte}' absent de la CSP "
                    "de site/vercel.json — le navigateur le bloquerait"
                )
    for orpheline in sorted(declares - utilises):
        ecarts.append(f"site/vercel.json : empreinte '{orpheline}' qui ne correspond plus à aucun script")
    for directive in ("default-src 'none'", "frame-ancestors 'none'"):
        if directive not in csp:
            ecarts.append(f"site/vercel.json : CSP sans « {directive} »")


def verifier_referencement(ecarts: list[str]) -> None:
    robots = PUBLIC / "robots.txt"
    plan = PUBLIC / "sitemap.xml"
    if not robots.is_file():
        ecarts.append("robots.txt absent")
    elif f"https://{DOMAINE}/sitemap.xml" not in robots.read_text(encoding="utf-8"):
        ecarts.append("robots.txt n'annonce pas le plan du site")
    if not plan.is_file():
        ecarts.append("sitemap.xml absent")
        return
    for url in re.findall(r"<loc>([^<]+)</loc>", plan.read_text(encoding="utf-8")):
        morceaux = urlsplit(url)
        if morceaux.netloc != DOMAINE or fichier_de(morceaux.path) is None:
            ecarts.append(f"sitemap.xml : « {url} » ne correspond à aucune page servie")


def verifier_marqueurs(ecarts: list[str]) -> list[str]:
    trouves = []
    for fichier in sorted(PUBLIC.rglob("*")):
        if fichier.suffix not in (".html", ".txt", ".xml", ".css", ".json"):
            continue
        for numero, ligne in enumerate(fichier.read_text(encoding="utf-8").splitlines(), 1):
            for marque in re.findall(re.escape(MARQUE) + r"[^\]]*\]", ligne):
                trouves.append(f"{fichier.relative_to(SITE)}:{numero} {marque}")
    for trouve in trouves:
        ecarts.append(f"marque restante : {trouve}")
    return trouves


def main(arguments: list[str]) -> int:
    analyseur = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    analyseur.add_argument(
        "--marqueurs",
        action="store_true",
        help="échoue aussi s'il reste une marque [À COMPLÉTER (contrôle de mise en ligne)",
    )
    analyseur.add_argument(
        "--lister-marqueurs",
        action="store_true",
        help="liste les marques restantes sans échouer pour autant",
    )
    options = analyseur.parse_args(arguments)

    if not PUBLIC.is_dir():
        print(f"::error::{PUBLIC} absent", file=sys.stderr)
        return 2

    analyses: dict[Path, Page] = {}
    for page in pages():
        analyse = Page()
        analyse.feed(page.read_text(encoding="utf-8"))
        analyses[page] = analyse

    ecarts: list[str] = []
    rapport: list[str] = [f"{len(analyses)} pages : {', '.join(p.name for p in analyses)}"]
    verifier_liens(analyses, ecarts)
    verifier_tiers(analyses, ecarts)
    verifier_poids(analyses, ecarts, rapport)
    verifier_pied(ecarts)
    verifier_csp(analyses, ecarts)
    verifier_referencement(ecarts)

    if options.marqueurs:
        verifier_marqueurs(ecarts)
    elif options.lister_marqueurs:
        restants: list[str] = []
        for trouve in verifier_marqueurs(restants):
            rapport.append(f"marque restante (non bloquante ici) : {trouve}")

    for ligne in rapport:
        print(ligne)
    if ecarts:
        for ecart in ecarts:
            print(f"::error::{ecart}")
        print(f"\n{len(ecarts)} écart(s).")
        return 1
    print("\nSite conforme.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
