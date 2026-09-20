# Firebase — ce qu'il faut créer pour que les notifications marchent

Ce document s'adresse au **propriétaire du projet**, pas au développeur. Il ne suppose aucune
connaissance du code. Suis-le dans l'ordre : il y a cinq valeurs à récupérer et à recopier dans un
fichier, et une vérification à la fin.

**Rien n'est cassé tant que ce n'est pas fait.** L'application fonctionne déjà sans Firebase : elle
s'ouvre, la saisie des disponibilités et le planning marchent, et l'écran « Profil » affiche
simplement « Notifications indisponibles sur cette installation ». Ce qui manque, ce sont les
alertes sur le téléphone — donc le fait qu'un pompier apprenne qu'on lui propose une astreinte sans
avoir à ouvrir l'application.

Compte à prévoir : **30 minutes**, un compte Google, aucune carte bancaire. Le plan gratuit
(« Spark ») suffit : Cloud Messaging n'est pas facturé.

---

## 1. Créer le projet Firebase

1. Va sur <https://console.firebase.google.com> et connecte-toi avec un compte Google.
   Utilise un compte **de la structure**, pas un compte personnel : il faudra le transmettre un
   jour.
2. Clique **« Créer un projet »**.
3. Nom du projet : `astreinte-sp` (ou `astreinte-sp-prod` si tu prévois un projet séparé pour les
   essais — voir § 7).
4. Google Analytics : **désactive-le**. L'application n'en fait rien et c'est une déclaration RGPD
   de moins.
5. Attends la création, puis **« Continuer »**.

## 2. Enregistrer l'application web

C'est l'étape qui produit quatre des cinq valeurs.

1. Sur la page d'accueil du projet, sous « Commencez par ajouter Firebase à votre application »,
   clique sur l'icône **`</>`** (« Web »). Pas iOS, pas Android : l'application est une PWA.
2. Pseudo de l'application : `Astreinte SP (PWA)`.
3. **Ne coche pas** « Configurer Firebase Hosting » : l'hébergement du site est ailleurs
   (ticket 032).
4. Clique **« Enregistrer l'application »**.
5. Firebase affiche un bloc de code qui ressemble à ceci :

```js
const firebaseConfig = {
  apiKey: "AIzaSyD-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  authDomain: "astreinte-sp.firebaseapp.com",
  projectId: "astreinte-sp",
  storageBucket: "astreinte-sp.appspot.com",
  messagingSenderId: "123456789012",
  appId: "1:123456789012:web:abcdef0123456789abcdef"
};
```

**Recopie quatre lignes** quelque part : `apiKey`, `projectId`, `messagingSenderId`, `appId`.
Ignore `authDomain` et `storageBucket` : l'application ne s'en sert pas (l'authentification passe
par Supabase).

> Ces valeurs **ne sont pas des secrets**. Firebase les publie dans le code de n'importe quel site
> web qui l'utilise ; elles identifient le projet, elles n'autorisent rien. Le droit d'*envoyer*
> une notification tient à une autre clé, qui vit côté serveur (§ 5).

Si tu as fermé la page : **roue dentée** en haut à gauche → **Paramètres du projet** → onglet
**Général** → section « Vos applications » → ton application web. Le bloc y est toujours.

## 3. Récupérer la clé VAPID (cinquième valeur)

C'est la clé qui autorise le navigateur à recevoir des notifications pour ce site.

1. **Roue dentée** → **Paramètres du projet** → onglet **Cloud Messaging**.
2. Descends jusqu'à **« Configuration Web »** → **« Certificats push Web »**.
3. S'il n'y a aucune paire de clés, clique **« Générer une paire de clés »**.
4. Copie la valeur affichée dans la colonne **« Paire de clés »**. C'est une longue chaîne qui
   commence en général par `B` et fait une centaine de caractères.

C'est la cinquième valeur : `FIREBASE_VAPID_KEY`.

> Si l'onglet Cloud Messaging affiche « L'API Cloud Messaging (V1) est désactivée », clique sur le
> lien **« Gérer l'API dans la console Google Cloud »** et active **Firebase Cloud Messaging API
> (V1)**. Reviens ensuite sur cette page.

## 4. Mettre les cinq valeurs dans l'application

Les valeurs ne s'écrivent **jamais** dans le code : elles sont fournies au moment de la
compilation, exactement comme celles de Supabase.

1. Dans le dossier du projet, ouvre `env/`.
2. Copie `prod.json.example` en `prod.json` (ce fichier n'est jamais envoyé sur GitHub :
   il est dans `.gitignore`).
3. Remplis-le :

```json
{
  "APP_ENV": "prod",
  "SUPABASE_URL": "https://xxxxxxxx.supabase.co",
  "SUPABASE_ANON_KEY": "…",
  "FIREBASE_PROJECT_ID": "astreinte-sp",
  "FIREBASE_API_KEY": "AIzaSyD-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "FIREBASE_APP_ID": "1:123456789012:web:abcdef0123456789abcdef",
  "FIREBASE_MESSAGING_SENDER_ID": "123456789012",
  "FIREBASE_VAPID_KEY": "BPxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx…"
}
```

Correspondance avec ce que Firebase affiche :

| Dans `prod.json` | Dans Firebase |
|---|---|
| `FIREBASE_PROJECT_ID` | `projectId` du bloc de code (§ 2) |
| `FIREBASE_API_KEY` | `apiKey` du bloc de code (§ 2) |
| `FIREBASE_APP_ID` | `appId` du bloc de code (§ 2) |
| `FIREBASE_MESSAGING_SENDER_ID` | `messagingSenderId` du bloc de code (§ 2) |
| `FIREBASE_VAPID_KEY` | « Certificats push Web » → paire de clés (§ 3) |

**Les cinq vont ensemble.** Si une seule manque ou est vide, l'application considère qu'il n'y a
pas de Firebase du tout et désactive les notifications — c'est volontaire : mieux vaut une
fonctionnalité annoncée comme absente qu'une fonctionnalité qui échoue en silence.

4. Reconstruis le site :

```sh
flutter build web --release --dart-define-from-file=env/prod.json
```

Pour essayer en local avant de publier :

```sh
flutter run -d chrome --dart-define-from-file=env/prod.json
```

> **Les notifications ne marchent qu'en HTTPS**, ou sur `localhost`. Un site servi en `http://`
> depuis une adresse IP ne recevra jamais rien : c'est une règle des navigateurs, pas un réglage.

## 5. La clé d'envoi (côté serveur, à faire une fois aussi)

Les cinq valeurs ci-dessus permettent à un téléphone de **recevoir**. Pour que le serveur puisse
**envoyer**, il faut un compte de service. Cette clé-là est un vrai secret.

1. **Roue dentée** → **Paramètres du projet** → onglet **Comptes de service**.
2. Clique **« Générer une nouvelle clé privée »**, puis confirme. Un fichier `.json` se télécharge.
3. **Ne le mets jamais dans le dépôt.** Il se dépose dans les secrets Supabase :

```sh
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat chemin/vers/le-fichier.json)"
```

C'est l'Edge Function `send-notification` qui s'en sert. Elle existe depuis le ticket 025, et elle
**fonctionne sans cette clé** : tant qu'elle est absente, le push est déclaré indisponible, la
notification reste lisible dans l'application et part par courriel. Aucun jeton d'appareil n'est
perdu. Poser cette clé, c'est donc allumer les alertes sur les téléphones, pas réparer quelque
chose de cassé.

## 6. Vérifier que ça marche

Trois vérifications, de la plus simple à la plus proche du terrain.

### a. Sur un ordinateur, en 2 minutes

1. Ouvre le site dans **Chrome**.
2. Connecte-toi. Si c'est un compte tout neuf, l'accueil te propose, à la fin, **« Reçois les
   propositions »** → clique **« Activer les notifications »** et accepte dans la fenêtre du
   navigateur. Si le compte existe déjà, va dans l'onglet **Profil** : le bloc « Notifications »
   porte un bouton « Activer les notifications ».
3. Le bloc « Notifications » du Profil doit afficher **« Activées sur cet appareil »**.
4. Dans Supabase (**Table Editor** → `push_tokens`), une ligne doit être apparue, avec ton
   `user_id`, `platform = web` et un `device_label` du genre « Mac · Chrome ».
5. Dans Firebase : menu de gauche → **Engagement** → **Messaging** → **« Créer votre première
   campagne »** → **« Messages Firebase Notifications »** → **« Envoyer un message de test »**.
   Colle le contenu de la colonne `token` de la ligne Supabase, puis **« Tester »**.
6. La notification doit apparaître. **Onglet au premier plan** : un bandeau bleu en haut de
   l'application. **Onglet en arrière-plan ou fermé** : une notification du système.

### b. Sur Android, avec la PWA installée

Même chose, en ouvrant le site dans Chrome sur le téléphone, puis menu **⋮** → **« Installer
l'application »**. Lance ensuite l'application depuis l'écran d'accueil et refais les étapes 2 à 6.
Une seconde ligne apparaît dans `push_tokens`, avec le modèle du téléphone.

### c. Sur iPhone — la vérification qui compte

**Sur iPhone, une page ouverte dans Safari ne reçoit jamais de notification.** Il faut que
l'application soit sur l'écran d'accueil, et iOS 16.4 au minimum.

1. Ouvre le site dans **Safari** (pas Chrome : sur iPhone, seul Safari sait installer).
2. Bouton **Partager** → **« Sur l'écran d'accueil »** → **« Ajouter »**.
3. **Ferme Safari** et lance l'application depuis l'icône de l'écran d'accueil.
4. Onglet **Profil** → « Notifications » → **« Activer les notifications »** → accepte.
5. Refais l'envoi de test du § 6.a.

Si tu tentes l'étape 4 **sans** avoir installé l'application, l'écran affiche « Ajoute
l'application à ton écran d'accueil pour les recevoir » et ne propose aucun bouton. C'est voulu :
une autorisation refusée sur iPhone ne se redemande pas.

## 7. Deux projets, ou un seul ?

Un seul projet Firebase suffit pour démarrer. Si tu veux séparer les essais de la production, crée
un second projet (`astreinte-sp-dev`), refais les § 1 à 3, et mets ses valeurs dans `env/dev.json`
au lieu de `prod.json`. Rien d'autre ne change : c'est la même application, compilée avec un
fichier différent.

## 8. Questions qui reviennent

**« Est-ce que ça coûte quelque chose ? »** Non. Cloud Messaging est gratuit et sans quota
pratique. Aucune carte n'est demandée sur le plan Spark.

**« Est-ce que Google voit les données de la caserne ? »** Non. Les notifications ne transportent
qu'un titre, une phrase et une destination (« /proposals »). Les disponibilités, les noms et les
plannings restent dans Supabase. Le contenu des notifications est écrit par l'Edge Function
(ticket 025) : une date, un créneau, le nom de la caserne. Ni donnée de santé, ni adresse.

**« J'ai refusé les notifications par erreur, comment revenir en arrière ? »** L'application ne
peut pas redemander : c'est le navigateur qui décide. Sur Chrome, clique sur le cadenas à gauche de
l'adresse → « Notifications » → « Autoriser ». Sur iPhone, Réglages → Notifications → l'application
installée.

**« Faut-il refaire quelque chose quand on change d'hébergement ? »** Non, sauf si le domaine
change : les autorisations de notification sont attachées au domaine, et chaque pompier devra
réactiver depuis son profil.

## Mettre à jour le SDK

Le fichier `web/firebase-messaging-sw.js` charge le SDK JavaScript de Firebase depuis Google, à une
version écrite en dur (`VERSION_SDK`). Elle doit rester **identique** à celle qu'attend le paquet
Flutter `firebase_core_web` (constante `supportedFirebaseJsSdkVersion`). Après un
`flutter pub upgrade` qui touche `firebase_core_web`, vérifier les deux et les réaligner, sinon
l'enregistrement du jeton échoue en arrière-plan sans message clair.

## Où vivent les choses, pour le développeur

| Quoi | Où |
|---|---|
| Les cinq variables | `env/prod.json`, lues par `lib/core/env.dart` |
| L'initialisation, qui ne lève jamais | `lib/core/firebase/firebase_bootstrap.dart` |
| L'état des notifications, fonction pure | `lib/features/notifications/domain/etat_notifications.dart` |
| Le service worker, configuré par son URL | `web/firebase-messaging-sw.js` |
| Les destinations des liens | `lib/features/notifications/domain/destination_push.dart` et `docs/WORKFLOWS.md § 8` |
| La table des jetons | `docs/SCHEMA.md § 2.11` |
| L'envoi côté serveur | `supabase/functions/send-notification/`, contrat dans `supabase/functions/README.md` |
