import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_divider.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/invitation.dart';
import '../domain/membres_providers.dart';
import 'widgets/entete_section.dart';
import 'widgets/ligne_invitation.dart';
import 'widgets/ligne_membre.dart';

/// L'écran « Membres » de la destination Admin.
///
/// Deux listes qui ne se confondent pas : qui est dans la caserne, et qui a
/// été invité sans avoir encore rejoint.
///
/// Les invitations ne sont pas répliquées en temps réel
/// (`docs/SCHEMA.md § 9`) : **personne ne prévient l'admin quand un invité
/// accepte**. L'écran relit donc à son ouverture (le provider est
/// auto-disposé), au retour de l'application au premier plan, et après chaque
/// action.
class MembresScreen extends ConsumerStatefulWidget {
  const MembresScreen({super.key});

  @override
  ConsumerState<MembresScreen> createState() => _MembresScreenState();
}

class _MembresScreenState extends ConsumerState<MembresScreen> {
  /// L'invitation sur laquelle une action est en cours : ses deux boutons
  /// sont inertes le temps de l'aller-retour.
  String? _occupee;

  /// Le retour de l'application au premier plan relit les deux listes.
  ///
  /// C'est le seul moment où l'écran peut apprendre qu'un invité a accepté
  /// pendant qu'il était rangé : rien ne pousse cette information (voir
  /// `MembresController`). L'ouverture de l'écran, elle, est couverte par
  /// l'auto-disposition du provider.
  late final AppLifecycleListener _cycleDeVie;

  @override
  void initState() {
    super.initState();
    _cycleDeVie = AppLifecycleListener(onResume: _relire);
  }

  @override
  void dispose() {
    _cycleDeVie.dispose();
    super.dispose();
  }

  void _relire() {
    if (!mounted) return;
    unawaited(ref.read(membresControllerProvider.notifier).rafraichir());
  }

  Future<void> _agir(
    Invitation invitation,
    Future<ResultatAction> Function(Invitation) action,
  ) async {
    if (_occupee != null) return;
    setState(() => _occupee = invitation.id);

    final resultat = await action(invitation);

    if (!mounted) return;
    setState(() => _occupee = null);
    _annoncer(resultat);
  }

  void _annoncer(ResultatAction resultat) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(resultat.message),
          backgroundColor: resultat.reussi
              ? null
              : theme.colorScheme.errorContainer,
          showCloseIcon: true,
          closeIconColor: resultat.reussi
              ? null
              : theme.colorScheme.onErrorContainer,
        ),
      );
  }

  void _versDestination(int index, List<AppDestination> destinations) {
    final destination = destinations[index];
    if (destination.route == _routeAdmin) return;

    // Les autres destinations vivent encore dans l'accueil (ticket 005) :
    // on y retourne en disant quel onglet ouvrir, pour ne pas ramener
    // quelqu'un sur « Mon mois » quand il a demandé « Planning ».
    context.goNamed(
      AppRoutes.accueilName,
      queryParameters: <String, String>{AppRoutes.parametreOnglet: '$index'},
    );
  }

  static const String _routeAdmin = 'admin';

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(estAdminCaserneProvider);
    final etat = ref.watch(membresControllerProvider);
    final destinations = AppDestination.pour(admin: admin);
    final indexAdmin = destinations.indexWhere(
      (AppDestination d) => d.route == _routeAdmin,
    );

    final donnees = etat.value;
    final enErreur = etat.hasError;

    return AppScaffold(
      titre: AppStrings.membresTitre,
      destinations: destinations,
      indexSelectionne: indexAdmin < 0 ? 0 : indexAdmin,
      onDestination: (int index) => _versDestination(index, destinations),
      actions: <Widget>[
        IconButton(
          onPressed: _relire,
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.membresRafraichir,
        ),
      ],
      // Une erreur survenue alors que la liste est déjà affichée se dit en
      // bannière : vider l'écran pour annoncer un échec de relecture ferait
      // perdre ce qui était juste.
      banniere: enErreur && donnees != null
          ? AppBanner(
              variante: AppBannerVariante.erreur,
              texte: AppStrings.membresErreurTexte,
              libelleAction: AppStrings.actionReessayer,
              onAction: _relire,
            )
          : null,
      filActions: admin
          ? PrimaryButton(
              libelle: AppStrings.membresInviter,
              icone: Icons.person_add_alt,
              onPressed: () => context.goNamed(AppRoutes.inviterName),
            )
          : null,
      child: _corps(admin: admin, etat: etat, donnees: donnees),
    );
  }

  Widget _corps({
    required bool admin,
    required AsyncValue<EtatMembres> etat,
    required EtatMembres? donnees,
  }) {
    if (!admin) {
      return const EmptyState(
        titre: AppStrings.membresTitre,
        texte: AppStrings.membresReserveAdmin,
        icone: Icons.lock_outline,
      );
    }

    if (donnees == null) {
      return etat.hasError
          ? EmptyState.erreur(
              texte: AppStrings.membresErreurTexte,
              onAction: _relire,
            )
          : const _SqueletteMembres();
    }

    if (donnees.vide) {
      return const EmptyState(
        titre: AppStrings.membresVideTitre,
        texte: AppStrings.membresVideTexte,
        icone: Icons.group_add_outlined,
      );
    }

    return _ListeMembres(
      donnees: donnees,
      occupee: _occupee,
      onRenvoyer: (Invitation invitation) => unawaited(
        _agir(
          invitation,
          ref.read(membresControllerProvider.notifier).renvoyer,
        ),
      ),
      onAnnuler: (Invitation invitation) => unawaited(
        _agir(invitation, ref.read(membresControllerProvider.notifier).annuler),
      ),
    );
  }
}

/// Les deux listes, virtualisées : une caserne peut compter cent pompiers.
class _ListeMembres extends StatelessWidget {
  const _ListeMembres({
    required this.donnees,
    required this.occupee,
    required this.onRenvoyer,
    required this.onAnnuler,
  });

  final EtatMembres donnees;
  final String? occupee;
  final ValueChanged<Invitation> onRenvoyer;
  final ValueChanged<Invitation> onAnnuler;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;
    final maintenant = DateTime.now();

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.xl),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppStrings.membresSousTitre,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              EnteteSection(
                titre: AppStrings.membresSectionActifs,
                compte: AppStrings.membresCompte(donnees.membres.length),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: marge),
          sliver: SliverList.builder(
            itemCount: donnees.membres.length,
            itemBuilder: (BuildContext context, int index) {
              final membre = donnees.membres[index];
              return Column(
                key: ValueKey<String>(membre.id),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  LigneMembre(membre: membre),
                  const AppDivider(),
                ],
              );
            },
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: marge),
          sliver: SliverToBoxAdapter(
            child: EnteteSection(
              titre: AppStrings.membresSectionInvitations,
              compte: AppStrings.invitationsCompte(donnees.invitations.length),
            ),
          ),
        ),
        if (donnees.invitations.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              marge,
              AppSpacing.md,
              marge,
              AppSpacing.md,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                AppStrings.membresInvitationsVide,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: marge),
            sliver: SliverList.builder(
              itemCount: donnees.invitations.length,
              itemBuilder: (BuildContext context, int index) {
                final invitation = donnees.invitations[index];
                return Column(
                  key: ValueKey<String>(invitation.id),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LigneInvitation(
                      invitation: invitation,
                      maintenant: maintenant,
                      occupee: occupee == invitation.id,
                      onRenvoyer: () => onRenvoyer(invitation),
                      onAnnuler: () => onAnnuler(invitation),
                    ),
                    const AppDivider(),
                  ],
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }
}

/// L'ossature du contenu attendu, jamais une roue au milieu de l'écran.
class _SqueletteMembres extends StatelessWidget {
  const _SqueletteMembres();

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return LoadingSkeleton(
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: marge,
          vertical: AppSpacing.lg,
        ),
        children: <Widget>[
          const SkeletonLigne(largeur: 200, hauteur: AppSpacing.xl),
          const SizedBox(height: AppSpacing.xl),
          for (int index = 0; index < 6; index++) ...<Widget>[
            const SkeletonLigne(),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonLigne(largeur: 160),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}
