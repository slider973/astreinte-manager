import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/plateforme/contexte_plateforme.dart';
import '../../../core/preferences/reperes_locaux.dart';
import '../../../core/router/app_router.dart';

/// L'enchaînement des écrans d'accueil, décidé **avant** de naviguer.
///
/// Chaque étape ne s'affiche que si elle a quelque chose à apprendre : le
/// guide une seule fois, l'aide à l'installation une seule fois et seulement
/// si l'application n'est pas déjà installée. Décider avant de naviguer évite
/// d'afficher un écran pour le refermer aussitôt.
class ParcoursAccueil {
  const ParcoursAccueil(this._reperes, this._plateforme);

  final ReperesLocaux _reperes;
  final ContextePlateforme _plateforme;

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

    if (!_plateforme.aideUtile) return AppRoutes.accueilName;
    if (await _reperes.dejaVu(RepereAccueil.aideInstallation)) {
      return AppRoutes.accueilName;
    }
    return AppRoutes.installationName;
  }

  /// Après l'aide à l'installation, vue ou remise à plus tard : elle ne
  /// revient pas d'elle-même.
  Future<String> apresLInstallation() async {
    await _reperes.marquerVu(RepereAccueil.aideInstallation);
    return AppRoutes.accueilName;
  }
}

final Provider<ParcoursAccueil> parcoursAccueilProvider =
    Provider<ParcoursAccueil>(
      (ref) => ParcoursAccueil(
        ref.watch(reperesLocauxProvider),
        ref.watch(contextePlateformeProvider),
      ),
    );
