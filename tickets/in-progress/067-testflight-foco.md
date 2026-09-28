# 067 — Distribuer l'app iOS Foco par TestFlight, depuis la CI du fork

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 066
- **Branche** : `feat/067-testflight-foco`
- **PR** : —
- **Statut** : en cours depuis 2026-09-28

## Contexte

L'app iOS native Foco (ticket 066) compile et se teste dans la CI du fork privé `slider973/Foco`
(runner `macos-26`, Xcode 26.4), mais personne ne peut encore l'installer : il n'existe ni
identifiant d'app à nous, ni fiche App Store Connect, ni build signé. Le Mac du propriétaire est
en Xcode 16.2 et ne peut pas archiver une app iOS 26.

Décisions du propriétaire, le 28 septembre 2026 :

1. **Compte Apple : le compte Apple Developer personnel du propriétaire**, pas l'équipe
   NOCHE APP Sarl utilisée par Noche. Le vendeur affiché sur l'App Store sera donc le propriétaire.
   Le projet porte encore l'équipe et l'identifiant de l'auteur de Foco (`7LTN3MGW4H`,
   `com.mazestudio.foco`) : ils sont remplacés.
2. **CI : GitHub Actions dans le fork**, là où Foco compile déjà. Pas de Codemagic.
3. **Nom : Astreinte SP**, comme la PWA. Le nom affiché sous l'icône (`CFBundleDisplayName`), le nom de la fiche App Store Connect et TestFlight, et tout texte de l'app qui dit « Foco » deviennent « Astreinte SP ». « Foco » ne reste que comme nom interne du projet Xcode, du dépôt et du submodule.

Modèle éprouvé à reprendre : `noche-monorepo` publie sur TestFlight avec fastlane
(`gym` puis `upload_to_testflight`) et une clé API App Store Connect lue depuis des secrets
GitHub (`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`,
`APP_STORE_CONNECT_API_KEY`). Ici, la signature est **automatique** par la clé API
(`xcodebuild -allowProvisioningUpdates` avec `-authenticationKeyPath`) : aucun certificat ni profil
exporté à la main.

## À faire

**Avec le propriétaire, dans Chrome (il se connecte lui-même, double authentification comprise ;
aucun mot de passe n'est saisi par l'agent) :**
- developer.apple.com : identifiant d'app (bundle ID, par exemple `ch.staticflow.astreintesp`), capacité
  Push Notifications, clé APNs `.p8` pour Firebase.
- App Store Connect : fiche de l'app, informations TestFlight (description du test, contact,
  conformité export : chiffrement standard), groupe de testeurs internes avec le propriétaire, clé
  API App Store Connect (rôle App Manager) pour la CI.
- Console Firebase : app iOS ajoutée au projet, clé APNs importée, `GoogleService-Info.plist`.

**Par le propriétaire, en ligne de commande (les fichiers secrets ne passent jamais par l'agent) :**
- `gh secret set … -R slider973/Foco` pour la clé API App Store Connect, son identifiant,
  l'identifiant de l'émetteur, le `Config.xcconfig` de production (clé anon seulement) et le
  `GoogleService-Info.plist`.

**Dans le fork (code) :**
- Équipe et identifiant de bundle remplacés dans le projet et dans `scripts/ci.sh`.
- Nom affiché `Astreinte SP` et textes de l'app qui citaient « Foco » (écran de démarrage, connexion, réglages, notifications, `FocoStrings`). Icône de l'app : celle de la PWA (`design/assets/icone.svg`, fond plein sans transparence et sans coins arrondis, comme l'exige iOS), déclinée en 1024 × 1024 pour les variantes claire, sombre et teintée d'iOS 26, à la place de l'icône Foco ; l'écran de démarrage suit.
- Workflow `.github/workflows/testflight.yml` sur `macos-26`, lancé à la main
  (`workflow_dispatch`) : configuration de production depuis les secrets, numéro de build
  incrémenté (numéro de la course ou dernier numéro TestFlight + 1), archive signée
  automatiquement par la clé API, envoi à TestFlight, groupe interne notifié. Aucun secret écrit
  dans le dépôt ni dans les journaux.
- `docs/IOS.md` : la procédure de publication et la liste des secrets attendus.

## Critères d'acceptation

- Un lancement du workflow `testflight.yml` produit un build visible dans TestFlight, installable
  sur l'iPhone 17 Pro Max du propriétaire.
- L'app installée se connecte par code à la base de production, et un push de test arrive avec le
  son.
- Aucun secret dans le dépôt, le fork ou les journaux de CI ; la CI `iOS` du fork reste verte.
- L'app s'affiche « Astreinte SP » sous son icône, dans TestFlight et dans ses écrans ; aucun « Foco » visible par l'utilisateur.
- L'icône de l'app est celle de la PWA.
- `docs/IOS.md` décrit comment publier une nouvelle version.
