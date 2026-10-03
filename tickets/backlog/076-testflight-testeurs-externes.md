# 076 — Ouvrir l'app iOS à des testeurs externes par TestFlight

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 067, 071
- **Branche** : `feat/076-testflight-testeurs-externes`
- **PR** : —
- **Statut** : à faire

## Contexte

Demande du propriétaire le 3 octobre 2026 : faire tester l'app iOS **Astreinte SP** (submodule
`foco/`, fork privé `slider973/Foco`) par des personnes extérieures à son compte Apple. Aujourd'hui,
seul le groupe interne « Équipe » reçoit les builds (ticket 067, dernier build retenu 1.0 (106)).

Un testeur externe passe par la **revue bêta d'Apple** (première build de chaque version), qui
exige des informations de test et **un accès de démonstration** quand l'app demande une connexion.
Or la connexion se fait par **code à 6 chiffres envoyé par courriel** : un relecteur d'Apple ne
peut pas le recevoir. C'est le seul vrai obstacle.

## Décisions (recommandations, 3 octobre 2026)

1. **Caserne de démonstration** dédiée en production, « CIS Démonstration », peuplée de données
   fictives (membres, mois ouvert, planning publié, propositions), avec un abonnement qui ne
   s'éteint pas. Le relecteur n'approche jamais une vraie caserne.
2. **Connexion de revue** : un seul compte, l'adresse de démonstration, peut se connecter par
   **mot de passe**. L'écran de connexion iOS n'affiche le champ mot de passe que lorsque cette
   adresse exacte est saisie (configurée dans `Config.xcconfig`, pas en dur) ; toute autre adresse
   garde le code par courriel. Le mot de passe est rangé dans 1Password (coffre Static Flow,
   « Astreinte SP — compte de revue Apple ») et **saisi par le propriétaire** dans App Store
   Connect ; aucun agent ne le transmet à Apple.
3. **Distribution par lien public** TestFlight (plafond réglable, 100 au départ), plus les
   invitations par courriel au besoin. Retours des testeurs activés.

## À faire

1. **Base** (`supabase-dev`) : script rejouable (pas une migration, ce sont des données)
   `supabase/scripts/caserne_demo.sql` qui crée ou remet à zéro la caserne de démonstration et son
   compte de revue (rôle membre **et** une seconde adresse admin si utile), données fictives
   seulement ; abonnement `active` sans date de fin ; règles RLS inchangées. Le mot de passe du
   compte de revue est posé par l'API d'administration Auth depuis 1Password, jamais écrit dans le
   dépôt. Documenter dans `docs/IOS.md`.
2. **iOS** (fork) : sur l'écran de connexion, adresse égale à `FOCO_REVIEW_EMAIL` → champ mot de
   passe et `signInWithPassword` ; sinon rien ne change. Tests de store (adresse de revue → mot de
   passe ; toute autre adresse → code ; adresse vide de config → jamais de mot de passe). Écart au
   contrat PWA (appel Auth `password`) consigné dans `docs/IOS.md`, avec sa raison.
3. **App Store Connect par l'API** (clé Admin, 1Password) : script du fork
   `scripts/testflight-externe.py`, idempotent :
   - groupe externe « Testeurs externes », lien public activé, plafond 100, retours activés ;
   - informations de test `fr-FR` : description, adresse de retour
     `jonathan.lemaine78@gmail.com`, politique de confidentialité
     `https://astreinte.staticflow.ch/legal/confidentialite` ;
   - détails de revue bêta : contact du propriétaire, « connexion requise » cochée, notes en
     anglais expliquant la connexion de revue — **le nom d'utilisateur et le mot de passe sont
     laissés au propriétaire** ;
   - ajout du dernier build au groupe et soumission à la revue bêta.
   Option `externe=true` du workflow `testflight.yml` pour ajouter automatiquement les builds
   suivants au groupe externe.
4. **Docs** : `docs/IOS.md` § 10 (testeurs externes, revue bêta, lien public, ce qui reste manuel).

## Critères d'acceptation

- La caserne de démonstration existe en production, sans aucune donnée réelle ; le script la
  remet à zéro sans toucher aux autres casernes.
- Sur l'app, l'adresse de revue + mot de passe ouvre la caserne de démonstration ; toute autre
  adresse passe par le code ; tests verts dans la CI du fork, zéro avertissement Swift.
- Un build (≥ 107) est publié, ajouté au groupe externe et soumis à la revue bêta ; le lien
  public est donné au propriétaire.
- Aucun secret dans le dépôt ni dans les journaux CI ; toutes les commandes de CI rejouées avant
  chaque push (règle du propriétaire).

## Hors périmètre

- La publication sur l'App Store (ticket 033).
- La connexion par mot de passe pour tout le monde.
