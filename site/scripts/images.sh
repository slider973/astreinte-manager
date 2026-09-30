#!/usr/bin/env bash
# Produit les images servies (AVIF et WebP, 1x et 2x) depuis les captures PNG sans perte
# de site/sources/captures/. Se lance à la main, une fois par changement de capture ;
# les fichiers produits sont versionnés dans site/public/images/ (brief 075 § 7.4, § 9.1).
#
# Outils : ImageMagick (`magick`), `avifenc` (libavif) et `cwebp` (libwebp).
#   macOS : brew install imagemagick libavif webp
# Les budgets sont vérifiés ensuite par `python3 site/scripts/verifier.py`.
set -euo pipefail

ici="$(cd "$(dirname "$0")/.." && pwd)"
source_="$ici/sources/captures"
sortie="$ici/public/images"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$sortie"

for outil in magick avifenc cwebp; do
  command -v "$outil" >/dev/null || { echo "outil absent : $outil" >&2; exit 2; }
done

# declinaison <png source> <nom> <largeur> [géométrie de recadrage, en pixels de la source]
declinaison() {
  local src="$1" nom="$2" largeur="$3" recadrage="${4:-}"
  local png="$tmp/$nom-$largeur.png"
  if [ -n "$recadrage" ]; then
    magick "$src" -crop "$recadrage" +repage -filter Lanczos -resize "${largeur}x" -strip "$png"
  else
    magick "$src" -filter Lanczos -resize "${largeur}x" -strip "$png"
  fi
  avifenc -q 60 -s 4 -y 420 "$png" "$sortie/$nom-$largeur.avif" >/dev/null
  cwebp -quiet -q 80 -m 6 -metadata none "$png" -o "$sortie/$nom-$largeur.webp"
  printf '%-28s %s\n' "$nom-$largeur" "$(magick identify -format '%wx%h' "$png")"
}

# Téléphone : 390 × 844 points à 2x (780 × 1688), affichés à 280–300 px.
for paire in a-accueil-pompier:a-accueil c-saisie-mois:c-saisie d-proposition:d-proposition; do
  declinaison "$source_/${paire%%:*}.png" "${paire##*:}" 300
  declinaison "$source_/${paire%%:*}.png" "${paire##*:}" 600
done

# Ordinateur : 1440 × 900 points à 2x (2880 × 1800).
declinaison "$source_/b-matrice-admin.png" b-matrice 720
declinaison "$source_/b-matrice-admin.png" b-matrice 1440

# Recadrage pour les écrans étroits : la colonne des membres et les cinq premiers jours
# (week-end compris), les neuf lignes. Dix jours, comme le brief le proposait, rendaient
# le texte illisible à 350 px de large ; cinq gardent les cases et les noms lisibles.
declinaison "$source_/b-matrice-admin.png" b-recadrage 360 1180x960+360+760
declinaison "$source_/b-matrice-admin.png" b-recadrage 720 1180x960+360+760

ls -l "$sortie"
