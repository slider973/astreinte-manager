# features/propositions — répondre en deux touches

Le deuxième écran du produit. Un pompier reçoit une notification, l'ouvre, et accepte. Deux
touches, chronométrables. Brief de design :
[`design/021-ecran-propositions.md`](../../../design/021-ecran-propositions.md).

| Fichier | Rôle |
|---|---|
| `data/propositions_repository.dart` | `assignments`, jointe à `shifts` et `schedules`. Une requête pour lire, une pour répondre, une colonne pour constater une validation. |
| `domain/proposition.dart` | Une astreinte proposée et sans réponse, plus l'aplatissement en éléments de liste groupés par mois. |
| `domain/propositions_providers.dart` | Le contrôleur, la pastille de l'onglet et les éléments affichés. |
| `presentation/propositions_screen.dart` | L'écran, ses bannières et ses états. |
| `presentation/widgets/ligne_proposition.dart` | La ligne du registre et sa rangée de deux boutons. |
| `presentation/widgets/feuille_refus.dart` | Le refus et son motif court facultatif. |
| `presentation/widgets/squelette_propositions.dart` | Le chargement, à la forme du contenu attendu. |

## Les trois invariants

### 1. La charge utile est construite à la main, clé par clé

`assignments_member_transition` (`docs/SCHEMA.md § 4`) compare `to_jsonb(new)` à `to_jsonb(old)`
en dehors d'une liste blanche de quatre colonnes. **Une colonne de trop fait échouer la requête
entière**, même à valeur identique — pas seulement le champ ajouté.

Conséquence : aucun modèle de cette fonctionnalité n'expose de `toJson()`. La charge vaut
`{'status': 'accepted'}`, ou `{'status': 'declined', 'decline_reason': '…'}` quand un motif a été
écrit. `responded_at` est posé par la base ; l'envoyer serait envoyer l'heure du téléphone.

`test/features/propositions/propositions_domaine_test.dart` lit le source du dépôt et échoue si
une septième colonne s'y glisse un jour.

### 2. L'`update` porte `status = 'proposed'` dans son `where`

Sans cette condition, une attribution annulée ou réattribuée entre-temps déclencherait
`invalid transition` et l'écran verrait une panne là où il y a une nouvelle. Avec elle, **zéro
ligne touchée** est la réponse propre du cas « ce créneau ne t'est plus proposé », et l'écran
affiche une bannière d'information — jamais de rouge, jamais un échec.

### 3. La réponse est optimiste

La ligne part avant la confirmation du serveur, et l'écriture suit. En 4G rurale, un aller-retour
coûte de 300 ms à 3 s : un écran qui attend transforme « deux touches » en « deux touches et une
attente ». Un échec réseau remet la ligne **à sa place exacte** — le pouce la cherche là où elle
était.

## Ce qui n'est pas ici, et pourquoi

- **Pas de canal temps réel.** Trente pompiers par caserne, quarante secondes de présence chacun :
  une connexion permanente par téléphone pour un événement qu'ils ne verront pas. Ce qui la
  remplace : une relecture au retour de l'application au premier plan, un geste de tirage, une
  action dans la barre d'application, et la vérité à la touche (invariant 2).
- **Pas « Mes astreintes ».** Une proposition répondue disparaît d'ici. La liste des gardes
  acceptées est le ticket 027.
- **Pas de réattribution.** C'est le ticket 020 ; cet écran doit y **survivre**, pas la provoquer.
- **Pas de modification d'une réponse déjà donnée.** `declined` est terminal
  (`docs/WORKFLOWS.md § 3`), et un bouton qui échouerait à tous les coups est pire que pas de
  bouton.

## Le contrôleur n'est pas auto-disposé

La pastille de l'onglet lit le même état depuis la coquille d'accueil, donc depuis tous les
écrans. Auto-disposé, le compte repartirait de zéro — donc clignoterait — à chaque changement
d'onglet. Même raisonnement, mêmes mots, que le centre de notifications (ticket 026).
