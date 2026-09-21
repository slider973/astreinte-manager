# Registre des traitements — Astreinte SP

Document de référence pour le RGPD (règlement UE 2016/679). Il décrit **ce que le logiciel fait
réellement**, vérifié contre `docs/SCHEMA.md` table par table et contre le code des Edge Functions.
Il n'anticipe rien : une durée qui n'est pas appliquée par une tâche automatique est signalée comme
telle.

Ce que le propriétaire doit compléter est marqué `[À COMPLÉTER : …]`. Ces marques sont volontaires :
une mention inventée se croirait, une mention trouée se corrige. Les deux pages publiques de
l'application (`/legal/confidentialite`, `/legal/mentions`) portent les mêmes.

- **Version** : 2 — ticket 043, 21 septembre 2026. La version 1 (ticket 034) signalait trois
  durées annoncées sans mécanisme qui les applique ; le § 2 bis les remplace par un inventaire
  table par table, et la migration `0030` les applique.
- **Portée** : l'application Astreinte SP (PWA), sa base Supabase, ses Edge Functions et ses
  sous-traitants listés au § 5.

---

## 1. Qui est responsable de quoi

Le produit sert des **centres de secours** qui y gèrent leurs propres sapeurs-pompiers. La
répartition qui en découle, à confirmer par écrit dans les conditions d'utilisation :

| Rôle | Qui | Sur quoi |
|---|---|---|
| **Responsable de traitement** | la caserne (son SDIS, sa commune ou l'association qui l'exploite) | les données de ses membres : identité, coordonnées, disponibilités, astreintes |
| **Sous-traitant** (art. 28) | l'éditeur d'Astreinte SP | l'hébergement et le traitement de ces données pour le compte de la caserne |
| **Responsable de traitement** | l'éditeur d'Astreinte SP | ses propres données de gestion : compte d'accès, facturation de l'abonnement, journaux techniques |

`[À COMPLÉTER : raison sociale, forme juridique, numéro SIREN et adresse du siège de l'éditeur.]`

`[À COMPLÉTER : adresse de contact pour l'exercice des droits — une adresse électronique
surveillée, pas une boîte de contact générique.]`

`[À COMPLÉTER : désignation ou non d'un délégué à la protection des données. Un DPO est obligatoire
pour un organisme public ; la plupart des SDIS en ont un, l'éditeur pas nécessairement.]`

`[À COMPLÉTER : un contrat de sous-traitance (art. 28.3) par caserne, ou une annexe unique aux
conditions d'utilisation. Sans lui, la répartition ci-dessus n'existe que dans ce document.]`

---

## 2. Les traitements

### 2.1 Gérer le compte et l'accès à l'application

| | |
|---|---|
| **Finalité** | Permettre à une personne de se connecter, de se faire reconnaître par sa caserne et d'être jointe |
| **Personnes concernées** | Sapeurs-pompiers volontaires et professionnels, chefs de centre, éditeur du produit |
| **Données** | Adresse électronique, prénom, nom, téléphone (facultatif), surnom affiché dans la caserne, rôle et statut d'appartenance, langue, date de création, date de dernière connexion |
| **Tables** | `profiles`, `memberships`, `invitations`, `super_admins`, et `auth.users` (schéma d'authentification Supabase) |
| **Base légale** | Exécution du contrat qui lie la caserne à ses membres, et intérêt légitime de la caserne à organiser ses gardes (art. 6.1.b et 6.1.f) |
| **Destinataires** | La personne elle-même ; les membres actifs de sa caserne (prénom, nom, surnom) ; les administrateurs de sa caserne (y compris téléphone et adresse) ; l'éditeur, pour l'exploitation |
| **Conservation** | Tant que l'appartenance existe. Après suppression de compte : le profil est **anonymisé** (« Membre supprimé », adresse non routable, téléphone effacé) et conservé sans limite, parce que les astreintes passées y pendent (§ 3). Les **invitations** ont leur propre durée : trente jours après l'expiration quand personne ne les a acceptées — l'adresse est alors celle de quelqu'un qui n'est jamais entré dans la caserne —, trois ans après l'acceptation, comme la trace d'administration qu'elles sont devenues (tâche `prune_retention`) |
| **Mesures** | Connexion par code à usage unique envoyé par courriel — aucun mot de passe stocké. Cloisonnement par caserne en Row Level Security sur chaque table (`docs/SCHEMA.md § 4`). Le jeton d'invitation n'est jamais rendu à un client |

### 2.2 Recueillir les disponibilités et construire les plannings

| | |
|---|---|
| **Finalité** | Savoir qui peut tenir une garde, composer le planning mensuel du centre, proposer les astreintes et suivre les réponses |
| **Personnes concernées** | Les membres actifs d'une caserne |
| **Données** | Disponibilité ou absence par date et par créneau (jour / nuit) ; quotas souhaités par mois et commentaire libre ; attributions, acceptations, refus et leur motif ; mention « attribué hors disponibilité » |
| **Tables** | `availabilities`, `availability_preferences`, `periods`, `schedules`, `shifts`, `assignments` |
| **Base légale** | Exécution du contrat et intérêt légitime de la caserne à assurer la continuité du service (art. 6.1.b et 6.1.f) |
| **Destinataires** | Le membre pour ses propres lignes ; les administrateurs de sa caserne pour toutes ; les autres membres uniquement quand le planning est **publié ou validé** (`docs/PRD.md § 7` règle 1) |
| **Conservation** | Les disponibilités et les quotas sont effacés à la suppression du compte. **Les attributions sont conservées sans limite**, sous la mention « Membre supprimé » : elles décrivent une garde tenue, c'est-à-dire un fait de service de la caserne, et non plus une donnée d'identité (`docs/PRD.md § 7` règle 6) |
| **Point d'attention** | Le commentaire libre de `availability_preferences` est saisi par le membre. Rien n'y empêche une mention de santé ou de famille (« indisponible, traitement médical »), qui serait une donnée sensible au sens de l'art. 9. L'interface n'en demande pas et la page de confidentialité déconseille d'en écrire ; c'est une atténuation, pas une garantie. `[À COMPLÉTER : décision du propriétaire — laisser le champ libre avec l'avertissement, ou le remplacer par des motifs pré-définis]` |

### 2.3 Prévenir, relancer, notifier

| | |
|---|---|
| **Finalité** | Faire savoir à un membre qu'une astreinte lui est proposée, qu'une échéance approche, qu'un planning est publié ou qu'une garde a changé |
| **Personnes concernées** | Les membres actifs d'une caserne, les administrateurs |
| **Données** | Titre et texte de chaque notification, canal (interne, push, courriel), horodatages d'envoi, de remise et de lecture, motif d'échec ; identifiant d'appareil émis par Firebase, plateforme, libellé lisible (« iPhone · Safari »), date de dernière utilisation |
| **Tables** | `notifications`, `push_tokens`, `notification_outbox` |
| **Base légale** | Exécution du contrat (art. 6.1.b). Les notifications **non critiques** — rappels de saisie, rapports — se coupent depuis le profil ; les propositions d'astreinte, elles, partent toujours : sans elles le produit ne rend pas son service |
| **Destinataires** | Le destinataire seul. Aucun administrateur ne lit les notifications d'un membre |
| **Conservation** | **Notifications** : 90 jours après la lecture, 365 jours après la création quand elles n'ont jamais été lues (tâche `prune_notifications`, migration `0030`). **Appareils** : 365 jours sans usage — `last_seen_at` est réécrit à chaque ouverture de l'application, et un jeton supprimé par erreur est réinscrit à la suivante. **File d'attente** : 30 jours après traitement ; une demande qui n'est pas encore partie (`pending`, `sending`) n'est **jamais** purgée par l'âge. Tout est effacé à la suppression du compte |
| **Mesures** | Un identifiant d'appareil définitivement rejeté par Firebase est supprimé par l'Edge Function d'envoi. La file d'attente `notification_outbox` n'est lisible par aucun client |

### 2.4 Tracer les actes d'administration

| | |
|---|---|
| **Finalité** | Rendre vérifiable ce qu'un administrateur fait sur les données d'un membre : saisir une disponibilité à sa place, attribuer une garde hors disponibilité, annuler, réouvrir un mois (`docs/PRD.md § 7` règle 7) |
| **Personnes concernées** | Les membres visés par l'acte, les administrateurs qui le posent |
| **Données** | Nature de l'acte, entité visée, date, caserne, et un détail structuré qui peut contenir une date, un créneau, un statut, un rôle ou une adresse invitée |
| **Tables** | `audit_log` |
| **Base légale** | Intérêt légitime : sans trace, un désaccord sur « qui a coché cette case » ne se tranche pas (art. 6.1.f) |
| **Destinataires** | Les administrateurs de la caserne concernée. Le membre lui-même, pour les actes qui le visent, par l'export du § 4 |
| **Conservation** | **Trois ans** (tâche `prune_retention`, migration `0030`). La trace survit à la suppression du compte pendant ce délai : `actor_id` désigne alors un profil anonyme. Le raisonnement est au § 2 bis |

### 2.5 Facturer l'abonnement de la caserne

| | |
|---|---|
| **Finalité** | Encaisser l'abonnement mensuel ou annuel d'une caserne, suspendre l'accès en écriture en cas d'impayé |
| **Personnes concernées** | Aucune, au sens du règlement : le client est la caserne. L'administrateur qui souscrit laisse toutefois ses coordonnées de facturation **chez le prestataire de paiement**, pas dans cette base |
| **Données** | Statut de l'abonnement, identifiants client et abonnement du prestataire, formule, dates d'échéance et de suspension |
| **Tables** | `subscriptions`, `stripe_events` |
| **Base légale** | Exécution du contrat d'abonnement, et obligation légale de conservation comptable (art. 6.1.b et 6.1.c) |
| **Destinataires** | Les administrateurs de la caserne, l'éditeur, le prestataire de paiement |
| **Conservation** | `subscriptions` : tant que la caserne existe — la ligne est créée avec elle et disparaît avec elle. `stripe_events` : **90 jours** pour les événements appliqués ou ignorés, sans limite pour ceux qui ont échoué (tâche `prune_retention`). **La durée légale comptable ne s'applique pas ici** : les pièces comptables — factures, reçus, moyens de paiement — sont chez le prestataire de paiement et relèvent de ses durées, pas des nôtres. La version 1 de ce document l'écrivait à tort ; `stripe_events` est un journal d'idempotence dont le rôle cesse quand le prestataire cesse de rejouer, c'est-à-dire au bout de trois jours. `[À COMPLÉTER : durée de conservation des factures chez le prestataire de paiement, et la manière dont l'éditeur en garde copie pour sa comptabilité — dix ans est la durée applicable en France aux livres et pièces comptables]` |

---

## 2 bis. Les durées de conservation, et ce qui les applique

Une durée affichée dans un registre et appliquée par rien est un manquement, pas un retard : le
document affirme quelque chose de faux. Ce tableau existe pour que la question se pose table par
table, et il se relit à chaque migration qui ajoute une table.

| Table | Durée | Ce qui l'applique |
|---|---|---|
| `profiles`, `memberships` | tant que l'appartenance existe, puis **anonymisé sans limite** | `delete_own_account` (migration `0026`) |
| `availabilities`, `availability_preferences` | effacées à la suppression du compte | `delete_own_account` (migration `0026`) |
| `periods`, `schedules`, `shifts`, `assignments` | **sans limite**, et c'est assumé : une garde tenue est un fait de service (`docs/PRD.md § 7` règle 6) | — |
| `subscriptions` | tant que la caserne existe | suppression en cascade avec `stations` |
| `notifications` | 90 jours après lecture, 365 jours sans lecture | tâche `prune_notifications` (migration `0030`) |
| `push_tokens` | 365 jours sans usage | tâche `prune_retention` (migration `0030`) |
| `notification_outbox` | 30 jours après traitement ; jamais une demande non partie | tâche `prune_retention` |
| `invitations` | 30 jours après expiration ; 3 ans après acceptation | tâche `prune_retention` |
| `invitation_rate_events` | **7 jours** — la table ne porte aucune adresse, seulement qui a invité et quand | tâche `prune_retention` (migration `0032`) |
| `audit_log` | **3 ans** | tâche `prune_retention` |
| `stripe_events` | 90 jours pour `processed` et `skipped` ; sans limite pour `failed` | tâche `prune_retention` |

Les durées sont des paramètres des fonctions de purge, pas des constantes : une caserne qui doit
en changer une change un chiffre (migration `0030`, et `supabase/tests/purges_conservation_test.sql`
qui vérifie chaque frontière à la journée près).

### Pourquoi trois ans pour le journal d'audit

La version 1 laissait la question ouverte en notant que « trois ans est l'ordre de grandeur
usuel ». Le chiffre est retenu, et voici sur quoi il repose plutôt que sur l'usage :

1. **À quoi sert la trace.** À expliquer *a posteriori* une décision d'administration sur les
   données d'un membre : qui a coché cette disponibilité à ma place, qui m'a attribué cette garde
   hors disponibilité, qui a réouvert ce mois (`docs/PRD.md § 7` règle 7). C'est un journal
   **métier**, pas un journal technique de sécurité : la recommandation de la CNIL de six mois à
   un an sur les journaux de connexion ne s'y applique pas.
2. **Sur quelle durée la question peut encore se poser.** Un désaccord sur une garde naît dans
   les jours qui suivent. Mais l'acte tracé sous-tend une indemnité de vacation horaire, et une
   réclamation sur une somme due se prescrit par trois ans (art. L3245-1 du code du travail,
   durée usuelle des créances salariales).
3. **Pourquoi pas davantage.** Au-delà, plus personne ne conteste, et le journal ne serait plus
   qu'un historique nominatif des gestes d'un chef de centre sur toute une carrière : conservé
   sans finalité, donc conservé sans base légale.
4. **Ce que la purge ne fait pas perdre.** Le fait reste : l'attribution, le créneau et la
   mention « attribué hors disponibilité » vivent dans `assignments`, conservés sans limite
   (§ 2.2). Ce qui expire au bout de trois ans, c'est le **nom de celui qui a posé le geste**,
   pas la garde.

`[À COMPLÉTER : une caserne publique dont le SDIS applique la déchéance quadriennale (loi du
31 décembre 1968) voudra quatre ans. C'est un seul chiffre — le paramètre p_days de
prune_audit_log — mais c'est une décision du responsable de traitement, pas de l'éditeur.]`

---

## 3. Ce qui reste après une suppression de compte

Le produit tient deux promesses qui se contredisent en apparence, et la frontière entre les deux
est la raison d'être de la migration `0026` :

- **Ce qui part** : disponibilités, préférences de charge et leur commentaire, appareils,
  notifications reçues, invitations en attente à l'adresse supprimée, appartenance au registre des
  éditeurs du produit.
- **Ce qui reste, anonymisé** : le profil, réduit à « Membre supprimé », adresse non routable
  (`supprime@astreinte.invalid`), téléphone effacé, notifications coupées ; les appartenances,
  passées en `disabled` et privées de leur surnom ; **et les attributions**, qui décrivent des
  gardes tenues.
- **Ce qui ne bouge pas** : les colonnes qui désignent l'auteur d'un acte
  (`audit_log.actor_id`, `assignments.created_by`, `schedules.created_by`,
  `invitations.invited_by`, `availabilities.set_by`). Elles pointent désormais vers un profil
  anonyme — c'est exactement l'effet recherché.

**Un reste connu, désormais borné.** L'invitation **déjà acceptée** garde l'adresse électronique
à laquelle elle a été envoyée : elle n'est pas dans « ce qui part », et l'anonymisation du profil
ne la touche pas. C'était, jusqu'au ticket 043, une adresse conservée sans limite malgré une
suppression de compte. Elle disparaît maintenant trois ans après l'acceptation (§ 2 bis). Ce n'est
pas un effacement immédiat, et ce document ne le présente pas comme tel — c'est une borne là où il
n'y en avait aucune. `[À COMPLÉTER : décision du propriétaire — effacer aussi cette adresse à la
suppression du compte, ce qui priverait la caserne de la trace de l'entrée de ce membre.]`

Une caserne qui perdrait son dernier administrateur actif n'aurait plus personne pour publier un
planning : la suppression est alors **refusée**, avec la sortie (« nomme d'abord quelqu'un »).

---

## 4. Les droits des personnes, et où ils s'exercent

| Droit | Article | Comment il s'exerce |
|---|---|---|
| Accès et portabilité | 15 et 20 | « Exporter mes données » dans l'écran Profil. Fichier JSON réutilisable, produit par l'Edge Function `export-user-data`, contenant les douze sections listées ci-dessous |
| Rectification | 16 | Prénom, nom et téléphone se corrigent dans l'écran Profil. L'adresse de connexion est l'identifiant du compte : sa correction passe par l'administrateur de la caserne |
| Effacement | 17 | « Supprimer mon compte » dans l'écran Profil, avec la liste de ce qui part et de ce qui reste **avant** le geste. Les astreintes passées sont conservées au titre de l'intérêt légitime de la caserne (art. 17.3.b et 17.3.e) |
| Opposition et limitation | 18 et 21 | Les notifications non critiques se coupent dans l'écran Profil. Pour le reste, `[À COMPLÉTER : adresse de contact]` |
| Réclamation | 77 | Auprès de la CNIL, 3 place de Fontenoy, 75007 Paris — [cnil.fr](https://www.cnil.fr) |

**Ce que contient l'export** (`supabase/functions/README.md § export-user-data`) : compte
d'authentification, profil, casernes, appartenances, disponibilités, préférences de charge,
attributions, notifications, appareils, invitations reçues, invitations envoyées, actes
d'administration concernant la personne, actes qu'elle a elle-même posés, et le fait d'être ou non
éditeur du produit. Un inventaire compte chaque section, y compris vide.

**Ce qu'il ne contient jamais** : le nom, l'adresse ou l'identifiant d'une autre personne. Quand un
acte implique quelqu'un d'autre, seul le fait est conservé — « cette case a été cochée par un
administrateur », « cette attribution a été remplacée » — jamais l'identité. L'adresse d'une
personne invitée est masquée. Le jeton d'un appareil est tronqué : c'est un identifiant
d'installation émis par Firebase, sans valeur pour la personne et réutilisable par qui le lit.

---

## 5. Sous-traitants et hébergement

| Sous-traitant | Ce qu'il traite | Où | Encadrement |
|---|---|---|---|
| **Supabase** | Base de données, authentification, Edge Functions : la totalité des données du § 2 | `[À COMPLÉTER : région du projet hébergé. Le PRD § 8 exige une région européenne — `eu-central-1` ou `eu-west`. À vérifier dans le tableau de bord avant toute mise en service]` | DPA de Supabase, clauses contractuelles types |
| **Google (Firebase Cloud Messaging)** | Identifiants d'appareil et contenu des notifications push | États-Unis | Clauses contractuelles types. **Transfert hors UE** : c'est le seul du produit, et il porte le titre et le corps de la notification — donc, parfois, une date de garde |
| **Resend** | Adresse électronique du destinataire et contenu des courriels (invitations, rappels, notifications de secours) | `[À COMPLÉTER : région retenue chez Resend]` | DPA de Resend |
| **Stripe** | Coordonnées de facturation de la caserne, jamais celles d'un membre | Irlande / États-Unis | DPA de Stripe, clauses contractuelles types |
| **Hébergeur de la PWA** | Aucune donnée personnelle : fichiers statiques uniquement | `[À COMPLÉTER : Vercel ou Cloudflare Pages, selon le choix du ticket 032]` | — |

`[À COMPLÉTER : la liste des sous-traitants doit être publiée et tenue à jour. Toute addition doit
être annoncée aux casernes avant d'entrer en service — c'est une obligation du contrat de
sous-traitance, pas une politesse.]`

---

## 6. Mesures de sécurité

- **Cloisonnement par caserne** en Row Level Security, sur chaque table, vérifié à chaque PR par
  `supabase/tests/rls_test.sql`. Aucune requête cliente n'échappe à ces politiques.
- **La clé de service ne quitte jamais le serveur.** Elle ouvre le client administrateur des Edge
  Functions et n'apparaît dans aucune réponse, aucun journal, aucun message d'erreur.
- **Aucun mot de passe** : la connexion se fait par code à usage unique envoyé par courriel.
- **Les fonctions qui portent un `user_id` en paramètre** — `delete_own_account`,
  `export_own_data`, les fonctions d'invitation — sont fermées aux rôles `anon` et `authenticated`.
  Seules les Edge Functions les appellent, avec une identité tirée du jeton d'accès.
- **Le jeton d'invitation** est hors du `grant` de lecture du rôle `authenticated` et ne sort ni
  dans une réponse, ni dans un export, ni par le canal temps réel.
- **Aucun secret dans le dépôt.**

`[À COMPLÉTER : procédure de notification de violation (art. 33 et 34) — qui prévient les casernes,
dans quel délai, par quel canal. 72 heures est le plafond légal pour saisir la CNIL.]`

`[À COMPLÉTER : politique de sauvegarde et de restauration de la base — fréquence, rétention,
localisation. Une sauvegarde est une copie des données du § 2 et relève du même régime.]`

---

## 7. Analyse d'impact

Une analyse d'impact (AIPD, art. 35) n'est **pas** manifestement requise en l'état : le traitement
ne porte ni sur des données sensibles au sens de l'art. 9, ni sur une surveillance systématique à
grande échelle, ni sur une décision automatisée produisant des effets juridiques. Deux réserves,
qui sont à surveiller et non à écarter :

1. Le commentaire libre des préférences de charge (§ 2.2) peut recueillir une donnée de santé.
2. La proposition automatique de remplissage du planning (ticket 018) est un traitement automatisé
   **assisté**, et il l'est par construction : la machine compose un plan, l'administrateur en lit
   le récapitulatif chiffré, et **rien n'est écrit tant qu'il n'a pas confirmé**. Aucune décision
   n'est prise sans lui. Si un jour la suggestion devenait une application directe, l'analyse serait
   à refaire.

`[À COMPLÉTER : position du responsable de traitement. Un SDIS a souvent un cadre interne qui
impose une AIPD indépendamment de ce raisonnement.]`
