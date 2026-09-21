# 028 — Export calendrier ICS

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Court par construction : ce ticket n'ajoute **aucun écran**. Il
ajoute un bloc à un écran de réglages (007) et un bouton à une feuille de détail (027).

`DESIGN.md` gagne sur ce brief pour toute valeur de token.

Sources : `docs/PRD.md § 5.5`, `§ 6.6`, `§ 8` ; `docs/SCHEMA.md § 2.1`, `§ 2.2`, `§ 2.9`, `§ 2.10`,
`§ 4`, `§ 7` ; `design/007-profil.md`, `design/027-mes-astreintes.md`,
`design/034-rgpd-export.md` (le mécanisme de téléchargement), `tickets/in-progress/028-export-ics.md`.

---

## 1. Job

**« Que mes astreintes apparaissent dans le calendrier où je regarde déjà ma vie. »**

Le pompier volontaire a un agenda — le travail, les enfants, le foot. Ses astreintes vivent
ailleurs, dans une application qu'il faut ouvrir. Tant que les deux sont séparés, il double-saisit,
ou il oublie. Ce ticket n'améliore pas l'application : il la fait **sortir** d'elle-même.

Deux gestes, et ils ne servent pas la même personne au même moment :

| Geste | Quand | Coût | Résultat |
|---|---|---|---|
| **S'abonner** | une fois, à l'installation, assis, sur un ordinateur ou le téléphone | trois minutes, un copier-coller dans un autre outil | toutes les astreintes, pour toujours, et celles à venir |
| **Ajouter celle-ci** | en voyant une date, debout, dans la feuille de détail | un appui | un fichier, un événement, figé |

L'abonnement est la vraie réponse ; le fichier unique est la réponse à qui ne veut pas s'abonner,
ou à qui vient d'accepter une garde et veut la voir tout de suite dans son agenda.

## 2. Ce qui n'est pas dans ce ticket

- Pas d'écriture dans le sens inverse : le calendrier tiers ne dit rien à l'application.
- Pas d'invitation par courriel avec pièce jointe : c'est une autre affaire (le ticket 025 tient
  les envois, et un `.ics` en pièce jointe est une notification, pas un export).
- Pas de plugin natif d'agenda. La PWA est le produit (`CLAUDE.md`), et aucun paquet
  `add_2_calendar` n'a d'implémentation web.

## 3. Le point dur : une adresse qui voyage

L'adresse d'abonnement est **publique**. Elle sera collée dans Google Agenda, donc lue par les
serveurs de Google ; dans Apple Calendar, donc recopiée dans iCloud ; peut-être dans un courriel à
soi-même. Elle se comporte comme un mot de passe qu'on affiche. Trois conséquences, toutes portées
par le code du ticket :

1. **Elle ne donne accès qu'aux astreintes acceptées de son porteur.** Pas ses disponibilités, pas
   son profil, pas l'identité d'un équipier, rien d'une autre caserne. Un flux calendrier n'est pas
   l'endroit où l'on apprend qui d'autre est de garde — et la RLS de `assignments` ne l'ouvre
   d'ailleurs qu'à planning validé (`docs/SCHEMA.md § 4`).
2. **Elle se révoque.** « Régénérer le lien » remplace le jeton : l'ancienne adresse répond `404`
   dès la transaction suivante, sans délai, sans liste de révocation.
3. **Elle suit l'état du membre.** Une appartenance `disabled` — départ de la caserne, compte
   supprimé (`0026`) — fait disparaître les astreintes de cette caserne du flux, sans que personne
   n'ait à penser à couper l'abonnement.

Et une conséquence côté écriture : **le jeton n'est jamais lisible par un autre membre**.
`profiles_select_self_or_same_station` (migration `0007`) ouvre la ligne `profiles` à tous les
membres de la caserne ; la colonne est donc hors du `grant` de colonne de `authenticated`, comme
`invitations.token` l'est depuis `0008`, et elle se lit par une fonction qui ne répond que sur
`auth.uid()`.

**Caserne suspendue : le flux continue.** `docs/PRD.md § 6.6` dit « suspendu : lecture seule pour
tous ». Un flux calendrier est une lecture. Le vider ferait croire à des gardes annulées — c'est le
contraire de ce que le produit promet quand il dit que rien n'est supprimé pour cause d'impayé.

## 4. Le contenu d'un événement

Un événement de calendrier se lit à 7 h du matin, dans une liste, sans contexte.

```
Astreinte jour — CIS Saint-Martin
07:00 → 19:00, le samedi 14 novembre
Lieu : CIS Saint-Martin
Créneau de jour, de 07:00 à 19:00. Astreinte acceptée.
```

- **Intitulé** : `Astreinte jour — <caserne>` / `Astreinte nuit — <caserne>`. Le mot « astreinte »
  en tête parce que c'est ce qu'on cherche des yeux ; la caserne parce qu'un pompier peut appartenir
  à deux centres et que l'événement ne dit rien d'autre de son origine.
- **Heures** : celles des paramètres de la caserne (`stations.settings.day_start` / `day_end`),
  jamais un 7 h – 19 h écrit en dur. La nuit est l'intervalle complémentaire, `day_end → day_start`
  du lendemain — exactement la règle de `HeuresAffichage` au ticket 027.
- **Lieu** : le nom de la caserne. `docs/SCHEMA.md § 2.1` n'a **pas** de colonne d'adresse et ce
  ticket n'en invente pas ; le jour où elle arrive, une seule ligne change.
- **Description** : la phrase qui dit *jour* ou *nuit* et les heures. Un intitulé se tronque dans
  une vue mensuelle ; la description, elle, survit.
- **Pas d'alarme (`VALARM`)**. L'application a déjà ses rappels (ticket 022) ; un second système de
  notification que le pompier n'a pas demandé se règle dans un troisième outil.

L'identifiant d'un événement est celui de l'attribution. C'est ce qui fait que le fichier unique et
le flux d'abonnement désignent **le même** événement : quelqu'un qui a fait les deux gestes n'a pas
deux lignes dans son agenda.

## 5. Le bloc « Ajouter à mon calendrier » (écran de profil)

Un `BlocRegle` de plus, posé **après le réglage des notifications** : les deux répondent à la même
famille de question — « comment cette application entre-t-elle dans ma journée ». Il précède la
langue et le bloc « Ton compte », qui reste le dernier de l'écran (`design/007-profil.md § 4`).

Ordre interne, du geste au garde-fou :

1. Une phrase : ce que l'abonnement fait, et qu'il se met à jour tout seul.
2. **L'adresse**, en entier, sélectionnable, dans un cadre atténué et une police à chasse fixe
   (`AtkinsonHyperlegibleMono`) — un jeton de 48 caractères hexadécimaux se relit lettre à lettre.
   Pas de masquage : le seul usage de cette ligne est d'être copiée, et masquer ce qu'on demande de
   copier est une friction sans bénéfice — la personne est déjà seule devant son écran de profil.
3. **« Copier le lien »**, bouton secondaire pleine largeur, avec sa confirmation **sur place**
   (`liveRegion`), comme l'export du 034 : dans une PWA installée, rien d'autre ne dit qu'il s'est
   passé quelque chose.
4. **L'avertissement** : ce lien vaut mot de passe, ne le partage pas.
5. **Les trois modes d'emploi** (Google Agenda, Apple Calendar, Outlook), repliés dans un
   `ExpansionTile` fermé par défaut. Trois listes de trois lignes dépliées feraient un mur au
   milieu d'un écran de réglages, et deux personnes sur trois n'en lisent qu'une seule.
6. **« Régénérer le lien »**, bouton `danger`, en bas, après un filet — même grammaire que
   « Supprimer mon compte », parce que c'est la même catégorie : ça casse quelque chose qui marchait.
   **Confirmation obligatoire** (dialogue), qui dit ce que ça casse : « tes abonnements existants
   cesseront de se mettre à jour, il faudra recoller la nouvelle adresse ».

États du bloc : chargement (une phrase, pas un squelette — l'écran est court, même raison qu'au
007), échec de lecture (phrase + « Réessayer », le reste du profil ne tombe pas avec), prêt.

## 6. Le bouton « Ajouter à mon agenda » (feuille de détail)

Dans `DetailAstreinte`, **un bouton par créneau**, sous les équipiers : la feuille porte une
journée, et un pompier peut être de jour **et** de nuit le même jour — un seul bouton ne saurait pas
lequel des deux enregistrer.

Bouton secondaire, icône `event_available`, plein largeur, puis la ligne d'état annoncée dessous
quand il s'est passé quelque chose. **Il ne charge rien** : le fichier est composé sur l'appareil à
partir de ce que la feuille a déjà en main. C'est la promesse du 027 — cette feuille s'ouvre aussi
vite hors ligne qu'en ligne — et la tenir voulait dire ne pas aller chercher le serveur ici.

L'enregistrement passe par `telechargementProvider` (ticket 034) et **rien d'autre** : partage
système sur iPhone, ancre `download` ailleurs, et les quatre issues déjà écrites — enregistré,
partagé, annulé (qui ne dit rien), impossible (qui le dit en rouge).

## 7. Accessibilité, et ce qui n'est pas négociable

- 44 pt sur les quatre boutons neufs ; `PrimaryButton` le tient déjà.
- Chaque confirmation est une `liveRegion` : un lecteur d'écran doit apprendre qu'un lien a été
  copié sans avoir à repartir en exploration.
- Le bouton « Ajouter à mon agenda » porte un `libelleAnnonce` complet — « Ajouter samedi
  14 novembre, nuit, à mon agenda » — parce que deux boutons au même libellé se suivent dans la
  feuille d'une journée à deux créneaux.
- Aucun état porté par la couleur seule : icône + libellé d'abord, couleur en quatrième
  (`DESIGN.md § Do's`).
- Tout en français, dans `AppStrings`. Les textes du fichier `.ics`, eux, sont **aussi** du produit :
  ils sont en français, et ils vivent côté serveur (Edge Function) et côté client (fichier unique).

## 8. Écarts assumés

- **Deux producteurs d'ICS**, un en TypeScript (le flux), un en Dart (le fichier unique). C'est une
  duplication, et elle est délibérée : la feuille de détail doit fonctionner hors ligne, et lui
  faire appeler le serveur reviendrait à mettre le jeton d'abonnement dans une URL ouverte par le
  navigateur — exactement ce que le 034 a refusé pour l'export. Les deux ne partagent que la
  RFC 5545 et l'identifiant d'événement, qui est celui de l'attribution.
- **Le flux ne remonte que 90 jours en arrière.** L'historique n'est jamais supprimé
  (`docs/PRD.md § 7.6`), mais un agenda rapatrie tout le fichier à chaque rafraîchissement, toutes
  les heures, pour tous les membres. Trois mois couvrent largement « c'était quand, ma dernière
  garde ? » ; l'écran « Mes astreintes » garde le reste.
