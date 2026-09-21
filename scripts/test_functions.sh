#!/usr/bin/env bash
# Tests de bout en bout des Edge Functions : invitations (ticket 006), envoi de
# notifications (ticket 025), publication d'un planning (ticket 019),
# réattribution d'un créneau refusé (ticket 020), remplissage automatique d'un
# brouillon (ticket 018), ligne interne d'un envoi définitivement abandonné
# (ticket 040), abonnement par caserne (ticket 029) et flux calendrier (ticket 028).
#
#   supabase start
#   supabase functions serve          # dans un autre terminal
#   scripts/test_functions.sh
#
# Pourquoi ce script n'est pas dans la CI : .github/workflows/ci.yml démarre la pile
# sans `edge-runtime` ni `kong` (plus de 4 Go d'images pour des conteneurs qui ne
# servent qu'au développement local). Les Edge Functions n'y sont donc pas joignables.
# La logique qu'elles portent est testée en SQL par supabase/tests/invitations_test.sql,
# qui tourne, lui, à chaque PR. Ce script couvre la couche HTTP : jeton de l'appelant,
# codes de statut, création du compte, envoi du courriel.
#
# Dépendances : curl, jq, et psql (ou le conteneur Postgres de la pile locale).
# Le script nettoie ses données avant et après : la base revient dans l'état du seed.

set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine"

API_URL="${API_URL:-http://127.0.0.1:54321}"
MAILPIT_URL="${MAILPIT_URL:-http://127.0.0.1:54324}"
DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
MDP="astreinte-dev"

STATION_A="aaaaaaaa-0000-4000-8000-000000000001"
STATION_B="bbbbbbbb-0000-4000-8000-000000000001"
STATION_INCONNUE="dddddddd-0000-4000-8000-0000000000ff"

for outil in curl jq; do
  command -v "$outil" >/dev/null 2>&1 || { echo "Outil manquant : $outil" >&2; exit 1; }
done

projet="$(sed -n 's/^[[:space:]]*project_id[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' \
  supabase/config.toml | head -1)"
conteneur="supabase_db_${projet:-pompier}"

# psql, ou à défaut le conteneur de la pile locale (même repli que scripts/test_rls.sh).
sql() {
  if command -v psql >/dev/null 2>&1; then
    psql "$DB_URL" -v ON_ERROR_STOP=1 -X -q -A -t -c "$1"
  elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$conteneur"; then
    docker exec -i "$conteneur" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -X -q -A -t -c "$1"
  else
    echo "Ni psql ni le conteneur $conteneur ne sont disponibles." >&2
    exit 1
  fi
}

# `supabase status -o json` écrit du JSON indenté sur plusieurs lignes.
etat="$(supabase status -o json 2>/dev/null)"
ANON_KEY="$(printf '%s' "$etat" | jq -r .ANON_KEY)"
SERVICE_KEY="$(printf '%s' "$etat" | jq -r .SERVICE_ROLE_KEY)"
if [ -z "$ANON_KEY" ] || [ "$ANON_KEY" = "null" ]; then
  echo "Pile locale introuvable : lancer « supabase start »." >&2
  exit 1
fi

code_http="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/functions/v1/invite-member" \
  -H "apikey: $ANON_KEY" -H 'content-type: application/json' -d '{}' || true)"
if [ "$code_http" = "000" ] || [ "$code_http" = "404" ]; then
  echo "Les Edge Functions ne répondent pas sur $API_URL/functions/v1/." >&2
  echo "Lancer « supabase functions serve » dans un autre terminal." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
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

# Dernière réponse : corps dans $CORPS, statut dans $STATUT.
appeler() { # appeler <fonction> <jeton|-> <corps json>
  local fonction="$1" jeton="$2" corps="$3" reponse
  local entetes=(-H "apikey: $ANON_KEY" -H 'content-type: application/json')
  [ "$jeton" != "-" ] && entetes+=(-H "Authorization: Bearer $jeton")
  reponse="$(curl -s -w $'\n%{http_code}' -X POST "$API_URL/functions/v1/$fonction" \
    "${entetes[@]}" -d "$corps")"
  STATUT="$(printf '%s' "$reponse" | tail -1)"
  CORPS="$(printf '%s' "$reponse" | sed '$d')"
}

# Le flux calendrier : un GET **sans aucun en-tête**, comme le ferait Google
# Agenda. Pas d'`apikey`, pas d'`Authorization` : c'est tout l'objet du ticket.
ics() { # ics <chemin après /functions/v1/ics-feed>
  local reponse
  reponse="$(curl -s -w $'\n%{http_code}' "$API_URL/functions/v1/ics-feed$1")"
  STATUT="$(printf '%s' "$reponse" | tail -1)"
  CORPS="$(printf '%s' "$reponse" | sed '$d')"
}

connexion() { # connexion <email> -> jeton d'accès
  curl -s -X POST "$API_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON_KEY" -H 'content-type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$MDP\"}" | jq -r '.access_token // empty'
}

MEMBRE1_A="aaaaaaaa-0000-4000-8000-000000000101"
MEMBRE2_A="aaaaaaaa-0000-4000-8000-000000000102"
# Le remplaçant du ticket 020 : il n'a aucune attribution dans ce planning, donc
# aucune notification à son nom avant la réattribution.
MEMBRE3_A="aaaaaaaa-0000-4000-8000-000000000103"

# Le mois M+2 de la caserne A, celui sur lequel le test de publication travaille :
# le seed le crée et rien d'autre ne s'en sert.
PERIODE_A="aaaaaaaa-0000-4000-8000-000000000202"

# Le mois M+1 de la caserne B, celui sur lequel la proposition automatique du
# ticket 018 travaille : le seed le crée et rien d'autre ne s'en sert.
PERIODE_B="bbbbbbbb-0000-4000-8000-000000000201"

# Le mois du flux calendrier (section 27), posé et retiré par ce script : les
# deux périodes du seed servent déjà aux sections 14 à 17 et 26, et une
# astreinte acceptée qui traînerait dans l'une d'elles fausserait leurs comptes.
PERIODE_ICS="aaaaaaaa-0000-4000-8000-0000000002ff"

nettoyer() {
  sql "delete from audit_log where action like 'invitation.%';
       delete from notifications where type = 'invitation';
       delete from invitations;
       delete from memberships where left(user_id::text, 4) <> left(station_id::text, 4);
       delete from auth.users where email like 'invite-test-%';
       -- Le profil ne part plus avec le compte depuis la migration 0026 :
       -- profiles.id ne référence plus auth.users, justement pour qu'un profil
       -- anonymisé survive à la suppression d'un compte. Un jeu d'essai doit
       -- donc balayer derrière lui, sans quoi l'orphelin fausse la section
       -- suivante. « supprime@… » est le profil qu'une section 24 interrompue
       -- aurait laissé : cette adresse constante n'appartient à personne.
       delete from profiles
        where email like 'invite-test-%' or email = 'supprime@astreinte.invalid';
       delete from notifications where type <> 'invitation';
       delete from notification_outbox;
       delete from push_tokens where token like 'jeton-test-%';
       update profiles set push_enabled = true where push_enabled = false;
       delete from audit_log where action like 'subscription.%';
       delete from stripe_events;
       -- Les traces laissées par les sections 15 à 17 : sans elles, deux
       -- exécutions de suite comptent les lignes de la précédente.
       delete from audit_log where action like 'assignment.%'
                                or action like 'schedule.%';" >/dev/null

  # Le planning du test de publication. Depuis la migration 0019, un planning
  # publié ne se supprime plus — pas même par le rôle de service, et c'est tout
  # l'intérêt. Le nettoyage d'un jeu d'essai est le seul endroit qui ait le droit
  # d'écarter le déclencheur, et il le remet aussitôt.
  sql "alter table schedules disable trigger schedules_guard_suppression;
       delete from schedules where period_id = '$PERIODE_A';
       alter table schedules enable trigger schedules_guard_suppression;" >/dev/null

  # Le brouillon de la proposition automatique (section 26). Un brouillon se
  # supprime sans écarter quoi que ce soit : c'est justement ce que la migration
  # 0019 autorise, et ses attributions partent avec lui.
  sql "delete from schedules where period_id = '$PERIODE_B';" >/dev/null

  # Le mois du flux calendrier (section 27) : son planning est publié, donc il
  # demande le même écartement de déclencheur que celui de la section 14.
  sql "alter table schedules disable trigger schedules_guard_suppression;
       delete from schedules where period_id = '$PERIODE_ICS';
       alter table schedules enable trigger schedules_guard_suppression;
       delete from periods where id = '$PERIODE_ICS';" >/dev/null
}

nettoyer
trap nettoyer EXIT

echo "=== Edge Functions d'invitation ($API_URL) ==="

ADMIN_A="$(connexion admin@caserne-a.test)"
ADMIN_B="$(connexion admin@caserne-b.test)"
MEMBRE_A="$(connexion membre1@caserne-a.test)"
[ -n "$ADMIN_A" ] || { echo "Connexion admin@caserne-a.test impossible (seed rejoué ?)" >&2; exit 1; }

# ---------------------------------------------------------------------------
echo ''
echo "--- 1. invite-member : identité et rôle de l'appelant"
# ---------------------------------------------------------------------------
appeler invite-member - "{\"station_id\":\"$STATION_A\",\"email\":\"invite-test-1@caserne-a.test\"}"
verifier "sans jeton porteur : 401" "401" "$STATUT"

appeler invite-member "$ANON_KEY" "{\"station_id\":\"$STATION_A\",\"email\":\"invite-test-1@caserne-a.test\"}"
verifier "la clé anon seule ne suffit pas : 401" "401" "$STATUT"
verifier "code unauthenticated" "unauthenticated" "$(jq -r '.error.code' <<<"$CORPS")"

appeler invite-member "$MEMBRE_A" "{\"station_id\":\"$STATION_A\",\"email\":\"invite-test-1@caserne-a.test\"}"
verifier "un membre simple ne peut pas inviter : 403" "403" "$STATUT"
verifier "code not_admin" "not_admin" "$(jq -r '.error.code' <<<"$CORPS")"

appeler invite-member "$ADMIN_B" "{\"station_id\":\"$STATION_A\",\"email\":\"invite-test-1@caserne-a.test\"}"
verifier "l'admin de la caserne B ne peut pas inviter dans la caserne A : 403" "403" "$STATUT"
verifier "code not_admin" "not_admin" "$(jq -r '.error.code' <<<"$CORPS")"

appeler invite-member "$ADMIN_A" "{\"station_id\":\"$STATION_INCONNUE\",\"email\":\"invite-test-1@caserne-a.test\"}"
verifier "caserne inconnue : 404" "404" "$STATUT"

appeler invite-member "$ADMIN_A" "{\"station_id\":\"$STATION_A\"}"
verifier "corps sans adresse : 400" "400" "$STATUT"

appeler invite-member "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"email\":\"x@y.fr\",\"role\":\"super\"}"
verifier "rôle inconnu : 400" "400" "$STATUT"

verifier "aucune invitation créée par les tentatives refusées" "0" "$(sql 'select count(*) from invitations')"

# ---------------------------------------------------------------------------
echo ''
echo '--- 2. invite-member : cas nominal'
# ---------------------------------------------------------------------------
appeler invite-member "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"email\":\"Invite-Test-1@caserne-a.test\"}"
verifier "invitation créée : 200" "200" "$STATUT"
verifier "ok" "true" "$(jq -r '.ok' <<<"$CORPS")"
verifier "statut invited" "invited" "$(jq -r '.results[0].status' <<<"$CORPS")"
verifier "adresse normalisée" "invite-test-1@caserne-a.test" "$(jq -r '.results[0].email' <<<"$CORPS")"
verifier "aucun oracle de compte dans la réponse" "null" "$(jq -r '.results[0].account_created' <<<"$CORPS")"
verifier "courriel envoyé" "true" "$(jq -r '.results[0].email_sent' <<<"$CORPS")"

INVITATION_ID="$(jq -r '.results[0].invitation_id' <<<"$CORPS")"
TOKEN1="$(sql "select token from invitations where email = 'invite-test-1@caserne-a.test'")"

verifier "le token n'apparaît pas dans la réponse" "absent" \
  "$(grep -q "$TOKEN1" <<<"$CORPS" && echo présent || echo absent)"
verifier "le compte a été créé dans auth.users" "1" \
  "$(sql "select count(*) from auth.users where email = 'invite-test-1@caserne-a.test'")"
verifier "le profil a été créé par le trigger" "1" \
  "$(sql "select count(*) from profiles where email = 'invite-test-1@caserne-a.test'")"
verifier "aucune membership tant que l'invitation n'est pas acceptée" "0" \
  "$(sql "select count(*) from memberships m join profiles p on p.id = m.user_id
          where p.email = 'invite-test-1@caserne-a.test'")"
verifier "envoi tracé dans notifications" "1" \
  "$(sql "select count(*) from notifications where type = 'invitation' and channel = 'email'")"

# Le courriel, dans Mailpit, avec le lien qui porte le token.
MSG_ID="$(curl -s "$MAILPIT_URL/api/v1/search?query=to%3Ainvite-test-1%40caserne-a.test" \
  | jq -r '.messages[0].ID // empty')"
verifier "un courriel est arrivé dans Mailpit" "oui" "$([ -n "$MSG_ID" ] && echo oui || echo non)"
if [ -n "$MSG_ID" ]; then
  CORPS_MAIL="$(curl -s "$MAILPIT_URL/api/v1/message/$MSG_ID")"
  verifier "le courriel porte le lien d'invitation" "oui" \
    "$(jq -r '.HTML' <<<"$CORPS_MAIL" | grep -q "/invite/$TOKEN1" && echo oui || echo non)"
  verifier "le courriel est en français" "oui" \
    "$(jq -r '.Subject' <<<"$CORPS_MAIL" | grep -q "t'invite sur Astreinte SP" && echo oui || echo non)"
fi

# ---------------------------------------------------------------------------
echo ''
echo '--- 3. invite-member : renvoi, doublons et lot'
# ---------------------------------------------------------------------------
sql "update invitations set expires_at = now() + interval '1 day'" >/dev/null
appeler invite-member "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"email\":\"invite-test-1@caserne-a.test\"}"
verifier "renvoi : 200" "200" "$STATUT"
verifier "statut resent" "resent" "$(jq -r '.results[0].status' <<<"$CORPS")"
verifier "même invitation, pas de doublon" "$INVITATION_ID" "$(jq -r '.results[0].invitation_id' <<<"$CORPS")"
verifier "invitation renvoyée sans recréer de compte" "resent" "$(jq -r '.results[0].status' <<<"$CORPS")"
verifier "une seule ligne en base" "1" "$(sql 'select count(*) from invitations')"
verifier "expiration repoussée à 14 jours" "t" \
  "$(sql "select expires_at > now() + interval '13 days' from invitations
          where email = 'invite-test-1@caserne-a.test'")"
verifier "le token est conservé" "$TOKEN1" \
  "$(sql "select token from invitations where email = 'invite-test-1@caserne-a.test'")"

appeler invite-member "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"email\":\"membre2@caserne-a.test\"}"
verifier "adresse déjà membre : 200 avec erreur par adresse" "200" "$STATUT"
verifier "ok = false" "false" "$(jq -r '.ok' <<<"$CORPS")"
verifier "code already_member" "already_member" "$(jq -r '.results[0].code' <<<"$CORPS")"

appeler invite-member "$ADMIN_A" \
  "{\"station_id\":\"$STATION_A\",\"emails\":[\"invite-test-2@caserne-a.test\",\"pas-une-adresse\",\"membre3@caserne-a.test\"],\"role\":\"admin\"}"
verifier "lot de trois adresses : 200" "200" "$STATUT"
verifier "une invitée" "1" "$(jq -r '.invited' <<<"$CORPS")"
verifier "deux refusées" "2" "$(jq -r '.failed' <<<"$CORPS")"
verifier "codes par adresse" "invalid_email already_member" \
  "$(jq -r '[.results[] | select(.status == "error") | .code] | join(" ")' <<<"$CORPS")"
verifier "rôle admin transmis à l'invitation" "admin" \
  "$(sql "select role from invitations where email = 'invite-test-2@caserne-a.test'")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 4. accept-invitation : refus'
# ---------------------------------------------------------------------------
appeler accept-invitation - "{\"token\":\"$TOKEN1\"}"
verifier "sans jeton porteur : 401" "401" "$STATUT"

appeler accept-invitation "$MEMBRE_A" '{}'
verifier "corps sans token : 400" "400" "$STATUT"

appeler accept-invitation "$MEMBRE_A" '{"token":"token-qui-nexiste-pas"}'
verifier "token inconnu : 404" "404" "$STATUT"
verifier "code invitation_not_found" "invitation_not_found" "$(jq -r '.error.code' <<<"$CORPS")"

appeler accept-invitation "$MEMBRE_A" "{\"token\":\"$TOKEN1\"}"
verifier "adresse de session différente de l'invitée : 403" "403" "$STATUT"
verifier "code email_mismatch" "email_mismatch" "$(jq -r '.error.code' <<<"$CORPS")"
verifier "adresse invitée masquée" "i•••••••••••1@caserne-a.test" \
  "$(jq -r '.error.invited_email_masked' <<<"$CORPS")"
verifier "invitation toujours en attente" "1" \
  "$(sql "select count(*) from invitations
          where email = 'invite-test-1@caserne-a.test' and accepted_at is null")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 5. accept-invitation : cas nominal'
# ---------------------------------------------------------------------------
# L'invité vient de recevoir un compte sans mot de passe (il se connectera par code
# OTP). Pour le test, on lui en pose un avec la clé de service, côté serveur.
INVITE_ID="$(sql "select id from profiles where email = 'invite-test-1@caserne-a.test'")"
curl -s -o /dev/null -X PUT "$API_URL/auth/v1/admin/users/$INVITE_ID" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" \
  -H 'content-type: application/json' -d "{\"password\":\"$MDP\"}"
JETON_INVITE="$(connexion invite-test-1@caserne-a.test)"
verifier "l'invité peut ouvrir une session" "oui" \
  "$([ -n "$JETON_INVITE" ] && echo oui || echo non)"

appeler accept-invitation "$JETON_INVITE" "{\"token\":\"$TOKEN1\"}"
verifier "acceptation : 200" "200" "$STATUT"
verifier "already_accepted = false" "false" "$(jq -r '.already_accepted' <<<"$CORPS")"
verifier "membership active" "active" "$(jq -r '.membership.status' <<<"$CORPS")"
verifier "rôle member" "member" "$(jq -r '.membership.role' <<<"$CORPS")"
verifier "caserne renvoyée" "CIS Saint-Martin" "$(jq -r '.station.name' <<<"$CORPS")"
verifier "inviteur renvoyé" "admin@caserne-a.test" "$(jq -r '.inviter.email' <<<"$CORPS")"
verifier "invitation marquée acceptée" "1" \
  "$(sql "select count(*) from invitations
          where email = 'invite-test-1@caserne-a.test' and accepted_at is not null")"
verifier "membership écrite en base" "1" \
  "$(sql "select count(*) from memberships
          where user_id = '$INVITE_ID' and station_id = '$STATION_A' and status = 'active'")"

appeler accept-invitation "$JETON_INVITE" "{\"token\":\"$TOKEN1\"}"
verifier "rejeu du même lien : 200" "200" "$STATUT"
verifier "already_accepted = true" "true" "$(jq -r '.already_accepted' <<<"$CORPS")"
verifier "toujours une seule membership" "1" \
  "$(sql "select count(*) from memberships where user_id = '$INVITE_ID'")"

# Une fois membre actif, la même adresse ne peut plus être invitée.
appeler invite-member "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"email\":\"invite-test-1@caserne-a.test\"}"
verifier "adresse devenue membre : already_member" "already_member" "$(jq -r '.results[0].code' <<<"$CORPS")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 6. accept-invitation : invitation expirée'
# ---------------------------------------------------------------------------
TOKEN2="$(sql "select token from invitations where email = 'invite-test-2@caserne-a.test'")"
INVITE2_ID="$(sql "select id from profiles where email = 'invite-test-2@caserne-a.test'")"
curl -s -o /dev/null -X PUT "$API_URL/auth/v1/admin/users/$INVITE2_ID" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" \
  -H 'content-type: application/json' -d "{\"password\":\"$MDP\"}"
JETON_INVITE2="$(connexion invite-test-2@caserne-a.test)"
sql "update invitations set expires_at = now() - interval '1 day'
     where email = 'invite-test-2@caserne-a.test'" >/dev/null

appeler accept-invitation "$JETON_INVITE2" "{\"token\":\"$TOKEN2\"}"
verifier "invitation expirée : 410" "410" "$STATUT"
verifier "code invitation_expired" "invitation_expired" "$(jq -r '.error.code' <<<"$CORPS")"
verifier "de quoi contacter l'admin" "admin@caserne-a.test" "$(jq -r '.error.inviter.email' <<<"$CORPS")"
verifier "aucune membership créée" "0" \
  "$(sql "select count(*) from memberships where user_id = '$INVITE2_ID'")"

# Renvoi par l'admin : l'invitation expirée repart pour 14 jours, même lien.
appeler invite-member "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"email\":\"invite-test-2@caserne-a.test\"}"
verifier "renvoi d'une invitation expirée : resent" "resent" "$(jq -r '.results[0].status' <<<"$CORPS")"
appeler accept-invitation "$JETON_INVITE2" "{\"token\":\"$TOKEN2\"}"
verifier "le lien renvoyé fonctionne : 200" "200" "$STATUT"

# ---------------------------------------------------------------------------
echo ''
echo '--- 7. Les fonctions SQL ne sont pas appelables depuis le client'
# ---------------------------------------------------------------------------
STATUT_RPC="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/rest/v1/rpc/create_invitation" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ADMIN_A" -H 'content-type: application/json' \
  -d "{\"p_station\":\"$STATION_A\",\"p_email\":\"pirate@caserne-a.test\",\"p_role\":\"admin\",\"p_invited_by\":\"aaaaaaaa-0000-4000-8000-000000000100\"}")"
verifier "create_invitation refusée en RPC PostgREST" "oui" \
  "$([ "$STATUT_RPC" = "404" ] || [ "$STATUT_RPC" = "403" ] && echo oui || echo non)"

STATUT_RPC="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/rest/v1/rpc/accept_invitation" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ADMIN_A" -H 'content-type: application/json' \
  -d "{\"p_token\":\"$TOKEN1\",\"p_user_id\":\"aaaaaaaa-0000-4000-8000-000000000100\",\"p_email\":\"admin@caserne-a.test\"}")"
verifier "accept_invitation refusée en RPC PostgREST" "oui" \
  "$([ "$STATUT_RPC" = "404" ] || [ "$STATUT_RPC" = "403" ] && echo oui || echo non)"

# ---------------------------------------------------------------------------
echo ''
echo '--- 8. send-notification : qui a le droit d'"'"'appeler'
# ---------------------------------------------------------------------------
appeler send-notification - '{}'
verifier "sans jeton : 401" "401" "$STATUT"

appeler send-notification "$ANON_KEY" '{}'
verifier "la clé anon ne suffit pas : 401" "401" "$STATUT"

# Le point le plus important de la fonction : un membre connecté, même admin, ne
# doit jamais pouvoir écrire une notification à qui il veut, dans la caserne qu'il
# veut. Cette fonction n'est pas une API cliente.
appeler send-notification "$ADMIN_A" "{\"type\":\"assignment_proposed\",\"user_ids\":[\"$MEMBRE1_A\"]}"
verifier "un admin connecté ne peut pas l'appeler : 401" "401" "$STATUT"
verifier "code unauthenticated" "unauthenticated" "$(jq -r '.error.code' <<<"$CORPS")"

appeler send-notification "$SERVICE_KEY" '{"type":"inconnu","user_ids":["'"$MEMBRE1_A"'"]}'
verifier "type inconnu : 400" "400" "$STATUT"
verifier "code invalid_type" "invalid_type" "$(jq -r '.error.code' <<<"$CORPS")"

appeler send-notification "$SERVICE_KEY" '{"type":"schedule_validated"}'
verifier "sans destinataire : code invalid_recipients" "invalid_recipients" \
  "$(jq -r '.error.code' <<<"$CORPS")"

# `/connexion` n'est pas un des quatre liens profonds : un push le portant
# n'ouvrirait rien. Le canal est refusé plutôt que le lien livré mort.
appeler send-notification "$SERVICE_KEY" '{"type":"invitation","user_ids":["'"$MEMBRE1_A"'"],"channels":["push"]}'
verifier "une invitation ne part pas en push : 400" "400" "$STATUT"
verifier "code invalid_channels" "invalid_channels" "$(jq -r '.error.code' <<<"$CORPS")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 9. send-notification : un membre sans appareil reçoit un courriel'
# ---------------------------------------------------------------------------
sql "delete from push_tokens where user_id = '$MEMBRE1_A'" >/dev/null
AVANT_MAIL="$(curl -s "$MAILPIT_URL/api/v1/messages?limit=1" | jq -r '.messages_count // 0')"

appeler send-notification "$SERVICE_KEY" "{
  \"type\": \"assignment_proposed\",
  \"station_id\": \"$STATION_A\",
  \"recipients\": [{\"user_id\": \"$MEMBRE1_A\", \"payload\": {
      \"period\": \"2026-10\",
      \"shifts\": [{\"date\": \"2026-10-12\", \"slot\": \"night\"}]}}]}"

verifier "appel accepté : 200" "200" "$STATUT"
verifier "le titre est lisible hors contexte" "Astreinte proposée le 12 octobre, nuit" \
  "$(jq -r '.results[0].title' <<<"$CORPS")"
verifier "lien profond /proposals" "/proposals" "$(jq -r '.results[0].route' <<<"$CORPS")"
verifier "push sauté faute d'appareil" "no_token" "$(jq -r '.results[0].push.skipped' <<<"$CORPS")"
verifier "courriel de repli parti" "true" "$(jq -r '.results[0].email.sent' <<<"$CORPS")"
verifier "c'est bien un repli" "true" "$(jq -r '.results[0].email.fallback' <<<"$CORPS")"

verifier "une ligne inapp pour le centre de notifications" "1" \
  "$(sql "select count(*) from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp' and type = 'assignment_proposed'")"
verifier "une ligne email tracée et délivrée" "1" \
  "$(sql "select count(*) from notifications where user_id = '$MEMBRE1_A' and channel = 'email' and delivered")"
verifier "le lien profond est dans data.route" "/proposals" \
  "$(sql "select data ->> 'route' from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp' limit 1")"

APRES_MAIL="$(curl -s "$MAILPIT_URL/api/v1/messages?limit=1" | jq -r '.messages_count // 0')"
verifier "le courriel est arrivé dans Mailpit" "oui" \
  "$([ "$APRES_MAIL" -gt "$AVANT_MAIL" ] && echo oui || echo non)"

# ---------------------------------------------------------------------------
echo ''
echo '--- 10. send-notification : le réglage du membre'
# ---------------------------------------------------------------------------
sql "delete from notifications; update profiles set push_enabled = false where id = '$MEMBRE2_A'" >/dev/null

appeler send-notification "$SERVICE_KEY" "{
  \"type\": \"schedule_validated\",
  \"station_id\": \"$STATION_A\",
  \"user_ids\": [\"$MEMBRE2_A\"],
  \"payload\": {\"period\": \"2026-10\"}}"

verifier "type non critique : push coupé par le réglage" "push_disabled" \
  "$(jq -r '.results[0].push.skipped' <<<"$CORPS")"
verifier "et pas de courriel de contournement" "null" "$(jq -r '.results[0].email' <<<"$CORPS")"
verifier "la ligne interne est écrite quand même" "1" \
  "$(sql "select count(*) from notifications where user_id = '$MEMBRE2_A' and channel = 'inapp'")"

appeler send-notification "$SERVICE_KEY" "{
  \"type\": \"assignment_proposed\",
  \"station_id\": \"$STATION_A\",
  \"user_ids\": [\"$MEMBRE2_A\"],
  \"payload\": {\"shifts\": [{\"date\": \"2026-10-12\", \"slot\": \"night\"}]}}"

# docs/PRD.md § 6.5 : une proposition d'astreinte n'est pas désactivable. Sans
# clés Firebase, le push est « indisponible » et non « coupé » — la nuance est
# exactement ce qu'on vérifie ici.
verifier "une proposition d'astreinte passe outre le réglage" "no_token" \
  "$(jq -r '.results[0].push.skipped' <<<"$CORPS")"
verifier "et repart par courriel faute d'appareil" "true" \
  "$(jq -r '.results[0].email.sent' <<<"$CORPS")"

sql "update profiles set push_enabled = true where id = '$MEMBRE2_A'" >/dev/null

# ---------------------------------------------------------------------------
echo ''
echo '--- 11. send-notification : le regroupement'
# ---------------------------------------------------------------------------
sql "delete from notifications" >/dev/null

appeler send-notification "$SERVICE_KEY" "{
  \"type\": \"assignment_proposed\",
  \"station_id\": \"$STATION_A\",
  \"payload\": {\"period\": \"2026-10\"},
  \"recipients\": [
    {\"user_id\": \"$MEMBRE1_A\", \"payload\": {\"shifts\": [{\"date\": \"2026-10-03\", \"slot\": \"day\"}]}},
    {\"user_id\": \"$MEMBRE1_A\", \"payload\": {\"shifts\": [{\"date\": \"2026-10-05\", \"slot\": \"night\"}]}},
    {\"user_id\": \"$MEMBRE1_A\", \"payload\": {\"shifts\": [{\"date\": \"2026-10-12\", \"slot\": \"night\"}]}},
    {\"user_id\": \"$MEMBRE2_A\", \"payload\": {\"shifts\": [{\"date\": \"2026-10-09\", \"slot\": \"day\"}]}}]}"

verifier "quatre créneaux, deux destinataires" "2" "$(jq -r '.recipients' <<<"$CORPS")"
verifier "une seule notification interne pour le membre aux trois créneaux" "1" \
  "$(sql "select count(*) from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp'")"
verifier "et elle les résume" "3 astreintes proposées en octobre" \
  "$(sql "select title from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp' limit 1")"
verifier "l'autre membre garde son créneau unique" "Astreinte proposée le 9 octobre, jour" \
  "$(sql "select title from notifications where user_id = '$MEMBRE2_A' and channel = 'inapp' limit 1")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 12. Sans clés Firebase : le push est indisponible, aucun jeton perdu'
# ---------------------------------------------------------------------------
sql "delete from notifications;
     insert into push_tokens (user_id, token, platform, device_label)
     values ('$MEMBRE1_A', 'jeton-test-inexistant', 'web', 'Test')" >/dev/null

appeler send-notification "$SERVICE_KEY" "{
  \"type\": \"assignment_proposed\",
  \"station_id\": \"$STATION_A\",
  \"user_ids\": [\"$MEMBRE1_A\"],
  \"payload\": {\"shifts\": [{\"date\": \"2026-10-12\", \"slot\": \"night\"}]}}"

verifier "push indisponible, pas en échec" "unavailable" "$(jq -r '.results[0].push.skipped' <<<"$CORPS")"
verifier "aucun jeton supprimé : l'absence de clés n'accuse pas l'appareil" "0" \
  "$(jq -r '.results[0].push.removed_tokens' <<<"$CORPS")"
verifier "le jeton est toujours là" "1" \
  "$(sql "select count(*) from push_tokens where token = 'jeton-test-inexistant'")"
verifier "l'incident est tracé sur la ligne push" "1" \
  "$(sql "select count(*) from notifications where user_id = '$MEMBRE1_A' and channel = 'push' and error is not null")"
verifier "et le courriel a pris le relais" "true" "$(jq -r '.results[0].email.sent' <<<"$CORPS")"

sql "delete from push_tokens where token = 'jeton-test-inexistant'" >/dev/null

# ---------------------------------------------------------------------------
echo ''
echo '--- 13. Le chemin depuis la base : notify() → pg_net → Edge Function'
# ---------------------------------------------------------------------------
sql "delete from notifications; delete from notification_outbox" >/dev/null

OUTBOX="$(sql "select notify('schedule_validated'::notification_type,
  array['$MEMBRE1_A']::uuid[], '$STATION_A'::uuid,
  '{\"period\":\"2026-10\"}'::jsonb)")"
verifier "notify rend un identifiant de file" "oui" \
  "$([ -n "$OUTBOX" ] && echo oui || echo non)"

# pg_net dépile après le COMMIT : on laisse quelques secondes, pas plus.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  ETAT="$(sql "select status from notification_outbox where id = '$OUTBOX'")"
  [ "$ETAT" = "sent" ] && break
  sleep 1
done
verifier "la demande est traitée puis close" "sent" "$ETAT"
verifier "compte rendu rangé dans la file" "1" \
  "$(sql "select (result ->> 'delivered')::int from notification_outbox where id = '$OUTBOX'")"
verifier "la notification interne existe" "Planning d'octobre validé" \
  "$(sql "select title from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp' limit 1")"

# Idempotence du rejeu : reposter la même demande ne renvoie rien.
APPEL="$(sql "select notify_post('$OUTBOX')")"
verifier "une demande close n'est pas repostée" "f" "$APPEL"

# Et si la reprise la postait quand même, la fonction ne renverrait rien : la
# prise en charge est exclusive, et une demande close n'est plus prise du tout.
appeler send-notification "$SERVICE_KEY" "{\"outbox_id\": \"$OUTBOX\"}"
verifier "rejeu d'une demande close : 200" "200" "$STATUT"
verifier "rien n'est renvoyé une seconde fois" "already_processed" \
  "$(jq -r '.skipped' <<<"$CORPS")"
verifier "toujours une seule notification interne" "1" \
  "$(sql "select count(*) from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp'")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 13 bis. Cinq échecs, abandon, et la ligne que le membre voit (ticket 040)'
# ---------------------------------------------------------------------------
# Le chemin complet de bout en bout : une proposition d'astreinte dont les cinq
# tentatives ont échoué. Avant ce ticket, elle finissait en ligne `failed` dans
# une table que seul le rôle de service lit — le pompier concerné, lui, ne
# l'apprenait jamais. Ici, on vérifie qu'il la voit, avec ses propres droits.
#
# L'état de départ est posé directement : reproduire cinq pannes de `net.http_post`
# prendrait cinq minutes d'horloge pour vérifier exactement la même chose.
sql "delete from notifications; delete from notification_outbox" >/dev/null

PERDUE="$(sql "insert into notification_outbox
  (station_id, type, recipients, payload, channels, created_at, attempts, locked_until)
  values ('$STATION_A', 'assignment_proposed',
    '[{\"user_id\":\"$MEMBRE1_A\",\"payload\":{\"shifts\":[{\"date\":\"2026-10-12\",\"slot\":\"night\"}]}}]'::jsonb,
    '{\"period\":\"2026-10\"}'::jsonb, array['push','inapp'],
    now() - interval '1 hour', 5, now() - interval '1 minute')
  returning id")"

sql "select cron_dispatch_notifications()" >/dev/null

verifier "après cinq tentatives, la demande est abandonnée" "failed" \
  "$(sql "select status from notification_outbox where id = '$PERDUE'")"

TRACE="$(sql "select id from notification_outbox where dedupe_key = 'delivery_failure:$PERDUE'")"
verifier "l'abandon met la ligne interne du destinataire en file" "oui" \
  "$([ -n "$TRACE" ] && echo oui || echo non)"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  ETAT="$(sql "select status from notification_outbox where id = '$TRACE'")"
  [ "$ETAT" = "sent" ] && break
  sleep 1
done
verifier "et l'Edge Function la traite" "sent" "$ETAT"

verifier "une ligne interne, et une seule" "1" \
  "$(sql "select count(*) from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp'")"
# Le mode trace n'envoie rien : pas de push sur un canal qui vient d'échouer cinq
# fois, pas de courriel de rattrapage. La trace dit ce qui s'est passé.
verifier "aucun envoi n'est rejoué" "0" \
  "$(sql "select count(*) from notifications where channel <> 'inapp'")"

# Les mots sont ceux de `construireContenu`, pas une phrase écrite en SQL : c'est
# tout l'intérêt du détour par l'Edge Function.
verifier "le membre lit l'astreinte qu'il a failli ne jamais connaître" \
  "Astreinte proposée le 12 octobre, nuit" \
  "$(sql "select title from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp'")"
verifier "la ligne porte la marque d'échec, que l'écran traduit" "t" \
  "$(sql "select error is not null and not delivered and sent_at is null
            from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp'")"
verifier "et le lien profond reste utilisable" "/proposals" \
  "$(sql "select data ->> 'route' from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp'")"

# Et surtout : elle est visible **par le membre**, avec ses propres droits, pas
# seulement par le rôle de service. C'est ce que le ticket demande.
MEMBRE1_A_JETON="$(connexion membre1@caserne-a.test)"
MEMBRE1_B_JETON="$(connexion membre1@caserne-b.test)"

lire_notifications() { # lire_notifications <jeton>
  curl -s "$API_URL/rest/v1/notifications?select=title,error&channel=eq.inapp" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $1"
}

VUE="$(lire_notifications "$MEMBRE1_A_JETON")"
verifier "le destinataire voit la ligne dans son centre de notifications" "1" \
  "$(jq -r 'length' <<<"$VUE")"
verifier "avec son titre" "Astreinte proposée le 12 octobre, nuit" \
  "$(jq -r '.[0].title' <<<"$VUE")"
verifier "et sa mention d'échec" "true" "$(jq -r '.[0].error != null' <<<"$VUE")"
verifier "un membre d'une autre caserne n'en voit rien" "0" \
  "$(jq -r 'length' <<<"$(lire_notifications "$MEMBRE1_B_JETON")")"

# Rejouée, la tâche ne produit ni seconde trace ni seconde ligne.
sql "select cron_dispatch_notifications()" >/dev/null
verifier "rejouée, la reprise ne double ni la trace…" "1" \
  "$(sql "select count(*) from notification_outbox where payload ? 'delivery_failure'")"
verifier "…ni la ligne interne" "1" \
  "$(sql "select count(*) from notifications where user_id = '$MEMBRE1_A' and channel = 'inapp'")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 14. publish-schedule : identité, rôle et corps de requête'
# ---------------------------------------------------------------------------
sql "delete from notifications; delete from notification_outbox" >/dev/null

# Un planning de brouillon pour le mois M+2, avec neuf attributions : sept pour
# membre1 — **le** cas du ticket — et deux pour membre2.
# `create_schedule` exige un `auth.uid()` d'administrateur : psql n'en a pas. Le
# planning et ses créneaux sont donc posés directement, exactement comme la
# fonction les pose — elle est couverte de son côté par
# `supabase/tests/planning_brouillon_test.sql`.
PLANNING="$(sql "
  insert into schedules (station_id, period_id, created_by)
  values ('$STATION_A', '$PERIODE_A', 'aaaaaaaa-0000-4000-8000-000000000100')
  returning id")"

sql "insert into shifts (station_id, schedule_id, date, slot, required_count)
     select '$STATION_A', '$PLANNING', j::date, s.slot, 1
       from periods p
       cross join lateral generate_series(
         make_date(p.year, p.month, 1),
         (make_date(p.year, p.month, 1) + interval '1 month - 1 day')::date,
         interval '1 day') j
       cross join (select unnest(enum_range(null::slot_type)) as slot) s
      where p.id = '$PERIODE_A'" >/dev/null

sql "insert into assignments (station_id, shift_id, user_id, created_by)
     select '$STATION_A', sh.id,
            case when row_number() over (order by sh.date, sh.slot) <= 7
                 then '$MEMBRE1_A'::uuid else '$MEMBRE2_A'::uuid end,
            'aaaaaaaa-0000-4000-8000-000000000100'
       from shifts sh
      where sh.schedule_id = '$PLANNING'
      order by sh.date, sh.slot
      limit 9" >/dev/null

appeler publish-schedule - "{\"schedule_id\": \"$PLANNING\"}"
verifier "sans jeton : 401" "401" "$STATUT"

appeler publish-schedule "$MEMBRE_A" "{\"schedule_id\": \"$PLANNING\"}"
verifier "un membre ne publie pas : 403" "403" "$STATUT"
verifier "et le code le dit" "not_admin" "$(jq -r '.error.code' <<<"$CORPS")"

appeler publish-schedule "$ADMIN_B" "{\"schedule_id\": \"$PLANNING\"}"
verifier "l'admin de la caserne voisine ne publie pas : 403" "403" "$STATUT"

appeler publish-schedule "$ADMIN_A" '{}'
verifier "sans schedule_id : 400" "400" "$STATUT"

appeler publish-schedule "$ADMIN_A" "{\"schedule_id\": \"$STATION_INCONNUE\"}"
verifier "planning inconnu : 404" "404" "$STATUT"

verifier "rien n'est publié tant que rien n'est accepté" "draft" \
  "$(sql "select status from schedules where id = '$PLANNING'")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 15. publish-schedule : une notification par membre, pas une par créneau'
# ---------------------------------------------------------------------------
appeler publish-schedule "$ADMIN_A" "{\"schedule_id\": \"$PLANNING\"}"
verifier "la publication réussit : 200" "200" "$STATUT"
verifier "le planning est publié" "published" "$(jq -r '.status' <<<"$CORPS")"
verifier "neuf attributions horodatées" "9" "$(jq -r '.assignments' <<<"$CORPS")"
verifier "deux membres notifiés pour neuf créneaux" "2" "$(jq -r '.notified' <<<"$CORPS")"
verifier "send-notification a servi les deux" "2" \
  "$(jq -r '.notification.delivered' <<<"$CORPS")"

verifier "la base dit la même chose" "published" \
  "$(sql "select status from schedules where id = '$PLANNING'")"
verifier "proposed_at est posé sur chaque attribution" "0" \
  "$(sql "select count(*) from assignments a join shifts sh on sh.id = a.shift_id
           where sh.schedule_id = '$PLANNING' and a.proposed_at is null")"

# **Le critère d'acceptation**, vu depuis la table des notifications.
verifier "membre1 : une seule notification interne" "1" \
  "$(sql "select count(*) from notifications
           where user_id = '$MEMBRE1_A' and type = 'assignment_proposed' and channel = 'inapp'")"
verifier "et elle résume ses sept créneaux" "7 astreintes proposées" \
  "$(sql "select left(title, 22) from notifications
           where user_id = '$MEMBRE1_A' and type = 'assignment_proposed' and channel = 'inapp'")"
verifier "membre2 : une seule notification interne" "1" \
  "$(sql "select count(*) from notifications
           where user_id = '$MEMBRE2_A' and type = 'assignment_proposed' and channel = 'inapp'")"
verifier "le lien profond mène aux propositions" "/proposals" \
  "$(sql "select data ->> 'route' from notifications
           where user_id = '$MEMBRE1_A' and channel = 'inapp' limit 1")"
verifier "l'audit garde la trace de la publication" "1" \
  "$(sql "select count(*) from audit_log
           where action = 'schedule.published' and entity_id = '$PLANNING'")"

appeler publish-schedule "$ADMIN_A" "{\"schedule_id\": \"$PLANNING\"}"
verifier "republier : 409" "409" "$STATUT"
verifier "et le code le dit" "schedule_not_draft" "$(jq -r '.error.code' <<<"$CORPS")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 16. reassign-shift : identité, rôle et corps de requête'
# ---------------------------------------------------------------------------
# Le premier créneau du planning publié, celui de membre1. Il va refuser.
CRENEAU="$(sql "select sh.id from shifts sh
                 where sh.schedule_id = '$PLANNING'
                 order by sh.date, sh.slot limit 1")"
ATTRIBUTION="$(sql "select a.id from assignments a
                     where a.shift_id = '$CRENEAU' and a.user_id = '$MEMBRE1_A'")"

appeler reassign-shift - "{\"shift_id\": \"$CRENEAU\", \"user_id\": \"$MEMBRE3_A\"}"
verifier "sans jeton : 401" "401" "$STATUT"

appeler reassign-shift "$MEMBRE_A" "{\"shift_id\": \"$CRENEAU\", \"user_id\": \"$MEMBRE3_A\"}"
verifier "un membre ne réattribue pas : 403" "403" "$STATUT"
verifier "et le code le dit" "not_admin" "$(jq -r '.error.code' <<<"$CORPS")"

appeler reassign-shift "$ADMIN_B" "{\"shift_id\": \"$CRENEAU\", \"user_id\": \"$MEMBRE3_A\"}"
verifier "l'admin de la caserne voisine ne réattribue pas : 403" "403" "$STATUT"

appeler reassign-shift "$ADMIN_A" "{\"user_id\": \"$MEMBRE3_A\"}"
verifier "sans shift_id : 400" "400" "$STATUT"

appeler reassign-shift "$ADMIN_A" "{\"shift_id\": \"$STATION_INCONNUE\", \"user_id\": \"$MEMBRE3_A\"}"
verifier "créneau inconnu : 404" "404" "$STATUT"

appeler reassign-shift "$ADMIN_A" "{\"shift_id\": \"$CRENEAU\", \"user_id\": \"$MEMBRE1_A\"}"
verifier "le titulaire actuel n'est pas réattribué à lui-même : 409" "409" "$STATUT"
verifier "et le code le dit" "already_assigned" "$(jq -r '.error.code' <<<"$CORPS")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 17. reassign-shift : un refus, une réattribution, UNE notification'
# ---------------------------------------------------------------------------
# Le refus de membre1, tel qu'il l'écrit depuis son écran.
sql "update assignments
        set status = 'declined', responded_at = now(), decline_reason = 'en formation'
      where id = '$ATTRIBUTION'" >/dev/null

sql "delete from notifications; delete from notification_outbox" >/dev/null

appeler reassign-shift "$ADMIN_A" \
  "{\"shift_id\": \"$CRENEAU\", \"user_id\": \"$MEMBRE3_A\", \"previous_assignment_id\": \"$ATTRIBUTION\"}"
verifier "la réattribution réussit : 200" "200" "$STATUT"
verifier "l'ancienne attribution était un refus" "declined" \
  "$(jq -r '.previous.status' <<<"$CORPS")"
verifier "et son titulaire n'est pas notifié" "false" \
  "$(jq -r '.previous.notified' <<<"$CORPS")"
verifier "le planning reste publié" "published" "$(jq -r '.schedule.status' <<<"$CORPS")"

# **Le critère d'acceptation du ticket**, vu depuis la table des notifications.
# La file de `notify` passe par pg_net : on laisse une seconde à la boucle.
sleep 2
verifier "une seule notification interne au total" "1" \
  "$(sql "select count(*) from notifications where channel = 'inapp'")"
verifier "et elle est pour le nouveau membre" "1" \
  "$(sql "select count(*) from notifications
           where user_id = '$MEMBRE3_A' and type = 'assignment_proposed' and channel = 'inapp'")"
verifier "l'ancien titulaire n'a rien reçu" "0" \
  "$(sql "select count(*) from notifications where user_id = '$MEMBRE1_A'")"
verifier "le refus reste un refus" "declined" \
  "$(sql "select status from assignments where id = '$ATTRIBUTION'")"
verifier "et il porte le fil vers l'attribution qui l'a couvert" "1" \
  "$(sql "select count(*) from assignments
           where id = '$ATTRIBUTION' and replaced_by is not null")"
verifier "la nouvelle attribution est horodatée" "1" \
  "$(sql "select count(*) from assignments
           where shift_id = '$CRENEAU' and user_id = '$MEMBRE3_A'
             and status = 'proposed' and proposed_at is not null")"
verifier "le reste du planning n'a pas bougé" "8" \
  "$(sql "select count(*) from assignments a join shifts sh on sh.id = a.shift_id
           where sh.schedule_id = '$PLANNING' and a.shift_id <> '$CRENEAU'
             and a.status = 'proposed'")"
verifier "l'audit garde la trace de la réattribution" "1" \
  "$(sql "select count(*) from audit_log where action = 'assignment.reassigned'")"

# Remplacer deux fois la même attribution : refus lisible, rien de plus n'est parti.
appeler reassign-shift "$ADMIN_A" \
  "{\"shift_id\": \"$CRENEAU\", \"user_id\": \"$MEMBRE2_A\", \"previous_assignment_id\": \"$ATTRIBUTION\"}"
verifier "remplacer deux fois la même attribution : 409" "409" "$STATUT"
verifier "et le code le dit" "assignment_not_replaceable" "$(jq -r '.error.code' <<<"$CORPS")"

# **Une réattribution remplace, elle n'ajoute pas.** Le créneau demande une
# personne et membre3 la tient : un appel de plus ferait sonner un téléphone
# pour une garde déjà couverte.
appeler reassign-shift "$ADMIN_A" \
  "{\"shift_id\": \"$CRENEAU\", \"user_id\": \"$MEMBRE2_A\"}"
verifier "un créneau déjà pourvu : 409" "409" "$STATUT"
verifier "et le code le dit" "shift_already_filled" "$(jq -r '.error.code' <<<"$CORPS")"
verifier "la réponse dit les places tenues" "1" "$(jq -r '.error.filled' <<<"$CORPS")"
verifier "et les places demandées" "1" "$(jq -r '.error.required' <<<"$CORPS")"
verifier "rien de plus n'est parti" "1" \
  "$(sql "select count(*) from notifications where channel = 'inapp'")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 18. create-checkout : qui a le droit d'"'"'ouvrir un paiement'
# ---------------------------------------------------------------------------
# `create-checkout` ouvre une session de paiement **et** le portail de gestion,
# où l'on peut résilier. Le droit s'établit en base, jamais sur le `station_id`
# du corps de la requête.
appeler create-checkout - "{\"station_id\":\"$STATION_A\",\"action\":\"state\"}"
verifier "sans jeton porteur : 401" "401" "$STATUT"

appeler create-checkout "$ANON_KEY" "{\"station_id\":\"$STATION_A\",\"action\":\"state\"}"
verifier "la clé anon seule ne suffit pas : 401" "401" "$STATUT"
verifier "code unauthenticated" "unauthenticated" "$(jq -r '.error.code' <<<"$CORPS")"

appeler create-checkout "$MEMBRE_A" "{\"station_id\":\"$STATION_A\",\"action\":\"state\"}"
verifier "un membre simple ne voit pas l'abonnement : 403" "403" "$STATUT"
verifier "code not_admin" "not_admin" "$(jq -r '.error.code' <<<"$CORPS")"

appeler create-checkout "$ADMIN_B" "{\"station_id\":\"$STATION_A\",\"action\":\"state\"}"
verifier "un admin d'une autre caserne : 403" "403" "$STATUT"
verifier "et le message ne dit pas si la caserne existe" "not_admin" \
  "$(jq -r '.error.code' <<<"$CORPS")"

appeler create-checkout "$ADMIN_A" "{\"station_id\":\"$STATION_INCONNUE\",\"action\":\"state\"}"
verifier "une caserne inconnue : 403, pas 404" "403" "$STATUT"

appeler create-checkout "$ADMIN_A" '{}'
verifier "sans station_id : 400" "400" "$STATUT"
verifier "code invalid_body" "invalid_body" "$(jq -r '.error.code' <<<"$CORPS")"

appeler create-checkout "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"action\":\"resilier\"}"
verifier "une action inconnue : 400" "400" "$STATUT"

# Un identifiant mal formé est une faute de frappe, pas un incident serveur :
# il partait dans une requête PostgREST et en revenait en 500.
appeler create-checkout "$ADMIN_A" '{"station_id":"pas-un-uuid","action":"state"}'
verifier "un station_id mal formé : 400, pas 500" "400" "$STATUT"
verifier "code invalid_body" "invalid_body" "$(jq -r '.error.code' <<<"$CORPS")"

code_http="$(curl -s -o /dev/null -w '%{http_code}' -X GET \
  "$API_URL/functions/v1/create-checkout" -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ADMIN_A" || true)"
verifier "un GET est refusé : 405" "405" "$code_http"

# ---------------------------------------------------------------------------
echo ''
echo '--- 19. create-checkout : l'"'"'état, sans compte chez le prestataire'
# ---------------------------------------------------------------------------
# **Le cas du projet aujourd'"'"'hui.** L'action « state » répond quand même :
# c'est ce qui permet à l'écran d'annoncer le tarif au lieu de planter.
appeler create-checkout "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"action\":\"state\"}"
verifier "l'état se lit : 200" "200" "$STATUT"
verifier "les tarifs sont ceux du PRD, en centimes" "1200" \
  "$(jq -r '.prices.monthly' <<<"$CORPS")"
verifier "et l'annuel aussi" "12000" "$(jq -r '.prices.yearly' <<<"$CORPS")"
verifier "la caserne du seed est en essai" "trialing" \
  "$(jq -r '.subscription.status' <<<"$CORPS")"
verifier "avec sa date de fin d'essai" "true" \
  "$(jq -r '.subscription.trial_ends_at != null' <<<"$CORPS")"
verifier "aucun portail à ouvrir" "false" "$(jq -r '.portal_available' <<<"$CORPS")"

# Ce que la fonction répond dépend de ce que le propriétaire a branché. Les deux
# cas sont vérifiés, et c'est le second — sans compte — qui est celui du projet
# aujourd'hui.
if [ -z "${STRIPE_WEBHOOK_SECRET:-}" ]; then
  verifier "sans compte, l'état le dit" "false" "$(jq -r '.configured' <<<"$CORPS")"

  # Souscrire sans compte : refus clair, jamais une erreur serveur.
  appeler create-checkout "$ADMIN_A" \
    "{\"station_id\":\"$STATION_A\",\"action\":\"checkout\",\"plan\":\"monthly\"}"
  verifier "souscrire sans compte : 503" "503" "$STATUT"
  verifier "code stripe_not_configured" "stripe_not_configured" \
    "$(jq -r '.error.code' <<<"$CORPS")"

  appeler create-checkout "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"action\":\"portal\"}"
  verifier "le portail non plus : 503" "503" "$STATUT"
else
  verifier "avec un compte, l'état le dit" "true" "$(jq -r '.configured' <<<"$CORPS")"

  # Une formule inconnue est refusée **avant** tout appel au prestataire.
  appeler create-checkout "$ADMIN_A" \
    "{\"station_id\":\"$STATION_A\",\"action\":\"checkout\",\"plan\":\"weekly\"}"
  verifier "une formule inconnue : 400" "400" "$STATUT"
  verifier "code invalid_plan" "invalid_plan" "$(jq -r '.error.code' <<<"$CORPS")"

  # Sans client chez le prestataire, il n'y a rien à gérer : 409, et la phrase
  # le dit. Ce n'est pas une panne.
  appeler create-checkout "$ADMIN_A" "{\"station_id\":\"$STATION_A\",\"action\":\"portal\"}"
  verifier "le portail sans client : 409" "409" "$STATUT"
  verifier "code no_customer" "no_customer" "$(jq -r '.error.code' <<<"$CORPS")"
fi

# Et la caserne écrit toujours : une caserne sans abonnement configuré reste
# pleinement utilisable (`station_writable`, migration 0007).
verifier "la caserne reste en écriture" "t" \
  "$(sql "select station_writable('$STATION_A')")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 20. stripe-webhook : un événement non signé est rejeté'
# ---------------------------------------------------------------------------
# **Le point de sécurité du ticket 029.** Cette fonction est publique par
# nature : Stripe appelle sans jeton. La signature est donc tout ce qui
# distingue un vrai événement d'un événement forgé — et un événement forgé
# vaudrait « cette caserne est active », ou « suspendue », sans qu'un euro
# ait circulé.
EVENEMENT="{\"id\":\"evt_forge\",\"type\":\"invoice.paid\",\"data\":{\"object\":{\"customer\":\"cus_forge\"}}}"

webhook() { # webhook <en-tête de signature|-> <corps>
  local entetes=(-H 'content-type: application/json')
  [ "$1" != "-" ] && entetes+=(-H "Stripe-Signature: $1")
  local reponse
  reponse="$(curl -s -w $'\n%{http_code}' -X POST "$API_URL/functions/v1/stripe-webhook" \
    "${entetes[@]}" -d "$2")"
  STATUT="$(printf '%s' "$reponse" | tail -1)"
  CORPS="$(printf '%s' "$reponse" | sed '$d')"
}

code_http="$(curl -s -o /dev/null -w '%{http_code}' -X GET \
  "$API_URL/functions/v1/stripe-webhook" || true)"
verifier "un GET est refusé : 405" "405" "$code_http"

webhook - "$EVENEMENT"
if [ -z "${STRIPE_WEBHOOK_SECRET:-}" ]; then
  # Tant qu'aucun secret n'est posé, **tout** est refusé : le repli n'est pas
  # « accepter sans vérifier », ce serait ouvrir la porte en grand.
  verifier "sans secret configuré, rien n'est traité : 503" "503" "$STATUT"
  verifier "code stripe_not_configured" "stripe_not_configured" \
    "$(jq -r '.error.code' <<<"$CORPS")"

  webhook "t=1730000000,v1=$(printf 'f%.0s' {1..64})" "$EVENEMENT"
  verifier "un événement forgé non plus : 503" "503" "$STATUT"
else
  verifier "sans en-tête de signature : 400" "400" "$STATUT"
  verifier "code missing_signature" "missing_signature" \
    "$(jq -r '.error.code' <<<"$CORPS")"
fi

# Et rien n'a bougé en base : c'est la vérification qui compte.
verifier "aucun abonnement n'a changé de statut" "trialing" \
  "$(sql "select status from subscriptions where station_id = '$STATION_A'")"
verifier "aucune ligne d'audit de paiement" "0" \
  "$(sql "select count(*) from audit_log where action like 'subscription.%'")"

# **Avec un secret posé**, la signature devient la seule porte. Ce bloc n'est
# joué que si `supabase functions serve --env-file` a fourni le secret : sans
# lui, la fonction répond 503 et le test ci-dessus le vérifie déjà.
signer() { # signer <horodatage> <corps>
  printf '%s.%s' "$1" "$2" \
    | openssl dgst -sha256 -hmac "${STRIPE_WEBHOOK_SECRET:-}" -hex \
    | sed 's/^.*= //'
}

if [ -n "${STRIPE_WEBHOOK_SECRET:-}" ]; then
  echo '    (secret de test présent : vérification de la signature complète)'
  T="$(date +%s)"

  webhook "t=$T,v1=$(signer "$T" "$EVENEMENT")" "$EVENEMENT"
  verifier "un événement signé passe : 200" "200" "$STATUT"
  verifier "et un client inconnu est ignoré, pas rejoué" "station_not_found" \
    "$(jq -r '.skipped' <<<"$CORPS")"

  webhook "t=$T,v1=$(printf 'f%.0s' {1..64})" "$EVENEMENT"
  verifier "une signature forgée : 400" "400" "$STATUT"
  verifier "code signature_mismatch" "signature_mismatch" \
    "$(jq -r '.error.code' <<<"$CORPS")"

  VIEUX=$((T - 3600))
  webhook "t=$VIEUX,v1=$(signer "$VIEUX" "$EVENEMENT")" "$EVENEMENT"
  verifier "un événement rejoué une heure plus tard : 400" "400" "$STATUT"
  verifier "code timestamp_out_of_tolerance" "timestamp_out_of_tolerance" \
    "$(jq -r '.error.code' <<<"$CORPS")"

  ALTERE="${EVENEMENT/cus_forge/cus_autre}"
  webhook "t=$T,v1=$(signer "$T" "$EVENEMENT")" "$ALTERE"
  verifier "un corps modifié après signature : 400" "400" "$STATUT"

  # Le tour complet : un événement signé qui touche vraiment une caserne.
  sql "update subscriptions set stripe_customer_id = 'cus_test_029'
        where station_id = '$STATION_A'" >/dev/null

  PAYE="{\"id\":\"evt_paye\",\"type\":\"invoice.paid\",\"data\":{\"object\":{\"customer\":\"cus_test_029\",\"subscription\":\"sub_test_029\",\"period_end\":1800000000}}}"
  webhook "t=$T,v1=$(signer "$T" "$PAYE")" "$PAYE"
  verifier "invoice.paid signé : 200" "200" "$STATUT"
  verifier "la caserne devient active" "active" "$(jq -r '.status' <<<"$CORPS")"
  verifier "et la base le dit aussi" "active" \
    "$(sql "select status from subscriptions where station_id = '$STATION_A'")"
  verifier "le passage est journalisé" "1" \
    "$(sql "select count(*) from audit_log where action = 'subscription.invoice.paid'")"

  # Remise du décor : la caserne du seed repart en essai.
  sql "update subscriptions
          set status = 'trialing', stripe_customer_id = null,
              stripe_subscription_id = null, plan = null,
              current_period_end = null, suspended_at = null
        where station_id = '$STATION_A';
       delete from audit_log where action like 'subscription.%';
       delete from stripe_events;" >/dev/null
fi

# ---------------------------------------------------------------------------
echo ''
echo '--- 21. stripe-webhook : le corps est lu sous plafond'
# ---------------------------------------------------------------------------
# C'est la seule fonction publique du projet, et elle lit le corps **avant**
# toute authentification — il le faut pour vérifier la signature. Sans plafond,
# un anonyme qui connaît l'adresse fait allouer autant de mémoire qu'il veut.
# Le corps passe par un fichier : 1,2 Mo sur la ligne de commande dépasse la
# taille maximale des arguments du système.
gros="$(mktemp)"
{ printf '{"charge":"'; head -c 1200000 /dev/zero | tr '\0' 'a'; printf '"}'; } > "$gros"
code_http="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  "$API_URL/functions/v1/stripe-webhook" -H 'content-type: application/json' \
  --data-binary "@$gros" || true)"
verifier "un corps de plus d'un mégaoctet : 413" "413" "$code_http"

# Et il est refusé **avant** toute lecture : rien n'en est analysé, donc rien
# n'a pu être écrit.
verifier "rien n'a été reçu en base" "0" "$(sql "select count(*) from stripe_events")"
rm -f "$gros"

# ---------------------------------------------------------------------------
echo ''
echo '--- 22. create-checkout : un abonnement en cours ne se souscrit pas deux fois'
# ---------------------------------------------------------------------------
# **Le cas qui compte n'est pas la caserne « active »** — elle ne voit pas le
# bouton. C'est celle dont la carte a expiré : son statut est « past_due », et
# un garde-fou posé sur le seul statut « active » la laisserait repartir avec un
# second abonnement, prélevé en parallèle du premier.
if [ -n "${STRIPE_WEBHOOK_SECRET:-}" ]; then
  for etat in active past_due trialing suspended; do
    sql "update subscriptions
            set status = '$etat', stripe_customer_id = 'cus_test_029',
                stripe_subscription_id = 'sub_test_029'
          where station_id = '$STATION_A'" >/dev/null

    appeler create-checkout "$ADMIN_A" \
      "{\"station_id\": \"$STATION_A\", \"action\": \"checkout\", \"plan\": \"monthly\"}"
    verifier "« $etat » avec un abonnement vivant : 409" "409" "$STATUT"
    verifier "  code already_subscribed" "already_subscribed" \
      "$(jq -r '.error.code' <<<"$CORPS")"
  done

  # Une résiliation, elle, se reprend : c'est un client qui revient, et rien ne
  # se dédouble. La session s'ouvre donc réellement — ici avec une clé de test
  # bidon, donc le refus vient du prestataire (502) et non de nous.
  sql "update subscriptions set status = 'cancelled'
        where station_id = '$STATION_A'" >/dev/null
  appeler create-checkout "$ADMIN_A" \
    "{\"station_id\": \"$STATION_A\", \"action\": \"checkout\", \"plan\": \"monthly\"}"
  verifier "une résiliation peut souscrire à nouveau" "true" \
    "$([ "$STATUT" != "409" ] && echo true || echo false)"

  sql "update subscriptions
          set status = 'trialing', stripe_customer_id = null,
              stripe_subscription_id = null, plan = null,
              current_period_end = null, suspended_at = null
        where station_id = '$STATION_A'" >/dev/null
else
  echo '    (sans secret : la souscription est refusée avant ce contrôle, voir § 19)'
fi

# ---------------------------------------------------------------------------
echo ''
echo '--- 23. stripe-webhook : rejeu et cohérence client/caserne'
# ---------------------------------------------------------------------------
if [ -n "${STRIPE_WEBHOOK_SECRET:-}" ]; then
  sql "delete from stripe_events;
       delete from audit_log where action like 'subscription.%';
       update subscriptions set stripe_customer_id = 'cus_test_029'
        where station_id = '$STATION_A';
       update subscriptions set stripe_customer_id = 'cus_test_b'
        where station_id = '$STATION_B'" >/dev/null

  T="$(date +%s)"

  # a. Un événement appliqué une fois.
  ECHEC="{\"id\":\"evt_rejeu\",\"type\":\"invoice.payment_failed\",\"data\":{\"object\":{\"customer\":\"cus_test_029\",\"subscription\":\"sub_test_029\"}}}"
  webhook "t=$T,v1=$(signer "$T" "$ECHEC")" "$ECHEC"
  verifier "un échec de paiement s'applique : 200" "200" "$STATUT"
  verifier "la caserne passe en retard de paiement" "past_due" \
    "$(sql "select status from subscriptions where station_id = '$STATION_A'")"

  # La caserne régularise.
  sql "update subscriptions set status = 'active' where station_id = '$STATION_A'" >/dev/null

  # b. **Le même événement, rejoué dans la fenêtre de tolérance.** La signature
  # le laisse passer — elle dit qu'il vient de Stripe, pas qu'il est neuf.
  webhook "t=$T,v1=$(signer "$T" "$ECHEC")" "$ECHEC"
  verifier "le rejeu répond 200" "200" "$STATUT"
  verifier "et il est reconnu comme un doublon" "duplicate" \
    "$(jq -r '.skipped' <<<"$CORPS")"
  verifier "**la caserne reste à jour**" "active" \
    "$(sql "select status from subscriptions where station_id = '$STATION_A'")"
  verifier "une seule ligne d'audit, pas deux" "1" \
    "$(sql "select count(*) from audit_log
             where action = 'subscription.invoice.payment_failed'")"

  # c. Un événement qui nomme la caserne B avec le client de A. Signature
  # valide : `client_reference_id` se pose depuis une URL.
  VOL="{\"id\":\"evt_vol\",\"type\":\"checkout.session.completed\",\"data\":{\"object\":{\"client_reference_id\":\"$STATION_B\",\"customer\":\"cus_test_029\",\"subscription\":\"sub_vole\",\"payment_status\":\"paid\"}}}"
  webhook "t=$T,v1=$(signer "$T" "$VOL")" "$VOL"
  verifier "un client qui n'est pas celui de la caserne nommée : écarté" \
    "customer_mismatch" "$(jq -r '.skipped' <<<"$CORPS")"
  verifier "B n'a pas changé de statut" "trialing" \
    "$(sql "select status from subscriptions where station_id = '$STATION_B'")"
  verifier "**et B n'a pas récupéré le client de A**" "cus_test_b" \
    "$(sql "select stripe_customer_id from subscriptions where station_id = '$STATION_B'")"

  # d. Un identifiant de caserne mal formé ne fait pas tomber la fonction.
  BANCAL="{\"id\":\"evt_bancal\",\"type\":\"invoice.paid\",\"data\":{\"object\":{\"customer\":\"cus_test_029\",\"period_end\":1800000000,\"metadata\":{\"station_id\":\"pas-un-uuid\"}}}}"
  webhook "t=$T,v1=$(signer "$T" "$BANCAL")" "$BANCAL"
  verifier "un station_id illisible : traité par le client, pas en 500" "200" "$STATUT"
  verifier "et la caserne est bien retrouvée" "active" \
    "$(jq -r '.status' <<<"$CORPS")"

  # e. La trace d'un échec survit aux rejeux abandonnés.
  sql "select stripe_event_fail('evt_perdu', 'invoice.paid', 'base indisponible')" >/dev/null
  verifier "un traitement en échec laisse une ligne « failed »" "failed" \
    "$(sql "select status from stripe_events where id = 'evt_perdu'")"

  # Remise du décor.
  sql "delete from stripe_events;
       delete from audit_log where action like 'subscription.%';
       update subscriptions
          set status = 'trialing', stripe_customer_id = null,
              stripe_subscription_id = null, plan = null,
              current_period_end = null, suspended_at = null" >/dev/null
else
  echo '    (sans secret : aucun événement ne franchit la signature, voir § 20)'
fi

# ---------------------------------------------------------------------------
echo ''
echo '--- 24. delete-account : anonymiser sans effacer l'"'"'histoire (ticket 007)'
# ---------------------------------------------------------------------------
# Le test travaille sur un **compte jetable**, jamais sur un membre du seed : une
# suppression est définitive et un compte d'authentification ne se recrée pas par
# un `delete` annulé. Le profil anonymisé, lui, n'a plus d'adresse pour être
# retrouvé — son identifiant est donc gardé ici, et c'est par lui qu'on nettoie.
JETABLE_EMAIL="invite-test-suppression@caserne-a.test"
JETABLE_ID="$(curl -s -X POST "$API_URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" \
  -H 'content-type: application/json' \
  -d "{\"email\":\"$JETABLE_EMAIL\",\"password\":\"$MDP\",\"email_confirm\":true}" \
  | jq -r '.id // empty')"

if [ -z "$JETABLE_ID" ]; then
  echo '    (compte jetable non créé : section ignorée)' >&2
  echecs=$((echecs + 1))
else
  sql "update profiles
          set first_name = 'Jean', last_name = 'Jetable', phone = '+33600000999'
        where id = '$JETABLE_ID';
       insert into memberships (station_id, user_id, role, status, display_name)
       values ('$STATION_A', '$JETABLE_ID', 'member', 'active', 'Jean J.');
       insert into push_tokens (user_id, token, platform)
       values ('$JETABLE_ID', 'jeton-test-suppression', 'web');
       insert into availabilities (station_id, user_id, date, slot, status, set_by)
       values ('$STATION_A', '$JETABLE_ID', current_date, 'day', 'available',
               '$JETABLE_ID');" >/dev/null

  # Une attribution passée, acceptée : c'est elle que la caserne doit garder. Le
  # planning du mois peut déjà exister — la section 15 en crée un sur la même
  # période — et `schedules` n'en accepte qu'un par mois.
  sql "insert into schedules (station_id, period_id, status, created_by, published_at)
       select '$STATION_A', '$PERIODE_A', 'published',
              'aaaaaaaa-0000-4000-8000-000000000100', now()
        where not exists (select 1 from schedules where period_id = '$PERIODE_A');
       insert into shifts (station_id, schedule_id, date, slot, required_count)
       select '$STATION_A', id, current_date, 'night', 1
         from schedules where period_id = '$PERIODE_A'
       on conflict (schedule_id, date, slot) do nothing;
       insert into assignments (station_id, shift_id, user_id, status, created_by,
                                proposed_at, responded_at)
       select '$STATION_A', s.id, '$JETABLE_ID', 'accepted',
              'aaaaaaaa-0000-4000-8000-000000000100', now(), now()
         from shifts s
         join schedules sc on sc.id = s.schedule_id
        where sc.period_id = '$PERIODE_A'
          and s.date = current_date and s.slot = 'night';" >/dev/null

  # a. Le portier : ni corps, ni identité déclarée. Tout vient du jeton.
  appeler delete-account - '{}'
  verifier "sans jeton : 401" "401" "$STATUT"
  verifier "et le code le dit" "unauthenticated" "$(jq -r '.error.code' <<<"$CORPS")"

  # b. Le dernier administrateur d'une caserne ne part pas.
  JETON_ADMIN="$(connexion admin@caserne-a.test)"
  appeler delete-account "$JETON_ADMIN" '{}'
  verifier "le dernier administrateur est refusé : 409" "409" "$STATUT"
  verifier "avec le code last_admin" "last_admin" "$(jq -r '.error.code' <<<"$CORPS")"
  verifier "et la caserne nommée" "CIS Saint-Martin" \
    "$(jq -r '.error.station' <<<"$CORPS")"
  verifier "**un refus n'écrit rien** : son appartenance est intacte" "active" \
    "$(sql "select status from memberships
             where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'")"

  # c. La suppression elle-même.
  JETON_JETABLE="$(connexion "$JETABLE_EMAIL")"
  appeler delete-account "$JETON_JETABLE" '{}'
  verifier "la suppression aboutit : 200" "200" "$STATUT"
  verifier "une appartenance désactivée" "1" "$(jq -r '.memberships' <<<"$CORPS")"

  verifier "le compte d'authentification est supprimé" "0" \
    "$(sql "select count(*) from auth.users where id = '$JETABLE_ID'")"
  verifier "le profil reste, anonymisé" "Membre supprimé" \
    "$(sql "select trim(first_name || ' ' || last_name)
              from profiles where id = '$JETABLE_ID'")"
  verifier "l'adresse devient non routable" "supprime@astreinte.invalid" \
    "$(sql "select email from profiles where id = '$JETABLE_ID'")"
  verifier "le téléphone est effacé" "" \
    "$(sql "select coalesce(phone, '') from profiles where id = '$JETABLE_ID'")"
  verifier "l'appartenance est désactivée" "disabled" \
    "$(sql "select status from memberships where user_id = '$JETABLE_ID'")"
  verifier "le surnom de caserne est effacé" "" \
    "$(sql "select coalesce(display_name, '') from memberships
             where user_id = '$JETABLE_ID'")"
  verifier "les disponibilités sont effacées" "0" \
    "$(sql "select count(*) from availabilities where user_id = '$JETABLE_ID'")"
  verifier "les appareils sont effacés" "0" \
    "$(sql "select count(*) from push_tokens where user_id = '$JETABLE_ID'")"

  # d. **Le critère d'acceptation du ticket.**
  verifier "l'attribution passée subsiste" "1" \
    "$(sql "select count(*) from assignments
             where user_id = '$JETABLE_ID' and status = 'accepted'")"
  verifier "et elle se lit « Membre supprimé »" "Membre supprimé" \
    "$(sql "select trim(p.first_name || ' ' || p.last_name)
              from assignments a join profiles p on p.id = a.user_id
             where a.user_id = '$JETABLE_ID'")"
  verifier "la suppression est tracée dans la caserne" "1" \
    "$(sql "select count(*) from audit_log
             where entity_id = '$JETABLE_ID' and action = 'account.deleted'")"

  # e. Le jeton d'un compte supprimé n'ouvre plus rien.
  appeler delete-account "$JETON_JETABLE" '{}'
  verifier "le jeton d'un compte supprimé est refusé" "401" "$STATUT"

  # Remise du décor : le compte jetable ne laisse rien derrière lui. Le planning
  # et son créneau partent avec lui — `nettoyer` en fait autant à la sortie.
  sql "alter table schedules disable trigger schedules_guard_suppression;
       delete from assignments where user_id = '$JETABLE_ID';
       delete from schedules where period_id = '$PERIODE_A';
       alter table schedules enable trigger schedules_guard_suppression;
       delete from audit_log where entity_id = '$JETABLE_ID';
       delete from memberships where user_id = '$JETABLE_ID';
       delete from profiles where id = '$JETABLE_ID';" >/dev/null
fi

# ---------------------------------------------------------------------------
echo ''
echo '--- 25. export-user-data : tout de moi, rien des autres (ticket 034)'
# ---------------------------------------------------------------------------
# Lecture seule : la section travaille sur un membre du seed, sans rien détruire.
# Elle pose seulement un appareil (préfixe `jeton-test-`, balayé par `nettoyer`)
# et une invitation, pour que les sections correspondantes ne soient pas vides.
sql "insert into push_tokens (user_id, token, platform, device_label)
     values ('$MEMBRE1_A', 'jeton-test-export-0123456789ABCDEF', 'web', 'iPhone · Safari')
     on conflict (token) do nothing;
     insert into invitations (station_id, email, role, invited_by, token)
     values ('$STATION_B', 'membre1@caserne-a.test', 'member',
             'bbbbbbbb-0000-4000-8000-000000000100', 'jeton-test-export-invitation')
     on conflict do nothing;" >/dev/null

# a. Le portier : la clé anon est un JWT valide, elle ne dit pas *qui*.
appeler export-user-data - '{}'
verifier "sans jeton : 401" "401" "$STATUT"
verifier "et le code le dit" "unauthenticated" "$(jq -r '.error.code' <<<"$CORPS")"

JETON_MEMBRE1="$(connexion membre1@caserne-a.test)"

# b. Une lecture n'est pas un GET ici : le jeton voyage en en-tête, jamais en URL.
STATUT_GET="$(curl -s -o /dev/null -w '%{http_code}' -X GET \
  "$API_URL/functions/v1/export-user-data" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JETON_MEMBRE1")"
verifier "GET refusé : 405" "405" "$STATUT_GET"

# c. **Le cœur du ticket** : un `user_id` glissé dans le corps est ignoré.
appeler export-user-data "$JETON_MEMBRE1" "{\"user_id\":\"$MEMBRE2_A\"}"
verifier "l'export aboutit : 200" "200" "$STATUT"
verifier "l'export est celui de l'appelant, pas celui du corps" "$MEMBRE1_A" \
  "$(jq -r '.export.personne' <<<"$CORPS")"
verifier "et son profil le confirme" "membre1@caserne-a.test" \
  "$(jq -r '.donnees.profil.email' <<<"$CORPS")"

# d. Toutes les sections attendues, y compris vides.
for section in compte profil casernes appartenances disponibilites \
               preferences_de_charge attributions notifications appareils \
               invitations_recues invitations_envoyees \
               actes_administratifs_me_concernant mes_actes_administratifs \
               editeur_du_produit; do
  verifier "la section « $section » est présente" "true" \
    "$(jq --arg s "$section" 'has("donnees") and (.donnees | has($s))' <<<"$CORPS")"
done
verifier "l'inventaire accompagne les données" "true" \
  "$(jq '.export.inventaire | has("disponibilites")' <<<"$CORPS")"
verifier "les données du compte d'authentification sont là" "membre1@caserne-a.test" \
  "$(jq -r '.donnees.compte.adresse_de_connexion' <<<"$CORPS")"

# e. **Le second critère du ticket** : rien d'une autre personne. Le fichier
#    entier est fouillé, en texte — nom, prénom, adresse, identifiant.
for interdit in Thomas Moreau 'membre2@caserne-a.test' "$MEMBRE2_A" \
                Dupont 'admin@caserne-a.test' \
                'aaaaaaaa-0000-4000-8000-000000000100'; do
  verifier "« $interdit » n'apparaît pas dans l'export" "0" \
    "$(grep -c -- "$interdit" <<<"$CORPS" || true)"
done
verifier "aucun jeton d'invitation dans l'export" "0" \
  "$(grep -c -- 'jeton-test-export-invitation' <<<"$CORPS" || true)"
verifier "le jeton de l'appareil est tronqué à ses douze derniers" "456789ABCDEF" \
  "$(jq -r '[.donnees.appareils[] | select(.appareil == "iPhone · Safari")][0].jeton_fin' \
     <<<"$CORPS")"

# f. La fonction SQL, elle, reste fermée : l'Edge Function est le seul chemin.
STATUT_RPC="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  "$API_URL/rest/v1/rpc/export_own_data" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JETON_MEMBRE1" \
  -H 'content-type: application/json' \
  -d "{\"p_user_id\":\"$MEMBRE2_A\"}")"
verifier "la RPC directe est refusée à authenticated : 403" "403" "$STATUT_RPC"

sql "delete from invitations where token = 'jeton-test-export-invitation';
     delete from push_tokens where token like 'jeton-test-export-%';" >/dev/null

# ---------------------------------------------------------------------------
echo ''
echo '--- 26. auto-propose : appliquer un remplissage de brouillon (ticket 018)'
# ---------------------------------------------------------------------------
# **Ce que cette section couvre, et ce qu'elle ne couvre pas.** La couche HTTP :
# jeton, rôle, corps de requête, codes de statut, et une application réelle
# vérifiée en base. Le **choix** des pompiers, lui, est calculé dans
# l'application avec le tri du ticket 017 et éprouvé par
# `test/features/planning/proposition_automatique_test.dart` : ici, le plan est
# écrit à la main, et c'est tout l'intérêt — on vérifie que la base tient ses
# limites même quand on lui envoie un plan qu'aucun tri n'aurait produit.
#
# La caserne B et son mois M+1 : rien d'autre dans ce script ne s'en sert.

appeler auto-propose - "{\"schedule_id\": \"$STATION_INCONNUE\", \"picks\": []}"
verifier "sans jeton : 401" "401" "$STATUT"

appeler auto-propose "$ADMIN_B" "{\"picks\": []}"
verifier "sans schedule_id : 400" "400" "$STATUT"

appeler auto-propose "$ADMIN_B" "{\"schedule_id\": \"$STATION_INCONNUE\"}"
verifier "sans picks : 400" "400" "$STATUT"

appeler auto-propose "$ADMIN_B" "{\"schedule_id\": \"$STATION_INCONNUE\", \"picks\": []}"
verifier "planning inconnu : 404" "404" "$STATUT"
verifier "et le code le dit" "schedule_not_found" "$(jq -r '.error.code' <<<"$CORPS")"

# Le brouillon du mois M+1 de la caserne B, créé **comme l'écran le crée** :
# `create_schedule` exige un `auth.uid()` d'administrateur, que psql n'a pas.
PLANNING_B="$(curl -s -X POST "$API_URL/rest/v1/rpc/create_schedule" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ADMIN_B" \
  -H 'content-type: application/json' \
  -d "{\"p_station\": \"bbbbbbbb-0000-4000-8000-000000000001\",
       \"p_period\": \"$PERIODE_B\"}" | jq -r '.id // empty')"
verifier "le brouillon de la caserne B existe" "true" \
  "$([ -n "$PLANNING_B" ] && echo true || echo false)"

appeler auto-propose "$ADMIN_A" "{\"schedule_id\": \"$PLANNING_B\", \"picks\": []}"
verifier "l'admin de la caserne voisine ne remplit pas : 403" "403" "$STATUT"
verifier "et le code le dit" "not_admin" "$(jq -r '.error.code' <<<"$CORPS")"

# Trois lignes écrites à la main, prises dans les disponibilités réelles du
# seed : les deux premiers créneaux qui ont un candidat, chacun avec **un seul**
# pompier, puis une répétition de la première — que la base doit écarter.
PICKS_B="$(sql "select jsonb_agg(p order by rang)::text from (
  select row_number() over (order by sh.date, sh.slot) as rang,
         jsonb_build_object('shift_id', sh.id, 'user_id', av.user_id) as p
    from shifts sh
    join lateral (
      select a.user_id from availabilities a
       where a.station_id = sh.station_id
         and a.date = sh.date and a.slot = sh.slot
         and a.status = 'available'
       order by a.user_id
       limit 1
    ) av on true
   where sh.schedule_id = '$PLANNING_B'
   order by sh.date, sh.slot
   limit 2
) t")"
PICKS_B="$(jq -c '. + [.[0]]' <<<"$PICKS_B")"

OUTBOX_AVANT="$(sql "select count(*) from notification_outbox")"

appeler auto-propose "$ADMIN_B" "{\"schedule_id\": \"$PLANNING_B\", \"picks\": $PICKS_B}"
verifier "l'admin remplit son brouillon : 200" "200" "$STATUT"
verifier "deux attributions posées" "2" "$(jq -r '.applied' <<<"$CORPS")"
verifier "la ligne en double est écartée" "already_assigned" \
  "$(jq -r '[.skipped[].code] | join(",")' <<<"$CORPS")"
verifier "les attributions sont bien en base" "2" \
  "$(sql "select count(*) from assignments a
           join shifts sh on sh.id = a.shift_id
          where sh.schedule_id = '$PLANNING_B'")"
verifier "aucune n'est hors disponibilité" "0" \
  "$(sql "select count(*) from assignments a
           join shifts sh on sh.id = a.shift_id
          where sh.schedule_id = '$PLANNING_B' and a.was_available is false")"
verifier "rien n'est parti : proposed_at reste nul" "0" \
  "$(sql "select count(*) from assignments a
           join shifts sh on sh.id = a.shift_id
          where sh.schedule_id = '$PLANNING_B' and a.proposed_at is not null")"
verifier "et personne n'a été notifié" "$OUTBOX_AVANT" \
  "$(sql "select count(*) from notification_outbox")"

# ---------------------------------------------------------------------------
echo ''
echo '--- 27. ics-feed : une adresse publique qui ne donne que ses propres astreintes'
# ---------------------------------------------------------------------------
# La seule fonction du projet qu'on appelle **sans en-tête** : ses clients sont
# les serveurs de Google, d'Apple et de Microsoft. Ce que ce bloc éprouve est
# exactement ce que le ticket 028 promet — un jeton valide, un jeton inconnu, un
# jeton régénéré, un membre désactivé, et le contenu de l'événement.

# Un mois à part, un planning publié, deux astreintes acceptées pour membre1 :
# une de jour, une de nuit, sur des dates fixes pour que les heures attendues
# soient calculables à la main (14 et 15 mars 2027 : l'heure d'été ne commence
# que le 28, la caserne est donc encore à UTC+1).
sql "insert into periods (id, station_id, year, month, status, deadline_at)
     values ('$PERIODE_ICS', '$STATION_A', 2027, 3, 'locked', '2027-02-15 23:59:59+01')
     on conflict (id) do nothing" >/dev/null

PLANNING_ICS="$(sql "
  insert into schedules (station_id, period_id, status, created_by, published_at)
  values ('$STATION_A', '$PERIODE_ICS', 'published',
          'aaaaaaaa-0000-4000-8000-000000000100', now())
  returning id")"

sql "with c as (
       insert into shifts (station_id, schedule_id, date, slot, required_count)
       values ('$STATION_A', '$PLANNING_ICS', date '2027-03-14', 'day',   1),
              ('$STATION_A', '$PLANNING_ICS', date '2027-03-15', 'night', 1)
       returning id
     )
     insert into assignments (station_id, shift_id, user_id, status, created_by,
                              proposed_at, responded_at)
     select '$STATION_A', c.id, '$MEMBRE1_A', 'accepted',
            'aaaaaaaa-0000-4000-8000-000000000100', now(), now()
       from c" >/dev/null

# **Le jeton se demande comme l'écran de profil le demande** : par RPC, avec le
# jeton d'accès du membre. Il n'est lisible nulle part ailleurs (migration 0029).
MEMBRE1_JWT="$(connexion membre1@caserne-a.test)"
JETON_ICS="$(curl -s -X POST "$API_URL/rest/v1/rpc/my_ics_token" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $MEMBRE1_JWT" \
  -H 'content-type: application/json' -d '{}' | tr -d '"')"
verifier "le membre lit son jeton d'abonnement" "48" "${#JETON_ICS}"

# Et il n'est **pas** lisible dans la table, ni par lui, ni par un collègue :
# c'est le grant de colonne de la migration 0029.
verifier "la colonne reste hors de portée de PostgREST" "42501" \
  "$(curl -s "$API_URL/rest/v1/profiles?select=ics_token&limit=1" \
     -H "apikey: $ANON_KEY" -H "Authorization: Bearer $MEMBRE1_JWT" | jq -r '.code // empty')"

ics "/$JETON_ICS.ics"
verifier "le flux répond sans le moindre en-tête : 200" "200" "$STATUT"
verifier "c'est bien un calendrier" "BEGIN:VCALENDAR" \
  "$(printf '%s' "$CORPS" | head -1 | tr -d '\r')"
verifier "deux événements, les deux astreintes acceptées" "2" \
  "$(grep -c 'BEGIN:VEVENT' <<<"$CORPS")"

# Le contenu de l'événement : le § 4 du brief de design, vu depuis le fichier servi.
verifier "l'intitulé dit le créneau et la caserne" "1" \
  "$(grep -c 'SUMMARY:Astreinte jour — CIS Saint-Martin' <<<"$CORPS")"
verifier "la nuit aussi" "1" \
  "$(grep -c 'SUMMARY:Astreinte nuit — CIS Saint-Martin' <<<"$CORPS")"
verifier "le lieu est la caserne" "2" "$(grep -c 'LOCATION:CIS Saint-Martin' <<<"$CORPS")"
# La virgule est échappée en `\,` (RFC 5545) : sans cela, elle couperait la
# propriété en deux et la description arriverait tronquée dans l'agenda.
verifier "la description dit jour ou nuit, et les heures" "1" \
  "$(grep -cF 'DESCRIPTION:Créneau de jour\, de 07:00 à 19:00. Astreinte acceptée.' <<<"$CORPS")"
verifier "et la nuit dit la sienne" "1" \
  "$(grep -cF 'DESCRIPTION:Créneau de nuit\, de 19:00 à 07:00. Astreinte acceptée.' <<<"$CORPS")"
# 07:00 à Paris le 14 mars 2027 = 06:00 UTC ; la nuit du 15 finit le 16 au matin.
verifier "les heures viennent des paramètres de la caserne" "1" \
  "$(grep -c 'DTSTART:20270314T060000Z' <<<"$CORPS")"
verifier "et la nuit déborde sur le lendemain" "1" \
  "$(grep -c 'DTEND:20270316T060000Z' <<<"$CORPS")"

# **Le point de sécurité** : cette adresse voyage.
verifier "aucun nom de membre dans le flux" "0" "$(grep -c 'Lefebvre' <<<"$CORPS")"
verifier "aucune adresse de courriel" "0" "$(grep -c '@caserne' <<<"$CORPS")"
verifier "rien de la caserne voisine" "0" "$(grep -c 'Val-de-Loue' <<<"$CORPS")"

ics "?token=$JETON_ICS"
verifier "la forme avec paramètre marche aussi : 200" "200" "$STATUT"

ics "/0000000000000000000000000000000000000000deadbeef.ics"
verifier "un jeton inconnu : 404" "404" "$STATUT"
verifier "et rien qui ressemble à un calendrier" "0" "$(grep -c 'VCALENDAR' <<<"$CORPS")"

ics ""
verifier "sans jeton : 404" "404" "$STATUT"

ics "/trop-court.ics"
verifier "un jeton mal formé n'atteint même pas la base : 404" "404" "$STATUT"

STATUT="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  "$API_URL/functions/v1/ics-feed/$JETON_ICS.ics")"
verifier "un POST sur une adresse d'abonnement : 405" "405" "$STATUT"

# La régénération, et l'invalidation immédiate qui va avec.
JETON_NEUF="$(curl -s -X POST "$API_URL/rest/v1/rpc/rotate_ics_token" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $MEMBRE1_JWT" \
  -H 'content-type: application/json' -d '{}' | tr -d '"')"
verifier "la régénération rend un jeton différent" "true" \
  "$([ "$JETON_NEUF" != "$JETON_ICS" ] && [ "${#JETON_NEUF}" = 48 ] && echo true || echo false)"

ics "/$JETON_ICS.ics"
verifier "l'ancienne adresse est morte sur-le-champ : 404" "404" "$STATUT"
ics "/$JETON_NEUF.ics"
verifier "la nouvelle sert le même calendrier : 200" "200" "$STATUT"
verifier "avec les deux mêmes événements" "2" "$(grep -c 'BEGIN:VEVENT' <<<"$CORPS")"

# Un membre désactivé : l'abonnement ne casse pas, il se vide.
sql "update memberships set status = 'disabled'
      where user_id = '$MEMBRE1_A' and station_id = '$STATION_A'" >/dev/null
ics "/$JETON_NEUF.ics"
verifier "membre désactivé : le flux répond quand même 200" "200" "$STATUT"
verifier "mais il est vide" "0" "$(grep -c 'BEGIN:VEVENT' <<<"$CORPS")"
verifier "et il reste un calendrier valide" "1" "$(grep -c 'END:VCALENDAR' <<<"$CORPS")"
sql "update memberships set status = 'active', disabled_at = null
      where user_id = '$MEMBRE1_A' and station_id = '$STATION_A'" >/dev/null

# Une caserne suspendue, elle, continue : « suspendu » veut dire lecture seule,
# pas gardes annulées (docs/PRD.md § 6.6).
sql "update subscriptions set status = 'suspended', suspended_at = now()
      where station_id = '$STATION_A'" >/dev/null
ics "/$JETON_NEUF.ics"
verifier "caserne suspendue : les astreintes restent au flux" "2" \
  "$(grep -c 'BEGIN:VEVENT' <<<"$CORPS")"
sql "update subscriptions set status = 'trialing', suspended_at = null
      where station_id = '$STATION_A'" >/dev/null

# ---------------------------------------------------------------------------
echo ''
if [ "$echecs" -eq 0 ]; then
  echo "=== Edge Functions : $total tests, tous verts ==="
  exit 0
fi
echo "=== Edge Functions : $echecs échec(s) sur $total ===" >&2
exit 1
