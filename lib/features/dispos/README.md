# features/dispos — « Mon mois »

L'écran le plus ouvert du produit : un membre y pose ses disponibilités du mois. Brief de
design : [`design/011-saisie-dispos-grille.md`](../../../design/011-saisie-dispos-grille.md).

| Fichier | Rôle |
|---|---|
| `data/dispos_repository.dart` | `periods` et `availabilities`. **Le contrat de coût est dans l'interface** : `enregistrerLot` et `supprimerLot` valent chacune exactement une requête PostgREST, et rendent le nombre de lignes affectées. |
| `domain/creneau_cle.dart` | `(date, créneau)` — la clé d'unicité de `docs/SCHEMA.md § 2.6`, et celle de la file d'écriture. C'est elle qui rend la coalescence gratuite. |
| `domain/periode_saisie.dart` | Une ligne de `periods`, plus le choix du mois par défaut. |
| `domain/disponibilite_mois.dart` | La carte du mois, les trois compteurs, l'unité de weekend, le cycle de la case. |
| `domain/dispos_providers.dart` | Dépôt, périodes, mois sélectionné, période courante. |
| `presentation/controllers/saisie_controller.dart` | Le cycle, la peinture, la file, le délai, les relances, l'annulation. |
| `presentation/mois_screen.dart` | L'écran et sa composition par classe de fenêtre. |
| `presentation/widgets/` | Sélecteur de mois, en-tête épinglé, registre, calendrier, ligne de jour, barre de compteurs, bloc d'aide. |

## Les deux invariants

1. **Rien ne part sur le réseau pendant un geste.** Le délai de 500 ms ne démarre qu'au
   relâchement. C'est ce qui rend l'annulation gratuite, et ce qui fait d'un mois peint **une**
   transition d'indicateur au lieu de quarante.
2. **La file est une `Map<CreneauCle, …>`**, donc coalescée par construction. Elle part en deux
   requêtes au plus : un envoi groupé, une suppression groupée. Mesuré dans Chrome : une colonne
   de trente nuits peinte d'un geste coûte **une** requête.

## Le piège des lignes affectées

En période verrouillée ou caserne suspendue, la clause `using` de la politique RLS **filtre sans
lever** : un `update` ou un `delete` refusé répond « 0 ligne, tout va bien »
(`supabase/README.md`, ticket 008). Le contrôleur compare donc systématiquement le nombre de
lignes rendues au nombre envoyé. Une case revenue à « non saisi » sans avoir jamais eu de ligne
n'est pas envoyée du tout : une requête de moins, et un « 0 ligne » de moins à interpréter.

## Ce qui n'est pas ici

Les raccourcis de sélection (ticket 012) et les quotas du mois (ticket 013). Leurs emplacements
sont réservés dans `mois_screen.dart` et **laissés vides** : pas de bouton fantôme, pas de place
dessinée. Les trois `CountStat` sont déjà construits avec `plafond: null`.
