import '../../../core/plateforme/contexte_plateforme.dart';

/// L'autorisation du navigateur, telle qu'on peut la lire **sans la demander**.
enum PermissionPush {
  /// Jamais demandée : la fenêtre du navigateur ne s'est pas encore ouverte.
  aDemander,

  /// Accordée. Les notifications arrivent.
  accordee,

  /// Refusée. **Irréversible depuis l'application** : seul l'utilisateur peut
  /// revenir dessus dans les réglages de son navigateur. D'où toute la
  /// prudence du ticket sur le moment de la demande.
  refusee,
}

/// Où en sont les notifications, pour cet appareil et ce navigateur.
///
/// Un seul état à la fois, et chacun a **une phrase et une seule action**.
/// L'ordre de déclaration est l'ordre de décision de
/// [deciderEtatNotifications] : le premier fait vrai gagne.
enum EtatNotifications {
  /// Aucun projet Firebase n'est configuré, ou l'initialisation a échoué. Rien
  /// n'est proposé, rien n'est promis.
  nonConfigure,

  /// Build iOS ou Android : le push natif est le ticket 036.
  horsWeb,

  /// iPhone ou iPad, application **pas encore sur l'écran d'accueil**. Il n'y
  /// a rien à demander tant qu'elle n'y est pas : iOS ne délivre aucune
  /// notification à une page ouverte dans Safari.
  installationRequise,

  /// Le navigateur ne sait pas recevoir de push (Firefox sur iOS, navigation
  /// privée, WebView).
  nonSupporte,

  /// L'utilisateur a refusé. On ne redemande jamais : on explique la sortie.
  refusee,

  /// Tout est prêt, l'autorisation n'a pas encore été demandée.
  aDemander,

  /// Autorisation accordée : les notifications arrivent sur cet appareil.
  active;

  /// Vrai si demander l'autorisation a une chance d'aboutir. C'est la seule
  /// condition qui autorise à ouvrir la fenêtre du navigateur.
  bool get peutDemander => this == aDemander;

  /// Vrai si l'appareil peut porter un jeton push.
  bool get estActive => this == active;
}

/// Décide de l'état à afficher. Fonction pure : c'est elle qui est testée.
///
/// [installationRequise] passe **avant** [nonSupporte] : sur iPhone hors écran
/// d'accueil, le navigateur répond « je ne sais pas faire », mais la vraie
/// phrase à dire est « ajoute l'application à ton écran d'accueil ». Dire la
/// première serait exact et inutile ; la seconde est la seule actionnable.
EtatNotifications deciderEtatNotifications({
  required bool configure,
  required bool supporte,
  required ContextePlateforme plateforme,
  required PermissionPush permission,
}) {
  if (!plateforme.web) return EtatNotifications.horsWeb;
  if (!configure) return EtatNotifications.nonConfigure;

  if (plateforme.navigateur == NavigateurInstallation.safariIos &&
      !plateforme.autonome) {
    return EtatNotifications.installationRequise;
  }

  if (!supporte) return EtatNotifications.nonSupporte;

  return switch (permission) {
    PermissionPush.accordee => EtatNotifications.active,
    PermissionPush.refusee => EtatNotifications.refusee,
    PermissionPush.aDemander => EtatNotifications.aDemander,
  };
}
