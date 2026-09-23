# Brief 064 — Un monde visuel pour le pompier

Ticket : `tickets/backlog/064-monde-visuel-pompier.md`. Référence :
`design/assets/064-reference-pompier.png`. Mode Impeccable : **Operate**, sur téléphone
d'abord. Ce brief est écrit après les trois décisions du propriétaire du 23 septembre 2026
(tableau de bord en premier ; « available shifts » = propositions reçues ; barre à quatre
entrées, profil derrière l'avatar).

## 1. Ce qui ne change pas

Les tokens du 061 : `DESIGN.md` v2, indigo `primary` et `primaryContainer` pour la sélection,
vert accepté, `orangeVif` et `roseVif` en remplissage seulement, violet décoratif, Archivo sur
les trois styles de titre, Atkinson pour le corps, Atkinson Mono pour les chiffres. Le modèle
jour / nuit. Les règles de fini : jamais la couleur seule, cibles 44, pas d'emoji, pas de filet
coloré en bord gauche. La coquille d'admin du 061 (colonne, en-tête, matrice) n'est pas touchée.

## 2. Ce qui distingue le monde du pompier

L'admin travaille sur une grille dense, blanche, à 28 points de pas. Le pompier lit trois
choses entre deux activités : quand est ma prochaine astreinte, qu'est-ce qu'on me demande,
ai-je saisi mes disponibilités. Le monde du pompier est donc fait de **cartes** sur un fond
doux, pas de tableaux :

- **Fond de page** `surfaceContainerLow`, cartes en `surface`, rayon `AppRadius.carte` = 20,
  sans ombre portée ou avec l'élévation 1 du thème au plus, jamais de bordure et d'ombre à la
  fois.
- **Cartes d'astreinte**, 144 × 168, en rangée horizontale défilante : la **prochaine astreinte
  acceptée** en `primary` avec texte `onPrimary` (numéro du jour en `displaySmall` Atkinson Mono,
  « Aujourd'hui » ou « mar. 24 », heures du créneau, « Jour » ou « Nuit » avec son icône, nom de
  la caserne) ; une **proposition en attente** en `orangeVif` avec texte `onSurface` et un bouton
  « Répondre » ; un **jour sans rien** en `surfaceContainerHigh` avec « Libre » et la date. Les
  cartes ne sont jamais la seule marque de l'état : l'icône et le libellé le disent.
- **Lignes de liste** (propositions, boîte, astreintes) : un carré de 40 à rayon 12 à gauche
  portant l'initiale du créneau (« J » ou « N ») en `primaryContainer` / `onPrimaryContainer`,
  un titre `titleMedium`, une ligne `bodyMedium` en `onSurfaceVariant`, à droite une mention
  (« 1/3 pourvus », « il y a 2 h ») et, pour le non-lu, une pastille indigo avec le nombre, jamais
  un point seul.
- **Bande de semaine à points** : sept jours, lettre puis numéro, le jour courant en pastille
  `primaryContainer`, sous chaque jour jusqu'à deux points de 6 : indigo pour une astreinte,
  orange pour une proposition ; chaque point est doublé dans la sémantique du jour.
- **Salutation** en `headlineSmall` Archivo : « Bonjour, » ou « Bonsoir, » selon l'heure, puis
  le prénom sur la ligne suivante ; à gauche l'avatar à initiales (`AvatarInitiales`, 40) qui
  ouvre le profil ; à droite la cloche avec le nombre de non-lus.

## 3. Les écrans

### 3.1 Accueil (`/`, nouveau)

1. En-tête : avatar, salutation, cloche.
2. « Mes astreintes · N » avec « Tout voir » vers Astreintes, puis la rangée de cartes : la
   prochaine acceptée d'abord, puis les jours qui viennent (proposition, libre, acceptée) sur
   sept jours au plus.
3. « Propositions · N » avec « Tout voir » vers la Boîte, onglet Propositions ; la bande de
   semaine à points ; puis les propositions en attente, trois au plus, en lignes de liste ;
   un appui ouvre la réponse (le même parcours qu'aujourd'hui).
4. « Disponibilités » : quand une période est ouverte, une carte d'appel « Saisir mes
   disponibilités d'octobre » avec « Reste 3 jours » ou « Plus qu'un jour », en
   `primaryContainer`, qui ouvre le Calendrier ; quand tout est saisi, une ligne
   « Octobre saisi : 12 jours, 4 nuits ». Quand rien n'est ouvert, la section n'existe pas.
5. États vides : « Aucune astreinte à venir », « Aucune proposition en attente », chacun avec la
   sortie qui a du sens (le Calendrier, ou rien).

### 3.2 Calendrier (`/calendrier`, l'actuel « Mon mois »)

La saisie des disponibilités du 016 ne change pas de fonction : grille du mois, raccourcis,
quotas, commentaire. Elle prend la matière du monde : fond doux, la grille dans une carte, le
sélecteur de mois en pastilles comme la bande de semaine, la barre de compteurs en bas de carte.
Aucune règle de saisie ne bouge.

### 3.3 Astreintes (`/astreintes`)

Liste des astreintes acceptées par mois, en lignes de liste ; en tête, la même rangée de cartes
que l'Accueil si elle apporte quelque chose, sinon rien. L'export ICS reste où il est.

### 3.4 Boîte (`/boite`, réunit Notifications et Propositions)

Titre « Boîte · N non lues ». Onglets `TabBar` : **Tout**, **Propositions**, **Rappels**. Lignes de
liste ; une proposition ouvre la réponse ; un rappel ouvre l'écran qu'il vise (deep links de
`docs/WORKFLOWS.md`). Le retour depuis la Boîte revient là d'où on vient : c'est une
destination, pas un écran poussé.

### 3.5 Profil

Derrière l'avatar, poussé, avec `BoutonRetour`. Contenu inchangé.

## 4. Navigation

Barre du bas (`NavigationBar`) : **Accueil** (`home`), **Calendrier** (`calendar_month`),
**Astreintes** (`event_available`), **Boîte** (`inbox`) ; **Admin** en cinquième pour l'admin
seulement. Sur grand écran, la colonne de navigation du 061 porte les mêmes destinations. Les
transitions entre destinations sont celles du 063 : aucun glissement. Les anciennes routes
(`/propositions`, `/notifications`, `/profil` en destination) redirigent vers les nouvelles
sans casser les liens des notifications envoyées avant.

## 5. Ce qu'on ne copie pas

Les photos d'avatar (initiales), le rôle « Registered Nurse » (chez nous c'est Jour ou Nuit),
la boîte de recherche des vacations, le jaune de la référence (c'est `orangeVif`), les
« Messages » (pas de messagerie dans le PRD), le compteur « 127 » décoratif dans les titres
quand il ne sert pas.

## 6. Découpage

- **064a :** navigation à quatre entrées, profil derrière l'avatar, redirections des anciennes
  routes, écran Accueil complet avec ses cartes, sa bande de semaine et son appel à saisir.
- **064b :** Boîte à onglets, fusion des écrans Notifications et Propositions, retour corrigé.
- **064c :** Calendrier et Astreintes dans la matière du monde.
- **064d :** passe de fini Impeccable sur tous les écrans du pompier (ex-061d) : `audit` et
  `polish`, corrections de fini seulement, inspection à 390 et sur téléphone.

Chaque chantier est une PR, revue puis fusionnée en squash ; le ticket reste en cours jusqu'au
064d.
