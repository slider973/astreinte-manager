# Tableau des tickets

Généré par `scripts/ticket.sh board` le 2026-09-20. Ne pas éditer à la main.

## En cours

| # | Ticket | Prio | Dépend de | PR |
|---|---|---|---|---|

## À faire

| # | Ticket | Prio | Dépend de | PR |
|---|---|---|---|---|
| 007 | [Profil utilisateur](backlog/007-profil.md) | P1 | 005 |  |
| 009 | [Gestion des membres par l'admin](backlog/009-gestion-membres.md) | P0 | 006 008 |  |
| 010 | [Paramètres de la caserne](backlog/010-parametres-caserne.md) | P1 | 008 |  |
| 011 | [Grille de saisie des disponibilités](backlog/011-saisie-dispos-grille.md) | P0 | 004 008 |  |
| 012 | [Raccourcis de sélection](backlog/012-raccourcis-selection.md) | P0 | 011 |  |
| 013 | [Préférences de charge par mois](backlog/013-preferences-quotas.md) | P0 | 011 |  |
| 014 | [Périodes, date limite et verrouillage](backlog/014-periodes-verrouillage.md) | P0 | 008 010 |  |
| 015 | [Rappels de saisie des disponibilités](backlog/015-rappels-saisie.md) | P1 | 014 025 |  |
| 016 | [Matrice des disponibilités pour l'admin](backlog/016-matrice-admin.md) | P0 | 008 013 014 |  |
| 017 | [Construction du planning en brouillon](backlog/017-brouillon-attribution.md) | P0 | 016 |  |
| 018 | [Proposition automatique de remplissage](backlog/018-proposition-automatique.md) | P1 | 017 |  |
| 019 | [Publication et suivi des réponses](backlog/019-publication-suivi.md) | P0 | 017 025 |  |
| 020 | [Réattribution d'un créneau refusé ou modifié](backlog/020-reattribution.md) | P0 | 019 |  |
| 021 | [Écran des propositions pour le membre](backlog/021-ecran-propositions.md) | P0 | 008 024 |  |
| 022 | [Relances automatiques](backlog/022-relances-auto.md) | P0 | 019 025 |  |
| 023 | [Vue du planning de la caserne pour les membres](backlog/023-planning-caserne.md) | P1 | 019 |  |
| 024 | [Push web via Firebase Cloud Messaging (PWA)](backlog/024-fcm-setup.md) | P0 | 001 005 |  |
| 025 | [Edge Function send-notification](backlog/025-edge-send-notification.md) | P0 | 002 024 |  |
| 026 | [Centre de notifications in-app](backlog/026-centre-notifications.md) | P1 | 025 |  |
| 027 | [Écran Mes astreintes](backlog/027-mes-astreintes.md) | P0 | 021 |  |
| 028 | [Export calendrier ICS](backlog/028-export-ics.md) | P1 | 027 |  |
| 029 | [Abonnement Stripe par caserne](backlog/029-stripe-abonnement.md) | P0 | 008 010 |  |
| 030 | [Mode suspendu et bannières](backlog/030-gating-suspension.md) | P1 | 029 |  |
| 031 | [Interface super-admin](backlog/031-super-admin.md) | P1 | 008 029 |  |
| 032 | [Build web PWA et déploiement](backlog/032-web-pwa-deploy.md) | P0 | 001 |  |
| 033 | [Publication sur les stores (à la demande d'une caserne)](backlog/033-stores-ios-android.md) | P2 — ne pas démarrer sans demande explicite d'une caserne | 024 032 |  |
| 034 | [RGPD : export et suppression des données](backlog/034-rgpd-export.md) | P1 | 007 |  |
| 035 | [Tests d'intégration bout en bout](backlog/035-tests-e2e.md) | P1 | 021 020 |  |
| 036 | [Push natives iOS et Android (à la demande d'une caserne)](backlog/036-push-natives.md) | P2 — ne pas démarrer sans demande explicite d'une caserne | 024 025 |  |
| 037 | [Supprimer la dépendance à fonts.gstatic.com au démarrage](backlog/037-canvaskit-autoheberge.md) | P1 | 004 032 |  |
| 038 | [Limiter le débit des invitations](backlog/038-limite-debit-invitations.md) | P1 | 006 |  |

## Terminés

| # | Ticket | Prio | Dépend de | PR |
|---|---|---|---|---|
| 001 | [Initialiser le projet Flutter et l'architecture](done/001-setup-flutter.md) | P0 |  | https://github.com/slider973/astreinte-manager/pull/1 |
| 002 | [Créer le projet Supabase et les migrations initiales](done/002-supabase-migrations.md) | P0 |  | https://github.com/slider973/astreinte-manager/pull/2 |
| 003 | [Mettre en place la CI](done/003-ci-github-actions.md) | P1 | 001 002 | https://github.com/slider973/astreinte-manager/pull/5 |
| 004 | [Thème et composants de base](done/004-design-system.md) | P1 | 001 | https://github.com/slider973/astreinte-manager/pull/4 |
| 005 | [Connexion par email et code OTP](done/005-auth-otp.md) | P0 | 001 002 | https://github.com/slider973/astreinte-manager/pull/6 |
| 006 | [Invitations et onboarding des membres](done/006-invitations-onboarding.md) | P0 | 005 008 | https://github.com/slider973/astreinte-manager/pull/7 |
| 008 | [Row Level Security et fonctions d'accès](done/008-rls-multi-tenant.md) | P0 | 002 | https://github.com/slider973/astreinte-manager/pull/3 |

