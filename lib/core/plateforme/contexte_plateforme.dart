import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'detection_stub.dart' if (dart.library.js_interop) 'detection_web.dart';

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
    this.libelleAppareil = _libelleInconnu,
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
      libelleAppareil: _libelleDepuis(userAgent),
    );
  }

  static const String _libelleInconnu = 'Appareil';

  final NavigateurInstallation navigateur;

  /// Vrai quand la page tourne déjà comme une application installée.
  final bool autonome;

  /// Vrai sur le web. Faux dans un build iOS ou Android natif.
  final bool web;

  /// De quoi reconnaître cet appareil dans une liste : « iPhone · Safari »,
  /// « Pixel 7 · Chrome », « Mac · Chrome ».
  ///
  /// C'est `push_tokens.device_label` (`docs/SCHEMA.md § 2.11`), donc du texte
  /// lu par un humain — jamais une empreinte. On ne garde que la marque de
  /// l'appareil et le nom du navigateur ; ni version, ni système, ni rien qui
  /// distingue deux téléphones du même modèle.
  final String libelleAppareil;

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

  /// « Modèle · Navigateur », ou le plus proche que l'agent utilisateur
  /// permette. Les agents modernes mentent beaucoup : quand on ne sait pas, on
  /// écrit « Appareil » plutôt que de deviner.
  static String _libelleDepuis(String userAgent) {
    final agent = userAgent.toLowerCase();

    final String appareil;
    if (agent.contains('iphone')) {
      appareil = 'iPhone';
    } else if (agent.contains('ipad')) {
      appareil = 'iPad';
    } else if (agent.contains('android')) {
      appareil = _modeleAndroid(userAgent) ?? 'Android';
    } else if (agent.contains('macintosh') || agent.contains('mac os')) {
      appareil = 'Mac';
    } else if (agent.contains('windows')) {
      appareil = 'PC Windows';
    } else if (agent.contains('linux')) {
      appareil = 'Ordinateur';
    } else {
      appareil = _libelleInconnu;
    }

    final String? navigateur;
    if (agent.contains('crios') || agent.contains('fxios')) {
      navigateur = agent.contains('crios') ? 'Chrome' : 'Firefox';
    } else if (agent.contains('samsungbrowser')) {
      navigateur = 'Samsung Internet';
    } else if (agent.contains('edg')) {
      navigateur = 'Edge';
    } else if (agent.contains('opr/')) {
      navigateur = 'Opera';
    } else if (agent.contains('firefox')) {
      navigateur = 'Firefox';
    } else if (agent.contains('chrome')) {
      navigateur = 'Chrome';
    } else if (agent.contains('safari')) {
      navigateur = 'Safari';
    } else {
      navigateur = null;
    }

    return navigateur == null ? appareil : '$appareil · $navigateur';
  }

  /// `Linux; Android 14; Pixel 7)` → `Pixel 7`. Les agents qui n'ont pas cette
  /// forme renvoient `null`.
  static String? _modeleAndroid(String userAgent) {
    final trouve = RegExp(
      r'Android [^;)]+;\s*([^;)]+)',
    ).firstMatch(userAgent);
    final modele = trouve?.group(1)?.trim();
    if (modele == null || modele.isEmpty) return null;
    // « Build/… » et « wv » ne disent rien à un humain.
    final propre = modele.split(' Build/').first.trim();
    return propre.isEmpty || propre == 'wv' ? null : propre;
  }

  @override
  bool operator ==(Object other) =>
      other is ContextePlateforme &&
      other.navigateur == navigateur &&
      other.autonome == autonome &&
      other.web == web &&
      other.libelleAppareil == libelleAppareil;

  @override
  int get hashCode => Object.hash(navigateur, autonome, web, libelleAppareil);
}

/// Le contexte de la plateforme courante. Surchargé dans les tests.
final Provider<ContextePlateforme> contextePlateformeProvider =
    Provider<ContextePlateforme>((ref) => detecterContextePlateforme());
