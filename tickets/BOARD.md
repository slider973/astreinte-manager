# Tableau des tickets

Généré par `scripts/ticket.sh board` le 2026-09-23. Ne pas éditer à la main.

## En cours

| # | Ticket | Prio | Dépend de | PR |
|---|---|---|---|---|
| 061 | [Un nouveau monde visuel, à partir de l'écran de l'admin](in-progress/061-monde-visuel-admin.md) | P1 | 004 016 017 | https://github.com/slider973/astreinte-manager/pull/54 (chantier 061a), https://github.com/slider973/astreinte-manager/pull/55 (chantier 061b), https://github.com/slider973/astreinte-manager/pull/56 (chantier 061c-1) |

## À faire

| # | Ticket | Prio | Dépend de | PR |
|---|---|---|---|---|
| 033 | [Publication sur les stores (à la demande d'une caserne)](backlog/033-stores-ios-android.md) | P2 — ne pas démarrer sans demande explicite d'une caserne | 024 032 |  |
| 036 | [Push natives iOS et Android (à la demande d'une caserne)](backlog/036-push-natives.md) | P2 — ne pas démarrer sans demande explicite d'une caserne | 024 025 |  |
| 055 | [Un refus annonce « ton chef de centre est prévenu » sans preuve](backlog/055-refus-prevenu-sans-preuve.md) | P2 | 050 | — |
| 056 | [L'éditeur sans caserne perd sa destination au démarrage à froid](backlog/056-superadmin-destination-perdue-a-froid.md) | P2 | 045 053 | — |
| 057 | [Le jeton d'appareil des notifications n'est pas branché sur l'oubli](backlog/057-jeton-appareil-hors-oubli.md) | P2 | 024 053 | — |
| 058 | [Lire l'adresse confirmée à la source, pas dans les métadonnées](backlog/058-invitations-en-attente-adresse-confirmee.md) | P2 | 051 | — |
| 063 | [Passer d'une destination à l'autre sans glissement](backlog/063-transition-entre-destinations.md) | P1 | 061 | — |

## Terminés

| # | Ticket | Prio | Dépend de | PR |
|---|---|---|---|---|
| 001 | [Initialiser le projet Flutter et l'architecture](done/001-setup-flutter.md) | P0 |  | https://github.com/slider973/astreinte-manager/pull/1 |
| 002 | [Créer le projet Supabase et les migrations initiales](done/002-supabase-migrations.md) | P0 |  | https://github.com/slider973/astreinte-manager/pull/2 |
| 003 | [Mettre en place la CI](done/003-ci-github-actions.md) | P1 | 001 002 | https://github.com/slider973/astreinte-manager/pull/5 |
| 004 | [Thème et composants de base](done/004-design-system.md) | P1 | 001 | https://github.com/slider973/astreinte-manager/pull/4 |
| 005 | [Connexion par email et code OTP](done/005-auth-otp.md) | P0 | 001 002 | https://github.com/slider973/astreinte-manager/pull/6 |
| 006 | [Invitations et onboarding des membres](done/006-invitations-onboarding.md) | P0 | 005 008 | https://github.com/slider973/astreinte-manager/pull/7 |
| 007 | [Profil utilisateur](done/007-profil.md) | P1 | 005 | https://github.com/slider973/astreinte-manager/pull/30 |
| 008 | [Row Level Security et fonctions d'accès](done/008-rls-multi-tenant.md) | P0 | 002 | https://github.com/slider973/astreinte-manager/pull/3 |
| 009 | [Gestion des membres par l'admin](done/009-gestion-membres.md) | P0 | 006 008 | https://github.com/slider973/astreinte-manager/pull/8 |
| 010 | [Paramètres de la caserne](done/010-parametres-caserne.md) | P1 | 008 | https://github.com/slider973/astreinte-manager/pull/9 |
| 011 | [Grille de saisie des disponibilités](done/011-saisie-dispos-grille.md) | P0 | 004 008 | https://github.com/slider973/astreinte-manager/pull/10 |
| 012 | [Raccourcis de sélection](done/012-raccourcis-selection.md) | P0 | 011 | https://github.com/slider973/astreinte-manager/pull/11 |
| 013 | [Préférences de charge par mois](done/013-preferences-quotas.md) | P0 | 011 | https://github.com/slider973/astreinte-manager/pull/12 |
| 014 | [Périodes, date limite et verrouillage](done/014-periodes-verrouillage.md) | P0 | 008 010 | https://github.com/slider973/astreinte-manager/pull/13 |
| 015 | [Rappels de saisie des disponibilités](done/015-rappels-saisie.md) | P1 | 014 025 | https://github.com/slider973/astreinte-manager/pull/17 |
| 016 | [Matrice des disponibilités pour l'admin](done/016-matrice-admin.md) | P0 | 008 013 014 | https://github.com/slider973/astreinte-manager/pull/18 |
| 017 | [Construction du planning en brouillon](done/017-brouillon-attribution.md) | P0 | 016 | https://github.com/slider973/astreinte-manager/pull/19 |
| 018 | [Proposition automatique de remplissage](done/018-proposition-automatique.md) | P1 | 017 | https://github.com/slider973/astreinte-manager/pull/33 |
| 019 | [Publication et suivi des réponses](done/019-publication-suivi.md) | P0 | 017 025 | https://github.com/slider973/astreinte-manager/pull/20 |
| 020 | [Réattribution d'un créneau refusé ou modifié](done/020-reattribution.md) | P0 | 019 | https://github.com/slider973/astreinte-manager/pull/22 |
| 021 | [Écran des propositions pour le membre](done/021-ecran-propositions.md) | P0 | 008 024 | https://github.com/slider973/astreinte-manager/pull/21 |
| 022 | [Relances automatiques](done/022-relances-auto.md) | P0 | 019 025 | https://github.com/slider973/astreinte-manager/pull/23 |
| 023 | [Vue du planning de la caserne pour les membres](done/023-planning-caserne.md) | P1 | 019 | https://github.com/slider973/astreinte-manager/pull/25 |
| 024 | [Push web via Firebase Cloud Messaging (PWA)](done/024-fcm-setup.md) | P0 | 001 005 | https://github.com/slider973/astreinte-manager/pull/14 |
| 025 | [Edge Function send-notification](done/025-edge-send-notification.md) | P0 | 002 024 | https://github.com/slider973/astreinte-manager/pull/15 |
| 026 | [Centre de notifications in-app](done/026-centre-notifications.md) | P1 | 025 | https://github.com/slider973/astreinte-manager/pull/16 |
| 027 | [Écran Mes astreintes](done/027-mes-astreintes.md) | P0 | 021 | https://github.com/slider973/astreinte-manager/pull/24 |
| 028 | [Export calendrier ICS](done/028-export-ics.md) | P1 | 027 | https://github.com/slider973/astreinte-manager/pull/34 |
| 029 | [Abonnement Stripe par caserne](done/029-stripe-abonnement.md) | P0 | 008 010 | https://github.com/slider973/astreinte-manager/pull/27 |
| 030 | [Mode suspendu et bannières](done/030-gating-suspension.md) | P1 | 029 | https://github.com/slider973/astreinte-manager/pull/28 |
| 031 | [Interface super-admin](done/031-super-admin.md) | P1 | 008 029 | https://github.com/slider973/astreinte-manager/pull/29 |
| 032 | [Build web PWA et déploiement](done/032-web-pwa-deploy.md) | P0 | 001 | https://github.com/slider973/astreinte-manager/pull/35 |
| 034 | [RGPD : export et suppression des données](done/034-rgpd-export.md) | P1 | 007 | https://github.com/slider973/astreinte-manager/pull/31 |
| 035 | [Tests d'intégration bout en bout](done/035-tests-e2e.md) | P1 | 021 020 | https://github.com/slider973/astreinte-manager/pull/32 |
| 037 | [Supprimer la dépendance à fonts.gstatic.com au démarrage](done/037-canvaskit-autoheberge.md) | P1 | 004 032 | https://github.com/slider973/astreinte-manager/pull/38 |
| 038 | [Limiter le débit des invitations](done/038-limite-debit-invitations.md) | P1 | 006 | https://github.com/slider973/astreinte-manager/pull/39 |
| 040 | [Rendre visible une notification définitivement perdue](done/040-ligne-interne-echec-definitif.md) | P0 | 025 026 | https://github.com/slider973/astreinte-manager/pull/26 |
| 041 | [Envoyer les rappels à une heure décente dans chaque fuseau](done/041-heure-locale-rappels.md) | P1 | 015 | https://github.com/slider973/astreinte-manager/pull/40 |
| 042 | [Réduire le coût d'une transition de route](done/042-transition-de-route.md) | P1 | 016 | https://github.com/slider973/astreinte-manager/pull/41 |
| 043 | [Purger réellement les anciennes notifications](done/043-purge-notifications.md) | P0 | 034 | https://github.com/slider973/astreinte-manager/pull/36 |
| 044 | [Archiver réellement les plannings des mois passés](done/044-archivage-plannings.md) | P1 | 019 | https://github.com/slider973/astreinte-manager/pull/37 |
| 045 | [Destination perdue au chargement à froid d'un écran d'administration](done/045-destination-perdue-a-froid.md) | P1 | 024 031 | https://github.com/slider973/astreinte-manager/pull/44 |
| 046 | [Servir les routes sans dièse, pour que la connexion par lien fonctionne](done/046-strategie-url-sans-diese.md) | P0 — bloquant en production | 032 | https://github.com/slider973/astreinte-manager/pull/42 |
| 047 | [Importer les membres d'une caserne depuis un fichier](done/047-import-membres.md) | P0 | 006 009 038 | https://github.com/slider973/astreinte-manager/pull/43 |
| 048 | [Finition de l'écran d'import des membres](done/048-finition-import-membres.md) | P1 | 047 | https://github.com/slider973/astreinte-manager/pull/45 |
| 049 | [Mettre la base et les Edge Functions en ligne avec la PWA](done/049-deploiement-base-et-fonctions.md) | P0 | 032 | https://github.com/slider973/astreinte-manager/pull/46 |
| 050 | [L'écran super-admin annonce un envoi sans preuve](done/050-envoi-annonce-sans-preuve-superadmin.md) | P2 | 048 | https://github.com/slider973/astreinte-manager/pull/49 |
| 051 | [Une invitation en attente reste invisible pour qui vient de se connecter](done/051-invitation-en-attente-ignoree.md) | P1 | 006 | https://github.com/slider973/astreinte-manager/pull/51 |
| 052 | [Le centre de notifications n'a pas de retour](done/052-centre-notifications-sans-retour.md) | P1 | 026 | https://github.com/slider973/astreinte-manager/pull/47 |
| 053 | [L'écran super-admin n'offre aucune déconnexion](done/053-superadmin-sans-deconnexion.md) | P2 | 031 | https://github.com/slider973/astreinte-manager/pull/50 |
| 054 | [Le déploiement automatique des fonctions ignore la carte d'imports](done/054-deploiement-fonctions-carte-imports.md) | P0 | 049 | https://github.com/slider973/astreinte-manager/pull/48 |
| 060 | [Mettre la PWA en ligne par l'API Vercel, avec le jeton de projet](done/060-deploiement-pwa-par-api.md) | P0 | 054 | https://github.com/slider973/astreinte-manager/pull/52 |
| 062 | [La vérification de la PWA vise un alias protégé au lieu du domaine](done/062-verification-pwa-sur-le-domaine.md) | P0 | 060 | https://github.com/slider973/astreinte-manager/pull/53 |

