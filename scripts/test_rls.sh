#!/usr/bin/env bash
# Exécute les tests de Row Level Security contre la base Supabase locale.
#
#   scripts/test_rls.sh              # base locale (supabase start)
#   DB_URL=postgresql://… scripts/test_rls.sh
#
# Sortie non nulle dès qu'un test échoue (ON_ERROR_STOP + exceptions SQL).
# Les tests tournent dans une transaction annulée à la fin : la base n'est pas modifiée.
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fichiers=("$racine"/supabase/tests/*.sql)

if [ ! -e "${fichiers[0]}" ]; then
  echo "Aucun fichier de test dans supabase/tests/." >&2
  exit 1
fi

# Par défaut : la base locale de `supabase start` (voir `supabase status`).
DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

lancer_psql() {
  if command -v psql >/dev/null 2>&1; then
    psql "$DB_URL" -v ON_ERROR_STOP=1 -X -q -f "$1"
  elif docker ps --format '{{.Names}}' | grep -qx supabase_db_pompier; then
    # Pas de psql sur la machine : on passe par le conteneur de la stack locale.
    docker exec -i supabase_db_pompier \
      psql -U postgres -d postgres -v ON_ERROR_STOP=1 -X -q -f - < "$1"
  else
    echo "Ni psql ni le conteneur supabase_db_pompier ne sont disponibles." >&2
    echo "Démarrer la stack avec « supabase start » ou installer psql." >&2
    exit 1
  fi
}

code=0
for fichier in "${fichiers[@]}"; do
  echo "== $(basename "$fichier")"
  if ! lancer_psql "$fichier"; then
    code=1
    echo "ÉCHEC : $(basename "$fichier")" >&2
  fi
done

if [ "$code" -eq 0 ]; then
  echo "Tests RLS : OK"
else
  echo "Tests RLS : ÉCHEC" >&2
fi
exit "$code"
