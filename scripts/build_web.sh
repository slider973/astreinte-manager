#!/usr/bin/env bash
# Construit la PWA prête à être servie par l'hébergeur.
#
#   scripts/build_web.sh [fichier-env]        (défaut : env/prod.json)
#
# Quatre choses de plus que `flutter build web --release` :
#
#   1. `--no-web-resources-cdn` : le moteur de rendu CanvasKit est servi par
#      l'hébergement du produit, pas par `www.gstatic.com` (ticket 037).
#      `web/flutter_bootstrap.js` pose déjà `canvasKitBaseUrl` et suffirait ;
#      le drapeau est la même décision côté ligne de commande, pour qu'une
#      construction reste correcte même si le gabarit d'amorçage disparaît ;
#   2. l'élagage de `canvaskit/` : la construction y recopie systématiquement
#      les deux moteurs WebAssembly (`skwasm*`, 14 Mo) et les tables de
#      symboles de débogage (`*.symbols`, 5,7 Mo). Aucun des deux n'est
#      atteignable depuis une construction `dart2js` + `canvaskit` — le
#      chargeur ne les demandera jamais. Ils ne partent donc pas chez
#      l'hébergeur ;
#   3. la compression brotli de ce qui reste et des polices embarquées.
#      `assets/fonts/README.md` explique pourquoi les polices restent en TTF
#      (Flutter web ne décode pas le WOFF2) ; le seul levier est la
#      compression de transport, et elle fait passer les cinq fichiers de
#      184 Ko à ~83 Ko. Pour CanvasKit, c'est ce qui rend l'auto-hébergement
#      viable : 5,7 Mo de `.wasm` deviennent 1,6 Mo, soit exactement ce que
#      servait le CDN de Google. Les octets sont remplacés **sur place** ;
#      c'est `vercel.json` qui annonce `Content-Encoding: br` sur ces chemins ;
#   4. un état des lieux chiffré de ce qui part en production.
#
# Le service worker n'est pas dérangé : sa table `RESOURCES` sert de clé de
# cache, pas de somme de contrôle — le navigateur lui remet des octets déjà
# décodés. Les fichiers élagués y restent listés sans conséquence : le moteur
# ne les demande pas, donc le service worker ne les met jamais en cache.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${1:-env/prod.json}"
SORTIE="build/web"
POLICES="$SORTIE/assets/assets/fonts"
MOTEUR="$SORTIE/canvaskit"

die() { echo "erreur : $*" >&2; exit 1; }

command -v flutter >/dev/null || die "flutter introuvable dans le PATH."
command -v brotli >/dev/null ||
  die "brotli introuvable. macOS : brew install brotli. Debian/Ubuntu : apt-get install -y brotli."
[ -f "$ENV_FILE" ] ||
  die "$ENV_FILE absent. Copier env/prod.json.example et le remplir (voir env/README.md)."

echo "→ flutter build web --release --no-web-resources-cdn --dart-define-from-file=$ENV_FILE"
flutter build web --release --no-web-resources-cdn --dart-define-from-file="$ENV_FILE"

# Garde-fou : si un jour le chargeur repartait chez Google, la mise en ligne
# doit s'arrêter ici plutôt que de le découvrir au journal réseau d'un
# téléphone. L'adresse `www.gstatic.com/flutter-canvaskit` est *présente* dans
# `flutter.js` — c'est la branche par défaut du chargeur ; ce qui compte est
# qu'aucune des deux conditions qui y mènent ne soit remplie.
grep -q '"useLocalCanvasKit":true' "$SORTIE/flutter_bootstrap.js" ||
  die "flutter_bootstrap.js sans useLocalCanvasKit : --no-web-resources-cdn n'a pas pris (ticket 037)."
grep -q 'canvasKitBaseUrl' "$SORTIE/flutter_bootstrap.js" ||
  die "flutter_bootstrap.js sans canvasKitBaseUrl : web/flutter_bootstrap.js n'a pas été repris (ticket 037)."
grep -q 'fontFallbackBaseUrl' "$SORTIE/flutter_bootstrap.js" ||
  die "flutter_bootstrap.js sans fontFallbackBaseUrl : les polices Noto repartiraient chez Google (ticket 037)."
# `flutter build web` substitue ses jetons `{{…}}` **aussi dans les
# commentaires** de `web/flutter_bootstrap.js`. Un jeton cité de travers y
# recopie tout `flutter.js` au milieu d'une phrase : le fichier est produit,
# il pèse le bon poids, et la page reste blanche. Un seul contrôle le voit.
if command -v node >/dev/null; then
  node --check "$SORTIE/flutter_bootstrap.js" ||
    die "flutter_bootstrap.js n'est pas du JavaScript valide : voir les jetons de web/flutter_bootstrap.js."
fi

echo
echo "→ élagage du moteur : ce qu'une construction dart2js/canvaskit ne demande jamais"
[ -d "$MOTEUR" ] || die "$MOTEUR absent : la construction n'a pas recopié CanvasKit."
if grep -q '"renderer":"skwasm"' "$SORTIE/flutter_bootstrap.js"; then
  die "la construction déclare un moteur skwasm : ne pas élaguer skwasm* sans revoir ce script."
fi
elague=0
while IFS= read -r -d '' inutile; do
  elague=$((elague + $(wc -c < "$inutile")))
  rm -f "$inutile"
done < <(find "$MOTEUR" \( -name '*.symbols' -o -name 'skwasm*' \) -type f -print0)
printf '   %-44s %6s Ko retirés\n' "skwasm*, *.symbols" "$((elague / 1024))"

echo
echo "→ compression brotli du moteur"
avant=0
apres=0
while IFS= read -r -d '' fichier; do
  taille_avant=$(wc -c < "$fichier")
  brotli --quality=11 --force --output="$fichier.br" "$fichier"
  mv "$fichier.br" "$fichier"
  taille_apres=$(wc -c < "$fichier")
  avant=$((avant + taille_avant))
  apres=$((apres + taille_apres))
  printf '   %-44s %6s Ko → %5s Ko\n' \
    "${fichier#"$SORTIE/"}" "$((taille_avant / 1024))" "$((taille_apres / 1024))"
done < <(find "$MOTEUR" \( -name '*.wasm' -o -name '*.js' \) -type f -print0)
[ "$avant" -gt 0 ] || die "aucun fichier de moteur à compresser dans $MOTEUR."
printf '   %-44s %6s Ko → %5s Ko\n' "TOTAL" "$((avant / 1024))" "$((apres / 1024))"

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
for fichier in main.dart.js flutter_bootstrap.js flutter_service_worker.js index.html \
               canvaskit/chromium/canvaskit.wasm canvaskit/canvaskit.wasm; do
  [ -f "$SORTIE/$fichier" ] &&
    printf '   %-26s %6s Ko\n' "$fichier" "$(( $(wc -c < "$SORTIE/$fichier") / 1024 ))"
done

echo
echo "Prêt. Les polices et CanvasKit ne sont lisibles qu'avec l'en-tête"
echo "Content-Encoding: br de vercel.json — les servir sans cet en-tête donne"
echo "des fichiers illisibles et une application qui ne démarre pas."
