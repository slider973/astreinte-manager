# 029 — Abonnement Stripe par caserne

- **Épopée** : E8 Abonnement
- **Priorité** : P0
- **Dépend de** : 008, 010
- **Branche** : `feat/029-stripe-abonnement`
- **PR** : https://github.com/slider973/astreinte-manager/pull/27
- **Statut** : terminé le 2026-09-21 (PR créée)

## À faire
- Produit et prix Stripe (mensuel, annuel), essai 60 jours sans carte géré côté app (`trial_ends_at`).
- Edge Function `create-checkout` : crée le client Stripe si besoin, session Checkout, retour vers l'app.
- Edge Function `stripe-webhook` : `checkout.session.completed`, `invoice.paid`, `invoice.payment_failed`, `customer.subscription.updated/deleted` → met à jour `subscriptions`.
- Cron : passe en `suspended` les essais expirés sans abonnement et les `past_due` depuis plus de 14 jours.
- Écran admin « Abonnement » : statut, date de fin, bouton S'abonner / Gérer (Customer Portal).

## Critères d'acceptation
- Test avec Stripe CLI : chaque webhook met à jour le statut attendu.
- Signature du webhook vérifiée, rejet sinon.
