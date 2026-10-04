# 077 — Servir l'app sur app.astreinte-sp.fr

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 075
- **Branche** : `feat/077-app-sur-app-astreinte-sp-fr`
- **PR** : —
- **Statut** : à faire

## Contexte

Demande du propriétaire le 4 octobre 2026 : l'app (PWA) doit répondre sur
`https://app.astreinte-sp.fr` au lieu de `https://astreinte.staticflow.ch`, pour être cohérente
avec le site vitrine `astreinte-sp.fr` (ticket 075). Le domaine `astreinte-sp.fr` est chez OVH,
déjà branché sur Vercel pour le site.

Occurrences de l'ancienne adresse relevées le 4 octobre (hors tickets terminés) :
`supabase/config.toml` (l. 573-578 : `site_url`, `additional_redirect_urls`), le secret Supabase
`APP_BASE_URL` (Stripe, liens des notifications et des courriels), `docs/DEPLOIEMENT.md`,
`docs/IOS.md`, `design/075-site-vitrine.md`, `site/public/*.html` (liens « Se connecter »),
et dans le fork iOS `foco/` : `Config/Foco.xcconfig` (`FOCO_PWA_URL`), `Config.example.xcconfig`,
`Foco/Core/FocoConfig.swift:25`, deux tests, `scripts/testflight-externe.py` (adresse de la
politique de confidentialité donnée à TestFlight). `scripts/deployer_pwa.py` lit le domaine de
production dans `supabase/config.toml`.

## À faire

1. **Vérifier avant d'agir** : l'inventaire complet (`grep` dépôt et fork, secrets Supabase et
   GitHub, réglages Auth en production, URL de retour Stripe, flux ICS déjà abonnés, liens déjà
   envoyés dans des courriels) ; rien n'est affirmé sans preuve dans le rapport.
2. **Vercel** : ajouter `app.astreinte-sp.fr` au projet `astreinte-manager` (domaine de
   production) ; `astreinte.staticflow.ch` **reste servi** et redirige en 308 vers la même route
   sur la nouvelle adresse, chemin et paramètres conservés — **sauf** les chemins qui ne doivent pas
   changer d'origine sans précaution (flux ICS, liens d'invitation et de connexion déjà envoyés :
   vérifier qu'une redirection les garde fonctionnels, sinon les servir tels quels).
3. **DNS OVH** : un `CNAME` `app` → la cible donnée par Vercel ; enregistrement à donner au
   propriétaire (pas d'accès API OVH).
4. **Supabase** : `site_url` et `additional_redirect_urls` (garder l'ancienne adresse dans les
   redirections le temps de la transition), `APP_BASE_URL` ; déployé par le workflow habituel.
5. **Code et docs** : PWA (aucune adresse en dur attendue — vérifier), site vitrine (liens « Se
   connecter » / « Déjà inscrit »), `scripts/verifier_production.sh`, `docs/DEPLOIEMENT.md`,
   `docs/IOS.md`, CLAUDE.md si besoin.
6. **iOS** (fork) : `FOCO_PWA_URL`, défaut de `FocoConfig.swift`, tests, script TestFlight
   (politique de confidentialité) ; CI du fork verte, pointeur à jour.
7. **Transition des utilisateurs déjà installés** : la session, les abonnements push et le
   stockage local sont liés à l'origine. Mesurer ce qui se passe réellement (Chrome, PWA
   installée) et prévoir le message montré sur l'ancienne adresse : se reconnecter, réactiver les
   notifications, réinstaller l'icône si nécessaire. Les jetons push web de l'ancienne origine
   deviennent inutiles : les laisser expirer (la file les supprime au premier rejet FCM).

## Critères d'acceptation

- `https://app.astreinte-sp.fr` sert la PWA (200, en-têtes COOP/COEP, service workers dont
  `/push/`), `scripts/verifier_production.sh` vert sur la nouvelle adresse.
- `https://astreinte.staticflow.ch/<chemin>?<requête>` redirige vers la même route sur la
  nouvelle adresse (ou est servi tel quel pour les chemins listés au point 2), vérifié par `curl`.
- Connexion par code de bout en bout sur la nouvelle adresse (lien du courriel compris) ; paiement
  Stripe de test : retour sur la nouvelle adresse.
- Le site vitrine et l'app iOS pointent vers la nouvelle adresse.
- Toutes les commandes des jobs de CI rejouées en local avant chaque push ; CI verte.

## Hors périmètre

- Le domaine `astreint-sp.fr`.
- Le domaine `astreinte.fr` (enregistré par un tiers depuis 2004).
