import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'detection_stub.dart'
    if (dart.library.js_interop) 'detection_web.dart';

/// Le navigateur, vu sous le seul angle qui nous intéresse : comment on y
/// ajoute l'application à l'écran d'accueil.
enum NavigateurInstallation {
  /// Safari sur iPhone ou iPad : bouton Partager, « Sur l'écran d'accueil ».
  /// **Le seul chemin vers les notifications sur iOS.**
  safariIos,

  /// Chrome sur Android : menu à trois points, « Installer l'application ».
  chromeAndroid,

  /// Tout le reste : navigateur de bureau, navigateur tiers sur iOS, appli
  /// native. On ne devine pas une procédure qu'on ne connaît pas.
  autre,
}

/// Où tourne l'application, du point de vue de l'aide à l'installation.
///
/// Construit par [ContextePlateforme.depuisAgent], une fonction pure : la
/// détection se teste sans navigateur.
@immutable
class ContextePlateforme {
  const ContextePlateforme({
    required this.navigateur,
    required this.autonome,
    required this.web,
  });

  /// Hors du web : rien à installer, rien à expliquer.
  static const ContextePlateforme natif = ContextePlateforme(
    navigateur: NavigateurInstallation.autre,
    autonome: true,
    web: false,
  );

  /// Déduit le contexte de l'agent utilisateur et du mode d'affichage.
  ///
  /// [affichageAutonome] vient de `matchMedia('(display-mode: standalone)')`,
  /// [autonomeIos] de `navigator.standalone`, que Safari est seul à porter.
  factory ContextePlateforme.depuisAgent({
    required String userAgent,
    bool affichageAutonome = false,
    bool autonomeIos = false,
  }) {
    return ContextePlateforme(
      navigateur: _navigateurDepuis(userAgent),
      autonome: affichageAutonome || autonomeIos,
      web: true,
    );
  }

  final NavigateurInstallation navigateur;

  /// Vrai quand la page tourne déjà comme une application installée.
  final bool autonome;

  /// Vrai sur le web. Faux dans un build iOS ou Android natif.
  final bool web;

  /// Vrai quand l'aide à l'installation a quelque chose à apprendre : on est
  /// sur le web, pas déjà installé, et on connaît la procédure du navigateur.
  bool get aideUtile =>
      web && !autonome && navigateur != NavigateurInstallation.autre;

  /// Les navigateurs tiers sur iOS ne sont pas classés `safariIos` : leur
  /// procédure diffère, et donner trois gestes faux est pire que se taire.
  static NavigateurInstallation _navigateurDepuis(String userAgent) {
    final agent = userAgent.toLowerCase();

    final iOS =
        agent.contains('iphone') ||
        agent.contains('ipad') ||
        agent.contains('ipod');
    if (iOS) {
      const tiers = <String>['crios', 'fxios', 'edgios', 'opios', 'yjapp'];
      final safari = !tiers.any(agent.contains);
      return safari
          ? NavigateurInstallation.safariIos
          : NavigateurInstallation.autre;
    }

    if (agent.contains('android') && agent.contains('chrome')) {
      const tiers = <String>['samsungbrowser', 'opr/', 'edga/', 'firefox'];
      final chrome = !tiers.any(agent.contains);
      return chrome
          ? NavigateurInstallation.chromeAndroid
          : NavigateurInstallation.autre;
    }

    return NavigateurInstallation.autre;
  }

  @override
  bool operator ==(Object other) =>
      other is ContextePlateforme &&
      other.navigateur == navigateur &&
      other.autonome == autonome &&
      other.web == web;

  @override
  int get hashCode => Object.hash(navigateur, autonome, web);
}

/// Le contexte de la plateforme courante. Surchargé dans les tests.
final Provider<ContextePlateforme> contextePlateformeProvider =
    Provider<ContextePlateforme>((ref) => detecterContextePlateforme());
