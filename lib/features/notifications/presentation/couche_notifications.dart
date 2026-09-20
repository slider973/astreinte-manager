import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../domain/destination_push.dart';
import '../domain/message_push.dart';
import '../domain/notifications_providers.dart';

/// La couche qui branche les notifications sur l'application entière.
///
/// Posée dans `MaterialApp.router`, au-dessus de toutes les routes, parce
/// qu'un push ne choisit pas l'écran sur lequel il tombe. Elle fait trois
/// choses, et rien d'autre :
///
/// 1. **publie le jeton** de cet appareil dès qu'il y a une session et une
///    autorisation — donc à chaque lancement ;
/// 2. **montre la bannière** quand un message arrive au premier plan, cas où
///    le système n'affiche rien ;
/// 3. **ouvre la destination** quand une notification est touchée pendant que
///    l'application tourne en arrière-plan.
///
/// Sans configuration Firebase, les trois flux sont vides et cette couche ne
/// coûte qu'un `Stack` d'un seul enfant.
class CoucheNotifications extends ConsumerStatefulWidget {
  const CoucheNotifications({required this.child, super.key});

  final Widget child;

  /// Ce que la bannière laisse le temps de lire.
  ///
  /// Plus long que les 3 à 5 secondes d'un message passager habituel : le
  /// téléphone est posé, regardé avec un temps de retard, souvent manipulé
  /// avec des gants. Rien ne se perd si elle s'efface — le centre de
  /// notifications garde tout (ticket 026).
  static const Duration duree = Duration(seconds: 8);

  @override
  ConsumerState<CoucheNotifications> createState() =>
      _CoucheNotificationsState();
}

class _CoucheNotificationsState extends ConsumerState<CoucheNotifications> {
  MessagePush? _message;
  Timer? _effacement;

  @override
  void dispose() {
    _effacement?.cancel();
    super.dispose();
  }

  void _montrer(MessagePush message) {
    if (!message.affichable) return;
    _effacement?.cancel();
    setState(() => _message = message);
    _effacement = Timer(CoucheNotifications.duree, _fermer);
  }

  void _fermer() {
    _effacement?.cancel();
    if (!mounted) return;
    setState(() => _message = null);
  }

  /// Ouvre le lien public d'une notification, ou l'accueil si le lien est
  /// inconnu ou interdit — **sans message d'erreur** : le membre n'a rien fait
  /// de mal, et un lien peut dater d'avant une rétrogradation.
  void _ouvrir(String? lien) {
    _fermer();
    final admin = ref.read(appartenanceCouranteProvider)?.estAdmin ?? false;
    final destination = destinationInterne(lien, admin: admin);
    ref.read(appRouterProvider).go(destination ?? AppRoutes.accueil);
  }

  @override
  Widget build(BuildContext context) {
    // Le jeton part dès que les deux conditions sont réunies, dans l'ordre où
    // elles arrivent : la session peut précéder l'autorisation, ou l'inverse.
    ref.listen(notificationsControllerProvider, (_, suivant) {
      if (suivant.value?.estActive ?? false) _publier();
    });
    ref.listen(sessionProvider, (_, suivant) {
      if (suivant.value != null) _publier();
    });

    ref.listen(messagesPremierPlanProvider, (_, suivant) {
      final message = suivant.value;
      if (message != null) _montrer(message);
    });

    ref.listen(routesServiceWorkerProvider, (_, suivant) {
      final route = suivant.value;
      if (route != null) _ouvrir(route);
    });

    final message = _message;

    return Stack(
      children: <Widget>[
        widget.child,
        if (message != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Material(
                  type: MaterialType.transparency,
                  child: _Banniere(
                    message: message,
                    onVoir: message.route == null
                        ? null
                        : () => _ouvrir(message.route),
                    onFermer: _fermer,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _publier() => unawaited(ref.read(jetonPushProvider.notifier).publier());
}

/// Le bandeau d'un message reçu au premier plan.
///
/// Même composant signature que le reste de l'application
/// (`DESIGN.md § AppBanner`), variante `information` : c'est un fait, pas une
/// alarme. Il est **fermable**, parce qu'il décrit un événement et non un état
/// persistant.
class _Banniere extends StatelessWidget {
  const _Banniere({
    required this.message,
    required this.onFermer,
    this.onVoir,
  });

  final MessagePush message;
  final VoidCallback? onVoir;
  final VoidCallback onFermer;

  @override
  Widget build(BuildContext context) {
    final titre = message.titre?.trim().isNotEmpty ?? false
        ? message.titre!.trim()
        : AppStrings.notifBanniereSansTitre;
    final corps = message.corps?.trim();

    // `liveRegion` sans libellé propre : les deux textes de la bannière sont
    // lus tels quels, et le bouton de fermeture garde le sien. Un libellé de
    // conteneur les doublerait.
    return Semantics(
      liveRegion: true,
      container: true,
      child: AppBanner(
        variante: AppBannerVariante.information,
        icone: Icons.notifications_active_outlined,
        texte: titre,
        detail: corps,
        libelleAction: onVoir == null ? null : AppStrings.notifBanniereVoir,
        onAction: onVoir,
        onFermer: onFermer,
        libelleFermer: AppStrings.notifBanniereFermer,
      ),
    );
  }
}
