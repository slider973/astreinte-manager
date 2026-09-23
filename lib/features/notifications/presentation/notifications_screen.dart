import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/destinations.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_divider.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/barre_actions_basse.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/primary_button.dart';
import '../../profil/presentation/widgets/bouton_compte.dart';
import '../domain/centre_providers.dart';
import '../domain/destination_push.dart';
import '../domain/notification_interne.dart';
import 'widgets/ligne_notification.dart';

/// **La Boîte** — le journal de bord du pompier.
///
/// Quatrième destination depuis le ticket 064, à la route `/boite` : elle
/// portait « Notifications » et se poussait, faute de place dans une barre à
/// cinq entrées dont le profil occupait la quatrième. Le chantier 064b y fera
/// entrer les propositions derrière trois onglets — Tout, Propositions,
/// Rappels — et le contenu servi ici est, d'ici là, celui du ticket 026.
///
/// C'est **le filet du produit** quand le push n'arrive pas — iPhone hors
/// écran d'accueil, autorisation refusée, batterie économisée. Une proposition
/// d'astreinte jamais lue est une garde non couverte, et cet écran est le seul
/// endroit où elle reste visible.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Une action est en cours : les lignes n'ouvrent rien le temps de
  /// l'aller-retour, sinon deux touches rapides partent deux fois.
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    // **Relire à l'ouverture.** Le contrôleur est gardé en vie pour la
    // pastille, donc il n'est pas relu par le simple fait d'arriver ici : sans
    // ceci, un onglet laissé ouvert une heure rouvrirait le centre sur la
    // liste d'il y a une heure. Une requête par ouverture, c'est le prix.
    // Reporté d'une image : modifier un provider pendant `initState` est
    // interdit par Riverpod.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _relire();
    });
  }

  void _relire() =>
      unawaited(ref.read(centreNotificationsProvider.notifier).rafraichir());

  /// Une touche fait **deux choses dans le même mouvement** : la ligne passe
  /// lue, et la destination s'ouvre.
  ///
  /// La destination passe par `destinationInterne` (ticket 024), **la même
  /// fonction que le push**, et pas une seconde. Un lien inconnu ou refusé
  /// ramène à l'accueil **sans message d'erreur** : le membre n'a rien fait de
  /// mal, et le lien peut dater d'avant une rétrogradation.
  Future<void> _ouvrir(NotificationInterne notification) async {
    if (_occupe) return;
    setState(() => _occupe = true);

    final admin = ref.read(appartenanceCouranteProvider)?.estAdmin ?? false;
    final destination =
        destinationInterne(notification.route, admin: admin) ??
        AppRoutes.accueil;

    // Le marquage part d'abord, mais la navigation ne l'attend pas : elle est
    // ce que le pompier a demandé. Un réseau lent ne doit pas retenir l'écran.
    final marquage = ref
        .read(centreNotificationsProvider.notifier)
        .marquerLue(notification);

    ref.read(appRouterProvider).go(destination);

    final reussi = await marquage;
    if (!mounted) return;
    setState(() => _occupe = false);
    if (!reussi) _annoncerEchec();
  }

  Future<void> _toutMarquerLu() async {
    if (_occupe) return;
    setState(() => _occupe = true);

    final reussi = await ref
        .read(centreNotificationsProvider.notifier)
        .toutMarquerLu();

    if (!mounted) return;
    setState(() => _occupe = false);
    _annoncer(
      reussi
          ? AppStrings.centreToutMarqueLuConfirmation
          : AppStrings.centreEchecLecture,
    );
  }

  void _annoncerEchec() => _annoncer(AppStrings.centreEchecLecture);

  void _annoncer(String message) {
    final messager = ScaffoldMessenger.maybeOf(context);
    if (messager == null) return;
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(centreNotificationsProvider);
    final donnees = etat.value;
    final enErreur = etat.hasError;
    final nonLues = donnees?.nonLues ?? 0;

    final destinations = ref.watch(destinationsProvider);

    return AppScaffold(
      titre: AppStrings.navBoite,
      destinations: destinations,
      indexSelectionne: indexDestination(destinations, AppRoutes.boiteName),
      onDestination: (index) =>
          allerVersDestination(context, destinations, index),
      actions: <Widget>[
        IconButton(
          onPressed: _relire,
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.centreRafraichir,
        ),
        const BoutonCompte(),
      ],
      // Une erreur survenue alors que la liste est déjà affichée se dit en
      // bannière : vider l'écran pour annoncer un échec de relecture ferait
      // perdre ce qui était juste.
      banniere: enErreur && donnees != null
          ? AppBanner(
              variante: AppBannerVariante.erreur,
              texte: AppStrings.centreErreurTexte,
              libelleAction: AppStrings.actionReessayer,
              onAction: _relire,
            )
          : null,
      child: Column(
        children: <Widget>[
          Expanded(child: _corps(etat: etat, donnees: donnees)),

          // Le bouton n'apparaît que s'il y a quelque chose à marquer. Un
          // bouton désactivé qu'il faudrait expliquer à côté vaut moins qu'un
          // bouton absent (`design/026 § 3`).
          //
          // Il vit dans le contenu et non dans `filActions` : `BarreActionsBasse`
          // porte déjà le filet, la surface de niveau 1 et la colonne bornée
          // que la zone d'actions de la coquille ne connaît pas.
          if (nonLues > 0)
            BarreActionsBasse(
              child: PrimaryButton(
                libelle: AppStrings.centreToutMarquerLu,
                icone: Icons.done_all,
                variante: PrimaryButtonVariante.secondaire,
                chargement: _occupe,
                onPressed: () => unawaited(_toutMarquerLu()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _corps({
    required AsyncValue<EtatCentre> etat,
    required EtatCentre? donnees,
  }) {
    if (donnees == null) {
      return etat.hasError
          ? EmptyState.erreur(
              texte: AppStrings.centreErreurTexte,
              onAction: _relire,
            )
          : const _SqueletteNotifications();
    }

    if (donnees.vide) {
      // Pas d'action : il n'y a rien à faire, et le dire est plus honnête
      // qu'un bouton qui n'irait nulle part.
      return const EmptyState(
        titre: AppStrings.centreVideTitre,
        texte: AppStrings.centreVideTexte,
        icone: Icons.notifications_none_outlined,
      );
    }

    return _ListeNotifications(
      donnees: donnees,
      onOuvrir: (NotificationInterne notification) =>
          unawaited(_ouvrir(notification)),
    );
  }
}

/// La liste, virtualisée : deux cents événements peuvent s'y trouver.
class _ListeNotifications extends StatelessWidget {
  const _ListeNotifications({required this.donnees, required this.onOuvrir});

  final EtatCentre donnees;

  final ValueChanged<NotificationInterne> onOuvrir;

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;
    final maintenant = DateTime.now();
    final lignes = donnees.notifications;


    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
        child: CustomScrollView(
          slivers: <Widget>[
            // Pas d'en-tête de section ici : il redirait « Notifications »
            // juste sous la barre d'application. Seul le compte est une
            // information — il dit combien de lignes suivent, et combien
            // restent à lire.
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                marge,
                AppSpacing.lg,
                marge,
                AppSpacing.md,
              ),
              sliver: SliverToBoxAdapter(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    AppStrings.centreCompte(lignes.length, donnees.nonLues),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: AppDivider()),
            SliverPadding(
              // Les lignes vont bord à bord : leur fond dit l'état de lecture,
              // et un fond qui s'arrête avant la marge ferait une carte.
              padding: EdgeInsets.only(
                left: marge - AppSpacing.md,
                right: marge - AppSpacing.md,
                // **Pas de réserve de zone sûre ici.** Elle existait quand la
                // Boîte était un écran poussé, sans rien sous elle. Depuis le
                // ticket 064 c'est une destination : la barre de navigation
                // ajoute `viewPadding.bottom` à sa propre hauteur, et doubler
                // la réserve creuserait un trou.
                bottom: AppSpacing.xl,
              ),
              sliver: SliverList.separated(
                itemCount: lignes.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const AppDivider(),
                itemBuilder: (BuildContext context, int index) {
                  final notification = lignes[index];
                  return LigneNotification(
                    key: ValueKey<String>(notification.id),
                    notification: notification,
                    maintenant: maintenant,
                    onTouche: () => onOuvrir(notification),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'ossature de la liste : cinq lignes. Jamais une roue au milieu de l'écran
/// (`DESIGN.md § Don't`).
class _SqueletteNotifications extends StatelessWidget {
  const _SqueletteNotifications();

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return LoadingSkeleton(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: marge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: AppSpacing.xl),
            const SkeletonLigne(largeur: 160),
            const SizedBox(height: AppSpacing.xl),
            for (var index = 0; index < 5; index++) ...<Widget>[
              const SkeletonBloc(hauteur: 64),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}
