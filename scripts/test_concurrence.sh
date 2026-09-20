#!/usr/bin/env bash
# Concurrence de la validation automatique d'un planning (migration 0019, ticket 019).
#
# Lancé par scripts/test_rls.sh, donc joué en CI comme en local.
#
# Pourquoi ce fichier n'est pas un `.sql` de plus
# -----------------------------------------------
# Le défaut qu'il attrape **demande deux transactions concurrentes**, et aucun
# fichier `psql` unique ne sait en produire : une seule session ne voit qu'un
# seul instantané. Les tests du dossier `supabase/tests/` tournent tous dans une
# transaction annulée à la fin ; celui-ci ouvre donc **trois** sessions — une
# pour poser les fixtures, deux pour les faire se marcher dessus — et il nettoie
# lui-même derrière lui, quoi qu'il arrive (`trap`).
#
# Ce qu'il reproduit
# ------------------
# Un créneau qui demande **deux** pompiers, deux attributions, deux acceptations
# **simultanées**. Chaque transaction lit son propre instantané et ne voit pas
# l'acceptation de l'autre. Sans verrou de ligne pris **avant** le test de
# complétude, aucune des deux ne conclut « complet », le planning reste publié
# pour toujours et aucune réponse ultérieure ne viendra le réveiller — il n'en
# reste plus à donner.
#
# Avec le verrou (`schedule_reevaluer`, `select … for update` en première
# instruction), la seconde transaction **attend** la première, reprend un
# instantané frais en `read committed`, voit l'acceptation déjà validée et
# conclut juste. Le test vérifie les deux moitiés : que la seconde session
# **attend vraiment**, et que le planning finit **validé**.
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

projet="$(sed -n 's/^[[:space:]]*project_id[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' \
  "$racine/supabase/config.toml" | head -1)"
conteneur="supabase_db_${projet:-pompier}"

# `psql` local, ou à défaut le conteneur de la pile locale — même repli que
# scripts/test_rls.sh. Les deux sessions concurrentes, elles, **exigent** un
# vrai `psql` : on ne pilote pas deux `docker exec` interactifs à l'aveugle.
if command -v psql >/dev/null 2>&1; then
  PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1)
  sql() { psql "$DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 -c "$1"; }
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$conteneur"; then
  echo "  (ignoré : psql absent — deux sessions concurrentes ne se pilotent pas par docker exec)"
  exit 0
else
  echo "Ni psql ni le conteneur $conteneur ne sont disponibles." >&2
  exit 1
fi

STATION="77777777-0000-4000-8000-000000000001"
PERIODE="77777777-0000-4000-8000-000000000002"
PLANNING="77777777-0000-4000-8000-000000000003"
CRENEAU="77777777-0000-4000-8000-000000000004"
ADMIN="77777777-0000-4000-8000-000000000101"
M1="77777777-0000-4000-8000-000000000102"
M2="77777777-0000-4000-8000-000000000103"
A1="77777777-0000-4000-8000-000000000201"
A2="77777777-0000-4000-8000-000000000202"

total=0
echecs=0

verifier() { # verifier <libellé> <attendu> <obtenu>
  total=$((total + 1))
  if [ "$2" = "$3" ]; then
    printf '  ok   %s\n' "$1"
  else
    echecs=$((echecs + 1))
    printf '  ECHEC %s\n        attendu : %s\n        obtenu  : %s\n' "$1" "$2" "$3" >&2
  fi
}

travail="$(mktemp -d)"

nettoyer() {
  # Les sessions concurrentes d'abord : une transaction restée ouverte tiendrait
  # le verrou et ferait attendre la suppression indéfiniment.
  exec 7>&- 2>/dev/null || true
  exec 8>&- 2>/dev/null || true
  wait 2>/dev/null || true
  # `schedules_guard_suppression` refuse un planning publié, et c'est le sujet
  # même de ce ticket : on l'écarte le temps de retirer un jeu d'essai, comme
  # `scripts/test_functions.sh` le fait pour le sien.
  sql "alter table schedules disable trigger schedules_guard_suppression;
       alter table shifts    disable trigger shifts_guard_suppression;
       delete from notification_outbox where station_id = '$STATION';
       delete from notifications where station_id = '$STATION';
       delete from audit_log where station_id = '$STATION';
       delete from schedules where station_id = '$STATION';
       delete from periods where station_id = '$STATION';
       delete from memberships where station_id = '$STATION';
       delete from stations where id = '$STATION';
       delete from auth.users where email like '%@concurrence.test';
       alter table shifts    enable trigger shifts_guard_suppression;
       alter table schedules enable trigger schedules_guard_suppression;" >/dev/null 2>&1 || true
  rm -rf "$travail"
}
trap nettoyer EXIT

echo "== concurrence de la validation automatique"

nettoyer_silencieux=1
sql "alter table schedules disable trigger schedules_guard_suppression;
     delete from schedules where station_id = '$STATION';
     alter table schedules enable trigger schedules_guard_suppression;
     delete from stations where id = '$STATION';" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Fixtures, **committées** : deux sessions concurrentes ne voient pas les
# écritures non validées l'une de l'autre.
# ---------------------------------------------------------------------------
"${PSQL[@]}" >/dev/null <<SQL
insert into stations (id, name, slug, timezone)
values ('$STATION', 'CIS Concurrence', 'cis-concurrence', 'Europe/Paris');

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
       u.email, now(), '{"provider": "email", "providers": ["email"]}'::jsonb,
       jsonb_build_object('first_name', u.prenom, 'last_name', u.nom),
       now(), now(), '', '', '', '', ''
from (values
  ('$ADMIN'::uuid, 'admin@concurrence.test',   'Ana',  'Alves'),
  ('$M1'::uuid,    'membre1@concurrence.test', 'Bilal','Benali'),
  ('$M2'::uuid,    'membre2@concurrence.test', 'Cora', 'Cadiot')
) as u(id, email, prenom, nom);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('$STATION', '$ADMIN', 'admin',  'active', 'Ana A.'),
  ('$STATION', '$M1',    'member', 'active', 'Bilal B.'),
  ('$STATION', '$M2',    'member', 'active', 'Cora C.');

insert into periods (id, station_id, year, month, status, deadline_at)
values ('$PERIODE', '$STATION', 2029, 4, 'locked', '2029-03-15 23:59:59+01');

insert into schedules (id, station_id, period_id, created_by)
values ('$PLANNING', '$STATION', '$PERIODE', '$ADMIN');

-- **Un créneau qui demande deux personnes** : c'est le cas qui casse. Avec un
-- seul requis, la première acceptation suffirait et la course n'existerait pas.
insert into shifts (id, station_id, schedule_id, date, slot, required_count)
values ('$CRENEAU', '$STATION', '$PLANNING', '2029-04-01', 'day', 2);

insert into assignments (id, station_id, shift_id, user_id, created_by) values
  ('$A1', '$STATION', '$CRENEAU', '$M1', '$ADMIN'),
  ('$A2', '$STATION', '$CRENEAU', '$M2', '$ADMIN');

select publish_schedule('$PLANNING', '$ADMIN');
SQL

verifier "le planning part publié" "published" \
  "$(sql "select status from schedules where id = '$PLANNING'")"

# ---------------------------------------------------------------------------
# Deux sessions, deux transactions, deux acceptations simultanées.
# ---------------------------------------------------------------------------
mkfifo "$travail/a.in" "$travail/b.in"
"${PSQL[@]}" < "$travail/a.in" > "$travail/a.out" 2>&1 &
pid_a=$!
"${PSQL[@]}" < "$travail/b.in" > "$travail/b.out" 2>&1 &
pid_b=$!
exec 7> "$travail/a.in"
exec 8> "$travail/b.in"

# A accepte et **reste ouverte** : elle tient le verrou de la ligne du planning.
printf "begin;\nupdate assignments set status = 'accepted', responded_at = now() where id = '%s';\n" "$A1" >&7
sleep 1

# B accepte à son tour. Le déclencheur va demander le même verrou.
printf "begin;\nupdate assignments set status = 'accepted', responded_at = now() where id = '%s';\n" "$A2" >&8
sleep 2

# **La preuve que le verrou précède le test** : B attend. Sans `for update` en
# tête de `schedule_reevaluer`, elle ne bloquerait sur rien, conclurait
# « pas complet » et rendrait la main sans rien valider.
attente="$(sql "select count(*) from pg_stat_activity
                 where datname = current_database()
                   and wait_event_type = 'Lock'
                   and query ilike '%update assignments%'")"
verifier "la seconde acceptation attend la première" "1" "$attente"

printf "commit;\n" >&7
sleep 1
printf "commit;\n" >&8
sleep 1

exec 7>&-
exec 8>&-
wait "$pid_a" "$pid_b" 2>/dev/null || true

verifier "les deux acceptations sont acquises" "2" \
  "$(sql "select count(*) from assignments where shift_id = '$CRENEAU' and status = 'accepted'")"

# Le cœur du bloquant : avant le correctif, le planning restait `published`.
verifier "le planning est validé malgré la simultanéité" "validated" \
  "$(sql "select status from schedules where id = '$PLANNING'")"
verifier "la date de validation est posée" "t" \
  "$(sql "select validated_at is not null from schedules where id = '$PLANNING'")"

# Et **une seule** notification : l'arbitrage n'a laissé passer qu'une bascule.
verifier "une seule notification de validation" "1" \
  "$(sql "select count(*) from notification_outbox
           where station_id = '$STATION' and type = 'schedule_validated'")"
verifier "elle vise les trois membres actifs" "3" \
  "$(sql "select jsonb_array_length(recipients) from notification_outbox
           where station_id = '$STATION' and type = 'schedule_validated'")"

if [ "$echecs" -eq 0 ]; then
  echo "Concurrence : $total tests, tous verts"
  exit 0
fi
echo "Concurrence : $echecs échec(s) sur $total" >&2
exit 1
