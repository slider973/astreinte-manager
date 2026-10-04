#!/usr/bin/env bash
# Concurrence de la validation automatique d'un planning (migration 0019,
# ticket 019), de la réattribution d'un créneau (migration 0020, ticket 020) et
# des échanges d'astreintes (migration 0041, ticket 073).
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
CRENEAU2="77777777-0000-4000-8000-000000000005"
A3="77777777-0000-4000-8000-000000000203"

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
       -- Depuis la migration 0026, `profiles` ne pend plus à `auth.users` : le
       -- profil d'essai ne part plus tout seul, il se supprime ici.
       delete from profiles where email like '%@concurrence.test';
       drop table if exists concurrence_resultats;
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

# ---------------------------------------------------------------------------
# Deux réattributions simultanées sur un créneau d'une seule place (0020).
# ---------------------------------------------------------------------------
# Le verrou sérialise les deux transactions, mais sérialiser ne suffit pas : il
# faut que la seconde **compte** ce que la première a écrit. Sans le test de
# capacité, les deux réussissaient — deux attributions actives, deux
# notifications, deux téléphones qui sonnent pour une place.
echo "== concurrence de la réattribution"

# Les fixtures du second scénario arrivent **après** les assertions du premier :
# un créneau de plus, non pourvu, empêcherait le planning de se valider et
# ferait échouer le scénario précédent pour une raison qui ne le regarde pas.
"${PSQL[@]}" >/dev/null <<SQL
-- **Un créneau d'une seule place, déjà refusé** : celui du ticket 020. Deux
-- adjoints vont le repourvoir en même temps ; il ne doit en sortir qu'une
-- attribution et qu'une notification.
insert into shifts (id, station_id, schedule_id, date, slot, required_count)
values ('$CRENEAU2', '$STATION', '$PLANNING', '2029-04-02', 'day', 1);

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by)
values ('$A3', '$STATION', '$CRENEAU2', '$M1', 'proposed', now(), '$ADMIN');

-- Bilal refuse : le trou que les deux adjoints verront.
update assignments set status = 'declined', responded_at = now(),
                       decline_reason = 'en formation'
 where id = '$A3';

-- Où les deux sessions déposeront ce que la fonction leur a répondu : une
-- session \`psql\` pilotée par tube ne rend pas sa sortie de façon exploitable.
create table if not exists concurrence_resultats (qui text primary key, r jsonb);
delete from concurrence_resultats;
SQL

sql "delete from notification_outbox where station_id = '$STATION'" >/dev/null

mkfifo "$travail/c.in" "$travail/d.in"
"${PSQL[@]}" < "$travail/c.in" > "$travail/c.out" 2>&1 &
pid_c=$!
"${PSQL[@]}" < "$travail/d.in" > "$travail/d.out" 2>&1 &
pid_d=$!
exec 7> "$travail/c.in"
exec 8> "$travail/d.in"

# C repourvoit et **reste ouverte** : elle tient le refus et le planning.
printf "begin;\ninsert into concurrence_resultats values ('c', reassign_shift('%s', '%s', '%s'));\n" \
  "$CRENEAU2" "$M2" "$ADMIN" >&7
sleep 1

# D repourvoit le même créneau, pour quelqu'un d'autre. La contrainte d'unicité
# ne dit rien de deux personnes différentes : seul le verrou puis le compte des
# places peuvent l'arrêter.
printf "begin;\ninsert into concurrence_resultats values ('d', reassign_shift('%s', '%s', '%s'));\n" \
  "$CRENEAU2" "$ADMIN" "$ADMIN" >&8
sleep 2

attente="$(sql "select count(*) from pg_stat_activity
                 where datname = current_database()
                   and wait_event_type = 'Lock'
                   and query ilike '%reassign_shift%'")"
verifier "la seconde réattribution attend la première" "1" "$attente"

printf "commit;\n" >&7
sleep 1
printf "commit;\n" >&8
sleep 1

exec 7>&-
exec 8>&-
wait "$pid_c" "$pid_d" 2>/dev/null || true

verifier "la première réattribution aboutit" "true" \
  "$(sql "select r ->> 'ok' from concurrence_resultats where qui = 'c'")"
verifier "la seconde est refusée" "false" \
  "$(sql "select r ->> 'ok' from concurrence_resultats where qui = 'd'")"
verifier "et elle dit que le créneau est pourvu" "shift_already_filled" \
  "$(sql "select r ->> 'code' from concurrence_resultats where qui = 'd'")"

# **Le critère du ticket, sous concurrence** : une place, une attribution, une
# notification.
verifier "une seule attribution active sur le créneau" "1" \
  "$(sql "select count(*) from assignments
           where shift_id = '$CRENEAU2' and status in ('proposed', 'accepted')")"
verifier "un seul téléphone sonne" "1" \
  "$(sql "select count(*) from notification_outbox
           where station_id = '$STATION' and type = 'assignment_proposed'")"
verifier "le refus garde le fil vers l'attribution qui l'a comblé" "t" \
  "$(sql "select replaced_by is not null from assignments where id = '$A3'")"

# ---------------------------------------------------------------------------
# Échanges d'astreintes (migration 0041, ticket 073).
# ---------------------------------------------------------------------------
# Deux courses, celles que le ticket nomme :
#   1. deux repreneurs acceptent **en même temps** la même demande « à la
#      caserne » : un seul la prend, l'autre lit `exchange_not_open` ;
#   2. une validation d'échange et une réattribution de l'administrateur sur la
#      **même garde**, dans les deux ordres : la seconde arrivée attend la
#      première sur la ligne de l'attribution, puis refuse proprement — jamais
#      deux titulaires, jamais d'interblocage.
echo "== concurrence des échanges"

CRENEAU3="77777777-0000-4000-8000-000000000006"
CRENEAU4="77777777-0000-4000-8000-000000000007"
A5="77777777-0000-4000-8000-000000000205"
A6="77777777-0000-4000-8000-000000000206"

"${PSQL[@]}" >/dev/null <<SQL
insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('$CRENEAU3', '$STATION', '$PLANNING', '2029-04-03', 'day', 1),
  ('$CRENEAU4', '$STATION', '$PLANNING', '2029-04-04', 'day', 1);

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, responded_at, created_by) values
  ('$A5', '$STATION', '$CRENEAU3', '$M1', 'accepted', now(), now(), '$ADMIN'),
  ('$A6', '$STATION', '$CRENEAU4', '$M1', 'accepted', now(), now(), '$ADMIN');

-- Ana et Cora sont libres le 3 avril : toutes deux recevront la demande.
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  ('$STATION', '$ADMIN', '2029-04-03', 'day', 'available', '$ADMIN'),
  ('$STATION', '$M2',    '2029-04-03', 'day', 'available', '$M2');

delete from concurrence_resultats;

-- Bilal cherche un remplaçant le 3 avril, et propose le 4 à Cora, qui accepte.
select set_config('request.jwt.claims', '{"sub": "$M1", "role": "authenticated"}', false);
insert into concurrence_resultats values ('x', request_exchange('$A5'));
insert into concurrence_resultats values ('y', request_exchange('$A6', '$M2'));
select set_config('request.jwt.claims', '{"sub": "$M2", "role": "authenticated"}', false);
insert into concurrence_resultats values ('y-ok',
  respond_exchange(((select r from concurrence_resultats where qui = 'y') ->> 'exchange_id')::uuid));
SQL

X="$(sql "select r ->> 'exchange_id' from concurrence_resultats where qui = 'x'")"
Y="$(sql "select r ->> 'exchange_id' from concurrence_resultats where qui = 'y'")"
verifier "la demande à la caserne est ouverte" "open" \
  "$(sql "select status from shift_exchanges where id = '$X'")"
verifier "la demande à Cora attend l'administrateur" "accepted_by_peer" \
  "$(sql "select status from shift_exchanges where id = '$Y'")"

# --- 1. Deux repreneurs ----------------------------------------------------
mkfifo "$travail/e.in" "$travail/f.in"
"${PSQL[@]}" < "$travail/e.in" > "$travail/e.out" 2>&1 &
pid_e=$!
"${PSQL[@]}" < "$travail/f.in" > "$travail/f.out" 2>&1 &
pid_f=$!
exec 7> "$travail/e.in"
exec 8> "$travail/f.in"

printf "begin;\nselect set_config('request.jwt.claims', '{\"sub\": \"%s\", \"role\": \"authenticated\"}', true);\ninsert into concurrence_resultats values ('e', respond_exchange('%s'));\n" \
  "$ADMIN" "$X" >&7
sleep 1
printf "begin;\nselect set_config('request.jwt.claims', '{\"sub\": \"%s\", \"role\": \"authenticated\"}', true);\ninsert into concurrence_resultats values ('f', respond_exchange('%s'));\n" \
  "$M2" "$X" >&8
sleep 2

verifier "le second repreneur attend le premier" "1" \
  "$(sql "select count(*) from pg_stat_activity
           where datname = current_database()
             and wait_event_type = 'Lock'
             and query ilike '%respond_exchange%'")"

printf "commit;\n" >&7
sleep 1
printf "commit;\n" >&8
sleep 1
exec 7>&-
exec 8>&-
wait "$pid_e" "$pid_f" 2>/dev/null || true

verifier "le premier prend la garde" "true" \
  "$(sql "select r ->> 'ok' from concurrence_resultats where qui = 'e'")"
verifier "le second trouve la demande déjà prise" "exchange_not_open" \
  "$(sql "select r ->> 'code' from concurrence_resultats where qui = 'f'")"
verifier "un seul repreneur inscrit" "$ADMIN" \
  "$(sql "select taker_id from shift_exchanges where id = '$X'")"

# --- 2a. Validation d'abord, réattribution ensuite -------------------------
mkfifo "$travail/g.in" "$travail/h.in"
"${PSQL[@]}" < "$travail/g.in" > "$travail/g.out" 2>&1 &
pid_g=$!
"${PSQL[@]}" < "$travail/h.in" > "$travail/h.out" 2>&1 &
pid_h=$!
exec 7> "$travail/g.in"
exec 8> "$travail/h.in"

# Ana valide la reprise du 3 avril (par elle-même : elle est seule admin).
printf "begin;\nselect set_config('request.jwt.claims', '{\"sub\": \"%s\", \"role\": \"authenticated\"}', true);\ninsert into concurrence_resultats values ('g', decide_exchange('%s', true));\n" \
  "$ADMIN" "$X" >&7
sleep 1
# Au même moment, la réattribution du même créneau vers Cora, sur la garde de Bilal.
printf "begin;\ninsert into concurrence_resultats values ('h', reassign_shift('%s', '%s', '%s', '%s'));\n" \
  "$CRENEAU3" "$M2" "$ADMIN" "$A5" >&8
sleep 2

verifier "la réattribution attend la validation" "1" \
  "$(sql "select count(*) from pg_stat_activity
           where datname = current_database()
             and wait_event_type = 'Lock'
             and query ilike '%reassign_shift%'")"

printf "commit;\n" >&7
sleep 1
printf "commit;\n" >&8
sleep 1
exec 7>&-
exec 8>&-
wait "$pid_g" "$pid_h" 2>/dev/null || true

verifier "la validation aboutit" "approved" \
  "$(sql "select r ->> 'status' from concurrence_resultats where qui = 'g'")"
verifier "la réattribution refuse : la garde est déjà remplacée" "assignment_not_replaceable" \
  "$(sql "select r ->> 'code' from concurrence_resultats where qui = 'h'")"
verifier "une seule garde active le 3 avril, celle d'Ana" "1|$ADMIN" \
  "$(sql "select count(*) || '|' || max(user_id::text) from assignments
           where shift_id = '$CRENEAU3' and status in ('proposed', 'accepted')")"

# --- 2b. Réattribution d'abord, validation ensuite -------------------------
mkfifo "$travail/i.in" "$travail/j.in"
"${PSQL[@]}" < "$travail/i.in" > "$travail/i.out" 2>&1 &
pid_i=$!
"${PSQL[@]}" < "$travail/j.in" > "$travail/j.out" 2>&1 &
pid_j=$!
exec 7> "$travail/i.in"
exec 8> "$travail/j.in"

printf "begin;\ninsert into concurrence_resultats values ('i', reassign_shift('%s', '%s', '%s', '%s'));\n" \
  "$CRENEAU4" "$ADMIN" "$ADMIN" "$A6" >&7
sleep 1
printf "begin;\nselect set_config('request.jwt.claims', '{\"sub\": \"%s\", \"role\": \"authenticated\"}', true);\ninsert into concurrence_resultats values ('j', decide_exchange('%s', true));\n" \
  "$ADMIN" "$Y" >&8
sleep 2

verifier "la validation attend la réattribution" "1" \
  "$(sql "select count(*) from pg_stat_activity
           where datname = current_database()
             and wait_event_type = 'Lock'
             and query ilike '%decide_exchange%'")"

printf "commit;\n" >&7
sleep 1
printf "commit;\n" >&8
sleep 1
exec 7>&-
exec 8>&-
wait "$pid_i" "$pid_j" 2>/dev/null || true

verifier "la réattribution aboutit" "true" \
  "$(sql "select r ->> 'ok' from concurrence_resultats where qui = 'i'")"
verifier "la validation trouve la demande close" "exchange_not_pending" \
  "$(sql "select r ->> 'code' from concurrence_resultats where qui = 'j'")"
verifier "la demande a échoué, garde changée" "failed|assignment_changed" \
  "$(sql "select status || '|' || reason_code from shift_exchanges where id = '$Y'")"
verifier "une seule garde active le 4 avril, aucune pour Cora" "1|0" \
  "$(sql "select count(*) || '|' || count(*) filter (where user_id = '$M2') from assignments
           where shift_id = '$CRENEAU4' and status in ('proposed', 'accepted')")"
verifier "aucun interblocage détecté" "0" \
  "$(cat "$travail"/[e-j].out | grep -ci 'deadlock' || true)"

if [ "$echecs" -eq 0 ]; then
  echo "Concurrence : $total tests, tous verts"
  exit 0
fi
echo "Concurrence : $echecs échec(s) sur $total" >&2
exit 1
