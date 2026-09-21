#!/usr/bin/env bash
# Répond à une seule question : « est-ce que la production est à jour ? »
#
# Le 21 septembre 2026, la réponse était non depuis le premier jour — onze Edge
# Functions absentes, cinq migrations en retard, un secret Vault qui visait Docker,
# une configuration d'authentification restée aux valeurs par défaut de Supabase —
# et **rien ne le disait**. Le défaut s'est découvert quand un pompier est resté à
# la porte. Ce script existe pour que l'écart se voie avant l'usager.
#
# Il ne écrit rien : quatre lectures, un compte rendu, un code de sortie.
#   0 — le dépôt et la production disent la même chose ;
#   1 — au moins un écart, chacun nommé et expliqué ;
#   2 — le script n'a pas pu conclure (outil ou secret manquant).
#
# Usage :
#   SUPABASE_ACCESS_TOKEN=sbp_… scripts/verifier_production.sh
#
# `SUPABASE_PROJECT_REF` est facultatif depuis un poste lié (`supabase link`) :
# la référence est alors lue dans `supabase/.temp/project-ref`.
#
# Lancé par `.github/workflows/verifier-production.yml` — à chaque mise en ligne
# et à la demande — et à la main en dépannage (docs/DEPLOIEMENT.md § 8).

set -uo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine"

# ---------------------------------------------------------------------------
# Compte rendu
# ---------------------------------------------------------------------------

ecarts=0

titre() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok() { printf '  OK     %s\n' "$1"; }
info() { printf '         %s\n' "$1"; }

ecart() {
  printf '  ÉCART  %s\n' "$1"
  ecarts=$((ecarts + 1))
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::error::%s\n' "$1"
  fi
}

fatal() {
  printf '\n  ARRÊT  %s\n\n' "$1" >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::error::%s\n' "$1"
  fi
  exit 2
}

# Le CLI mêle ses messages de progression (« Connecting to remote database… ») au
# JSON demandé. On ne garde que la dernière ligne qui ressemble à un objet.
dernier_json() { grep -E '^\{.*\}$' | tail -1; }

# ---------------------------------------------------------------------------
# Ce qu'il faut pour conclure
# ---------------------------------------------------------------------------

command -v supabase >/dev/null || fatal "Le CLI Supabase est absent : https://supabase.com/docs/guides/cli"
command -v jq >/dev/null || fatal "jq est absent (brew install jq)."
command -v curl >/dev/null || fatal "curl est absent."

if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then
  fatal "SUPABASE_ACCESS_TOKEN absent. En local : \`export SUPABASE_ACCESS_TOKEN=\$(…)\` depuis https://supabase.com/dashboard/account/tokens. En CI : secret GitHub (docs/DEPLOIEMENT.md § 3)."
fi

ref="${SUPABASE_PROJECT_REF:-}"
if [ -z "$ref" ] && [ -f supabase/.temp/project-ref ]; then
  ref="$(cat supabase/.temp/project-ref)"
fi
if [ -z "$ref" ]; then
  fatal "SUPABASE_PROJECT_REF absent et le projet n'est pas lié (\`supabase link --project-ref …\`)."
fi

printf '\033[1mVérification de la production — projet %s\033[0m\n' "$ref"

# ---------------------------------------------------------------------------
# 1. Les migrations
#
# `migration list` compare la table d'historique du projet hébergé au contenu de
# `supabase/migrations/`. Une version locale sans jumelle distante est une
# migration qui n'a jamais été jouée : c'est exactement ce qui manquait le
# 21 septembre (0030 à 0034). L'inverse — une version distante inconnue du dépôt —
# est un écart aussi, et plus grave : quelqu'un a écrit sur la base hors du dépôt.
# ---------------------------------------------------------------------------

titre "1. Migrations"

sortie_migrations="$(supabase migration list --project-ref "$ref" --output-format json 2>&1)"
json_migrations="$(printf '%s\n' "$sortie_migrations" | dernier_json)"
if [ -z "$json_migrations" ]; then
  printf '%s\n' "$sortie_migrations" >&2
  fatal "Impossible de lire l'historique des migrations du projet $ref."
fi

manquantes="$(printf '%s' "$json_migrations" |
  jq -r '[.migrations[] | select((.local // "") != "" and (.remote // "") == "") | .local] | join(", ")')"
inconnues="$(printf '%s' "$json_migrations" |
  jq -r '[.migrations[] | select((.remote // "") != "" and (.local // "") == "") | .remote] | join(", ")')"
nb_local="$(printf '%s' "$json_migrations" | jq '[.migrations[] | select((.local // "") != "")] | length')"
nb_distant="$(printf '%s' "$json_migrations" | jq '[.migrations[] | select((.remote // "") != "")] | length')"

info "$nb_local dans le dépôt, $nb_distant appliquées sur le projet."
if [ -n "$manquantes" ]; then
  ecart "Migrations jamais appliquées en production : $manquantes. Rattrapage : supabase db push --linked --include-all"
fi
if [ -n "$inconnues" ]; then
  ecart "Migrations présentes en production et absentes du dépôt : $inconnues. La base a été modifiée hors du dépôt."
fi
[ -z "$manquantes$inconnues" ] && ok "Le dépôt et la production ont la même histoire."

# ---------------------------------------------------------------------------
# 2. Les Edge Functions
#
# Attendu = un dossier de `supabase/functions/` qui porte un `index.ts`. `_shared`
# et `tests` n'en ont pas et ne se déploient pas. On vérifie la présence, l'état,
# et le portier : un `verify_jwt` qui ne suit pas `supabase/config.toml` ouvre ou
# ferme une fonction sans que personne l'ait décidé.
# ---------------------------------------------------------------------------

titre "2. Edge Functions"

attendues=()
for dossier in supabase/functions/*/; do
  [ -f "$dossier/index.ts" ] || continue
  attendues+=("$(basename "$dossier")")
done

sortie_fonctions="$(supabase functions list --project-ref "$ref" --output-format json 2>&1)"
json_fonctions="$(printf '%s\n' "$sortie_fonctions" | dernier_json)"
if [ -z "$json_fonctions" ]; then
  printf '%s\n' "$sortie_fonctions" >&2
  fatal "Impossible de lire la liste des Edge Functions du projet $ref."
fi

info "${#attendues[@]} attendues par le dépôt, $(printf '%s' "$json_fonctions" | jq '.functions | length') déployées."

fonctions_en_ecart=0
for nom in "${attendues[@]}"; do
  ligne="$(printf '%s' "$json_fonctions" | jq --arg n "$nom" '.functions[] | select(.slug == $n)')"
  if [ -z "$ligne" ]; then
    ecart "Edge Function jamais déployée : $nom. Tout appel rend un 404. Rattrapage : supabase functions deploy $nom"
    fonctions_en_ecart=$((fonctions_en_ecart + 1))
    continue
  fi

  etat="$(printf '%s' "$ligne" | jq -r '.status')"
  if [ "$etat" != "ACTIVE" ]; then
    ecart "Edge Function $nom déployée mais dans l'état $etat."
    fonctions_en_ecart=$((fonctions_en_ecart + 1))
  fi

  # `verify_jwt` déclaré dans config.toml ; en son absence, le CLI déploie avec
  # la valeur par défaut, qui est « vrai ».
  attendu="$(awk -v cible="$nom" '
    /^\[functions\./ { section = $0; sub(/^\[functions\./, "", section); sub(/\]$/, "", section); next }
    /^\[/ { section = "" }
    section == cible && /^verify_jwt/ { gsub(/[^a-z]/, "", $3); print $3; exit }
  ' supabase/config.toml)"
  [ -n "$attendu" ] || attendu=true

  reel="$(printf '%s' "$ligne" | jq -r '.verify_jwt')"
  if [ "$reel" != "$attendu" ]; then
    ecart "Edge Function $nom : verify_jwt vaut $reel en production, $attendu dans supabase/config.toml."
    fonctions_en_ecart=$((fonctions_en_ecart + 1))
  fi
done

# Une fonction déployée que le dépôt ne connaît plus reste joignable : elle tourne
# sur du code que plus personne ne relit.
for slug in $(printf '%s' "$json_fonctions" | jq -r '.functions[].slug'); do
  trouvee=0
  for nom in "${attendues[@]}"; do [ "$nom" = "$slug" ] && trouvee=1; done
  if [ "$trouvee" -eq 0 ]; then
    ecart "Edge Function déployée et absente du dépôt : $slug. Elle sert du code qui n'est plus relu."
    fonctions_en_ecart=$((fonctions_en_ecart + 1))
  fi
done

[ "$fonctions_en_ecart" -eq 0 ] && ok "Les ${#attendues[@]} fonctions sont déployées, actives, et leur portier suit config.toml."

# ---------------------------------------------------------------------------
# 3. Le répartiteur de notifications
#
# `public.notify(...)` lit dans Vault l'adresse où joindre `send-notification`.
# La migration 0014 y pose l'adresse Docker de la pile locale. En production, tant
# qu'elle n'est pas remplacée, `cron_dispatch_notifications` réussit toutes les
# minutes, pousse vers un hôte qui n'existe pas, et la file grossit en silence.
# On ne lit que l'adresse ; le secret partagé, lui, ne sort jamais de la base.
# ---------------------------------------------------------------------------

titre "3. Répartiteur de notifications (Vault)"

attendu_notify="https://$ref.supabase.co/functions/v1/send-notification"
reponse_vault="$(curl -sS -X POST "https://api.supabase.com/v1/projects/$ref/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"select decrypted_secret as url from vault.decrypted_secrets where name = '"'"'notify_function_url'"'"'"}' 2>&1)"

url_notify="$(printf '%s' "$reponse_vault" | jq -r 'if type == "array" then (.[0].url // "") else "" end' 2>/dev/null)"

if [ -z "$url_notify" ]; then
  ecart "Le secret Vault notify_function_url est introuvable en production. Les notifications déclenchées depuis la base ne partiront pas."
elif [ "$url_notify" != "$attendu_notify" ]; then
  ecart "notify_function_url vise $url_notify au lieu de $attendu_notify. La file reste en attente, tentatives comptées, sans erreur visible."
else
  ok "notify_function_url vise bien la fonction du projet hébergé."
fi

# La file dit la vérité mieux qu'un réglage : une notification en échec définitif
# est un symptôme, pas une preuve, donc elle informe sans faire échouer.
file="$(curl -sS -X POST "https://api.supabase.com/v1/projects/$ref/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"select status, count(*)::int as n from notification_outbox group by status order by status"}' 2>&1)"
if printf '%s' "$file" | jq -e 'type == "array"' >/dev/null 2>&1; then
  resume="$(printf '%s' "$file" | jq -r '[.[] | "\(.status) : \(.n)"] | join(", ")')"
  info "File de notifications — ${resume:-vide}."
fi

# ---------------------------------------------------------------------------
# 4. La configuration d'authentification
#
# `config diff` compare `supabase/config.toml` — bloc `[remotes.production]`
# compris — au projet hébergé. C'est ce qui manquait le plus : le gabarit français
# existait dans le dépôt depuis le ticket 001, et la production servait celui de
# Supabase, en anglais, avec un lien là où l'application attend six chiffres.
#
# Seule la classe `update` fait échouer : une valeur déclarée ici et différente
# là-bas. `local_only` (l'API ne rend pas la propriété) et `remote_only` (le dépôt
# ne la déclare pas, `config push` n'y touche pas) sont du bruit, pas des écarts.
# ---------------------------------------------------------------------------

titre "4. Configuration d'authentification"

sortie_config="$(supabase config diff --project-ref "$ref" --output-format json 2>&1)"
json_config="$(printf '%s\n' "$sortie_config" | dernier_json)"
if [ -z "$json_config" ]; then
  printf '%s\n' "$sortie_config" >&2
  fatal "Impossible de comparer la configuration du projet $ref."
fi

portee="$(printf '%s' "$json_config" | jq -r '.target.local_scope')"
if [ "$portee" != "remotes.production" ]; then
  ecart "La comparaison utilise « $portee » et non « remotes.production » : le project_id de [remotes.production] ne correspond pas à $ref. Poussée en l'état, la configuration locale écraserait la production."
else
  info "Comparé avec la surcouche [remotes.production] de supabase/config.toml."
fi

divergences="$(printf '%s' "$json_config" | jq -r '
  [.changes[] | select(.class == "update")
   | "\(.path | join(".")) : dépôt \(.local | tostring) / production \(.remote | tostring)"] | .[]')"

if [ -n "$divergences" ]; then
  while IFS= read -r d; do
    ecart "Configuration : $d"
  done <<<"$divergences"
  info "Rattrapage : SUPABASE_AUTH_SMTP_PASSWORD=… supabase config push --project-ref $ref"
else
  ok "Le projet hébergé sert la configuration du dépôt : gabarits, serveur d'envoi, plafonds, redirections."
fi

# Le mot de passe SMTP et les autres identifiants sont masqués par l'API : aucune
# comparaison n'est possible, et ce script ne peut donc pas dire s'ils sont bons.
masques="$(printf '%s' "$json_config" | jq -r '[.masked[] | join(".")] | join(", ")')"
[ -n "$masques" ] && info "Non vérifiable (masqué par l'API) : $masques."

# ---------------------------------------------------------------------------

printf '\n'
if [ "$ecarts" -eq 0 ]; then
  printf '\033[1mProduction à jour.\033[0m Dépôt et projet %s disent la même chose.\n\n' "$ref"
  exit 0
fi

printf '\033[1m%s écart(s).\033[0m La production est en retard sur le dépôt — docs/DEPLOIEMENT.md § 8.\n\n' "$ecarts"
exit 1
