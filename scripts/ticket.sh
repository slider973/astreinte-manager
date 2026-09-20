#!/usr/bin/env bash
# Gestion du cycle de vie des tickets : backlog → in-progress → done.
# Usage : scripts/ticket.sh <board|next|status|show N|start N [--force]|pr N [--draft]|done N|reopen N>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TICKETS="$ROOT/tickets"
BOARD="$TICKETS/BOARD.md"
TODAY="$(date +%Y-%m-%d)"

die() { echo "erreur : $*" >&2; exit 1; }

find_ticket() {            # $1 = numéro → chemin du fichier (vide si absent)
  local n d f; n="$(printf '%03d' "$((10#$1))")"
  for d in backlog in-progress done; do
    for f in "$TICKETS/$d/$n"-*.md; do
      [ -e "$f" ] && { echo "$f"; return 0; }
    done
  done
  return 0
}
state_of() { basename "$(dirname "$1")"; }
num_of()   { basename "$1" | cut -d- -f1; }
slug_of()  { basename "$1" .md | cut -d- -f2-; }
title_of() { sed -n '1s/^# [0-9]* — //p' "$1"; }
prio_of()  { sed -n 's/^- \*\*Priorité\*\* : //p' "$1"; }
deps_of()  { sed -n 's/^- \*\*Dépend de\*\* : //p' "$1" | grep -oE '[0-9]{3}' || true; }
pr_of()    { sed -n 's/^- \*\*PR\*\* : //p' "$1"; }

set_meta() {               # $1 fichier, $2 clé, $3 valeur : remplace ou insère après la ligne Branche
  local f="$1" key="$2" val="$3"
  if grep -q "^- \*\*$key\*\* :" "$f"; then
    sed -i '' "s|^- \*\*$key\*\* :.*|- **$key** : $val|" "$f"
  else
    sed -i '' "/^- \*\*Branche\*\* :/a\\
- **$key** : $val
" "$f"
  fi
}

deps_done() {              # $1 fichier → 0 si toutes les dépendances sont en done
  local d f
  for d in $(deps_of "$1"); do
    f="$(find_ticket "$d")"
    [ -n "$f" ] || die "dépendance $d introuvable"
    [ "$(state_of "$f")" = "done" ] || return 1
  done
  return 0
}

board() {
  {
    echo "# Tableau des tickets"
    echo
    echo "Généré par \`scripts/ticket.sh board\` le $TODAY. Ne pas éditer à la main."
    echo
    for st in in-progress backlog done; do
      case $st in
        in-progress) echo "## En cours";;
        backlog)     echo "## À faire";;
        done)        echo "## Terminés";;
      esac
      echo
      echo "| # | Ticket | Prio | Dépend de | PR |"
      echo "|---|---|---|---|---|"
      for f in "$TICKETS/$st"/*.md; do
        [ -e "$f" ] || continue
        printf '| %s | [%s](%s/%s) | %s | %s | %s |\n' \
          "$(num_of "$f")" "$(title_of "$f")" "$st" "$(basename "$f")" \
          "$(prio_of "$f")" "$(deps_of "$f" | tr '\n' ' ' | sed 's/ $//')" "$(pr_of "$f")"
      done
      echo
    done
  } > "$BOARD"
  echo "BOARD.md régénéré"
}

next() {
  echo "Tickets prêts à démarrer (dépendances terminées), P0 d'abord :"
  for f in "$TICKETS"/backlog/*.md; do
    [ -e "$f" ] || continue
    if deps_done "$f"; then printf '%s %s — %s\n' "$(prio_of "$f")" "$(num_of "$f")" "$(title_of "$f")"; fi
  done | sort
}

status() {
  for st in backlog in-progress done; do
    printf '%-12s %s\n' "$st" "$(ls "$TICKETS/$st"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  done
}

require_clean() { [ -z "$(git -C "$ROOT" status --porcelain)" ] || die "arbre de travail non propre, commitez ou stashez d'abord"; }

start() {
  local n="$1" force="${2:-}"
  local f; f="$(find_ticket "$n")"; [ -n "$f" ] || die "ticket $n introuvable"
  [ "$(state_of "$f")" = "backlog" ] || die "ticket $n n'est pas dans backlog (état : $(state_of "$f"))"
  if ! deps_done "$f"; then
    [ "$force" = "--force" ] || die "dépendances non terminées pour $n ($(deps_of "$f" | tr '\n' ' ')). Relancer avec --force pour passer outre."
  fi
  require_clean
  git -C "$ROOT" checkout -q main
  git -C "$ROOT" pull -q --ff-only origin main 2>/dev/null || true
  local base slug branch dest
  base="$(basename "$f")"; slug="$(slug_of "$f")"; branch="feat/$(num_of "$f")-$slug"
  dest="$TICKETS/in-progress/$base"
  git -C "$ROOT" mv "$f" "$dest"
  set_meta "$dest" "Statut" "en cours depuis $TODAY"
  board
  git -C "$ROOT" add "$TICKETS"
  git -C "$ROOT" commit -q -m "chore(tickets): $(num_of "$dest") en cours — $(title_of "$dest")"
  git -C "$ROOT" push -q origin main
  git -C "$ROOT" checkout -q -b "$branch"
  echo "ticket $(num_of "$dest") → in-progress, branche $branch créée"
}

pr() {
  local n="$1" draft="${2:-}"
  local f; f="$(find_ticket "$n")"; [ -n "$f" ] || die "ticket $n introuvable"
  [ "$(state_of "$f")" = "in-progress" ] || die "ticket $n n'est pas en cours (état : $(state_of "$f"))"
  local branch cur; branch="feat/$(num_of "$f")-$(slug_of "$f")"; cur="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
  [ "$cur" = "$branch" ] || die "vous êtes sur $cur, attendu $branch"
  require_clean
  local base dest title
  base="$(basename "$f")"; dest="$TICKETS/done/$base"; title="$(num_of "$f") — $(title_of "$f")"
  git -C "$ROOT" mv "$f" "$dest"
  set_meta "$dest" "Statut" "terminé le $TODAY (PR créée)"
  board
  git -C "$ROOT" add "$TICKETS"
  git -C "$ROOT" commit -q -m "chore(tickets): $(num_of "$dest") terminé — $(title_of "$dest")"
  git -C "$ROOT" push -q -u origin "$branch"
  local body
  body="$(printf 'Ticket : `tickets/done/%s`\n\n%s\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)' \
    "$base" "$(sed -n '/^## Critères d.acceptation/,/^## /p' "$dest" | sed '$d' | sed '1s/.*/## Critères d'"'"'acceptation à vérifier en revue/')")"
  local url
  if [ "$draft" = "--draft" ]; then
    url="$(gh pr create --base main --head "$branch" --title "$title" --body "$body" --draft)"
  else
    url="$(gh pr create --base main --head "$branch" --title "$title" --body "$body")"
  fi
  set_meta "$dest" "PR" "$url"
  board
  git -C "$ROOT" add "$TICKETS"
  git -C "$ROOT" commit -q -m "chore(tickets): lien PR pour $(num_of "$dest")"
  git -C "$ROOT" push -q origin "$branch"
  echo "ticket $(num_of "$dest") → done, PR : $url"
}

move_simple() {            # $1 numéro, $2 destination (done|backlog), $3 statut
  local f; f="$(find_ticket "$1")"; [ -n "$f" ] || die "ticket $1 introuvable"
  local dest="$TICKETS/$2/$(basename "$f")"
  git -C "$ROOT" mv "$f" "$dest"
  set_meta "$dest" "Statut" "$3"
  board
  echo "ticket $(num_of "$dest") → $2 (déplacé, non commité)"
}

show() { local f; f="$(find_ticket "$1")"; [ -n "$f" ] || die "ticket $1 introuvable"; echo "[$(state_of "$f")] $f"; echo; cat "$f"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  board)  board;;
  next)   next;;
  status) status;;
  show)   show "${1:?numéro}";;
  start)  start "${1:?numéro}" "${2:-}";;
  pr)     pr "${1:?numéro}" "${2:-}";;
  done)   move_simple "${1:?numéro}" done "terminé le $TODAY (manuel)";;
  reopen) move_simple "${1:?numéro}" backlog "rouvert le $TODAY";;
  *) sed -n '2,3p' "$0"; exit 1;;
esac
