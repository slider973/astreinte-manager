# 031 — Interface super-admin

- **Épopée** : E8 Abonnement
- **Priorité** : P1
- **Dépend de** : 008, 029
- **Branche** : `feat/031-super-admin`
- **Statut** : en cours depuis 2026-09-21

## À faire
- Route `/superadmin` réservée à `super_admins` : liste des casernes (nom, membres actifs, statut abonnement, dernier planning publié, création), créer une caserne, nommer le premier admin par email (invitation), suspendre / réactiver manuellement.
- Accès aux données de planning uniquement via une action « support » tracée dans `audit_log`.

## Critères d'acceptation
- Un utilisateur non super-admin qui tape l'URL est redirigé.
