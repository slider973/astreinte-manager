# Product

<!-- impeccable:product-schema 1 -->

Rédigé à partir de `docs/PRD.md`, puis confirmé en entretien `impeccable init` avec le propriétaire
du produit le 20 septembre 2026 (plateforme, usage admin, marque, méthode de construction).

## Platform

web

## Stack

Flutter 3.x. Canal principal : la PWA web, installée sur l'écran d'accueil des téléphones,
mobile-first, avec une disposition grand écran pour l'admin (décision confirmée le 20 septembre
2026). Les builds iOS et Android natifs existent dans le même code mais ne sont produits qu'à la
demande explicite d'une caserne ; ils ne conditionnent aucun ticket du MVP. Langage de design :
Material 3, une seule apparence partout. Sur iPhone en PWA, respecter les zones sûres, le geste
retour et Reduce Motion. Backend Supabase. Choix confirmé par le propriétaire du produit après comparaison avec Next.js + Capacitor,
Expo et Appwrite.

## Users

- **Sapeur-pompier volontaire (membre)** : saisit ses disponibilités du mois, répond aux
  propositions d'astreinte, consulte ses astreintes. Usage sur téléphone, en quelques secondes,
  entre deux activités, parfois en extérieur ou avec des gants. Tous âges, aisance numérique
  variable.
- **Admin de caserne** (chef de centre ou adjoint) : construit le planning du mois à partir des
  disponibilités, publie, suit les réponses, réattribue les refus. Usage sur ordinateur en
  priorité, tablette parfois, téléphone pour le suivi.
- **Super-admin (éditeur)** : gère les casernes et les abonnements. Interface web minimale.

## Product Purpose

Collecter les disponibilités, construire le planning d'astreintes et le faire valider par chaque
pompier concerné, sans aller-retour ni ressaisie. Remplace un intranet web existant dont la saisie
est case par case et qui n'a pas de boucle de validation. Succès : un mois saisi en moins de deux
minutes, un planning validé en moins de 48 heures, moins de 10 % de créneaux réattribués.

## Positioning

Deux mécanismes que l'outil remplacé n'a pas :
1. La séparation entre « je suis disponible » et « je veux être planifié », via des quotas par mois
   (max astreintes, max weekends) saisis par le membre.
2. La validation par créneau et non par planning : un refus ne touche qu'un créneau, la
   réattribution ne notifie que la nouvelle personne.

## Operating Context

- Un mois de saisie s'ouvre deux mois à l'avance et se verrouille à une date limite fixée par la
  caserne (par défaut le 15 du mois précédent).
- Deux créneaux par jour : jour et nuit. Un weekend = samedi et dimanche, jour et nuit. Jours fériés
  français comptés comme weekend.
- Les notifications (push, email de secours) sont le canal principal de la boucle de validation.
  Sur iOS web, le push n'existe que si la PWA est installée sur l'écran d'accueil.
- Une caserne a typiquement 15 à 60 membres. L'admin voit une matrice membres × jours × créneaux.
- Confirmé : l'admin fait le planning sur ordinateur (la matrice est conçue pour grand écran,
  consultable sur téléphone), les membres répondent sur téléphone.

## Capabilities and Constraints

- Auth par email et code à 6 chiffres, pas de mot de passe, pas d'OAuth au MVP.
- Multi-tenant : un projet Supabase pour toutes les casernes, isolation par RLS.
- Abonnement par caserne via Stripe, essai 60 jours. Caserne suspendue = lecture seule.
- Pas de SMS, pas de gestion des interventions, du matériel ou de la paie.
- Terminologie : caserne ou centre de secours ; membre ; admin ; astreinte ; créneau ; jour / nuit ;
  disponible / absent / non saisi ; proposé / accepté / refusé ; brouillon / publié / validé.
- Décisions ouvertes : état « disponible en dernier recours » ; grades et compétences pour composer
  un créneau (champ `skills` réservé) ; tarif définitif ; nom définitif de l'application.

## Brand Commitments

Nom de travail : Astreinte SP. Aucune contrainte de marque (confirmé) : ni logo, ni charte, ni
couleur imposée, y compris les codes visuels des sapeurs-pompiers. Le monde visuel est libre et
sera établi par Impeccable (`new-work`) au ticket 004.
Ton : direct, tutoiement du membre, phrases courtes, vocabulaire des pompiers sans jargon logiciel.

## Evidence on Hand

- Captures d'écran de l'intranet remplacé (grille mensuelle avec deux cases par jour, compteurs
  jour / nuit, commentaire du mois, mention « saisie bloquée »). Servent d'anti-référence
  visuelle et de référence fonctionnelle.
- Aucun témoignage, aucune donnée d'usage, aucun chiffre client : ne rien inventer.

## Product Principles

1. Deux touches suffisent : saisir un mois, répondre à une proposition, réattribuer un créneau.
2. L'état est toujours lisible sans la couleur, en plein soleil, avec des gants.
3. Un refus ne casse jamais le reste du planning.
4. Les quotas sont une information pour l'admin, pas un verrou : l'app avertit, l'humain décide.
5. Rien n'est supprimé : désactivation, annulation et suspension sont des statuts.

## Accessibility & Inclusion

Contraste 4.5:1 minimum, cibles tactiles 44 pt, tailles de police dynamiques, états portés par icône
ou texte en plus de la couleur (daltonisme), motion réduite respectée. Public avec aisance numérique
variable : pas de gestes cachés sans équivalent visible.
