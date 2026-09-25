# 066 — L'app iOS native Foco, branchée sur la même base que la PWA

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 064, 065
- **Branche** : `feat/066-app-ios-native`
- **PR** : —
- **Statut** : en cours depuis 2026-09-26

## Contexte

Demandé par le propriétaire le 26 septembre 2026. Une app iOS native existe : **Foco**, SwiftUI,
iOS 26.4, environ 7 000 lignes, forkée en `slider973/Foco` depuis `T4ruxx/Foco`. Elle couvre le
parcours du pompier — disponibilités (grille jour / nuit, appui long puis glissement, raccourcis,
préférences de charge, date limite), propositions (accepter, refuser avec motif), mes astreintes
(par mois, export `.ics`), planning de la caserne (mois, semaine, trois jours), notifications — plus
trois extras : échanges d'astreinte, contrôles matériel, discussion d'équipe.

**Elle n'a aucun backend** : toutes ses données sont des données de démo en mémoire (`DemoData`,
un `AppStore` `@Observable`). Son modèle recoupe déjà le schéma presque à l'identique :
`Shift` jour / nuit et effectif requis, `Planning` draft / published / validated / archived,
`Assignment` proposed / accepted / refused / replaced / cancelled, disponibilité available /
absent, préférences de charge par mois.

L'objectif du propriétaire : **garder l'app Flutter telle quelle** (PWA et admin), ajouter Foco en
**submodule**, la **brancher sur le Supabase existant** et l'adapter pour qu'elle **fonctionne
pareil que la PWA sur la partie utilisateur**.

Cette demande lève une règle écrite : `CLAUDE.md` (« Canal principal : la PWA ») et `docs/PRD.md
§ 4.3` réservaient les builds iOS à la demande d'une caserne. Ces deux documents sont mis à jour
dans ce ticket : la PWA reste le produit et le seul canal de l'admin ; l'app iOS native devient un
second client du pompier.

## Décisions

1. **Submodule** `ios/` pointant sur `slider973/Foco`, branche `main`. Le code Swift vit et se
   commite dans le fork ; `astreinte-manager` ne commite que le pointeur. `scripts/ticket.sh` et la
   CI savent qu'un submodule existe (`git submodule update --init`).
2. **Même base, même contrat.** `supabase-swift` par Swift Package Manager, clé publique seulement
   (jamais la clé service), URL et clé lues d'un `.xcconfig` non commité avec un exemple commité
   (`env/` a le même rôle côté Flutter). Mêmes tables, mêmes RLS, **mêmes fonctions RPC que
   l'app Flutter** : aucune requête que la PWA ne fait pas, aucune colonne absente de
   `docs/SCHEMA.md`. Si l'app iOS a besoin d'une lecture que la PWA n'a pas, elle passe par un
   ticket `supabase-dev`, pas par un contournement.
3. **Une couche de données derrière un protocole** : `DemoData` reste pour les aperçus SwiftUI
   et les captures, une implémentation Supabase sert l'app ; l'`AppStore` ne sait pas laquelle il
   a. Le temps réel suit ce que la PWA écoute (propositions, notifications).
4. **Connexion par code à six chiffres** reçu par courriel, comme la PWA (même modèle de mail
   Resend). Le sélecteur de caserne de l'écran de connexion disparaît : la caserne vient de
   l'appartenance ; plusieurs appartenances → choix après connexion, comme la PWA.
5. **Parité du parcours pompier, écran par écran**, avec les règles métier de la PWA : période
   ouverte / verrouillée et date limite depuis `periods`, planning visible seulement publié,
   réponse aux propositions par la même fonction, quotas et commentaire du mois dans
   `availability_preferences`, export ICS par le même lien d'abonnement que la PWA.
6. **Les extras hors schéma sont masqués**, pas supprimés : échanges d'astreinte (v1.1 du PRD),
   contrôles matériel et discussion d'équipe (hors périmètre) passent derrière un drapeau de
   compilation désactivé. On n'invente aucune table pour eux.
7. **L'admin reste dans la PWA.** Un admin connecté sur iOS voit son parcours pompier, et un lien
   « Gérer la caserne » qui ouvre la PWA dans Safari.
8. **Le design de Foco est conservé** (sa palette, sa pile de cartes, ses écrans de connexion) :
   c'est la parité **fonctionnelle** qui est demandée, pas la copie de la PWA. Les règles
   binding restent : cibles 44 pt, aucun état porté par la couleur seule, textes en français.
9. **Notifications push** : Firebase Messaging iOS, jeton enregistré dans `push_tokens` avec la
   plateforme iOS ; l'Edge Function d'envoi FCM existante sert les deux clients. Les liens des
   notifications ouvrent le bon écran natif (mêmes chemins que `docs/WORKFLOWS.md § 8`). La
   configuration Firebase et la clé APNs restent à la charge du propriétaire (`docs/FIREBASE.md`).
10. **Règle des caches locaux** : tout ce que l'app écrit sur l'appareil (Keychain, UserDefaults,
    fichiers) disparaît à la déconnexion, et une appartenance restaurée revient en simple membre,
    comme `lib/core/session/deconnexion.dart`.
11. **CI** : une tâche macOS construit et teste l'app iOS **seulement quand `ios/` change**
    (`xcodebuild build test` sur un simulateur) ; la CI Flutter ne change pas.

## Chantiers

- **066a** — submodule, `supabase-swift`, configuration, couche de données derrière protocole,
  connexion par code, appartenance, déconnexion qui vide tout ; extras masqués ; CI macOS.
- **066b** — disponibilités et préférences de charge sur les vraies données (périodes, date
  limite, verrouillage, raccourcis, copie du mois précédent).
- **066c** — propositions (réponse, motif), mes astreintes, export ICS, planning de la caserne
  publié, accueil.
- **066d** — notifications : centre in-app, push FCM, liens profonds ; `CLAUDE.md`, `PRD`,
  `WORKFLOWS` à jour ; passe de fini.

## Critères d'acceptation

- `ios/` est un submodule de `slider973/Foco` ; un clone neuf avec `--recurse-submodules`
  construit les deux apps.
- Un pompier se connecte sur iOS avec le code reçu par courriel et retrouve exactement ce que la
  PWA lui montre : mêmes disponibilités, mêmes propositions, mêmes astreintes, même planning.
  Une saisie faite sur iOS apparaît dans la PWA et inversement.
- Aucune clé service ni secret dans le dépôt ni dans le binaire ; aucune requête hors du contrat
  de la PWA.
- La déconnexion vide tout ce que l'app a écrit sur l'appareil.
- Les extras hors schéma sont invisibles dans le build livré.
- La tâche iOS de la CI est verte ; `flutter analyze`, `flutter test` et le déploiement de la PWA
  ne changent pas.
- Vérifié par le propriétaire sur son iPhone 17 Pro Max via un build de développement ou
  TestFlight.
