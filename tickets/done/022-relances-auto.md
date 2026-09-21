# 022 — Relances automatiques

- **Épopée** : E5 Validation
- **Priorité** : P0
- **Dépend de** : 019, 025
- **Branche** : `feat/022-relances-auto`
- **PR** : https://github.com/slider973/astreinte-manager/pull/23
- **Statut** : terminé le 2026-09-21 (PR créée)

## À faire
- Migration 0009 (partie 2) : crons `assignment_reminders` et `late_responders_report` selon `docs/WORKFLOWS.md` section 6.
- Utilise les délais des settings de chaque caserne.
- Bouton admin « Relancer maintenant » (ticket 019) appelle la même logique en forçant l'envoi.

## Critères d'acceptation
- Test en local avec délais réduits à quelques minutes : push à T+1, email à T+2, rapport admin à T+3.
- Un membre qui a répondu ne reçoit plus rien.
