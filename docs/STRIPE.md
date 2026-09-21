# Stripe — ce qu'il faut créer pour que l'abonnement marche

Ce document s'adresse au **propriétaire du projet**, pas au développeur. Il ne suppose aucune
connaissance du code. Suis-le dans l'ordre : il y a **quatre valeurs** à récupérer et à déposer
dans les secrets du serveur, et une vérification à la fin.

**Rien n'est cassé tant que ce n'est pas fait.** L'application fonctionne déjà sans Stripe : les
casernes s'ouvrent en **période d'essai de 60 jours**, saisissent leurs disponibilités, publient
leurs plannings, et l'écran « Abonnement » affiche simplement :

> « L'abonnement n'est pas encore ouvert. Ta caserne fonctionne normalement pendant l'essai. »

Les tarifs y sont quand même affichés — un chef de centre en essai a le droit de savoir ce que ça
coûtera — et les deux boutons « S'abonner » sont inertes, avec la mention « Bientôt disponible »
écrite à côté. Ce qui manque, c'est la possibilité d'encaisser.

Compte à prévoir : **45 minutes**, une adresse e-mail, un IBAN et les statuts de la structure.
Stripe ne prend pas d'abonnement mensuel : il se paie à la commission (1,5 % + 0,25 € par paiement
de carte européenne, au tarif public de 2026).

---

## 0. Ce que Stripe va contenir, en une phrase

**Un produit, deux prix** (mensuel et annuel) et **un point de terminaison webhook** qui prévient
l'application quand un paiement passe ou échoue. C'est tout. Il n'y a **aucun essai à configurer
chez Stripe** : les 60 jours sont gérés par l'application, sans carte bancaire (`docs/PRD.md § 6.6`).

## 1. Créer le compte

1. Va sur <https://dashboard.stripe.com/register>.
   Utilise une adresse **de la structure**, pas une adresse personnelle : il faudra la transmettre
   un jour.
2. Renseigne le pays : **France**.
3. Stripe ouvre le tableau de bord en **mode test** — l'interrupteur est en haut à droite. Tout ce
   qui suit se fait **d'abord en mode test**, puis se refait à l'identique en mode réel (§ 7).
4. L'activation du compte réel (« Activer les paiements ») demande : forme juridique, numéro SIRET
   ou RNA pour une association, pièce d'identité du représentant, IBAN. Ça peut attendre : le mode
   test suffit pour tout vérifier.

> **Association loi 1901 (amicale de sapeurs-pompiers)** : choisir « Association / Organisme sans
> but lucratif » et fournir le **numéro RNA** (`W` + 9 chiffres) et le récépissé de déclaration en
> préfecture. Les statuts et le procès-verbal désignant le président sont demandés dans la foulée.

## 2. Créer le produit et ses deux prix

1. Menu de gauche → **Catalogue de produits** → **« + Ajouter un produit »**.
2. Nom : `Astreinte SP`.
   Description : `Gestion des astreintes pour un centre de secours. Un abonnement par caserne.`
3. Section **Tarification** :
   - Modèle : **Standard**
   - Montant : **12,00 €**
   - Devise : **EUR**
   - Période de facturation : **Mensuelle**
   - **Ne coche pas** « Période d'essai » : l'essai est géré par l'application.
4. Clique **« Ajouter un autre tarif »** et recommence :
   - Montant : **120,00 €**
   - Période de facturation : **Annuelle**
5. **Enregistrer le produit.**
6. Rouvre le produit : chaque tarif a un identifiant qui commence par **`price_`**. Recopie les
   deux quelque part :
   - celui du mensuel → `STRIPE_PRICE_MONTHLY`
   - celui de l'annuel → `STRIPE_PRICE_YEARLY`

> **Changer un prix plus tard** ne se fait pas en modifiant un tarif : Stripe les rend immuables.
> On en crée un nouveau, on remplace l'identifiant dans les secrets, et les abonnements en cours
> gardent l'ancien — ce qui est le comportement voulu, personne n'augmente rétroactivement une
> caserne. Il faut alors aussi changer `STRIPE_AMOUNT_MONTHLY` / `STRIPE_AMOUNT_YEARLY` (§ 5), qui
> sont ce que l'écran **affiche**.

## 3. Récupérer la clé secrète

1. Menu de gauche → **Développeurs** → **Clés d'API**.
2. Ligne **« Clé secrète »** → **« Révéler la clé »**. Elle commence par `sk_test_…` en mode test,
   `sk_live_…` en mode réel.

C'est la première valeur : `STRIPE_SECRET_KEY`.

> **C'est un vrai secret.** Elle permet d'encaisser, de rembourser et de lire tous les clients.
> Elle ne va **jamais** dans le dépôt ni dans `env/prod.json` : sa place est dans les secrets
> Supabase (§ 5), où seul le serveur la lit. La clé *publiable* (`pk_…`) ne sert pas à ce produit —
> l'application n'affiche aucun formulaire de carte, elle envoie vers la page hébergée par Stripe.

## 4. Créer le point de terminaison webhook

C'est par là que Stripe prévient l'application qu'un paiement est passé. Sans lui, une caserne
paierait sans jamais devenir « active ».

1. Menu de gauche → **Développeurs** → **Webhooks** → **« + Ajouter un point de terminaison »**.
2. **URL du point de terminaison** :

   ```
   https://<ref-du-projet>.supabase.co/functions/v1/stripe-webhook
   ```

   `<ref-du-projet>` est l'identifiant du projet Supabase (visible dans son tableau de bord, ou
   dans `SUPABASE_URL`).
3. **Événements à envoyer** — exactement ces cinq, pas un de plus :

   | Événement | Ce qu'il fait |
   |---|---|
   | `checkout.session.completed` | la caserne vient de souscrire → **active** |
   | `invoice.paid` | le renouvellement est passé → **active**, période repoussée |
   | `invoice.payment_failed` | la carte a été refusée → **paiement en retard** |
   | `customer.subscription.updated` | changement de formule, ou statut remonté par Stripe |
   | `customer.subscription.deleted` | résiliation → **lecture seule**, rien n'est supprimé |

   Tout autre événement reçu est **ignoré** par l'application, qui répond quand même « reçu » pour
   que Stripe n'insiste pas.
4. **Ajouter le point de terminaison.**
5. Sur la page du point de terminaison : **« Secret de signature »** → **« Révéler »**. Il commence
   par **`whsec_`**.

C'est la quatrième valeur : `STRIPE_WEBHOOK_SECRET`.

> **C'est le secret le plus important des quatre.** Cette fonction est publique : Stripe l'appelle
> sans mot de passe, depuis Internet. La signature est **la seule chose** qui distingue un vrai
> événement d'un faux — et un faux vaudrait « cette caserne est active » sans qu'un euro ait
> circulé, ou pire « cette caserne est suspendue », ce qui mettrait tous ses pompiers en lecture
> seule. Tant que ce secret n'est pas posé, la fonction **refuse tout**, y compris les vrais
> événements. C'est volontaire : le repli n'est pas « accepter sans vérifier ».

## 5. Déposer les quatre valeurs

Elles vont dans les **secrets Supabase**, jamais dans le dépôt, jamais dans `env/prod.json` :

```sh
supabase secrets set STRIPE_SECRET_KEY=sk_live_…
supabase secrets set STRIPE_PRICE_MONTHLY=price_…
supabase secrets set STRIPE_PRICE_YEARLY=price_…
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_…
```

Correspondance avec ce que Stripe affiche :

| Secret | Dans Stripe |
|---|---|
| `STRIPE_SECRET_KEY` | Développeurs → Clés d'API → « Clé secrète » (§ 3) |
| `STRIPE_PRICE_MONTHLY` | Catalogue → Astreinte SP → tarif mensuel → `price_…` (§ 2) |
| `STRIPE_PRICE_YEARLY` | Catalogue → Astreinte SP → tarif annuel → `price_…` (§ 2) |
| `STRIPE_WEBHOOK_SECRET` | Développeurs → Webhooks → le point de terminaison → secret de signature (§ 4) |

**Les quatre vont ensemble.** Si une seule manque ou est vide, l'application considère qu'il n'y a
pas de Stripe du tout et garde l'écran « pas encore ouvert ». C'est volontaire, et c'est la même
règle que pour Firebase (`docs/FIREBASE.md`) : mieux vaut une fonctionnalité annoncée comme absente
qu'une fonctionnalité qui échoue en silence devant un chef de centre.

### Trois réglages facultatifs

| Variable | Défaut | Rôle |
|---|---|---|
| `STRIPE_AMOUNT_MONTHLY` | `1200` | Le montant **affiché** par l'écran, en centimes. À changer en même temps que `STRIPE_PRICE_MONTHLY`. |
| `STRIPE_AMOUNT_YEARLY` | `12000` | Idem pour l'annuel. L'écran calcule tout seul l'économie annoncée (« 24 € offerts »). |
| `STRIPE_CURRENCY` | `eur` | Le symbole affiché à côté des montants. |

Et l'adresse de retour, partagée avec les autres fonctions :

| Variable | Défaut | Rôle |
|---|---|---|
| `APP_BASE_URL` | `http://127.0.0.1:3000` | Origine de la PWA. **À régler en production**, sinon Stripe renverra le navigateur sur `127.0.0.1`. |
| `APP_SUBSCRIPTION_PATH` | `/#/admin/abonnement` | Le chemin de l'écran d'abonnement. La valeur par défaut suit la stratégie de hash de `go_router`, en vigueur dans l'application. |

```sh
supabase secrets set APP_BASE_URL=https://app.astreinte-sp.fr
supabase secrets set APP_SUBSCRIPTION_PATH='/#/admin/abonnement'
```

Ces deux-là servent à construire les deux adresses de retour, que Stripe appelle après le
paiement : `…/#/admin/abonnement?paiement=ok` et `…?paiement=annule`. **Il n'y a rien à déclarer
chez Stripe** : l'application les envoie avec chaque session.

## 6. Vérifier que ça marche

Trois vérifications, de la plus simple à la plus proche du réel.

### a. L'écran, en 1 minute

1. Ouvre l'application, connecte-toi comme **administrateur** d'une caserne.
2. Onglet **Admin** → icône **carte de membre** dans la barre du haut → écran **« Abonnement »**.
3. La bannière « L'abonnement n'est pas encore ouvert » doit avoir **disparu**, et les deux boutons
   « S'abonner » doivent être **actifs**.

Si la bannière est toujours là, c'est qu'une des quatre valeurs manque. `supabase secrets list` les
montre par leur nom (jamais leur contenu).

### b. Un paiement de bout en bout, en mode test

1. Sur l'écran « Abonnement », clique **« S'abonner »** sur la formule mensuelle.
2. Un nouvel onglet s'ouvre sur la page de Stripe. Numéro de carte de test :
   **`4242 4242 4242 4242`**, date future quelconque, CVC quelconque, code postal quelconque.
3. Valide. Stripe renvoie sur l'écran « Abonnement ».
4. La bannière doit dire **« Paiement enregistré. »** et le statut passer à **« Abonnement actif »**
   avec sa date de prochain paiement. Le bloc des formules disparaît : il n'y a plus rien à
   souscrire.
   Si elle dit « Le statut se met à jour dans un instant », c'est que le webhook n'est pas encore
   arrivé : l'écran relit tout seul dix secondes plus tard.
5. Dans Stripe : **Développeurs → Webhooks → ton point de terminaison** : les événements doivent
   être en **200**. Un **400** signifie que le secret de signature ne correspond pas — reprends § 4
   et § 5.
6. Reclique **« Renvoyer »** sur un événement déjà passé : il doit répondre **200** sans rien
   changer au statut de la caserne. C'est le dédoublonnage — un événement n'est appliqué qu'une
   fois, même réémis dans la minute.

Autres cartes de test utiles (<https://stripe.com/docs/testing>) :

| Carte | Ce qu'elle produit |
|---|---|
| `4000 0000 0000 0341` | le paiement de renouvellement échoue → statut « Paiement en retard ». **L'écran ne propose alors plus « S'abonner »**, seulement « Gérer mon abonnement » : une carte se change dans le portail, ré-souscrire ferait payer deux fois |
| `4000 0025 0000 3155` | demande une authentification 3-D Secure |

### c. Le portail de gestion

Une fois abonné, le bouton **« Gérer mon abonnement »** apparaît. Il ouvre le portail Stripe, où
l'on change de carte, télécharge les factures et résilie.

**Il faut l'activer une fois** : Stripe → **Paramètres** → **Facturation** → **Portail client** →
**« Activer le lien du portail client »**. Coche au minimum :

- « Les clients peuvent mettre à jour leurs moyens de paiement »
- « Les clients peuvent consulter leur historique de facturation »
- « Les clients peuvent annuler leur abonnement »

Sans cette activation, le bouton rend une erreur et l'écran affiche « Le paiement n'a pas pu
s'ouvrir. Réessaie dans un instant. »

## 7. Passer en réel

Rien de neuf : **refaire les § 2, 3 et 4 avec l'interrupteur en mode réel**, puis redéposer les
quatre secrets (§ 5). Les identifiants `price_…` et le secret `whsec_…` du mode test **ne valent
rien** en mode réel, et inversement.

Les casernes déjà abonnées en mode test ne sont pas migrées : ce sont des données de test, elles
restent dans le monde de test.

## 8. Questions qui reviennent

**« Que se passe-t-il si une caserne ne paie pas ? »** Rien pendant **quatorze jours** : le statut
passe à « Paiement en retard » et la caserne continue de fonctionner normalement — les pompiers
répondent à leurs astreintes, le chef de centre publie ses plannings. Passé quatorze jours, une
tâche automatique la passe en **lecture seule**. **Aucune donnée n'est supprimée, jamais** : un
paiement qui revient rouvre tout, en l'état.

**« Et si l'essai de 60 jours expire sans abonnement ? »** Même chose : lecture seule, rien de
supprimé. L'écran « Abonnement » l'annonce plusieurs jours avant, avec la date exacte.

**« Une caserne peut-elle payer par virement ou par chèque ? »** Pas dans l'application. Le contour
pour un cas particulier : créer l'abonnement à la main dans le tableau de bord Stripe, en rattachant
le client à la caserne (champ `station_id` dans les **métadonnées** du client **et** de
l'abonnement). Le webhook fera le reste — à condition que la caserne n'ait pas déjà un **autre**
client rattaché, auquel cas il refusera (voir l'encadré ci-dessous).

**« Puis-je créer un lien de paiement (Payment Link) ? »** **Non.** L'adresse d'un lien de paiement
est publique, et n'importe qui peut y accoler `?client_reference_id=<identifiant d'une caserne>` :
c'est exactement le champ par lequel l'application reconnaît la caserne qui souscrit. L'application
refuse ce cas — un client ne peut pas être rattaché à une caserne qui en porte déjà un autre, ni à
une caserne alors qu'il appartient déjà à une autre — mais le bon geste reste de **ne pas créer de
lien de paiement du tout**. Toutes les souscriptions passent par le bouton de l'écran
« Abonnement », qui ouvre une session nominative.

**« Un paiement n'est jamais arrivé jusqu'à l'application, que regarder ? »** Dans Stripe :
**Développeurs → Webhooks → ton point de terminaison**, l'onglet des tentatives. Côté application,
tous les événements reçus laissent une ligne :

```sql
select id, type, status, attempts, error, received_at
from stripe_events
where status <> 'processed'
order by received_at desc;
```

`failed` = le traitement a échoué et sera rejoué (Stripe insiste trois jours ; passé ce délai,
cette ligne est la seule trace). `skipped` = l'événement a été écarté volontairement, et `error`
dit pourquoi : `station_not_found` (il ne concerne pas ce projet), `customer_mismatch` (le client
et la caserne nommée ne vont pas ensemble), `invalid_plan`.

**« Stripe voit-il les données de la caserne ? »** Non. Stripe reçoit le nom de la caserne,
l'adresse e-mail de l'administrateur qui souscrit, et un identifiant technique. Les
disponibilités, les plannings et les noms des pompiers restent dans Supabase.

**« Qui a le droit de s'abonner ? »** Un **administrateur actif** de la caserne, et seulement pour
**sa** caserne. C'est vérifié en base à chaque appel, pas dans l'application : un membre ordinaire
qui forcerait la requête reçoit un refus.

**« Et si le navigateur bloque l'onglet de paiement ? »** L'écran le dit et propose d'autoriser les
fenêtres pour le site. Il ne reste jamais un bouton qui ne fait rien.

## Où vivent les choses, pour le développeur

| Quoi | Où |
|---|---|
| Les quatre secrets et les trois facultatifs | Secrets Supabase, lus par `supabase/functions/_shared/stripe.ts` |
| La vérification de signature | `_shared/stripe.ts` → `verifierSignature`, testée par `supabase/functions/tests/stripe_signature_test.ts` |
| La traduction des événements | `stripe-webhook/evenement.ts`, testée par `tests/stripe_evenement_test.ts` |
| L'ouverture d'un paiement et du portail | `supabase/functions/create-checkout/`, contrat dans `supabase/functions/README.md` |
| L'écriture en base | `subscription_sync(...)`, migration `0023`, réservée au rôle de service |
| Le dédoublonnage et la trace des échecs | table `stripe_events`, `docs/SCHEMA.md § 2.17` |
| Le contrôle de droits du paiement | `supabase/functions/create-checkout/acces.ts`, testé par `tests/stripe_acces_test.ts` |
| L'essai de 60 jours | Déclencheur `stations_subscription_bootstrap`, migration `0023` |
| La suspension automatique | `cron_suspend_subscriptions(...)`, tâche `suspend_subscriptions`, `docs/SCHEMA.md § 8` |
| La lecture seule qui en découle | `station_writable(uuid)`, migration `0007` |
| La table | `docs/SCHEMA.md § 2.13` |
| L'écran | `lib/features/abonnement/`, brief dans `design/029-stripe-abonnement.md` |
