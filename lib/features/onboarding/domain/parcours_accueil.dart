import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/plateforme/contexte_plateforme.dart';
import '../../../core/preferences/reperes_locaux.dart';
import '../../../core/router/app_router.dart';
import '../../notifications/domain/etat_notifications.dart';
import '../../notifications/domain/notifications_providers.dart';

/// L'enchaînement des écrans d'accueil, décidé **avant** de naviguer.
///
/// Chaque étape ne s'affiche que si elle a quelque chose à apprendre : le
/// guide une seule fois, l'aide à l'installation une seule fois et seulement
/// si l'application n'est pas déjà installée, la proposition d'activer les
/// notifications une seule fois et seulement si elle peut aboutir. Décider
/// avant de naviguer évite d'afficher un écran pour le refermer aussitôt.
///
/// **Les notifications arrivent en dernier, jamais au premier lancement**
/// (ticket 024) : au premier lancement, personne ne sait encore ce qu'est une
/// proposition d'astreinte, et un refus d'autorisation ne se rattrape pas.
class ParcoursAccueil {
  const ParcoursAccueil(this._reperes, this._plateforme, this._etat);

  final ReperesLocaux _reperes;
  final ContextePlateforme _plateforme;

  /// L'état des notifications, lu au moment de décider — pas avant : le
  /// navigateur met un instant à répondre et rien ne presse.
  final Future<EtatNotifications> Function() _etat;

  /// Après le complément de profil.
  Future<String> apresLeProfil() async {
    if (!await _reperes.dejaVu(RepereAccueil.guide)) {
      return AppRoutes.guideName;
    }
    return apresLeGuide();
  }

  /// Après le guide — ou après l'avoir passé.
  Future<String> apresLeGuide() async {
    await _reperes.marquerVu(RepereAccueil.guide);

    if (!_plateforme.aideUtile) return _etapeNotifications();
    if (await _reperes.dejaVu(RepereAccueil.aideInstallation)) {
      return _etapeNotifications();
    }
    return AppRoutes.installationName;
  }

  /// Après l'aide à l'installation, vue ou remise à plus tard : elle ne
  /// revient pas d'elle-même.
  Future<String> apresLInstallation() async {
    await _reperes.marquerVu(RepereAccueil.aideInstallation);
    return _etapeNotifications();
  }

  /// Après la proposition d'activer les notifications, acceptée ou non.
  Future<String> apresLesNotifications() async {
    await _reperes.marquerVu(RepereAccueil.activationNotifications);
    return AppRoutes.accueilName;
  }

  /// La dernière étape, ou l'accueil quand elle n'a rien à dire.
  ///
  /// Trois états ne se montrent pas : pas de projet Firebase, build natif, ou
  /// navigateur incapable de recevoir un push. Dans ces trois cas, il n'y a
  /// ni promesse à faire ni geste à proposer — un écran qui annonce une
  /// impossibilité au milieu d'un accueil est du bruit. L'état reste lisible
  /// dans le profil pour qui le cherche.
  Future<String> _etapeNotifications() async {
    if (await _reperes.dejaVu(RepereAccueil.activationNotifications)) {
      return AppRoutes.accueilName;
    }

    final etat = await _etat();
    const muets = <EtatNotifications>{
      EtatNotifications.nonConfigure,
      EtatNotifications.horsWeb,
      EtatNotifications.nonSupporte,
    };
    if (muets.contains(etat)) {
      await _reperes.marquerVu(RepereAccueil.activationNotifications);
      return AppRoutes.accueilName;
    }

    return AppRoutes.activationNotificationsName;
  }
}

final Provider<ParcoursAccueil> parcoursAccueilProvider =
    Provider<ParcoursAccueil>(
      (ref) => ParcoursAccueil(
        ref.watch(reperesLocauxProvider),
        ref.watch(contextePlateformeProvider),
        () => ref.read(notificationsControllerProvider.future),
      ),
    );
