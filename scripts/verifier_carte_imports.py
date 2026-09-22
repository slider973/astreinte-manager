#!/usr/bin/env python3
"""Répond à une seule question : « le déploiement saura-t-il résoudre les imports
des Edge Functions ? »

Le 21 septembre 2026, la réponse était non, et rien ne le disait (ticket 054).
Le travail « fonctions » déploie avec `--use-api` : l'empaquetage se fait **côté
serveur**, à partir des seuls fichiers que le CLI téléverse. Le CLI téléverse le
graphe des imports relatifs — et la carte d'imports **seulement si on la lui
nomme**. La nôtre vit dans `supabase/functions/deno.json` ; Deno la trouve en
remontant les dossiers, le téléverseur non. Les onze fonctions sont donc parties
sans elle, et le serveur a refusé les onze empaquetages :

    Failed to bundle the function (reason: Relative import path
    "@supabase/supabase-js" not prefixed with / or ./ or ../
      at …/supabase/functions/_shared/supabase.ts:7:51)

La tâche « edge-functions » de la CI ne pouvait pas l'attraper : `deno fmt`,
`deno lint`, `deno check` et `deno test` lisent le `deno.json` local, donc
passent. Ce script regarde ailleurs : il lit la **commande de déploiement** dans
`.github/workflows/deploy.yml`, en déduit la carte que le déploiement enverra,
puis vérifie que chaque specifier nu du graphe de chaque fonction y est résolu.

Ce n'est pas un empaquetage : il n'y a pas d'empaqueteur hors ligne qui
reproduise celui du serveur. C'est la seule chose que l'empaquetage distant sait
faire de plus que `deno check`, et c'est précisément celle qui a échoué.

Deux régressions le font échouer, et ce sont les deux à craindre :
  1. la carte disparaît de la commande de déploiement (ou le fichier n'existe
     plus) : plus rien ne résout les specifiers nus ;
  2. une fonction importe un specifier nu absent de la carte : `deno check`
     l'accepterait s'il était résolu autrement, le serveur non.

Usage :
    python3 scripts/verifier_carte_imports.py

Codes de sortie :
    0 — chaque specifier nu est résolu par la carte que le déploiement envoie ;
    1 — au moins un défaut, chacun nommé avec le fichier et la ligne ;
    2 — le script n'a pas pu conclure (fichier de workflow illisible).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
WORKFLOW = RACINE / ".github/workflows/deploy.yml"
DOSSIER_SUPABASE = RACINE / "supabase"
DOSSIER_FONCTIONS = DOSSIER_SUPABASE / "functions"
CONFIG = DOSSIER_SUPABASE / "config.toml"

# Dossiers de `supabase/functions/` qui ne sont pas des fonctions déployées.
NON_DEPLOYES = {"_shared", "tests"}

# Un specifier porté par un schéma (`npm:`, `jsr:`, `node:`, `https:`, `data:`)
# se résout tout seul, carte ou pas.
SCHEMA = re.compile(r"^[A-Za-z][A-Za-z0-9+.\-]*:")

# Les trois formes d'import qui créent une arête dans le graphe.
FORMES = (
    re.compile(r"""\bfrom\s*["']([^"']+)["']"""),
    re.compile(r"""\bimport\s*\(\s*["']([^"']+)["']"""),
    re.compile(r"""^\s*import\s+["']([^"']+)["']""", re.MULTILINE),
)

defauts: list[str] = []


def defaut(message: str) -> None:
    defauts.append(message)
    print(f"  DÉFAUT  {message}")


def ok(message: str) -> None:
    print(f"  OK      {message}")


def info(message: str) -> None:
    print(f"          {message}")


# ---------------------------------------------------------------------------
# 1. Quelle carte le déploiement envoie-t-il ?
# ---------------------------------------------------------------------------


def commande_de_deploiement() -> str:
    """La commande `supabase functions deploy` du workflow, continuations recollées."""
    if not WORKFLOW.exists():
        print(f"Workflow introuvable : {WORKFLOW}", file=sys.stderr)
        sys.exit(2)
    lignes = WORKFLOW.read_text(encoding="utf-8").splitlines()
    for depart, ligne in enumerate(lignes):
        nue = ligne.strip()
        if nue.startswith("#") or "supabase functions deploy" not in nue:
            continue
        morceaux = [nue]
        while morceaux[-1].endswith("\\") and depart + 1 < len(lignes):
            depart += 1
            morceaux.append(lignes[depart].strip())
        return " ".join(m.rstrip("\\").strip() for m in morceaux)
    print(
        "Aucune commande `supabase functions deploy` dans "
        f"{WORKFLOW.relative_to(RACINE)} : ce script ne sait plus ce que le "
        "déploiement enverra.",
        file=sys.stderr,
    )
    sys.exit(2)


def carte_globale(commande: str) -> Path | None:
    """Le chemin passé à `--import-map`, s'il y en a un.

    Le CLI le résout depuis le dossier de travail, qui est la racine du dépôt
    dans le workflow.
    """
    trouve = re.search(r"--import-map[=\s]+([^\s]+)", commande)
    if not trouve:
        return None
    return RACINE / trouve.group(1).strip("\"'")


def cartes_de_config() -> dict[str, str]:
    """Les `import_map` déclarés par fonction dans `supabase/config.toml`.

    L'autre voie possible : `[functions.<nom>] import_map = "…"`. Elle ne vaut
    que faute de mieux : `--import-map` la couvre (voir `carte_retenue`). Les
    chemins sont relatifs au dossier `supabase/`, pas à la racine du dépôt —
    `join(input.supabaseDir, configured.import_map)` dans le CLI.
    """
    if not CONFIG.exists():
        return {}
    cartes: dict[str, str] = {}
    section = None
    for ligne in CONFIG.read_text(encoding="utf-8").splitlines():
        nue = ligne.strip()
        if nue.startswith("#"):
            continue
        entete = re.match(r"^\[functions\.([A-Za-z0-9_-]+)\]", nue)
        if entete:
            section = entete.group(1)
            continue
        if nue.startswith("["):
            section = None
            continue
        valeur = re.match(r"""^import_map\s*=\s*["']([^"']+)["']""", nue)
        if valeur and section:
            cartes[section] = valeur.group(1)
    return cartes


def carte_retenue(
    fonction: str, globale: Path | None, par_fonction: dict[str, str]
) -> Path | None:
    """La carte que le déploiement enverra pour cette fonction.

    Précédence du CLI (2.117.0, `apps/cli/src/shared/functions/deploy.ts`) :

        let importMap = importMapOverride;
        if (importMap.length === 0) { … join(input.supabaseDir, configured.import_map) … }

    C'est donc `--import-map` qui prime, et non `[functions.<nom>] import_map` :
    dès que la commande désigne une carte, celle de `config.toml` est ignorée,
    pour toutes les fonctions. Prendre la précédence à l'envers laisserait
    passer une fonction dont le `config.toml` déclare une carte complète
    pendant que le déploiement enverrait la carte globale, incomplète.
    """
    if globale is not None:
        return globale
    relatif = par_fonction.get(fonction)
    if relatif is None:
        return None
    return DOSSIER_SUPABASE / relatif


def lire_carte(chemin: Path) -> dict[str, str] | None:
    if not chemin.exists():
        defaut(
            f"La carte d'imports désignée au déploiement n'existe pas : "
            f"{chemin.relative_to(RACINE) if chemin.is_relative_to(RACINE) else chemin}"
        )
        return None
    try:
        contenu = json.loads(chemin.read_text(encoding="utf-8"))
    except json.JSONDecodeError as erreur:
        defaut(f"Carte d'imports illisible ({chemin.name}) : {erreur}")
        return None
    imports = contenu.get("imports")
    if not isinstance(imports, dict) or not imports:
        # Faux positif théorique assumé : une carte d'imports n'ayant que
        # `scopes` est légale et peut tout résoudre. Aucune des nôtres n'est
        # dans ce cas, et le message resterait juste sur le fond (la carte
        # envoyée ne résout rien au premier niveau). À reprendre le jour où une
        # fonction aura besoin de `scopes`.
        defaut(f"La carte {chemin.name} ne déclare aucun `imports`.")
        return None
    return imports


def resolu(specifier: str, imports: dict[str, str]) -> bool:
    if specifier in imports:
        return True
    # Une clé terminée par « / » couvre tout ce qui commence par elle.
    return any(cle.endswith("/") and specifier.startswith(cle) for cle in imports)


# ---------------------------------------------------------------------------
# 2. Le graphe de chaque fonction, tel que le déploiement le téléverse
# ---------------------------------------------------------------------------


def sans_commentaires(source: str) -> str:
    """Retire les lignes entièrement commentées : un import commenté n'est pas un import."""
    gardees = []
    for ligne in source.splitlines():
        nue = ligne.lstrip()
        if nue.startswith(("//", "*", "/*")):
            gardees.append("")
        else:
            gardees.append(ligne)
    return "\n".join(gardees)


def specifiers(fichier: Path) -> list[tuple[str, int]]:
    source = sans_commentaires(fichier.read_text(encoding="utf-8"))
    trouves: list[tuple[str, int]] = []
    for forme in FORMES:
        for marque in forme.finditer(source):
            ligne = source.count("\n", 0, marque.start()) + 1
            trouves.append((marque.group(1), ligne))
    return sorted(set(trouves), key=lambda couple: couple[1])


def parcourir(entree: Path) -> tuple[set[Path], list[tuple[Path, str, int]]]:
    """Le graphe des imports relatifs, et les specifiers nus rencontrés en chemin."""
    vus: set[Path] = set()
    nus: list[tuple[Path, str, int]] = []
    pile = [entree]
    while pile:
        fichier = pile.pop()
        if fichier in vus:
            continue
        vus.add(fichier)
        for specifier, ligne in specifiers(fichier):
            if specifier.startswith(("./", "../", "/")):
                voisin = (fichier.parent / specifier).resolve()
                if not voisin.exists():
                    defaut(
                        f"{fichier.relative_to(RACINE)}:{ligne} importe "
                        f"« {specifier} », qui n'existe pas : le déploiement "
                        "téléverserait un graphe incomplet."
                    )
                    continue
                pile.append(voisin)
            elif not SCHEMA.match(specifier):
                nus.append((fichier, specifier, ligne))
    return vus, nus


# ---------------------------------------------------------------------------
# 3. Le verdict
# ---------------------------------------------------------------------------


def main() -> int:
    print("Carte d'imports du déploiement des Edge Functions")

    commande = commande_de_deploiement()
    globale = carte_globale(commande)
    par_fonction = cartes_de_config()

    if globale is not None:
        ok(
            "Le déploiement désigne une carte : "
            f"{globale.relative_to(RACINE) if globale.is_relative_to(RACINE) else globale}"
        )
        if par_fonction:
            info(
                f"{len(par_fonction)} `import_map` de supabase/config.toml "
                "ignoré(s) : `--import-map` les couvre."
            )
    elif par_fonction:
        ok(f"Cartes déclarées dans supabase/config.toml : {len(par_fonction)}")
    else:
        defaut(
            "La commande de déploiement ne désigne aucune carte d'imports "
            "(`--import-map`) et supabase/config.toml n'en déclare aucune. "
            "Avec `--use-api`, l'empaquetage se fait côté serveur sur les seuls "
            "fichiers téléversés : un `deno.json` trouvé en remontant les "
            "dossiers n'y est pas. Toute fonction important un specifier nu sera "
            "refusée (exécution 35651547935, docs/DEPLOIEMENT.md § 8)."
        )

    # Une fonction est un dossier avec un `index.ts` : c'est la forme de nos
    # onze. Le CLI accepte aussi `[functions.<nom>] entrypoint = "…"`, qui
    # rendrait la fonction invisible ici. Aucune ne l'utilise ; à reprendre si
    # l'une vient à le faire.
    fonctions = sorted(
        dossier
        for dossier in DOSSIER_FONCTIONS.iterdir()
        if dossier.is_dir()
        and dossier.name not in NON_DEPLOYES
        and (dossier / "index.ts").exists()
    )
    if not fonctions:
        print("Aucune Edge Function trouvée.", file=sys.stderr)
        return 2
    info(f"{len(fonctions)} fonctions à déployer")

    caches: dict[Path, dict[str, str] | None] = {}
    for fonction in fonctions:
        _, nus = parcourir(fonction / "index.ts")
        if not nus:
            ok(f"{fonction.name} — aucun specifier nu")
            continue

        chemin_carte = carte_retenue(fonction.name, globale, par_fonction)
        if chemin_carte is None:
            for fichier, specifier, ligne in nus:
                defaut(
                    f"{fonction.name} : {fichier.relative_to(RACINE)}:{ligne} "
                    f"importe « {specifier} », qu'aucune carte envoyée au "
                    "déploiement ne résout."
                )
            continue

        if chemin_carte not in caches:
            caches[chemin_carte] = lire_carte(chemin_carte)
        imports = caches[chemin_carte]
        if imports is None:
            continue

        manquants = [triplet for triplet in nus if not resolu(triplet[1], imports)]
        for fichier, specifier, ligne in manquants:
            defaut(
                f"{fonction.name} : {fichier.relative_to(RACINE)}:{ligne} "
                f"importe « {specifier} », absent de {chemin_carte.name}. "
                "Ajouter la clé à la carte, ou préfixer le specifier "
                "(`npm:`, `jsr:`, `node:`)."
            )
        if not manquants:
            resumes = ", ".join(sorted({triplet[1] for triplet in nus}))
            ok(f"{fonction.name} — {resumes} résolu par {chemin_carte.name}")

    print()
    if defauts:
        print(
            f"{len(defauts)} défaut(s) : le déploiement des Edge Functions serait "
            "refusé à l'empaquetage."
        )
        return 1
    print("Chaque specifier nu est résolu par la carte que le déploiement envoie.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
