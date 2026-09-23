#!/usr/bin/env bash
# Construit la PWA prête à être servie par l'hébergeur.
#
#   scripts/build_web.sh [fichier-env]        (défaut : env/prod.json)
#
# Cinq choses de plus que `flutter build web --release` :
#
#   0. `--wasm` (ticket 065) : la construction sort **deux** applications dans
#      le même répertoire. `main.dart.wasm` + `main.dart.mjs` pour les
#      navigateurs qui ont WasmGC — Chrome, Edge, Firefox, et Safari depuis
#      18.2 —, rendus par **Skwasm**, qui rastérise sur un fil séparé ;
#      `main.dart.js` pour les autres, rendu par CanvasKit comme avant. Le
#      chargeur choisit seul, à l'ouverture. Ce qui rend le premier chemin
#      possible est ailleurs : les deux en-têtes d'isolation de `vercel.json`
#      (`Cross-Origin-Opener-Policy`, `Cross-Origin-Embedder-Policy`). Sans
#      eux, la page n'a pas `SharedArrayBuffer`, Skwasm retombe sur sa variante
#      à un seul fil (`skwasm_heavy`) et la construction ne sert à rien ;
#   1. `--no-web-resources-cdn` : le moteur de rendu est servi par
#      l'hébergement du produit, pas par `www.gstatic.com` (ticket 037).
#      `web/flutter_bootstrap.js` pose déjà `canvasKitBaseUrl` et suffirait ;
#      le drapeau est la même décision côté ligne de commande, pour qu'une
#      construction reste correcte même si le gabarit d'amorçage disparaît ;
#   2. l'élagage des tables de symboles de débogage de `canvaskit/`
#      (`*.symbols`, 4,4 Mo) : le chargeur ne les demande jamais. Les moteurs
#      `skwasm*`, eux, **partent désormais** : ce sont ceux de la construction
#      Wasm. Jusqu'au ticket 065 ils étaient élagués, parce qu'une construction
#      `dart2js` + `canvaskit` ne pouvait pas les atteindre ;
#   3. la compression brotli de ce qui reste, de `main.dart.wasm` et des
#      polices embarquées.
#      `assets/fonts/README.md` explique pourquoi les polices restent en TTF
#      (Flutter web ne décode pas le WOFF2) ; le seul levier est la
#      compression de transport, et elle fait passer les cinq fichiers de
#      184 Ko à ~83 Ko. Pour les moteurs, c'est ce qui rend l'auto-hébergement
#      viable : 3,4 Mo de Skwasm deviennent 1,1 Mo, 5,4 Mo de CanvasKit
#      deviennent 1,5 Mo. `main.dart.wasm` suit la même règle, 3,6 Mo → 1,0 Mo,
#      parce que rien ne garantit qu'un CDN comprime `application/wasm` à la
#      volée comme il comprime le JavaScript. Les octets sont remplacés **sur
#      place** ; c'est `vercel.json` qui annonce `Content-Encoding: br` sur ces
#      chemins ;
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

echo "→ flutter build web --release --wasm --no-web-resources-cdn --dart-define-from-file=$ENV_FILE"
flutter build web --release --wasm --no-web-resources-cdn --dart-define-from-file="$ENV_FILE"

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

# **Les deux applications doivent être là.** Une construction `--wasm` qui
# n'aurait produit que le repli s'installerait sans bruit : la PWA marcherait,
# simplement sans rien de ce que ce ticket est allé chercher. Et l'inverse —
# le Wasm sans son repli — laisserait à la porte tout navigateur sans WasmGC.
grep -q '"renderer":"skwasm"' "$SORTIE/flutter_bootstrap.js" ||
  die "flutter_bootstrap.js ne déclare aucun moteur skwasm : --wasm n'a pas pris (ticket 065)."
grep -q '"renderer":"canvaskit"' "$SORTIE/flutter_bootstrap.js" ||
  die "flutter_bootstrap.js ne déclare aucun moteur canvaskit : le repli des navigateurs sans WasmGC a disparu (ticket 065)."
for indispensable in main.dart.wasm main.dart.mjs main.dart.js; do
  [ -s "$SORTIE/$indispensable" ] ||
    die "$indispensable absent ou vide : la construction Wasm et son repli JavaScript partent ensemble (ticket 065)."
done
for indispensable in skwasm.wasm skwasm.js skwasm_heavy.wasm skwasm_heavy.js; do
  [ -s "$MOTEUR/$indispensable" ] ||
    die "canvaskit/$indispensable absent : Skwasm n'a pas été recopié, la construction Wasm n'a pas de rastériseur."
done

echo
echo "→ élagage du moteur : ce que le chargeur ne demande jamais"
[ -d "$MOTEUR" ] || die "$MOTEUR absent : la construction n'a pas recopié les moteurs."
# `skwasm*` **reste** depuis le ticket 065 : c'est le rastériseur de la
# construction Wasm. Seules les tables de symboles partent — elles ne servent
# qu'à lire une pile d'appels dans un rapport de plantage, et le chargeur ne
# les demande jamais.
elague=0
while IFS= read -r -d '' inutile; do
  elague=$((elague + $(wc -c < "$inutile")))
  rm -f "$inutile"
done < <(find "$MOTEUR" -name '*.symbols' -type f -print0)
printf '   %-44s %6s Ko retirés\n' "*.symbols" "$((elague / 1024))"

echo
echo "→ compression brotli des moteurs et de l'application Wasm"
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
done < <(
  {
    find "$MOTEUR" \( -name '*.wasm' -o -name '*.js' \) -type f -print0
    # `main.dart.wasm` seulement : `main.dart.mjs` et `main.dart.js` sont du
    # texte, que le CDN comprime à la volée (`docs/DEPLOIEMENT.md` § 10).
    printf '%s\0' "$SORTIE/main.dart.wasm"
  }
)
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
for fichier in main.dart.wasm main.dart.mjs main.dart.js flutter_bootstrap.js \
               flutter_service_worker.js index.html \
               canvaskit/skwasm.wasm canvaskit/skwasm_heavy.wasm \
               canvaskit/chromium/canvaskit.wasm canvaskit/canvaskit.wasm; do
  [ -f "$SORTIE/$fichier" ] &&
    printf '   %-26s %6s Ko\n' "$fichier" "$(( $(wc -c < "$SORTIE/$fichier") / 1024 ))"
done

echo
echo "Prêt. Les polices, les moteurs et main.dart.wasm ne sont lisibles qu'avec"
echo "l'en-tête Content-Encoding: br de vercel.json — les servir sans cet"
echo "en-tête donne des fichiers illisibles et une application qui ne démarre"
echo "pas. Et sans les deux en-têtes d'isolation du même fichier, le chemin"
echo "Wasm se charge mais rastérise sur un seul fil : tout ce travail pour rien."
