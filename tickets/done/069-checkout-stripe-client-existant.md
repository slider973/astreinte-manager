# 069 — Le paiement Stripe ne s'ouvre pas pour une caserne

- **Épopée** : E8 Abonnement
- **Priorité** : P0
- **Dépend de** : 029
- **Branche** : `feat/069-checkout-stripe-client-existant`
- **PR** : https://github.com/slider973/astreinte-manager/pull/73, puis https://github.com/slider973/astreinte-manager/pull/76 (réouverture)
- **Statut** : terminé le 2026-09-28 (manuel)

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

1. Passer `customer_update: { name: "auto", address: "auto" }` à la session Checkout, avec un
   commentaire court (voir « Réouverture » : l'adresse est exigée elle aussi).
2. Un test Deno vérifie les paramètres de la session, encodés comme les envoie `appelStripe`
   (`customer_update[name]=auto` et `customer_update[address]=auto`).

## Critères d'acceptation

- Une session Checkout se crée pour une caserne dont le client Stripe existe déjà (en base ou créé
  à l'instant) : la session porte `customer_update[name]=auto` et `customer_update[address]=auto`
  avec `tax_id_collection[enabled]`.
- Le message d'erreur affiché en cas d'échec Stripe est inchangé.
- Un test Deno couvre les paramètres de la session ; `deno fmt --check`, `deno lint`, `deno check`
  et `deno test` passent comme en CI.
- Après fusion, le déploiement automatique publie une nouvelle version de `create-checkout`, qui
  contient `address`.

## Hors périmètre

- Le calcul automatique de la TVA (`automatic_tax`).
- Le portail de gestion, le webhook et l'écran Abonnement de la PWA.

## Réouverture (28 septembre 2026)

Le premier correctif (PR #73, `customer_update: { name: "auto" }`) n'a pas suffi. Production,
`create-checkout` v51, 28/09 18:58 UTC :

```
We could not find a valid address on the provided customer. To enable tax ID collection, please
set customer_update[address] to auto.
```

Vérification **directe contre l'API Stripe en mode test** :

- `customer_update[name]=auto` seul → cette même erreur ;
- `customer_update[name]=auto` **et** `customer_update[address]=auto` → session créée (`cs_test_…`).

Correction : `customer_update: { name: "auto", address: "auto" }`, et le test Deno exige les deux
champs (il imposait auparavant « seulement le nom »).

Leçon : le premier correctif reposait sur une supposition non vérifiée contre l'API (« l'adresse
n'est exigée qu'avec `automatic_tax` »). Un paramètre Stripe se vérifie par un appel réel en mode
test avant d'être livré, pas par la lecture d'un seul message d'erreur.
