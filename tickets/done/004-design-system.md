# 004 — Thème et composants de base

- **Épopée** : E0 Fondations
- **Priorité** : P1
- **Dépend de** : 001
- **Branche** : `feat/004-design-system`
- **Statut** : terminé le 2026-09-20 (PR créée)

## Contexte
L'app doit être lisible d'un coup d'œil sur téléphone, avec de grandes cibles tactiles. Public : pompiers volontaires, usage rapide entre deux activités.

## À faire
- Thème Material 3, palette (couleur principale, disponible, absent, non saisi, proposé, accepté, refusé), mode sombre.
- Composants : `SlotChip` (case jour/nuit avec état), `DayCell`, `StatusBadge`, `PrimaryButton`, `EmptyState`, `LoadingSkeleton`, `AppScaffold` avec barre de navigation (Mon mois, Propositions, Planning, Profil ; Admin en plus pour les admins).
- Tailles de police dynamiques, cibles tactiles 44 pt minimum.
- Écran Storybook-like (`/dev/components`) accessible en build dev pour voir tous les composants.

## Critères d'acceptation
- Tous les composants ont un widget test de rendu.
- Les couleurs d'état sont distinguables en niveaux de gris (daltonisme) : utiliser une icône en plus de la couleur.
