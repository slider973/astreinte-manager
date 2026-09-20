#!/usr/bin/env bash
# Tests de bout en bout des Edge Functions : invitations (ticket 006) et envoi de
# notifications (ticket 025).
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

connexion() { # connexion <email> -> jeton d'accès
  curl -s -X POST "$API_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON_KEY" -H 'content-type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$MDP\"}" | jq -r '.access_token // empty'
}

MEMBRE1_A="aaaaaaaa-0000-4000-8000-000000000101"
MEMBRE2_A="aaaaaaaa-0000-4000-8000-000000000102"

nettoyer() {
  sql "delete from audit_log where action like 'invitation.%';
       delete from notifications where type = 'invitation';
       delete from invitations;
       delete from memberships where left(user_id::text, 4) <> left(station_id::text, 4);
       delete from auth.users where email like 'invite-test-%';
       delete from notifications where type <> 'invitation';
       delete from notification_outbox;
       delete from push_tokens where token like 'jeton-test-%';
       update profiles set push_enabled = true where push_enabled = false;" >/dev/null
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

# ---------------------------------------------------------------------------
echo ''
if [ "$echecs" -eq 0 ]; then
  echo "=== Edge Functions : $total tests, tous verts ==="
  exit 0
fi
echo "=== Edge Functions : $echecs échec(s) sur $total ===" >&2
exit 1
