#!/usr/bin/env python3
"""Met la PWA en ligne chez Vercel **par l'API**, sans la ligne de commande.

Pourquoi ce script existe
-------------------------
Le jeton posé dans les secrets du dépôt est un jeton **de projet** (préfixe
`vcp_`), créé depuis la page des jetons du compte avec le projet pour portée.
Il autorise l'API de déploiement mais n'a aucun contexte utilisateur, et la
ligne de commande Vercel commence par charger l'utilisateur : `vercel pull`,
`vercel build` et `vercel deploy` répondent tous

    Not able to load user because of unexpected error: User not found. (404)

Le propriétaire en a créé deux, même résultat ; c'est le type de jeton qui veut
ça, pas le jeton. L'API, elle, accepte ce jeton : les mises en ligne des 21 et
22 septembre 2026 sont passées par elle. Ce script fait ce qu'elles faisaient,
en le rendant rejouable (ticket 060).

Ce qu'il fait, dans l'ordre
---------------------------
1. empreinte SHA-1 de chaque fichier de `build/web`, plus `vercel.json` ;
2. `POST /v2/files` avec l'en-tête `x-vercel-digest` — quelques envois de front,
   reprise sur erreur passagère ;
3. `POST /v13/deployments` avec la liste des fichiers, `target: production`,
   `projectSettings` vides — **aucune construction côté Vercel** au sens Flutter,
   la PWA est construite sur l'exécuteur ;
4. attente de l'état `READY`, délai borné, échec bruyant sinon ;
5. attente de l'**alias de production** — le domaine du produit — dans les
   alias du déploiement, délai borné, échec bruyant sinon (ticket 062) ;
6. sortie de l'URL et de l'identifiant, sur la sortie standard et dans
   `$GITHUB_OUTPUT` quand la variable existe.

Le domaine de production, une constante, jamais un choix
--------------------------------------------------------
Jusqu'au 22 septembre 2026, l'adresse rendue au workflow était **choisie à
l'exécution** parmi les alias du déploiement : le premier qui ne finissait pas
par `.vercel.app`. Un déploiement peut être `READY` avant que Vercel ait posé
l'alias du domaine ; l'API ne listait alors que
`astreinte-manager-<équipe>.vercel.app`, et le script s'y rabattait. Cet alias
d'équipe est derrière la protection de déploiement : il rend 302 vers
`vercel.com/sso-api`, et l'étape « Vérifier les en-têtes servis » lisait les
en-têtes de vercel.com au lieu de ceux de l'application (run 35768686568).

Le domaine est donc lu **dans le dépôt**, à l'endroit où il est déjà écrit :
`supabase/config.toml`, `[remotes.production.auth].site_url`. Ce n'est pas une
coïncidence de valeur, c'est la même chose — l'origine publique de
l'application ; si les deux divergeaient, les liens de connexion ramèneraient
ailleurs que sur le site servi. Une variable de plus dans le workflow, ou un
secret, aurait créé un second endroit où dire la même adresse, donc un endroit
où l'oublier.

Le script attend ensuite que ce domaine figure dans les alias, puis le rend. Il
ne choisit plus : un déploiement `READY` dont l'alias de production n'est pas
posé n'est pas une mise en ligne, et le dire en rouge vaut mieux que vérifier
une autre adresse.

La place de `vercel.json`, et pourquoi elle compte
--------------------------------------------------
**Un déploiement par l'API n'applique `vercel.json` que si le fichier fait
partie des fichiers envoyés**, à la racine du déploiement. Les quatre mises en
ligne manuelles ne l'envoyaient pas : le 22 septembre 2026, la production
répondait **404 sur `/install` et sur `/admin/planning`** (la réécriture vers
`index.html` n'existait pas) et ne servait ni `X-Content-Type-Options`, ni
`Referrer-Policy`, ni `X-Frame-Options`. Le `Cache-Control: public, max-age=0,
must-revalidate` que l'on y lisait n'était pas le nôtre, c'est celui que Vercel
pose par défaut — d'où l'illusion que la configuration passait.

Ce script envoie donc `vercel.json` à la racine et range les fichiers construits
sous le chemin que ce même `vercel.json` déclare en `outputDirectory`
(`build/web`). La disposition du déploiement est alors celle du dépôt, et les
en-têtes comme les réécritures sont ceux du fichier versionné : rien n'est
dérivé, rien ne peut diverger. La « construction » que Vercel lance alors est
celle que `vercel.json` déclare, deux `echo` (§ 7 de docs/DEPLOIEMENT.md).

Usage
-----
    VERCEL_TOKEN=vcp_… VERCEL_ORG_ID=team_… VERCEL_PROJECT_ID=prj_… \
        scripts/deployer_pwa.py [options]

    --racine CHEMIN      répertoire construit à envoyer (défaut : build/web)
    --config CHEMIN      configuration Vercel à joindre (défaut : vercel.json,
                         `--config ""` pour n'en joindre aucune)
    --attente SECONDES   délai maximal d'attente de `READY` (défaut : 600)
    --attente-alias SEC  délai maximal d'attente de l'alias de production
                         (défaut : 120)
    --domaine DOMAINE    domaine de production à attendre et à rendre ; par
                         défaut, `site_url` de `[remotes.production.auth]` dans
                         `supabase/config.toml`
    --parallele N        envois de front (défaut : 8)
    --dry-run            n'envoie rien, liste ce qui partirait

Codes de sortie
---------------
    0 — déploiement `READY` et alias de production posé, ou `--dry-run` mené à
        son terme ;
    1 — échec : envoi refusé, déploiement en erreur, `READY` non atteint, alias
        de production absent à l'échéance ;
    2 — le script n'a pas pu commencer (variable ou fichier manquant).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

try:  # Python ≥ 3.11 ; l'exécuteur d'Actions est en 3.12.
    import tomllib
except ModuleNotFoundError:  # pragma: no cover — ne se produit qu'en 3.10 et avant
    tomllib = None  # type: ignore[assignment]

API = "https://api.vercel.com"

# Le domaine de production n'est écrit qu'une fois dans le dépôt : c'est
# l'origine publique de l'application, et `config push` la pose aussi comme
# `site_url` de l'authentification. Le lire ici plutôt que le redire garde les
# deux d'accord — voir l'en-tête du module.
CONFIG_SUPABASE = Path(__file__).resolve().parent.parent / "supabase" / "config.toml"
SECTION_DOMAINE = ("remotes", "production", "auth")
CLE_DOMAINE = "site_url"

# Un envoi qui échoue pour une raison passagère — 429, 5xx, coupure — est rejoué.
# Un 4xx qui n'est pas un 429 est une erreur de notre côté : le rejouer ferait
# perdre du temps sans rien changer.
TENTATIVES = 4
ATTENTE_ENTRE_TENTATIVES = 2.0
DELAI_RESEAU = 120

ETATS_FINAUX = {"READY", "ERROR", "CANCELED", "DELETED"}


class Echec(Exception):
    """Une raison d'arrêter, formulée pour être lue dans un journal d'Actions."""


def journal(message: str) -> None:
    print(message, flush=True)


# ---------------------------------------------------------------------------
# Appels HTTP
# ---------------------------------------------------------------------------


def appeler(
    url: str,
    jeton: str,
    *,
    corps: bytes | None = None,
    entetes: dict[str, str] | None = None,
    methode: str | None = None,
) -> dict:
    """Un appel à l'API, la réponse JSON décodée. Lève `urllib.error.HTTPError`."""
    tous = {"Authorization": f"Bearer {jeton}"}
    tous.update(entetes or {})
    requete = urllib.request.Request(url, data=corps, headers=tous, method=methode)
    contexte = ssl.create_default_context()
    with urllib.request.urlopen(requete, timeout=DELAI_RESEAU, context=contexte) as reponse:
        brut = reponse.read()
    return json.loads(brut or b"{}")


def passager(erreur: BaseException) -> bool:
    if isinstance(erreur, urllib.error.HTTPError):
        return erreur.code == 429 or erreur.code >= 500
    return isinstance(erreur, (urllib.error.URLError, TimeoutError, OSError))


def avec_reprise(quoi: str, action) -> dict:
    """Rejoue `action` tant que l'échec est passager, puis abandonne en le disant."""
    derniere: BaseException | None = None
    for tentative in range(1, TENTATIVES + 1):
        try:
            return action()
        except Exception as erreur:  # noqa: BLE001 — le détail est rendu plus bas
            derniere = erreur
            if not passager(erreur) or tentative == TENTATIVES:
                break
            pause = ATTENTE_ENTRE_TENTATIVES * tentative
            journal(f"  {quoi} : {decrire(erreur)} — nouvelle tentative dans {pause:.0f} s")
            time.sleep(pause)
    raise Echec(f"{quoi} : {decrire(derniere)}")


def decrire(erreur: BaseException | None) -> str:
    if isinstance(erreur, urllib.error.HTTPError):
        try:
            detail = erreur.read().decode("utf-8", "replace")[:500]
        except Exception:  # noqa: BLE001
            detail = ""
        return f"HTTP {erreur.code} {detail}".strip()
    return f"{type(erreur).__name__}: {erreur}" if erreur else "raison inconnue"


# ---------------------------------------------------------------------------
# Les fichiers à envoyer
# ---------------------------------------------------------------------------


def sortie_declaree(config: Path | None) -> str:
    """Le `outputDirectory` de `vercel.json`, sous lequel ranger la construction.

    Lire la valeur plutôt que la redire ici garde le déploiement et le dépôt
    d'accord : changer `outputDirectory` dans `vercel.json` déplace du même coup
    ce que ce script envoie.
    """
    if config is None:
        return ""
    try:
        declare = json.loads(config.read_text(encoding="utf-8")).get("outputDirectory")
    except (OSError, json.JSONDecodeError) as erreur:
        raise Echec(f"{config} illisible : {erreur}") from erreur
    return (declare or "").strip("/")


def recenser(racine: Path, prefixe: str, config: Path | None) -> list[dict]:
    """La liste des fichiers du déploiement : chemin, empreinte, taille, octets."""
    fichiers: list[dict] = []

    if config is not None:
        octets = config.read_bytes()
        fichiers.append(
            {
                "file": config.name,
                "sha": hashlib.sha1(octets).hexdigest(),
                "size": len(octets),
                "octets": octets,
            }
        )

    for chemin in sorted(p for p in racine.rglob("*") if p.is_file()):
        relatif = chemin.relative_to(racine).as_posix()
        octets = chemin.read_bytes()
        fichiers.append(
            {
                "file": f"{prefixe}/{relatif}" if prefixe else relatif,
                "sha": hashlib.sha1(octets).hexdigest(),
                "size": len(octets),
                "octets": octets,
            }
        )
    return fichiers


def televerser(fichiers: list[dict], jeton: str, equipe: str, parallele: int) -> None:
    total = len(fichiers)
    faits = 0

    def un(fichier: dict) -> dict:
        return avec_reprise(
            f"envoi de {fichier['file']}",
            lambda: appeler(
                f"{API}/v2/files?teamId={equipe}",
                jeton,
                corps=fichier["octets"],
                entetes={
                    "Content-Type": "application/octet-stream",
                    "x-vercel-digest": fichier["sha"],
                    "Content-Length": str(fichier["size"]),
                },
                methode="POST",
            ),
        )

    with ThreadPoolExecutor(max_workers=max(1, parallele)) as grappe:
        for _ in grappe.map(un, fichiers):
            faits += 1
            if faits % 16 == 0 or faits == total:
                journal(f"  {faits}/{total} envoyés")


# ---------------------------------------------------------------------------
# Le déploiement
# ---------------------------------------------------------------------------


def nom_projet(jeton: str, equipe: str, projet: str) -> str:
    """Le nom du projet, que `POST /v13/deployments` exige en plus de son identifiant.

    Sans lui : « Invalid request: missing required property `name` ». Il est lu
    plutôt que posé en secret — un secret de plus à tenir à jour pour une valeur
    que le jeton sait déjà lire serait une occasion de dérive.
    """
    reponse = avec_reprise(
        "lecture du projet",
        lambda: appeler(f"{API}/v9/projects/{projet}?teamId={equipe}", jeton),
    )
    nom = reponse.get("name")
    if not nom:
        raise Echec(f"projet {projet} sans nom lisible : {json.dumps(reponse)[:300]}")
    return nom


def corps_deploiement(fichiers: list[dict], projet: str, nom: str) -> dict:
    return {
        "name": nom,
        "project": projet,
        "target": "production",
        "files": [{"file": f["file"], "sha": f["sha"], "size": f["size"]} for f in fichiers],
        # Rien ici : ce que Vercel doit faire est écrit dans `vercel.json`, qui
        # fait partie des fichiers envoyés. Laisser ces quatre champs nuls évite
        # qu'un réglage du tableau de bord prenne le pas sur le dépôt.
        "projectSettings": {
            "framework": None,
            "buildCommand": None,
            "installCommand": None,
            "outputDirectory": None,
        },
    }


def creer(fichiers: list[dict], jeton: str, equipe: str, projet: str, nom: str) -> dict:
    corps = json.dumps(corps_deploiement(fichiers, projet, nom)).encode()
    return avec_reprise(
        "création du déploiement",
        lambda: appeler(
            f"{API}/v13/deployments?teamId={equipe}&skipAutoDetectionConfirmation=1",
            jeton,
            corps=corps,
            entetes={"Content-Type": "application/json"},
            methode="POST",
        ),
    )


def attendre(identifiant: str, jeton: str, equipe: str, limite: float) -> dict:
    """Attend un état final. Rend le dernier état lu ; lève si le délai est passé."""
    echeance = time.monotonic() + limite
    precedent = ""
    while time.monotonic() < echeance:
        etat = avec_reprise(
            "lecture de l'état du déploiement",
            lambda: appeler(f"{API}/v13/deployments/{identifiant}?teamId={equipe}", jeton),
        )
        courant = etat.get("readyState") or etat.get("status") or "?"
        if courant != precedent:
            journal(f"  état : {courant}")
            precedent = courant
        if courant in ETATS_FINAUX:
            return etat
        time.sleep(3)
    raise Echec(
        f"le déploiement {identifiant} n'a pas atteint READY en {limite:.0f} s "
        f"(dernier état lu : {precedent or 'aucun'})"
    )


def domaine_production(source: Path = CONFIG_SUPABASE) -> str:
    """Le domaine du produit, lu là où le dépôt l'écrit déjà, sans le scheme.

    `supabase/config.toml`, `[remotes.production.auth].site_url` : l'origine
    servie par Vercel, que `config push` pose aussi comme adresse de retour des
    liens de connexion. Une seule écriture pour une seule adresse.
    """
    if tomllib is None:  # pragma: no cover — Python 3.10 et avant
        raise Echec(
            "lecture du domaine impossible : tomllib demande Python 3.11. "
            "Passer --domaine <domaine> pour s'en dispenser."
        )
    try:
        config = tomllib.loads(source.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as erreur:
        raise Echec(f"{source} illisible : {erreur}") from erreur

    noeud: object = config
    chemin = ".".join(SECTION_DOMAINE)
    for clef in SECTION_DOMAINE:
        if not isinstance(noeud, dict) or clef not in noeud:
            raise Echec(f"{source} : section [{chemin}] absente, domaine de production inconnu")
        noeud = noeud[clef]

    brut = noeud.get(CLE_DOMAINE) if isinstance(noeud, dict) else None
    if not isinstance(brut, str) or not brut.strip():
        raise Echec(f"{source} : [{chemin}] sans {CLE_DOMAINE}, domaine de production inconnu")
    return normaliser_domaine(brut)


def normaliser_domaine(brut: str) -> str:
    """`https://astreinte.example/` → `astreinte.example`, forme des alias."""
    domaine = brut.strip().split("://", 1)[-1].strip("/")
    if not domaine:
        raise Echec(f"domaine de production vide : « {brut} »")
    return domaine


def attendre_alias(
    identifiant: str, jeton: str, equipe: str, domaine: str, limite: float
) -> list[str]:
    """Attend que `domaine` figure dans les alias du déploiement. Lève sinon.

    `READY` et « en ligne » ne sont pas le même instant : Vercel bascule l'alias
    du domaine quelques secondes après l'état final. Vérifier l'application
    avant cette bascule, c'est vérifier l'alias d'équipe `*.vercel.app`, que la
    protection de déploiement renvoie vers une page de connexion Vercel. Et un
    déploiement dont l'alias de production n'arrive jamais n'est pas une mise en
    ligne : il faut alors le dire, pas rendre une autre adresse.
    """
    debut = time.monotonic()
    echeance = debut + limite
    derniers: list[str] = []
    annonce = ""
    while True:
        etat = avec_reprise(
            "lecture des alias du déploiement",
            lambda: appeler(f"{API}/v13/deployments/{identifiant}?teamId={equipe}", jeton),
        )
        derniers = [a for a in (etat.get("alias") or []) if a]
        if domaine in derniers:
            journal(
                f"  alias de production posé au bout de {time.monotonic() - debut:.0f} s : "
                f"https://{domaine}"
            )
            return derniers
        if time.monotonic() >= echeance:
            break
        courant = ", ".join(derniers) or "aucun"
        if courant != annonce:
            journal(f"  alias posés : {courant} — {domaine} pas encore là")
            annonce = courant
        time.sleep(3)

    raise Echec(
        f"le déploiement {identifiant} est READY mais {domaine} ne figure pas dans ses alias "
        f"après {limite:.0f} s (alias lus : {', '.join(derniers) or 'aucun'}). "
        f"Un déploiement prêt sans son alias de production n'est pas une mise en ligne : "
        f"vérifier le domaine dans Vercel → Settings → Domains et "
        f"[{'.'.join(SECTION_DOMAINE)}].{CLE_DOMAINE} dans "
        f"{CONFIG_SUPABASE.parent.name}/{CONFIG_SUPABASE.name}."
    )


def publier_sorties(**valeurs: str) -> None:
    """Écrit les sorties dans `$GITHUB_OUTPUT` si la variable existe, sinon rien.

    Aucun chemin en dur : hors d'Actions, la sortie standard suffit.
    """
    destination = os.environ.get("GITHUB_OUTPUT")
    if not destination:
        return
    with open(destination, "a", encoding="utf-8") as sortie:
        for cle, valeur in valeurs.items():
            sortie.write(f"{cle}={valeur}\n")


# ---------------------------------------------------------------------------


def analyser(arguments: list[str]) -> argparse.Namespace:
    analyseur = argparse.ArgumentParser(
        description="Met build/web en ligne chez Vercel par l'API.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    analyseur.add_argument("--racine", default="build/web", help="répertoire construit")
    analyseur.add_argument(
        "--config",
        default="vercel.json",
        help="configuration Vercel jointe à la racine du déploiement ; vide pour aucune",
    )
    analyseur.add_argument("--attente", type=float, default=600.0, help="secondes avant abandon")
    analyseur.add_argument(
        "--attente-alias",
        type=float,
        default=120.0,
        help="secondes d'attente de l'alias de production après READY",
    )
    analyseur.add_argument(
        "--domaine",
        default="",
        help="domaine de production ; par défaut celui de supabase/config.toml",
    )
    analyseur.add_argument("--parallele", type=int, default=8, help="envois de front")
    analyseur.add_argument(
        "--dry-run",
        action="store_true",
        help="n'envoie rien : liste les fichiers, les empreintes et le corps du déploiement",
    )
    return analyseur.parse_args(arguments)


def main(arguments: list[str]) -> int:
    options = analyser(arguments)

    racine = Path(options.racine)
    if not racine.is_dir():
        journal(
            f"::error::{racine} absent : construire d'abord "
            f"(`scripts/build_web.sh env/prod.json`)."
        )
        return 2

    config = Path(options.config) if options.config else None
    if config is not None and not config.is_file():
        journal(f"::error::{config} absent : sans lui, ni en-têtes ni réécritures.")
        return 2

    manquants = [
        nom
        for nom in ("VERCEL_TOKEN", "VERCEL_ORG_ID", "VERCEL_PROJECT_ID")
        if not os.environ.get(nom)
    ]
    if manquants and not options.dry_run:
        journal(
            "::error::Variables absentes : "
            + " ".join(manquants)
            + ". Les poser dans Settings → Secrets and variables → Actions "
            "(voir docs/DEPLOIEMENT.md § 3)."
        )
        return 2

    jeton = os.environ.get("VERCEL_TOKEN", "")
    equipe = os.environ.get("VERCEL_ORG_ID", "")
    projet = os.environ.get("VERCEL_PROJECT_ID", "")

    try:
        domaine = (
            normaliser_domaine(options.domaine) if options.domaine else domaine_production()
        )
        journal(f"domaine de production : https://{domaine}")

        prefixe = sortie_declaree(config)
        fichiers = recenser(racine, prefixe, config)
        if not fichiers:
            journal(f"::error::{racine} est vide.")
            return 2

        octets = sum(f["size"] for f in fichiers)
        journal(
            f"{len(fichiers)} fichiers, {octets // 1024} Kio — "
            f"{racine} rangé sous « {prefixe or 'la racine'} »"
            + (f", {config.name} à la racine" if config is not None else "")
        )

        if options.dry_run:
            journal("\n--dry-run : rien n'est envoyé. Ce qui partirait :\n")
            for fichier in fichiers:
                journal(f"  {fichier['sha']}  {fichier['size']:>9}  {fichier['file']}")
            corps = corps_deploiement(
                fichiers, projet or "<VERCEL_PROJECT_ID>", "<nom lu chez Vercel>"
            )
            journal("\nPOST /v13/deployments :")
            journal(json.dumps({**corps, "files": f"[{len(fichiers)} entrées]"}, indent=2))
            return 0

        journal(f"→ téléversement ({options.parallele} de front)")
        televerser(fichiers, jeton, equipe, options.parallele)

        journal("→ création du déploiement de production")
        nom = nom_projet(jeton, equipe, projet)
        cree = creer(fichiers, jeton, equipe, projet, nom)
        identifiant = cree.get("id") or ""
        if not identifiant:
            raise Echec(f"réponse sans identifiant de déploiement : {json.dumps(cree)[:400]}")
        adresse = "https://" + (cree.get("url") or "")
        journal(f"  identifiant : {identifiant}")
        journal(f"  adresse     : {adresse}")

        journal(f"→ attente de READY (au plus {options.attente:.0f} s)")
        final = attendre(identifiant, jeton, equipe, options.attente)
        etat = final.get("readyState") or final.get("status") or "?"
        if etat != "READY":
            erreur = final.get("errorMessage") or final.get("errorCode") or ""
            raise Echec(f"déploiement {identifiant} en état {etat}. {erreur}".strip())

        journal(f"→ attente de l'alias {domaine} (au plus {options.attente_alias:.0f} s)")
        alias = attendre_alias(identifiant, jeton, equipe, domaine, options.attente_alias)
        for pose in alias:
            journal(f"  alias : https://{pose}")

        # L'adresse rendue est le domaine, toujours : c'est elle que les deux
        # étapes de vérification du workflow interrogent, et la seule qui ne
        # soit pas derrière la protection de déploiement de l'équipe.
        publique = f"https://{domaine}"
        journal(f"\nREADY — {identifiant} — {publique}")
        publier_sorties(url=publique, id=identifiant, deploiement=adresse)
        return 0

    except Echec as echec:
        journal(f"::error::Mise en ligne Vercel : {echec}")
        return 1
    except KeyboardInterrupt:
        journal("::error::Interrompu.")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
