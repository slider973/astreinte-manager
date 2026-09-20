#!/usr/bin/env sh
# Génère les types TypeScript du schéma public depuis la base locale.
# Sortie : supabase/types/database.types.ts (référence pour les Edge Functions et
# pour écrire les modèles Dart à la main, voir supabase/README.md).
#
# Prérequis : `supabase start` lancé.
set -eu
cd "$(dirname "$0")/.."
mkdir -p supabase/types
supabase gen types typescript --local --schema public > supabase/types/database.types.ts
echo "Types écrits dans supabase/types/database.types.ts"
