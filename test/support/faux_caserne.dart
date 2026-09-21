import 'package:astreinte_sp/core/caserne/caserne_repository.dart';
import 'package:astreinte_sp/core/caserne/etat_caserne.dart';

import 'faux_abonnement.dart';

/// L'état par défaut de tous les tests : une caserne en essai, qui écrit.
///
/// `finEssaiSeed` est le 20 novembre et `maintenantTest` le 21 septembre :
/// **60 jours d'écart**, donc aucune bannière d'essai. Un écran qui en affiche
/// une dans un test qui n'a rien demandé est un écran qui se trompe de seuil.
final EtatCaserne caserneEnEssai = EtatCaserne(
  statut: StatutAbonnement.essai,
  ecriture: true,
  finEssai: finEssaiSeed,
);

/// Un essai qui se termine dans [jours] jours, compté depuis `maintenantTest`.
EtatCaserne caserneEssaiDans(int jours) => EtatCaserne(
  statut: StatutAbonnement.essai,
  ecriture: true,
  finEssai: maintenantTest.add(Duration(days: jours)),
);

/// Une caserne suspendue : lecture seule, avec la date de bascule.
final EtatCaserne caserneSuspendue = EtatCaserne(
  statut: StatutAbonnement.suspendu,
  ecriture: false,
  finEssai: finEssaiSeed,
  suspendueLe: DateTime(2026, 9, 4),
);

/// Le faux dépôt de l'état de caserne.
class FauxCaserneRepository implements CaserneRepository {
  FauxCaserneRepository([EtatCaserne? etat]) : etat = etat ?? caserneEnEssai;

  EtatCaserne etat;

  /// Combien de fois l'état a été lu. Un écran qui relit à chaque geste ferait
  /// une requête par case peinte.
  int lectures = 0;

  @override
  Future<EtatCaserne> lire(String stationId) async {
    lectures++;
    return etat;
  }
}
