import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fraicheur/fraicheur.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/bascule_caserne.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../domain/centre_providers.dart';
import '../domain/destination_push.dart';
import '../domain/message_push.dart';
import '../domain/notifications_providers.dart';

/// La couche qui branche les notifications sur l'application entière.
///
/// Posée dans `MaterialApp.router`, au-dessus de toutes les routes, parce
/// qu'un push ne choisit pas l'écran sur lequel il tombe. Elle fait quatre
/// choses, et rien d'autre :
///
/// 1. **publie le jeton** de cet appareil dès qu'il y a une session et une
///    autorisation — donc à chaque lancement ;
/// 2. **montre la bannière** quand un message arrive au premier plan, cas où
///    le système n'affiche rien ;
/// 3. **ouvre la destination** quand une notification est touchée pendant que
///    l'application tourne en arrière-plan ;
/// 4. **tient le centre de notifications à jour** (ticket 026) ;
/// 5. **dit quelle caserne est ouverte** après une bascule automatique —
///    notification d'une autre caserne, lien, accès retiré (ticket 072). Une
///    seule bannière à la fois : celle de la bascule remplace celle du push.
///
/// Le quatrième point mérite son explication. `docs/SCHEMA.md § 9` annonce le
/// temps réel sur `notifications`, mais **il n'est pas encore posé** : aucune
/// table n'est dans la publication `supabase_realtime`, ce qui se vérifie en
/// une requête sur la base locale, et aucune migration ne l'y met. S'abonner
/// quand même donnerait un canal silencieux qui ne lève jamais — la pire des
/// pannes, celle qui a l'air de marcher.
///
/// La liste et la pastille sont donc relues à trois moments : un push reçu au
/// premier plan (le message **est** le signal), une notification touchée
/// depuis l'arrière-plan, et le retour de l'application au premier plan. Ils
/// sont ici, et pas dans l'écran, pour que la pastille se mette à jour quel
/// que soit l'écran affiché. À reprendre quand le ticket 017 posera la
/// publication.
///
/// Sans configuration Firebase, les flux de push sont vides et cette couche se
/// réduit à la relecture du centre au premier plan, dans un `Stack` d'un seul
/// enfant.
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

  /// La bascule automatique annoncée, s'il y en a une. Copiée de
  /// `basculeCaserneProvider` : le bandeau s'efface à sa propre minuterie.
  BasculeAutomatique? _bascule;

  /// Le retour de l'application au premier plan relit le centre, comme
  /// l'écran « Membres » relit ses invitations (ticket 009). C'est le seul
  /// moment où l'on peut apprendre ce qui est arrivé pendant que la PWA était
  /// rangée et que le push n'a rien affiché.
  late final AppLifecycleListener _cycleDeVie;

  @override
  void initState() {
    super.initState();
    _cycleDeVie = AppLifecycleListener(onResume: _relireLeCentre);
  }

  @override
  void dispose() {
    _cycleDeVie.dispose();
    _effacement?.cancel();
    super.dispose();
  }

  void _relireLeCentre() {
    if (!mounted) return;
    unawaited(ref.read(centreNotificationsProvider.notifier).rafraichir());
  }

  /// **Un push annonce une nouveauté ailleurs que dans le centre** (ticket
  /// 070) : une proposition, un planning validé, un mois ouvert. Les écrans
  /// qui les montrent — l'accueil d'abord, son « Propositions » et ses
  /// astreintes — sont relus tout de suite, délai minimal ou pas : c'est un
  /// événement, pas une grappe de retours au premier plan.
  void _relireCeQuiAChange() {
    if (!mounted) return;
    unawaited(
      ref.read(fraicheurProvider).maintenant(const <Donnee>{
        Donnee.propositions,
        Donnee.astreintes,
        Donnee.periodes,
      }),
    );
  }

  void _montrer(MessagePush message) {
    if (!message.affichable) return;
    _effacement?.cancel();
    setState(() {
      _message = message;
      _bascule = null;
    });
    _programmerEffacement();
  }

  /// **Huit secondes, sauf sous un lecteur d'écran ou au clavier**
  /// (`design/072 § 6.3`) : la bannière attend alors « Fermer ». Rien ne se
  /// perd si elle s'efface — le centre garde la notification, le sélecteur
  /// garde le nom de la caserne.
  void _programmerEffacement() {
    _effacement?.cancel();
    final accessible =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    if (accessible) return;
    _effacement = Timer(CoucheNotifications.duree, _fermer);
  }

  void _fermer() {
    _effacement?.cancel();
    if (!mounted) return;
    final bascule = _bascule;
    setState(() {
      _message = null;
      _bascule = null;
    });
    if (bascule != null) ref.read(basculeCaserneProvider.notifier).oublier();
  }

  /// Ouvre le lien public d'une notification, ou l'accueil si le lien est
  /// inconnu ou interdit — **sans message d'erreur** : le membre n'a rien fait
  /// de mal, et un lien peut dater d'avant une rétrogradation.
  ///
  /// **D'abord la caserne** (ticket 072, `docs/WORKFLOWS.md § 8`) : une
  /// notification d'une autre caserne où le compte est membre actif fait
  /// basculer l'application avant d'ouvrir le lien, et le rôle qui décide de
  /// la destination est celui de **cette** caserne. Une caserne où l'accès
  /// n'est plus actif ne fait rien basculer : l'accueil, sans message.
  void _ouvrir(String? lien, {String? stationId}) {
    _fermer();
    final cible = ref
        .read(basculeCaserneProvider.notifier)
        .ouvrirPour(stationId, raison: RaisonBascule.notification);
    final destination = cible == null
        ? null
        : destinationInterne(lien, admin: cible.estAdmin);
    ref.read(appRouterProvider).go(destination ?? AppRoutes.accueil);
  }

  /// « Revenir à {ancienne} » : l'ancienne caserne et son accueil — la
  /// destination ouverte par la notification n'a pas d'équivalent garanti
  /// là-bas.
  void _revenir() {
    _effacement?.cancel();
    setState(() => _bascule = null);
    ref.read(basculeCaserneProvider.notifier).revenir();
    ref.read(appRouterProvider).go(AppRoutes.accueil);
  }

  /// Le nom de la caserne d'un message, **s'il vient d'une autre caserne que
  /// celle qui est ouverte** et où le compte est membre actif.
  String? _autreCaserne(MessagePush message) {
    final stationId = message.stationId;
    if (stationId == null) return null;
    if (stationId == ref.read(appartenanceCouranteProvider)?.stationId) {
      return null;
    }
    for (final appartenance in ref.read(appartenancesActivesProvider)) {
      if (appartenance.stationId == stationId) return appartenance.nomCaserne;
    }
    return null;
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
      if (message == null) return;
      _montrer(message);
      // La ligne interne a été écrite **avant** l'envoi (ticket 025) : elle
      // est donc déjà en base quand le message arrive. C'est ce qui permet de
      // tenir « la notification apparaît dans la liste sans relancer l'app »
      // sans temps réel.
      _relireLeCentre();
      _relireCeQuiAChange();
    });

    ref.listen(routesServiceWorkerProvider, (_, suivant) {
      final ouverture = suivant.value;
      if (ouverture == null) return;
      _relireLeCentre();
      _ouvrir(ouverture.route, stationId: ouverture.stationId);
    });

    ref.listen<BasculeAutomatique?>(basculeCaserneProvider, (_, suivante) {
      if (suivante == null) return;
      setState(() {
        _bascule = suivante;
        _message = null;
      });
      _programmerEffacement();
    });

    final message = _message;
    final bascule = _bascule;

    return Stack(
      children: <Widget>[
        widget.child,
        if (bascule != null)
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
                  child: BandeauBascule(
                    bascule: bascule,
                    onRevenir: bascule.peutRevenir ? _revenir : null,
                    onFermer: _fermer,
                  ),
                ),
              ),
            ),
          )
        else if (message != null)
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
                    autreCaserne: _autreCaserne(message),
                    onVoir: message.route == null
                        ? null
                        : () => _ouvrir(
                            message.route,
                            stationId: message.stationId,
                          ),
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
    this.autreCaserne,
    this.onVoir,
  });

  final MessagePush message;

  /// Le nom de la caserne du message quand ce n'est pas la caserne ouverte :
  /// il préfixe le titre (`design/072 § 6.3`), avant toute bascule.
  final String? autreCaserne;
  final VoidCallback? onVoir;
  final VoidCallback onFermer;

  @override
  Widget build(BuildContext context) {
    final titreSeul = message.titre?.trim().isNotEmpty ?? false
        ? message.titre!.trim()
        : AppStrings.notifBanniereSansTitre;
    final caserne = autreCaserne;
    final titre = caserne == null
        ? titreSeul
        : AppStrings.pushTitreAutreCaserne(caserne, titreSeul);
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

/// **Le bandeau « caserne ouverte »** après une bascule automatique
/// (`design/072 § 6.3`).
///
/// Le nom de la caserne ouverte d'abord — c'est le fait —, puis la raison et
/// l'ancienne caserne. Même composant et même place que le bandeau d'un push,
/// icône `swap_horiz` : l'événement est un changement de cadre. Annoncé
/// poliment, sans voler le focus : la personne arrive sur la destination
/// qu'elle a demandée.
class BandeauBascule extends StatelessWidget {
  const BandeauBascule({
    required this.bascule,
    required this.onFermer,
    this.onRevenir,
    super.key,
  });

  final BasculeAutomatique bascule;

  /// `null` quand on ne peut pas revenir (accès désactivé).
  final VoidCallback? onRevenir;
  final VoidCallback onFermer;

  @override
  Widget build(BuildContext context) {
    final ancienne = bascule.ancienne.nomCaserne;
    final texte = AppStrings.bandeauCaserneOuverte(bascule.nouvelle.nomCaserne);
    final detail = switch (bascule.raison) {
      RaisonBascule.notification => AppStrings.bandeauRaisonNotification(
        ancienne,
      ),
      RaisonBascule.lien => AppStrings.bandeauRaisonLien(ancienne),
      RaisonBascule.desactivee => AppStrings.bandeauRaisonDesactivee(ancienne),
    };

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.duree(context, AppDuration.courant),
      builder: (BuildContext context, double opacite, Widget? enfant) =>
          Opacity(opacity: opacite, child: enfant),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: AppBanner(
          variante: AppBannerVariante.information,
          icone: Icons.swap_horiz,
          texte: texte,
          detail: detail,
          libelleAction: onRevenir == null
              ? null
              : AppStrings.bandeauRevenir(ancienne),
          onAction: onRevenir,
          onFermer: onFermer,
          libelleFermer: AppStrings.bandeauFermer,
        ),
      ),
    );
  }
}
