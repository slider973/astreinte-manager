import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import 'membre_caserne.dart';

/// Ce qu'un admin peut faire à un membre de sa caserne.
///
/// Cinq actes, pas un de plus : **supprimer un membre n'existe pas**.
/// L'historique n'est jamais effacé (`docs/PRD.md § 8`), la ligne
/// `memberships` reste et c'est la désactivation qui coupe l'accès.
enum ActionMembre {
  renommer(AppStrings.membreActionRenommer),
  promouvoir(AppStrings.membreActionPromouvoir),
  retrograder(AppStrings.membreActionRetrograder),
  desactiver(AppStrings.membreActionDesactiver),
  reactiver(AppStrings.membreActionReactiver);

  const ActionMembre(this.libelle);

  final String libelle;
}

/// Pourquoi une action d'administration est interdite.
///
/// Les deux motifs sont ceux du déclencheur `memberships_guard_admin`
/// (migration `0010`), dans le même ordre : l'interface dit **avant** le geste
/// ce que la base dirait après.
enum RefusAdministration {
  /// La caserne se retrouverait sans administrateur actif.
  dernierAdmin(AppStrings.membreRefusDernierAdmin),

  /// Un admin ne se retire pas son propre accès.
  soiMeme(AppStrings.membreRefusSoiMeme);

  const RefusAdministration(this.message);

  final String message;
}

/// Ce que l'écran a besoin de savoir pour arbitrer une action.
@immutable
class ContexteAdministration {
  const ContexteAdministration({
    required this.adminsActifs,
    required this.userIdCourant,
  });

  /// Nombre d'administrateurs **actifs** de la caserne, celui-là même que le
  /// déclencheur compte côté base.
  final int adminsActifs;

  /// L'utilisateur connecté, ou `null` si la session n'est pas encore lue.
  final String? userIdCourant;

  bool estMoi(MembreCaserne membre) =>
      userIdCourant != null && membre.userId == userIdCourant;
}

/// Le motif de refus d'une action sur un membre, ou `null` si elle est permise.
///
/// Fonction pure, testée seule : c'est elle qui décide qu'une ligne d'action
/// s'affiche inerte avec sa phrase, plutôt que d'attendre le refus du serveur.
///
/// L'ordre des deux motifs suit celui du déclencheur (`0010`) : « dernier
/// admin » gagne sur « soi-même », parce que le chef de centre seul à bord a
/// besoin qu'on lui dise de nommer quelqu'un, pas d'aller demander à un autre
/// administrateur qui n'existe pas.
RefusAdministration? refusPour({
  required ActionMembre action,
  required MembreCaserne membre,
  required ContexteAdministration contexte,
}) {
  final retireLAdmin =
      action == ActionMembre.retrograder || action == ActionMembre.desactiver;
  if (!retireLAdmin || !membre.estAdminActif) return null;

  if (contexte.adminsActifs <= 1) return RefusAdministration.dernierAdmin;
  return contexte.estMoi(membre) ? RefusAdministration.soiMeme : null;
}

/// Les actions proposées pour ce membre, dans l'ordre d'affichage.
///
/// On ne propose jamais « Réactiver » un membre actif : une action sans objet
/// n'a rien à faire dans une feuille de dix secondes. Les actions **refusées**,
/// elles, restent visibles avec leur raison — c'est le refus qui instruit.
List<ActionMembre> actionsPour(MembreCaserne membre) => <ActionMembre>[
  ActionMembre.renommer,
  if (membre.estAdmin) ActionMembre.retrograder else ActionMembre.promouvoir,
  if (membre.estDesactive) ActionMembre.reactiver else ActionMembre.desactiver,
];
