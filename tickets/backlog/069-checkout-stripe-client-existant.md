# 069 — Le paiement Stripe ne s'ouvre pas pour une caserne

- **Épopée** : E8 Abonnement
- **Priorité** : P0
- **Dépend de** : 029
- **Branche** : `feat/069-checkout-stripe-client-existant`
- **Statut** : à faire

## Contexte

Bug de production du 28 septembre 2026 : l'écran Admin → Abonnement affiche « Le paiement n'a pas
pu s'ouvrir. Réessaie dans un instant. » à chaque appui sur « S'abonner ».

Journal de l'Edge Function `create-checkout` en production (10:48 et 10:58 UTC) :

```
stripe 400 invalid_request_error : Tax ID collection requires updating business name on the
customer. To enable tax ID collection for an existing customer, please set customer_update[name]
to auto.
```

Cause : `supabase/functions/create-checkout/index.ts` passe **toujours** un `customer` à la session
Checkout (le client créé par `creerClient`, ou celui déjà retenu en base) avec
`tax_id_collection: { enabled: true }`, mais sans `customer_update`. Stripe refuse alors toute
session : il doit pouvoir écrire sur le client le nom de l'entreprise saisi avec le numéro de TVA.

## À faire

1. Passer `customer_update: { name: "auto" }` à la session Checkout, avec un commentaire court.
   `customer_update[address]` n'est pas ajouté : Stripe ne l'exige qu'avec `automatic_tax`, que la
   session n'active pas.
2. Un test Deno vérifie les paramètres de la session, encodés comme les envoie `appelStripe`
   (`customer_update[name]=auto`).

## Critères d'acceptation

- Une session Checkout se crée pour une caserne dont le client Stripe existe déjà (en base ou créé
  à l'instant) : la session porte `customer_update[name]=auto` avec `tax_id_collection[enabled]`.
- Le message d'erreur affiché en cas d'échec Stripe est inchangé.
- Un test Deno couvre les paramètres de la session ; `deno fmt --check`, `deno lint`, `deno check`
  et `deno test` passent comme en CI.
- Après fusion, le déploiement automatique publie une nouvelle version de `create-checkout`.

## Hors périmètre

- Le calcul automatique de la TVA (`automatic_tax`) et la collecte de l'adresse de facturation.
- Le portail de gestion, le webhook et l'écran Abonnement de la PWA.
