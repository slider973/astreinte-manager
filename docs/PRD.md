# PRD — Astreinte SP

Version 1.0 — 20 septembre 2026
Statut : validé pour développement (Flutter + Supabase)

---

## 1. Vision

Astreinte SP est l'application qui permet à un centre de secours de collecter les
disponibilités de ses sapeurs-pompiers, de construire le planning d'astreintes, et de le
faire valider par chaque pompier concerné, sans aller-retour ni ressaisie.

Elle remplace un intranet web existant (type `cschatel-intranet.fr`) qui fonctionne mais
crée trois frictions majeures :

1. La saisie des disponibilités est case par case (deux cases par jour, jour et nuit),
   sans raccourci ni récurrence.
2. « Je suis disponible » et « je veux être planifié » sont confondus. Un pompier qui
   coche tous ses weekends pour laisser le choix à l'admin se retrouve planifié tous les
   weekends.
3. Le planning proposé par l'admin n'a pas de boucle de validation. Si un pompier ne peut
   pas, l'admin l'apprend tard et refait un planning complet.

## 2. Objectifs et indicateurs

| Objectif | Indicateur | Cible |
|---|---|---|
| Saisie rapide des dispos | Temps médian pour saisir un mois | < 2 minutes |
| Planning validé vite | Délai entre publication et validation complète | < 48 h |
| Moins de refontes | Nombre de créneaux réattribués par planning | < 10 % des créneaux |
| Adoption | Part des membres actifs ayant saisi le mois avant la date limite | > 90 % |
| Modèle économique viable | Coût d'infrastructure par caserne | < 3 €/mois |

## 3. Utilisateurs et rôles

### 3.1 Membre (sapeur-pompier)
- Saisit ses disponibilités par mois, jour et nuit.
- Indique ses préférences de charge (combien d'astreintes il veut réellement faire).
- Reçoit les propositions d'astreinte, accepte ou refuse.
- Consulte ses astreintes validées et les exporte vers son calendrier.

### 3.2 Admin de caserne
- Gère les membres (invitation, désactivation, rôle).
- Configure la caserne (effectif requis par créneau, date limite de saisie, délais de réponse).
- Voit la matrice des disponibilités du mois avec les quotas de chacun.
- Construit le planning, le publie, suit les réponses, réattribue les refus.
- Gère l'abonnement.

Une caserne peut avoir plusieurs admins. Un admin est aussi membre et peut être planifié.

### 3.3 Super-admin (éditeur de l'application)
- Voit toutes les casernes, leur statut d'abonnement, leur activité.
- Peut créer une caserne et nommer son premier admin.
- N'accède pas aux données de planning des casernes hors support explicite.

## 4. Périmètre

### 4.1 MVP (v1.0)
- Authentification par email sans mot de passe (code à 6 chiffres ou lien magique).
- Casernes multi-tenant, invitation des membres par email.
- Saisie des disponibilités avec raccourcis et préférences de charge.
- Date limite de saisie et verrouillage du mois.
- Construction du planning par l'admin avec la matrice des disponibilités.
- Publication et validation par créneau avec push et email de secours.
- Relances automatiques.
- Vue « mes astreintes » et export calendrier (ICS).
- Abonnement Stripe par caserne avec période d'essai.
- PWA web installable, canal principal et unique du MVP.

### 4.2 v1.1
- Échange d'astreinte entre deux membres avec validation admin.
- Statistiques par membre et par caserne (astreintes faites, taux de réponse).
- Export PDF et impression du planning du mois.
- Import des membres par CSV.

### 4.3 Hors périmètre (pour l'instant)
- Apps iOS et Android sur les stores : uniquement à la demande explicite d'une caserne. Le code
  Flutter les permet, mais aucun ticket du MVP n'en dépend.
- Gestion des interventions, du matériel, des formations.
- Feuilles de temps ou paie.
- SMS (coût par message incompatible avec un abonnement bon marché).
- Intégration avec les logiciels départementaux (SDIS).

## 5. Parcours utilisateurs

### 5.1 Première connexion d'un membre
1. Reçoit un email d'invitation de son admin avec un lien.
2. Ouvre le lien, saisit son email, reçoit un code à 6 chiffres, le saisit.
3. Complète son profil (nom, prénom, téléphone facultatif).
4. Sur mobile web, un écran explique comment ajouter l'app à l'écran d'accueil pour
   recevoir les notifications. Sur app native, demande de permission push.
5. Arrive sur le mois en cours avec un guide de trois écrans maximum.

### 5.2 Saisie des disponibilités d'un mois
1. Ouvre le mois (par défaut le prochain mois ouvert à la saisie).
2. Voit la grille des jours avec deux zones par jour : jour et nuit.
3. Peut sélectionner par touche simple, par glissement continu sur plusieurs jours,
   ou par raccourci : « tous les weekends », « toutes les nuits en semaine »,
   « tout le mois », « copier le mois précédent », « tout effacer ».
4. Peut marquer une plage en « absent » (vacances) pour que l'admin distingue
   « pas dispo » de « pas encore saisi ».
5. Renseigne ses préférences pour ce mois : nombre max d'astreintes, nombre max de
   weekends, ou « illimité ». Un commentaire libre est possible.
6. La sauvegarde est automatique à chaque changement, avec indicateur visuel.
7. Un compteur affiche le total jour / nuit / weekends cochés.

### 5.3 Construction du planning par l'admin
1. Ouvre le mois, voit la matrice membres × jours × créneaux.
2. Chaque cellule indique : disponible, absent, non saisi. Chaque ligne membre affiche
   ses quotas restants (ex. « 2/3 astreintes, 1/1 weekend »).
3. Sous chaque créneau à pourvoir, la liste des membres disponibles, triés par quota
   restant décroissant, puis par nombre d'astreintes déjà faites croissant.
4. L'admin attribue par touche. Un membre à quota atteint est grisé mais reste
   attribuable avec un avertissement.
5. Un bouton « proposition automatique » remplit les créneaux vides en respectant les
   quotas et en équilibrant la charge. L'admin reste libre de modifier.
6. Le planning reste en brouillon, invisible des membres, jusqu'à la publication.

### 5.4 Publication et validation
1. L'admin publie. Chaque membre attribué reçoit un push par créneau ou groupé
   (« 3 astreintes proposées en octobre »).
2. Le membre ouvre l'écran « Propositions », voit chaque créneau, accepte ou refuse.
   Un refus demande un motif court facultatif.
3. L'admin voit en temps réel l'état de chaque créneau : en attente, accepté, refusé.
4. Sans réponse après le délai configuré (défaut 24 h), un rappel push part. Après un
   second délai (défaut 48 h), un email part. L'admin voit les retardataires.
5. Sur refus, l'admin réattribue uniquement ce créneau. Seule la nouvelle personne est
   notifiée. Le reste du planning ne bouge pas.
6. Quand tous les créneaux sont acceptés, le planning passe en « validé ». Tous les
   membres reçoivent une notification et voient le planning complet.
7. L'admin peut modifier un planning validé. Toute modification renvoie le créneau
   concerné en « proposé » et notifie les personnes impactées.

### 5.5 Consultation
- « Mes astreintes » : liste et vue calendrier des astreintes acceptées, mois en cours et
  à venir.
- « Planning de la caserne » : vue de tous les créneaux du mois avec les noms, visible
  par tous les membres une fois le planning publié.
- Export ICS par membre avec un lien d'abonnement calendrier (Google, Apple, Outlook).

## 6. Fonctionnalités détaillées

### 6.1 Authentification
- Email + code OTP à 6 chiffres via Supabase Auth. Lien magique en alternative.
- Pas de mot de passe. Pas d'OAuth au MVP.
- Session longue durée sur mobile (refresh token), déconnexion explicite.
- Un utilisateur peut appartenir à plusieurs casernes (rare, mais possible dans les
  regroupements). Un sélecteur de caserne apparaît dans ce cas.

### 6.2 Caserne et membres
- Une caserne a un nom, un fuseau horaire, des paramètres et un abonnement.
- Paramètres par défaut : 1 personne requise par créneau jour, 1 par créneau nuit,
  modifiable par jour de semaine et par date spécifique.
- Les créneaux sont fixes : jour et nuit. Les heures de début et fin sont un paramètre
  d'affichage (ex. jour 7h-19h, nuit 19h-7h).
- L'admin invite par email. L'invitation expire après 14 jours et peut être renvoyée.
- Un membre désactivé garde son historique mais ne peut plus se connecter à la caserne.

### 6.3 Disponibilités
- Unité : (membre, date, créneau). Un enregistrement existe si le membre a saisi quelque
  chose. Absence d'enregistrement = non saisi.
- États : disponible, absent.
- Un mois est ouvert à la saisie jusqu'à sa date limite, configurée par l'admin
  (ex. le 15 du mois précédent). Après, le mois est verrouillé pour les membres.
  L'admin peut le rouvrir ou saisir pour un membre (avec trace d'audit).
- Préférences par mois : max astreintes (entier ou illimité), max weekends (entier ou
  illimité), commentaire. Par défaut, les préférences du mois précédent sont reprises.
- Un weekend = samedi jour, samedi nuit, dimanche jour, dimanche nuit. Une astreinte
  sur l'un de ces créneaux compte pour un weekend.
- Jours fériés français affichés et considérés comme weekend pour le comptage.

### 6.4 Planning
- Un planning par caserne et par mois. États : brouillon, publié, validé, archivé.
- Un créneau (shift) = (date, jour ou nuit, effectif requis).
- Une attribution (assignment) = (créneau, membre, statut).
- Statuts d'attribution : proposé, accepté, refusé, remplacé, annulé.
- Un membre ne peut pas être attribué deux fois au même créneau (contrainte en base).
- Un membre peut être attribué sur un créneau où il n'est pas disponible, avec
  avertissement explicite (cas des urgences). Il reçoit la proposition normalement.
- La proposition automatique est une heuristique simple : pour chaque créneau vide,
  choisir le membre disponible avec le plus de quota restant, puis le moins d'astreintes
  sur les 3 derniers mois. Pas d'optimisation globale au MVP.

### 6.5 Notifications
- Canaux : push (FCM sur iOS, Android, Web), email (Resend), centre de notifications
  in-app.
- Événements notifiés :
  - Invitation reçue (email uniquement).
  - Rappel de saisie des disponibilités à J-3 de la date limite (push, puis email J-1).
  - Astreinte proposée (push, groupé par publication).
  - Rappel de réponse (push à 24 h, email à 48 h, configurable).
  - Planning validé (push).
  - Créneau modifié ou annulé (push).
  - Pour l'admin : refus reçu, tous les créneaux acceptés, retardataires à J+3.
- Chaque notification est tracée avec son canal, sa date d'envoi et sa date de lecture.
- Le membre peut désactiver les push non critiques dans son profil. Les propositions
  d'astreinte ne sont pas désactivables.

### 6.6 Abonnement
- Un abonnement par caserne, payé par la caserne (l'amicale ou le centre).
- Plan unique au MVP : mensuel ou annuel, tarif à définir (hypothèse 12 €/mois ou
  120 €/an), essai gratuit 60 jours sans carte.
- Stripe Checkout pour la souscription, Stripe Customer Portal pour la gestion.
- Statuts : essai, actif, en retard de paiement, suspendu.
- Suspendu : lecture seule pour tous. Les données ne sont jamais supprimées pour cause
  d'impayé.

### 6.7 Super-admin
- Interface web minimale : liste des casernes, statut, nombre de membres, dernier
  planning publié, actions créer une caserne et nommer un admin.

## 7. Règles métier clés

1. Un créneau de planning est visible des membres uniquement quand le planning est publié
   ou validé.
2. Un refus ne remet jamais en cause les autres attributions.
3. Une réattribution notifie uniquement le nouveau membre et informe l'admin.
4. Les quotas sont des indications pour l'admin, pas des blocages. L'app avertit, l'admin
   décide.
5. La date limite de saisie verrouille les membres, jamais l'admin.
6. L'historique n'est jamais supprimé. Une désactivation, une annulation ou une
   suspension sont des changements de statut.
7. Toute action d'admin sur les données d'un membre (saisie pour lui, réouverture,
   attribution hors disponibilité) est tracée dans le journal d'audit.

## 8. Exigences non fonctionnelles

- **Sécurité** : isolation par caserne via Row Level Security. Aucune requête client ne
  passe sans RLS. Les Edge Functions utilisent la clé service uniquement côté serveur.
- **RGPD** : données hébergées en Europe (région Supabase eu-central-1 ou eu-west).
  Export des données personnelles d'un membre sur demande. Suppression de compte avec
  anonymisation de l'historique (le nom devient « Membre supprimé », les astreintes
  restent pour les statistiques de la caserne).
- **Performance** : la grille d'un mois se charge en moins d'une seconde sur 4G.
  La matrice admin pour 60 membres × 31 jours × 2 créneaux se charge en moins de
  deux secondes.
- **Hors ligne** : lecture du dernier état connu (mes astreintes, mon mois) sans réseau.
  La saisie hors ligne n'est pas au MVP.
- **Accessibilité** : contrastes conformes, cibles tactiles de 44 pt minimum, tailles de
  police dynamiques.
- **Web** : Flutter web avec renderer CanvasKit, manifeste PWA, service worker par défaut.
  Écran d'aide pour l'installation sur iOS. La PWA est le canal principal : chaque écran est
  vérifié sur Chrome et sur un téléphone avec la PWA installée, jamais seulement en natif.
- **Coût** : un seul projet Supabase pour toutes les casernes. Objectif < 3 €/mois par
  caserne en charge d'infrastructure.

## 9. Stack technique

| Couche | Choix | Notes |
|---|---|---|
| Front | Flutter 3.x, une base de code | Web/PWA en priorité ; iOS et Android natifs à la demande |
| État | Riverpod | Voir ticket 004 |
| Navigation | go_router | Deep links pour les notifications |
| Backend | Supabase | Postgres, Auth, Realtime, Storage, Edge Functions |
| Push | FCM Web (VAPID) via `firebase_messaging` | Natif APNs/Android seulement si une caserne demande l'app. Tokens dans `push_tokens` |
| Email | Resend | Appelé depuis les Edge Functions |
| Cron | pg_cron | Relances, verrouillage, rappels |
| Paiement | Stripe | Checkout, Customer Portal, webhooks vers Edge Function |
| Hébergement web | Vercel ou Cloudflare Pages | Build statique Flutter web |
| CI | GitHub Actions | analyze, test, build web |

## 10. Risques

| Risque | Impact | Mitigation |
|---|---|---|
| Push iOS web peu fiables (PWA non installée, réglages) | Membres ne voient pas les propositions | Email de secours systématique, badge in-app, guide d'installation insistant ; app native uniquement pour une caserne qui la réclame |
| Flutter web lourd au premier chargement | Abandon sur mobile | PWA installée charge une fois, écran de chargement soigné, mesure du temps de premier rendu |
| Admin qui refuse le changement d'outil | Pas d'adoption | Import des membres par CSV en v1.1, période d'essai longue, accompagnement |
| Projet Supabase gratuit en pause | Service indisponible | Passer en Pro dès le premier client payant |
| Double attribution concurrente par deux admins | Créneau sur-staffé | Contrainte d'unicité en base, Realtime pour rafraîchir la vue |

## 11. Questions ouvertes

1. Faut-il un statut « disponible mais en dernier recours » en plus de disponible et
   absent ? Décision reportée après retours du pilote.
2. Faut-il gérer les grades et compétences (chef d'agrès, conducteur) pour contraindre la
   composition d'un créneau ? Hors MVP, mais le schéma prévoit un champ `skills` sur le
   membre pour ne pas bloquer.
3. Tarif définitif et existence d'un plan « petite caserne » (moins de 15 membres).
4. Nom définitif de l'application.
