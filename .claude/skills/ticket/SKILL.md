---
name: ticket
description: Déroule un ticket de bout en bout (démarrage, design, développement, revue, PR) en orchestrant les agents ticket-manager, ui-designer, flutter-dev, supabase-dev et pr-reviewer. Usage : /ticket <numéro> ou /ticket next.
user-invocable: true
argument-hint: "<numéro> | next | status"
---

Tu orchestres le cycle de vie complet d'un ticket du projet Astreinte SP. Tu délègues chaque
phase à l'agent spécialisé et tu ne codes pas toi-même, sauf corrections mineures après revue.

## Arguments

- `next` ou vide : lancer `ticket-manager` pour lister les tickets prêts (`scripts/ticket.sh next`),
  présenter la liste et s'arrêter.
- `status` : `scripts/ticket.sh status` et `scripts/ticket.sh board`, résumer.
- `<numéro>` : dérouler les phases ci-dessous.

## Phases pour `/ticket <numéro>`

1. **Démarrage** : agent `ticket-manager`, « démarre le ticket N ». S'il refuse (dépendances,
   arbre non propre), rapporter et s'arrêter. Ne jamais passer `--force` sans demande explicite
   de l'utilisateur.
2. **Classification** : lire le ticket. Déterminer s'il touche la base ou les Edge Functions
   (`docs/SCHEMA.md` cité, mots « migration », « RLS », « Edge Function », « cron », « RPC »),
   et s'il touche l'UI (mots « écran », « grille », « bouton », « composant », « thème », ou
   épopées E3 à E7).
3. **Backend** si concerné : agent `supabase-dev`, avec le numéro de ticket. Attendre son compte
   rendu. S'il signale un écart avec `docs/SCHEMA.md`, le mentionner à l'utilisateur.
4. **Design** si UI concernée : agent `ui-designer`, avec le numéro de ticket. Attendre le brief
   `design/<numéro>-*.md`.
5. **Développement Flutter** si concerné : agent `flutter-dev`, avec le numéro de ticket et le
   chemin du brief. Attendre son compte rendu, y compris les sorties de `flutter analyze` et
   `flutter test`.
6. **Revue** : agent `pr-reviewer`. Si le verdict est « à corriger », renvoyer les bloquants à
   l'agent de développement concerné (`flutter-dev` ou `supabase-dev`) via SendMessage pour
   garder son contexte, puis relancer `pr-reviewer`. Au plus deux tours. Si des bloquants
   subsistent après deux tours, créer la PR en brouillon et lister les bloquants restants.
7. **PR** : agent `ticket-manager`, « crée la PR du ticket N » (avec `--draft` si la revue a
   laissé des réserves). Le script déplace le ticket en `done` et ajoute le lien de la PR.
8. **Compte rendu final** à l'utilisateur : URL de la PR, critères d'acceptation couverts ou non,
   points à vérifier sur appareil réel, écarts documentaires éventuels.

## Règles

- Un seul ticket à la fois. Ne pas enchaîner sur le suivant sans demande.
- Les agents de développement travaillent sur la branche créée en phase 1 ; vérifier qu'aucun
  d'eux n'a changé de branche.
- Si un agent échoue sur un outil (Docker absent, `flutter` absent, `gh` non authentifié),
  rapporter la cause exacte et s'arrêter plutôt que contourner.
- Ne pas fusionner la PR.
