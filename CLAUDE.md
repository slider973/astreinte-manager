# Astreinte SP — instructions pour Claude Code

Application Flutter + Supabase de gestion des astreintes pour les centres de secours.
Réponds en français. Tous les textes de l'app sont en français.

## Sources de vérité

| Fichier | Rôle |
|---|---|
| `docs/PRD.md` | Ce que le produit fait et pourquoi. Périmètre du MVP. |
| `docs/SCHEMA.md` | Schéma Supabase : tables, RLS, fonctions, vues, Edge Functions, cron. À implémenter tel quel. |
| `docs/WORKFLOWS.md` | Machines à états et séquences. Deep links des notifications. |
| `PRODUCT.md` | Vérité produit au format Impeccable (design). |
| `DESIGN.md` | Système de design en vigueur, créé par Impeccable au ticket 004. |
| `design/<ticket>.md` | Brief de design d'un ticket, écrit avant le code. |
| `tickets/` | Un ticket = une PR. `backlog/`, `in-progress/`, `done/`. Tableau dans `tickets/BOARD.md`. |

En cas de contradiction entre le code et ces documents, le document gagne, sauf si un commit
explique l'écart et met le document à jour.

## Workflow de développement

Tout passe par les tickets. Ne pas coder hors ticket.

```
/ticket next        # voir les tickets prêts
/ticket 011         # dérouler le ticket 011 de bout en bout
scripts/ticket.sh   # commandes bas niveau (start, pr, board, status, show)
```

Le déroulé de `/ticket N` (défini dans `.claude/skills/ticket/SKILL.md`) :

1. `ticket-manager` déplace le ticket en `in-progress`, commite sur `main`, crée la branche `feat/N-slug`.
2. `supabase-dev` si le ticket touche la base ou les Edge Functions.
3. `ui-designer` si le ticket touche un écran : brief `design/N-slug.md` avec Impeccable et ui-ux-pro-max.
4. `flutter-dev` implémente le brief.
5. `pr-reviewer` vérifie chaque critère d'acceptation, au plus deux tours de correction.
6. `ticket-manager` déplace le ticket en `done`, pousse la branche et crée la PR avec `gh`. Le lien de la PR est écrit dans le ticket.

Les tickets ne se déplacent jamais à la main : toujours via `scripts/ticket.sh`.

Fusion : depuis le 20 septembre 2026, le propriétaire autorise la fusion automatique en squash
d'une PR dont la revue n'a relevé aucun bloquant, afin d'enchaîner les tickets. Une revue avec
bloquants non résolus reste en brouillon et attend un humain.

## Agents

| Agent | Rôle | Code ? |
|---|---|---|
| `ticket-manager` | tickets, branches, PR | non |
| `ui-designer` | brief de design par ticket | non |
| `flutter-dev` | écrans, état, navigation, accès données, tests | Flutter |
| `supabase-dev` | migrations, RLS, Edge Functions, seed | SQL, TypeScript |
| `pr-reviewer` | revue contre les critères d'acceptation | non |

## Design

- Skill `impeccable` (plugin) : `init` a produit `PRODUCT.md`. `shape` pour les briefs, `craft-floor`
  avant d'écrire des widgets, `audit` en revue, `document` pour `DESIGN.md`.
  Plateforme enregistrée : `web` (PWA mobile-first, Material 3 partout, une seule apparence).
  Méthode : code d'abord (`.impeccable/config.json`). Le monde visuel n'existe pas encore :
  `new-work` au ticket 004.
- Skill `ui-ux-pro-max` (`.claude/skills/ui-ux-pro-max/`) : données de design interrogeables.
  `python3 .claude/skills/ui-ux-pro-max/scripts/search.py "<besoin en anglais>" --stack flutter`
  ou `--domain ux|web|color|typography|icons`. Mots-clés métier, jamais génériques.
- Contexte d'usage binding : pompiers volontaires, usage rapide entre deux activités, souvent en
  extérieur, parfois avec des gants. Lisibilité, cibles tactiles 44 pt, états jamais portés par la
  couleur seule. Mode Impeccable : Operate. Pas d'emoji comme icônes.

## Canal principal : la PWA

La PWA web est le produit. Développer et vérifier sur Chrome (`flutter run -d chrome
--dart-define-from-file=env/dev.json`) et, pour les écrans clés, sur un téléphone avec la PWA
installée. Les builds iOS et Android natifs ne sont produits qu'à la demande d'une caserne :
aucun ticket du MVP ne doit exiger un simulateur ou un émulateur, et aucun plugin uniquement natif
ne doit être ajouté sans équivalent web.

## Conventions de code

- Flutter 3.x, Riverpod, go_router, supabase_flutter, firebase_messaging.
- `lib/features/<feature>/{data,domain,presentation}`, transverse dans `lib/core/`.
- Textes centralisés, jamais en dur dans les widgets.
- `flutter analyze` sans avertissement, `flutter test` verts et `flutter build web` qui passe avant toute PR.
- Migrations dans `supabase/migrations/`, rejouables avec `supabase db reset`. RLS sur chaque table.
  Jamais de clé service côté app, jamais de secret dans le dépôt.
- Commits : Conventional Commits, sujet en français, scope = feature (`feat(dispos): …`,
  `feat(db): …`, `chore(tickets): …`). Terminer par la ligne `Co-Authored-By:` du modèle de la
  session en cours, telle que le harnais la fournit.
- PR : titre `N — Titre du ticket`, corps généré par le script, terminé par
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

## Ce qu'il ne faut pas faire

- Coder une fonctionnalité qui n'est pas dans le ticket en cours.
- Inventer une colonne ou une table absente de `docs/SCHEMA.md`.
- Fusionner, fermer ou supprimer une PR ou une branche.
- Pousser sur `main` autrement que via `scripts/ticket.sh`.
- Passer `--force` au démarrage d'un ticket sans demande explicite.
