# 034 — RGPD : export et suppression des données

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Bref : ce ticket **remplit trois places déjà réservées** par le
007 et ajoute deux pages de texte.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Les écarts constatés à
l'implémentation sont au § 7.

Sources : `docs/PRD.md § 8` (RGPD), `§ 7` règle 6 ; `docs/SCHEMA.md § 2` table par table, `§ 7` ;
`design/007-profil.md § 4`, `§ 5.3` et la mention « la place du ticket 034 » ;
`tickets/in-progress/034-rgpd-export.md` ; `docs/RGPD.md` (écrit par ce ticket).

---

## 1. Les trois places réservées, et ce qu'on y pose

| Place | Réservée par | Ce qu'on y pose |
|---|---|---|
| Bloc « Ton compte », entre le filet et la suppression | `BlocCompte`, commentaire « le ticket 034 pose ici » | `BoutonExportDonnees`, variante **secondaire** |
| Feuille de suppression, au-dessus du bouton rouge | `FeuilleSuppression`, même commentaire | le **même** bouton, précédé d'une phrase : « Récupère d'abord tes données » |
| Bas du bloc « Ton compte » | rien | deux liens de texte : « Confidentialité » et « Mentions légales » |

Un seul composant pour les deux premières places. Le bouton d'export n'a pas deux comportements
selon l'endroit : il demande le fichier, il le range, il dit ce qu'il a fait.

## 2. Job et audience

**Quelqu'un qui s'apprête à partir, ou qui veut simplement voir ce que l'application sait de lui.**
Deux fois dans la vie d'un compte, pas plus. Ce n'est donc pas un écran, c'est **un bouton et une
phrase** — et la phrase compte autant que le bouton, parce qu'un fichier JSON qui tombe dans les
téléchargements sans un mot n'a rien prouvé à personne.

Le second public est réel et invisible : **le chef de centre qui doit répondre à une question de
sa mairie** sur ce que l'outil collecte. C'est à lui que s'adressent les deux pages de texte et
`docs/RGPD.md`.

## 3. Résultat et preuve

**Résultat.** Je pars avec tout ce qui me concerne, dans un fichier que je peux rouvrir dans dix
ans, et je sais ce qui reste.

**Preuve, dans l'ordre :**

1. Une touche sur « Exporter mes données » produit un fichier nommé, daté, lisible, et l'écran me
   **dit** qu'il est parti — pas seulement la barre de téléchargement du navigateur, qui n'existe
   pas dans une PWA installée.
2. Le fichier contient mon profil, mes casernes, mes disponibilités, mes préférences, mes
   astreintes, mes notifications, mes appareils, mes invitations, et le journal des actes
   d'administration qui me concernent. Il ne contient **le nom de personne d'autre**.
3. Au moment de supprimer, la sortie est proposée **avant** le bouton rouge, jamais après.
4. « Confidentialité » répond en français simple à : qu'est-ce qui est collecté, pourquoi,
   combien de temps, qui le voit, et comment je m'y oppose.

## 4. Le bouton d'export : quatre états, une ligne d'état

```
┌ Ton compte ──────────────────────────┐
│ [Se déconnecter]                     │
│ ── filet ──                          │
│ [Exporter mes données]   (secondaire)│
│ ⓘ Fichier JSON, tout ce que…         │   ← la phrase, toujours visible
│ ✓ Fichier enregistré : astreinte-…   │   ← liveRegion, après coup
│ [Supprimer mon compte]   (danger)    │
│ ── filet ──                          │
│ Confidentialité · Mentions légales   │
└──────────────────────────────────────┘
```

| État | Ce qu'on voit |
|---|---|
| Au repos | Le bouton, et sous lui la phrase qui dit ce que contient le fichier |
| En cours | `PrimaryButton.chargement` : libellé inchangé, indicateur de 20 dp devant, largeur figée |
| Enregistré | Ligne `liveRegion` : « Fichier enregistré : *nom du fichier* » |
| Partagé (iOS) | Ligne `liveRegion` : « Fichier envoyé au partage. » — le geste suivant appartient à iOS |
| Annulé | **Rien.** Refermer la feuille de partage n'est pas une erreur, et une erreur qui n'en est pas une apprend aux gens à ne plus lire |
| Refusé / en panne | Ligne `liveRegion` en `error`, icône `error_outline`, le motif **et** la sortie |

Pas de toast : l'écran de profil n'a pas de `ScaffoldMessenger` de confiance dans une feuille
modale, et `DESIGN.md § 6` du 007 a déjà tranché — le résultat d'une action se lit sur place.

## 5. Les quatre décisions

### 5.1 Le fichier est rangé par le navigateur, pas ouvert dans un onglet

`window.open` est le geste qui marche dans un onglet et **casse dans une PWA installée** : en
`display-mode: standalone`, il n'y a pas de barre d'adresse, et le navigateur ouvre soit une
fenêtre hors de l'application, soit rien du tout. L'export utilise donc un objet `Blob`, une
ancre `download`, un clic programmatique, et libère l'URL derrière lui.

Sur **iOS installé**, l'attribut `download` reste inégal ; quand `navigator.canShare({files})`
répond oui, on passe par la feuille de partage du système — « Enregistrer dans Fichiers » est
exactement le geste attendu là-bas. Le repli est l'ancre, dans tous les autres cas. Trois
résultats distincts remontent à l'écran (`enregistre`, `partage`, `annule`) parce qu'ils se
disent différemment.

### 5.2 L'export est proposé dans la feuille, il ne l'interrompt pas

Dans la feuille de suppression, le bouton d'export est **au-dessus** du bouton rouge, en variante
secondaire, précédé d'une phrase courte. Il ne ferme pas la feuille, il ne bloque pas la
suppression, et il ne devient pas une étape obligatoire : forcer un téléchargement avant de
partir, c'est retenir quelqu'un qui a décidé.

L'ordre de lecture devient : ce qui part → ce qui reste → **récupère-le d'abord** → supprimer →
annuler. La dernière sortie est juste avant le point de non-retour, ce qui est sa seule place
utile.

### 5.3 Deux pages de texte, pas une modale, pas un lien sortant

La politique de confidentialité et les mentions légales sont **des routes** :
`/legal/confidentialite` et `/legal/mentions`. Trois raisons, dans l'ordre d'importance :

1. Une politique de confidentialité doit être lisible **sans compte** — par une mairie, par un
   candidat à l'invitation, par quelqu'un qui a reçu un courriel. Les deux routes traversent donc
   `redirectionAuth` sans condition, comme le lien d'invitation.
2. Elle doit avoir une **URL** qu'on colle dans un courriel ou dans une délibération.
3. Elle doit rester lisible quand elle fait quatre écrans de haut, ce qu'une feuille ne permet pas.

Les deux pages partagent une mise en page : `EcranSimple` (pas de navigation — un visiteur non
connecté n'en a pas), un titre, une date de version, des sections `titre + paragraphes`, et un
pied qui renvoie vers l'autre page. Aucune chaîne dans les widgets : les deux documents sont des
**données** (`features/legal/domain/documents_legaux.dart`), le widget ne fait que les rendre.

### 5.4 Ce qui n'est pas décidé se voit

Raison sociale, adresse, directeur de la publication, hébergeur contractuel, contact du
responsable de traitement : ce sont des décisions du propriétaire, pas du code. Chacune apparaît
telle quelle dans la page sous la forme `[À COMPLÉTER : …]`, en `titleSmall` sur
`surface-container-high`, **visible**, jamais un texte plausible inventé. Une mention légale
fausse est pire qu'une mention légale trouée : la seconde se corrige, la première se croit.

## 6. Accessibilité

- Le bouton d'export est un `PrimaryButton` : 52 dp de haut, pleine largeur sur compact, icône
  `download` 20 dp.
- Chaque résultat passe par une région `liveRegion` — un fichier enregistré sans barre de
  téléchargement (PWA installée) n'est **annoncé par rien d'autre**.
- Les deux liens de bas de bloc sont des `TextButton` de 48 dp de haut, séparés de 8 dp, jamais
  deux mots collés dans un `RichText`.
- Les pages légales : `Semantics(header: true)` sur le titre et sur chaque titre de section, ordre
  de lecture = ordre visuel, aucune information portée par la seule couleur.

## 7. Écarts constatés à l'implémentation

1. **Le fichier est construit dans le navigateur, pas servi par le serveur.** L'Edge Function rend
   du JSON ; c'est le client qui compose le nom, met en forme et déclenche l'enregistrement. Servir
   un `Content-Disposition` demanderait une URL signée que le navigateur visite lui-même — donc un
   jeton d'accès dans une URL, donc dans l'historique. Le détour par le SDK garde le jeton dans
   un en-tête.
2. **Le nom du fichier porte la date, pas l'heure** : `astreinte-sp-export-2026-09-21.json`. Deux
   exports le même jour donnent deux fichiers au même nom, et c'est le navigateur qui numérote —
   comportement attendu partout ailleurs.
3. **Les liens légaux sont aussi dans l'écran de connexion**, en pied : c'est le seul écran qu'un
   visiteur non connecté voit, et une politique de confidentialité joignable seulement une fois
   connecté ne remplit pas son office.
