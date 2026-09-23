# features/boite — le journal de bord, et ce à quoi il faut répondre

La quatrième destination du pompier (ticket 064), à la route `/boite`. Elle réunit depuis le
chantier **064b** les deux écrans qui vivaient à côté l'un de l'autre : le centre de notifications
du ticket 026 et les propositions du ticket 021. Brief de design :
[`design/064-monde-visuel-pompier.md § 3.4`](../../../design/064-monde-visuel-pompier.md).

| Fichier | Rôle |
|---|---|
| `domain/onglet_boite.dart` | Les trois onglets et leur mot dans l'URL. |
| `domain/composition_boite.dart` | La fusion des deux sources, l'état par onglet, la proposition dont la réponse est ouverte. |
| `presentation/boite_screen.dart` | L'écran : le titre, les onglets, les bannières, les deux gestes. |
| `presentation/widgets/liste_boite.dart` | Les trois listes, et la carte qui porte un rappel. |
| `presentation/widgets/panneau_reponse.dart` | La réponse : volet en `large`, feuille en dessous. |
| `presentation/widgets/squelette_boite.dart` | Le chargement, à la forme du contenu attendu. |

## Les quatre invariants

### 1. Aucune requête nouvelle

Les propositions viennent du contrôleur du ticket 021, les rappels de celui du ticket 026. La
Boîte ne fait que les assembler, et `core/router/prechargement_route.dart` les réveille tous les
deux sur `/boite`. Trois onglets qui relanceraient chacun leur lecture feraient six requêtes pour
un écran. Les heures d'affichage de la caserne voyagent avec les astreintes (ticket 027), dont le
contrôleur vit déjà depuis l'accueil ; tant qu'il n'a rien rendu, la Boîte affiche les valeurs par
défaut de la colonne `settings`, exactement ce que `lireHeuresAffichage` rend elle-même quand la
caserne est illisible.

### 2. L'onglet vit dans l'URL, jamais dans un cache

`/boite?onglet=propositions` est l'adresse de « Tout voir » de l'accueil, du lien public
`/proposals` et de l'ancienne route `/propositions`. Un onglet retenu sur l'appareil aurait fait
ouvrir la Boîte ailleurs que là où le lien promettait, et il aurait survécu à une déconnexion —
ce que la règle des caches de `CLAUDE.md` interdit. Une valeur inconnue tombe sur « Tout », qui
contient les deux autres : personne n'arrive sur une page qui ne montre pas ce qu'il cherchait.

### 3. Un rappel est une notification qui n'est pas une proposition

`assignment_proposed` et `assignment_reminder` posent la **même question** que la ligne de
proposition qui vit à côté, à ceci près que la ligne, elle, porte la réponse. Les afficher en
rappel aurait posé deux fois la même question, l'une répondable et l'autre non. Le compte de
non-lues suit la même règle — cloche, pastille de la barre et titre lisent `EtatCentre.nonLues` —
pour qu'aucune non-lue ne reste invisible **et** incomptée dans une pastille que plus aucun écran
ne saurait vider.

La règle porte sur le **type**, jamais sur la route : `assignment_changed` mène aussi à
`/proposals` (`supabase/functions/README.md § Liens profonds`), et c'est pourtant un rappel — une
réattribution est un fait, pas une question.

### 4. Une source en panne n'efface jamais l'autre

Les propositions restent justes quand les notifications tombent, et réciproquement. Chaque onglet
porte alors son propre bloc « Réessayer », dans le contenu et non en bannière (écart du ticket
023, repris au 064a). **La condition porte sur le contenu, jamais sur `hasValue` ni sur
`hasError` seul** : un `AsyncValue` en erreur garde la valeur du calcul précédent, et les deux
contrôleurs en produisent une avant même d'avoir lu. C'est le piège consigné au ticket 023 puis au
064a ; `test/features/boite/composition_boite_test.dart` l'éprouve sur le vrai contrôleur.

## Ce qui n'est pas ici, et pourquoi

- **Pas de section « Répondues ».** `EtatPropositions` ne porte que les propositions **en
  attente** : une réponse donnée quitte la liste (ticket 021). L'écran d'avant ne les montrait pas
  non plus, et le brief du 064b ne les demande que « si l'écran actuel les montre ». L'histoire des
  attributions se lit dans « Astreintes ».
- **Pas de glissement entre onglets.** Le contenu change sous la barre, il ne passe pas de côté :
  le ticket 063 a retiré le glissement entre destinations, et `DESIGN.md § Zones sûres` réserve les
  vingt-quatre premiers points du bord gauche au geste retour du navigateur, que le pompier utilise
  en PWA installée.
- **Pas de canal temps réel.** Une relecture à l'ouverture, une au retour de l'application au
  premier plan, un geste de tirage et un bouton dans la barre — les mêmes quatre moments que les
  deux écrans d'avant, et pour les mêmes raisons (`design/021 § 7.3`, `design/026 § 6`).
- **Pas de cloche dans la barre d'application.** Elle mènerait à l'écran qu'elle occupe. Le compte
  qu'elle porte ailleurs est dans le titre, « Boîte · 2 non lues ».
