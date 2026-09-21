#!/usr/bin/env bash
# Construit la PWA prête à être servie par l'hébergeur.
#
#   scripts/build_web.sh [fichier-env]        (défaut : env/prod.json)
#
# Deux choses de plus que `flutter build web --release` :
#
#   1. la compression brotli des polices embarquées. `assets/fonts/README.md`
#      explique pourquoi elles restent en TTF (Flutter web ne décode pas le
#      WOFF2) ; le seul levier est donc la compression de transport, et elle
#      fait passer les cinq fichiers de 184 Ko à ~83 Ko. Les octets sont
#      remplacés **sur place** ; c'est `vercel.json` qui annonce
#      `Content-Encoding: br` sur ces chemins ;
#   2. un état des lieux chiffré de ce qui part en production.
#
# Le service worker n'est pas dérangé : sa table `RESOURCES` sert de clé de
# cache, pas de somme de contrôle — le navigateur lui remet des octets déjà
# décodés.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${1:-env/prod.json}"
SORTIE="build/web"
POLICES="$SORTIE/assets/assets/fonts"

die() { echo "erreur : $*" >&2; exit 1; }

command -v flutter >/dev/null || die "flutter introuvable dans le PATH."
command -v brotli >/dev/null ||
  die "brotli introuvable. macOS : brew install brotli. Debian/Ubuntu : apt-get install -y brotli."
[ -f "$ENV_FILE" ] ||
  die "$ENV_FILE absent. Copier env/prod.json.example et le remplir (voir env/README.md)."

echo "→ flutter build web --release --dart-define-from-file=$ENV_FILE"
flutter build web --release --dart-define-from-file="$ENV_FILE"

echo
echo "→ compression brotli des polices"
[ -d "$POLICES" ] || die "$POLICES absent : la construction n'a pas produit les polices."

avant=0
apres=0
for police in "$POLICES"/*.ttf; do
  [ -e "$police" ] || die "aucune police dans $POLICES."
  taille_avant=$(wc -c < "$police")
  # -11 : le meilleur taux. Ces fichiers sont compressés une fois par
  # construction, jamais à la requête ; le temps CPU n'a pas d'importance ici.
  brotli --quality=11 --force --output="$police.br" "$police"
  mv "$police.br" "$police"
  taille_apres=$(wc -c < "$police")
  avant=$((avant + taille_avant))
  apres=$((apres + taille_apres))
  printf '   %-44s %6s Ko → %5s Ko\n' \
    "$(basename "$police")" "$((taille_avant / 1024))" "$((taille_apres / 1024))"
done
printf '   %-44s %6s Ko → %5s Ko\n' "TOTAL" "$((avant / 1024))" "$((apres / 1024))"

echo
echo "→ ce qui part en production"
du -sh "$SORTIE" | awk '{ printf "   %-12s %s\n", "total", $1 }'
for fichier in main.dart.js flutter_bootstrap.js flutter_service_worker.js index.html; do
  [ -f "$SORTIE/$fichier" ] &&
    printf '   %-26s %6s Ko\n' "$fichier" "$(( $(wc -c < "$SORTIE/$fichier") / 1024 ))"
done

echo
echo "Prêt. Les polices ne sont lisibles qu'avec l'en-tête Content-Encoding: br"
echo "de vercel.json — les servir sans cet en-tête donne des fichiers illisibles."
