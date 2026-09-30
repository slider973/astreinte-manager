# 074 — Aucune notification push n'arrive sur la PWA

- **Épopée** : E6 Notifications
- **Priorité** : P0
- **Dépend de** : 070
- **Branche** : `feat/074-push-web-portee-service-worker`
- **PR** : —
- **Statut** : terminé le 2026-09-30 (PR créée)

## Contexte

Signalé par le propriétaire le 29 septembre 2026 : aucune notification push sur la PWA. En
production, `push_tokens` ne contient aucun jeton `web` ; le seul appel `register_push_token` des
trois derniers jours vient de l'app iOS native.

Diagnostic du 30 septembre (reproduit sur la production avec Chrome headless, sans compte) :

1. **Deux service workers sur la même portée `/`.** `messagerie_push.dart:64-67` passe
   `firebase-messaging-sw.js?apiKey=…` à `getToken(serviceWorkerScriptPath:)` ;
   `firebase_messaging_web-4.2.5/lib/src/interop/messaging.dart:51-52` l'enregistre sans portée,
   donc sur `/`, déjà tenue par `flutter_service_worker.js` (qui fait `skipWaiting()`). Le jeton
   s'obtient (142 caractères, configuration de prod valide), mais le worker Firebase reste en
   attente : un push envoyé arrive au worker Flutter, qui n'a pas de gestionnaire `push`, et se
   perd. Le même script sur une portée dédiée reçoit le push et le relaie à la page. Rien à
   corriger dans la console Firebase.
2. **Worker Firebase sans paramètres à la déconnexion.** `OubliLocal.tout()`
   (`oubli_local.dart:71`) → `oublierJeton()` → `deleteToken()` : sans `getToken` préalable, le SDK
   JS enregistre `/firebase-messaging-sw.js` sans configuration. Inerte, mais du bruit.
3. **Pas de jeton en base** : le propriétaire utilise Safari iPhone sans avoir installé la PWA
   (état `installationRequise`, bouton « Activer » masqué par construction), et l'étape d'accueil
   des notifications a pu être marquée vue quand Firebase n'était pas configuré
   (`parcours_accueil.dart:75-82`).
4. **Échecs invisibles** : les erreurs de `jeton()` et de `publier()` ne sont journalisées qu'en
   debug.

## À faire

1. Déplacer le service worker dans `web/push/firebase-messaging-sw.js` (portée `/push/`) ;
   `messagerie_push.dart:65` → `push/firebase-messaging-sw.js` (relatif au base href) ; dans le
   worker, `PORTEE = new URL('../', self.location).pathname` pour les icônes et `adresseInterne` ;
   `vercel.json` : en-têtes du nouveau chemin. Garder `web/firebase-messaging-sw.js` le temps d'une
   version, réduit à un worker qui se désinscrit lui-même, pour nettoyer les navigateurs déjà
   passés.
2. Déconnexion : `deleteToken()` seulement si la permission est accordée et qu'un jeton est connu ;
   désabonnement local toujours ; désinscrire les registrations Firebase restées sur `/` ou sur
   `/firebase-cloud-messaging-push-scope` sans paramètres.
3. Démarrage : si la registration `/` porte un worker Firebase en attente ou un abonnement push,
   le désabonner ; le prochain `getToken` le recrée sur `/push/`.
4. Journaliser en release l'échec de `jeton()` et de l'enregistrement (`console.warn`, sans le
   jeton).
5. L'étape d'accueil « Reçois les propositions » n'est pas marquée vue quand l'état est
   `nonConfigure` ; elle revient quand Firebase est branché.
6. Docs : `docs/FIREBASE.md`, `docs/DEPLOIEMENT.md`, `supabase/functions/README.md`, commentaires
   de `_shared/fcm.ts`. Dans `docs/FIREBASE.md`, le mode d'emploi iPhone : installer la PWA,
   l'ouvrir depuis l'icône, Profil → Notifications → Activer.

## Critères d'acceptation

- Test Dart : le chemin du worker commence par `push/`, sans `/` initial, avec les quatre
  paramètres.
- Test de `desenregistrer()` avec un faux `MessageriePush` : pas d'appel au SDK sans permission ni
  jeton ; appel sinon.
- Test du worker (Node ou Deno) avec `self.location` sous `/push/` : `adresseInterne('/proposals')`
  vise la racine, l'icône aussi, un lien externe retombe sur l'accueil.
- Test Playwright (CI, contre la PWA construite et servie en local) : permission accordée, worker
  enregistré sur une portée différente de `/` et **actif**, push livré par CDP reçu par la page
  (`isFirebaseMessaging`).
- `flutter analyze`, `flutter test`, `flutter build web` et le parcours verts ; toutes les
  commandes des jobs de la CI rejouées en local avant le push.
- Après déploiement, sur Chrome desktop : Profil → Activer → un jeton `web` apparaît dans
  `push_tokens`, et une proposition envoyée affiche une notification.

## Hors périmètre

- L'app iOS native (déjà branchée sur APNs).
- Le temps réel sur de nouvelles tables.
