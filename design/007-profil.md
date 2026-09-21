# 007 — Profil utilisateur

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Bref, parce que ce ticket **rassemble** plus qu'il n'invente :
trois de ses quatre morceaux existent déjà ailleurs dans le produit.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Les écarts constatés à
l'implémentation sont au § 8.

Sources : `docs/PRD.md § 6.1`, `§ 7` règle 6, `§ 8` (RGPD) ; `docs/SCHEMA.md § 2.2`, `§ 2.3`,
`§ 2.10`, `§ 4`, `§ 7` ; `tickets/in-progress/007-profil.md` ; `design/006-invitations-onboarding.md`
(le complément de profil), `design/024-fcm-setup.md` (le réglage des notifications),
`design/027-mes-astreintes.md` (l'effacement des caches à la déconnexion).

---

## 1. Ce qui existe déjà, et qu'on ne réécrit pas

| Morceau | Où il est aujourd'hui | Ce qu'on en fait |
|---|---|---|
| Prénom, nom, téléphone | `ProfilAccueilScreen` (006), écrit via `ProfilRepository.completer` | Le **même** dépôt, la même validation, une seconde façade : l'accueil remplit, le profil corrige |
| Réglage des notifications non critiques | `ReglageNotifications`, posé sur l'onglet « Profil » au 024 avec la mention « il déménagera au 007 » | Déménage **tel quel**, sans une ligne de style changée |
| Déconnexion + effacement des caches | `BoutonDeconnexion` / `DeconnexionController` (027) | Déménage tel quel ; l'effacement est **extrait** dans un service partagé avec la suppression |
| Caserne et rôle | `_BlocIdentite` de `AccueilScreen` | Devient le bloc « Ta caserne », qui gagne un sélecteur quand il y en a plusieurs |

Le seul morceau neuf est **la suppression de compte**.

## 2. Job et audience

**Un pompier volontaire qui vient corriger une faute de frappe dans son nom, ou couper des
notifications, une ou deux fois par an.** Ce n'est pas un écran de travail : il se visite
rarement, et chaque visite a un seul but. Il doit donc être **plat, ordonné et sans surprise** —
on trouve la ligne qu'on cherche en défilant une fois.

Un cas rare mais réel : la personne appartient à **deux casernes** (regroupement de centres,
`docs/PRD.md § 6.1`). Aujourd'hui l'application choisit pour elle — `appartenanceCouranteProvider`
prend la première appartenance active dans l'ordre alphabétique — et **rien ne permet d'en
changer**. C'est le défaut que ce ticket corrige.

## 3. Résultat et preuve

**Résultat.** Tout ce que l'application sait de moi est sur un seul écran, et je peux en partir.

**Preuve, dans l'ordre :**

1. Mon nom tel qu'il apparaîtra dans le planning de la caserne est lisible et corrigible en
   place ; l'enregistrement dit qu'il a eu lieu, et l'admin voit le nouveau nom dans sa liste.
2. Quand j'ai deux casernes, je vois laquelle est active et j'en change en deux touches. Tout
   l'écran qui suit — mon mois, mes astreintes, le planning — suit ce choix, y compris après
   avoir fermé l'application.
3. Quand je n'en ai qu'une, **aucun sélecteur n'apparaît** : un contrôle à un seul choix est un
   contrôle de trop.
4. Je peux supprimer mon compte, l'écran me dit **exactement** ce qui part et ce qui reste, et
   après coup l'appareil est aussi propre qu'après une déconnexion.
5. La caserne, elle, garde ses astreintes passées — sous « Membre supprimé ».

## 4. Structure de l'écran

Une seule colonne, blocs réglés (`DESIGN.md § Cards / Containers` : filet 1 dp, rayon 8, aucune
ombre), dans cet ordre, du plus consulté au plus définitif :

```
Profil                                    (titre, semantics header)

┌ Ton identité ────────────────────────┐   prénom, nom, téléphone (facultatif)
│ [Prénom] [Nom] [Téléphone]           │   + adresse de connexion, en lecture
│ Adresse de connexion : …@…           │   + bouton « Enregistrer mes informations »
│ [Enregistrer mes informations]       │
└──────────────────────────────────────┘

┌ Ta caserne ──────────────────────────┐   nom + rôle (bloc du 006, inchangé)
│ CIS Saint-Martin                     │   + sélecteur SI ≥ 2 appartenances actives
│ Membre                               │
│ ─ Tu appartiens à 2 casernes ─       │
│ ( ) CIS Saint-Martin  (•) CIS Val-…  │
└──────────────────────────────────────┘

┌ Notifications ───────────────────────┐   ReglageNotifications, tel quel (024)
└──────────────────────────────────────┘

┌ Langue ──────────────────────────────┐   « Français », lecture seule + la raison
└──────────────────────────────────────┘

┌ Ton compte ──────────────────────────┐   [Se déconnecter]  (secondaire)
│                                      │   ── filet ──
│                                      │   [Supprimer mon compte]  (danger, texte)
└──────────────────────────────────────┘
```

L'ordre est un argument : **on ne tombe pas sur la suppression en cherchant son téléphone**. Elle
est en bas, dans son propre bloc, derrière un filet, et elle n'est jamais le premier bouton
atteint par le clavier.

## 5. Les quatre décisions

### 5.1 La langue s'affiche, elle ne se règle pas

Le MVP est en français seulement : `profiles.locale` a `default 'fr'` et aucune autre valeur n'est
produite. Un sélecteur à un seul choix promet une traduction qui n'existe pas. On affiche donc la
ligne — parce que « quelle langue l'application m'écrit-elle » est une question légitime, et parce
que la colonne existe — **en lecture seule, avec sa raison écrite à côté** (`DESIGN.md § Do's` :
« Expliquer pourquoi un contrôle est désactivé, à côté du contrôle »). Le jour où une deuxième
langue arrive, la ligne devient un choix sans bouger de place.

### 5.2 Le sélecteur de caserne n'apparaît qu'à partir de deux

Un `RadioListTile` par caserne active, 48 dp minimum, libellé complet, **jamais un menu
déroulant** : deux ou trois entrées tiennent à l'écran, et un menu cache le fait qu'il y a un
choix. Le choix est gardé sur l'appareil (`session.caserne.<userId>`, même mécanique que les
appartenances du 027) : il survit à la fermeture, il s'efface à la déconnexion comme le reste.

Un choix qui ne correspond plus à aucune appartenance active — on m'a retiré de cette caserne —
retombe silencieusement sur la première : l'application ne se bloque pas sur un souvenir.

### 5.3 La suppression est une feuille, pas une boîte de dialogue

`DESIGN.md § Don't` interdit la modale pour ce qui ne demande « ni interruption ni protection ».
Celle-ci demande les deux — mais elle demande surtout **de la place pour lire**. Une feuille de
bas d'écran (`showModalBottomSheet`, comme `ConfirmationDesactivation` du 009) porte :

- ce qui **part** : nom, téléphone, adresse, disponibilités saisies, notifications, appareils ;
- ce qui **reste** : les astreintes passées, sous « Membre supprimé », parce que la caserne en a
  besoin pour ses statistiques (`docs/PRD.md § 7` règle 6) ;
- que c'est **définitif** ;
- un bouton `danger` « Supprimer définitivement » et une sortie « Annuler » de même taille.

Pas de saisie de confirmation à recopier : le public a une aisance numérique variable, et deux
touches réfléchies valent mieux qu'une phrase recopiée sans lire. Le bouton est en variante
`danger` — le rouge est un état, et là il en est un.

**La place du ticket 034.** L'export des données personnelles s'insère au-dessus du bouton de
suppression, dans le même bloc « Ton compte », et **dans la feuille** comme dernière sortie avant
le point de non-retour (« Récupère d'abord tes données »). Rien n'est posé aujourd'hui : un bouton
mort est pire qu'un bouton absent.

### 5.4 Un administrateur seul à bord ne peut pas partir

Si la personne est **le dernier administrateur actif** d'une caserne, la suppression est refusée
par la base (`delete_own_account`, code `last_admin`, même raisonnement que
`memberships_guard_admin` du 009) et l'écran affiche la sortie : « Nomme d'abord un autre
administrateur ». Sans cette garde, une caserne se retrouve sans personne pour publier un
planning, et personne ne s'en aperçoit avant le mois suivant.

## 6. États

| État | Ce que l'écran montre |
|---|---|
| Chargement du profil | Les champs sont désactivés, aucun squelette : l'écran est court et la lecture est brève |
| Échec de lecture | `AppBanner` variante `erreur` + « Réessayer » ; le reste de l'écran reste utilisable |
| Enregistrement | Le bouton garde son libellé, un indicateur de 20 dp le précède (`DESIGN.md § Buttons`) |
| Enregistré | Une ligne `liveRegion` sous le bouton : « Informations enregistrées. » Pas de toast |
| Prénom ou nom vide | Erreur sous le champ concerné, `liveRegion`, mêmes textes qu'au 006 |
| Suppression en cours | La feuille reste ouverte, le bouton `danger` porte l'indicateur, rien n'est fermable |
| Suppression refusée | Le motif **dans la feuille**, sous le bouton, jamais dans un toast qui part |
| Caserne suspendue | Rien de particulier : le profil est une donnée personnelle, pas une donnée de caserne, et `station_writable()` ne le concerne pas |

## 7. Accessibilité

- Chaque champ garde son libellé visible au-dessus (`DESIGN.md § Inputs`), `keyboardType`
  `name` / `phone`, autofill `givenName` / `familyName` / `telephoneNumber`.
- Le sélecteur de caserne est un groupe de radios annoncé comme tel ; la caserne active porte
  `selected: true` en semantics, pas seulement une couleur.
- Chaque résultat d'action (« enregistré », « impossible d'enregistrer », « compte supprimé »)
  passe par une région `liveRegion` : rien d'important n'est signalé par la seule disparition
  d'un indicateur.
- Cibles 48 dp partout, 8 dp entre deux cibles.

## 8. Écarts constatés à l'implémentation

1. **La cascade `profiles → auth.users` rendait le ticket impossible.** `profiles.id references
   auth.users(id) on delete cascade` (migration `0002`), et `assignments.user_id references
   profiles(id) on delete cascade` (`0004`) : supprimer le compte d'authentification effaçait le
   profil, qui effaçait **les attributions passées**. Le critère « la suppression conserve les
   attributions passées » était donc inatteignable sans migration. `0026` retire cette contrainte
   et documente pourquoi : un profil anonymisé **survit** à son compte d'authentification, c'est
   ce qui reste de lui dans l'histoire de la caserne. Aucune colonne n'est ajoutée — `first_name`,
   `last_name`, `email` et `phone` suffisent à porter « Membre supprimé ».
2. **L'effacement des caches locaux passait à côté des casernes secondaires.**
   `DeconnexionController._oublierLesCaches` n'effaçait que la caserne *courante* ; avec un
   sélecteur, une personne à deux casernes laissait derrière elle l'instantané de l'autre — qui
   porte **les noms de ses collègues**. L'effacement est extrait dans `OubliLocal`, qui boucle sur
   **toutes** les appartenances connues, et sert aussi bien la déconnexion que la suppression.
   Il emporte au passage la file de saisie hors ligne (`dispos.file.*`), qui n'était effacée par
   personne.
3. **Le jeton push de l'appareil (`notifications.jeton.appareil`) n'est pas effacé.** Ce n'est pas
   une donnée de personne mais une donnée d'appareil : son rôle est justement de survivre à un
   changement d'utilisateur pour ne pas laisser de ligne morte dans `push_tokens`. Les lignes
   `push_tokens`, elles, sont supprimées côté serveur.
4. **Une route impérative fermée après la session laisse un écran blanc.** La feuille de
   suppression est poussée par `showModalBottomSheet` ; `go_router` ne la connaît pas. Fermer la
   session pendant qu'elle est ouverte remplace toutes les pages du routeur et laisse la feuille
   **seule** au sommet de la pile : l'écran devient blanc et le reste jusqu'au rechargement.
   Constaté dans Chrome, PWA, après une vraie suppression — le compte était bien anonymisé en base,
   mais la personne restait devant un écran vide. Le geste est donc coupé en deux :
   `SuppressionCompteController.supprimer` fait le serveur et le ménage local, la feuille se
   referme, **puis** `fermerSession` laisse le routeur faire son travail.
5. **Le profil n'a pas de route à lui.** Il reste l'onglet 3 de la coquille d'accueil, comme les
   autres destinations de premier niveau, en attendant que `DESIGN.md § Navigation` soit honoré
   par un éclatement en routes (`/mois`, `/profil`, …). Même écart que les tickets 011 et 027.
