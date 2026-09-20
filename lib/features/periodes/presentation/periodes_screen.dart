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
import '../../../core/widgets/entete_section.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/primary_button.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../../membres/domain/membres_providers.dart';
import '../domain/periodes_providers.dart';
import 'widgets/confirmation_verrouillage.dart';
import 'widgets/feuille_ouvrir_mois.dart';
import 'widgets/feuille_reouverture.dart';
import 'widgets/ligne_periode.dart';

/// L'écran « Périodes » de la destination Admin.
///
/// Les mois de saisie de la caserne : leur état, leur date limite, combien de
/// pompiers ont rempli. Et les trois gestes qui les font vivre — ouvrir un
/// mois, le verrouiller avant l'heure, le rouvrir en repoussant sa date
/// limite.
///
/// **Rouvrir, c'est dire jusqu'à quand.** La base refuse une réouverture dont
/// la date limite est déjà passée (`period_reopen_deadline_passed`,
/// migration `0012`) parce que la tâche horaire la défferait dans l'heure :
/// l'écran demande donc la nouvelle date limite dans le même geste.
class PeriodesScreen extends ConsumerStatefulWidget {
  const PeriodesScreen({super.key});

  @override
  ConsumerState<PeriodesScreen> createState() => _PeriodesScreenState();
}

class _PeriodesScreenState extends ConsumerState<PeriodesScreen> {
  static const String _routeAdmin = 'admin';

  /// Le mois dont une action est en vol : son bouton porte l'indicateur, et
  /// aucun autre ne part tant qu'elle n'est pas rendue.
  String? _occupee;

  PeriodesController get _controleur =>
      ref.read(periodesControllerProvider.notifier);

  void _relire() => unawaited(_controleur.rafraichir());

  Future<void> _verrouiller(PeriodeSaisie periode) async {
    if (_occupee != null) return;

    final confirme = await confirmerVerrouillage(
      context: context,
      periode: periode,
    );
    if (!confirme || !mounted) return;

    await _executer(periode, () => _controleur.verrouiller(periode));
  }

  Future<void> _rouvrir(PeriodeSaisie periode) async {
    if (_occupee != null) return;

    final limite = await afficherReouverture(
      context: context,
      periode: periode,
    );
    if (limite == null || !mounted) return;

    await _executer(periode, () => _controleur.rouvrir(periode, limite));
  }

  Future<void> _ouvrirUnMois(EtatPeriodes etat) async {
    if (_occupee != null) return;

    final choix = await afficherOuvrirMois(
      context: context,
      existantes: etat.periodes,
    );
    if (choix == null || !mounted) return;

    setState(() => _occupee = _creationEnCours);
    final resultat = await _controleur.creer(choix.annee, choix.mois);

    if (!mounted) return;
    setState(() => _occupee = null);
    _annoncer(resultat);
  }

  /// La clé d'occupation d'une création : aucune période n'a encore d'identifiant.
  static const String _creationEnCours = 'creation';

  Future<void> _executer(
    PeriodeSaisie periode,
    Future<ResultatPeriode> Function() action,
  ) async {
    setState(() => _occupee = periode.id);
    final resultat = await action();

    if (!mounted) return;
    setState(() => _occupee = null);
    _annoncer(resultat);
  }

  void _annoncer(ResultatPeriode resultat) {
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
    if (destinations[index].route == _routeAdmin) return;
    context.goNamed(
      AppRoutes.accueilName,
      queryParameters: <String, String>{AppRoutes.parametreOnglet: '$index'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(estAdminCaserneProvider);
    final etat = ref.watch(periodesControllerProvider);
    final destinations = AppDestination.pour(admin: admin);
    final indexAdmin = destinations.indexWhere(
      (AppDestination d) => d.route == _routeAdmin,
    );

    final donnees = etat.value;

    return AppScaffold(
      titre: AppStrings.periodesTitre,
      destinations: destinations,
      indexSelectionne: indexAdmin < 0 ? 0 : indexAdmin,
      onDestination: (int index) => _versDestination(index, destinations),
      actions: <Widget>[
        if (admin)
          IconButton(
            onPressed: () => context.goNamed(AppRoutes.membresName),
            icon: const Icon(Icons.group_outlined),
            tooltip: AppStrings.parametresVersMembres,
          ),
        if (admin)
          IconButton(
            onPressed: () => context.goNamed(AppRoutes.parametresName),
            icon: const Icon(Icons.tune),
            tooltip: AppStrings.parametresDepuisMembres,
          ),
        IconButton(
          onPressed: _relire,
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.periodesRafraichir,
        ),
      ],
      // Une erreur survenue alors que la liste est déjà affichée se dit en
      // bannière : vider l'écran pour annoncer un échec de relecture ferait
      // perdre ce qui était juste.
      banniere: etat.hasError && donnees != null
          ? AppBanner(
              variante: AppBannerVariante.erreur,
              texte: AppStrings.periodesErreurTexte,
              libelleAction: AppStrings.actionReessayer,
              onAction: _relire,
            )
          : null,
      filActions: admin && donnees != null
          ? PrimaryButton(
              libelle: AppStrings.periodesOuvrirUnMois,
              icone: Icons.event_available_outlined,
              chargement: _occupee == _creationEnCours,
              onPressed: () => unawaited(_ouvrirUnMois(donnees)),
            )
          : null,
      child: _corps(admin: admin, etat: etat, donnees: donnees),
    );
  }

  Widget _corps({
    required bool admin,
    required AsyncValue<EtatPeriodes> etat,
    required EtatPeriodes? donnees,
  }) {
    if (!admin) {
      return const EmptyState(
        titre: AppStrings.periodesTitre,
        texte: AppStrings.periodesReserveAdmin,
        icone: Icons.lock_outline,
      );
    }

    if (donnees == null) {
      return etat.hasError
          ? EmptyState.erreur(
              texte: AppStrings.periodesErreurTexte,
              onAction: _relire,
            )
          : const _SquelettePeriodes();
    }

    if (donnees.vide) {
      return const EmptyState(
        titre: AppStrings.periodesVideTitre,
        texte: AppStrings.periodesVideTexte,
        icone: Icons.event_busy_outlined,
      );
    }

    return _ListePeriodes(
      donnees: donnees,
      occupee: _occupee,
      onVerrouiller: (PeriodeSaisie p) => unawaited(_verrouiller(p)),
      onRouvrir: (PeriodeSaisie p) => unawaited(_rouvrir(p)),
    );
  }
}

/// Les deux sections, virtualisées.
///
/// `SliverList.builder` ne construit que les lignes visibles, et **c'est ce
/// qui borne le coût du taux de saisie** : chaque ligne demande son propre
/// comptage (`design/014 § 7`). Une caserne de trois ans d'historique ne
/// compte donc pas trente-six mois pour en montrer trois.
class _ListePeriodes extends StatelessWidget {
  const _ListePeriodes({
    required this.donnees,
    required this.occupee,
    required this.onVerrouiller,
    required this.onRouvrir,
  });

  final EtatPeriodes donnees;
  final String? occupee;
  final ValueChanged<PeriodeSaisie> onVerrouiller;
  final ValueChanged<PeriodeSaisie> onRouvrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;
    final maintenant = DateTime.now();
    final aVenir = donnees.aVenir(maintenant);
    final ecoulees = donnees.ecoulees(maintenant);

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: marge),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppStrings.periodesSousTitre,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              EnteteSection(
                titre: AppStrings.periodesSectionAVenir,
                compte: AppStrings.periodesCompte(aVenir.length),
              ),
            ]),
          ),
        ),
        _section(
          marge: marge,
          periodes: aVenir,
          vide: AppStrings.periodesAucunAVenir,
          theme: theme,
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: marge),
          sliver: SliverToBoxAdapter(
            child: EnteteSection(
              titre: AppStrings.periodesSectionEcoules,
              compte: AppStrings.periodesCompte(ecoulees.length),
            ),
          ),
        ),
        _section(
          marge: marge,
          periodes: ecoulees,
          vide: AppStrings.periodesAucunEcoule,
          theme: theme,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }

  Widget _section({
    required double marge,
    required List<PeriodeSaisie> periodes,
    required String vide,
    required ThemeData theme,
  }) {
    if (periodes.isEmpty) {
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(marge, AppSpacing.md, marge, AppSpacing.md),
        sliver: SliverToBoxAdapter(
          child: Text(
            vide,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: marge),
      sliver: SliverList.builder(
        itemCount: periodes.length,
        itemBuilder: (BuildContext context, int index) {
          final periode = periodes[index];
          return Column(
            key: ValueKey<String>(periode.id),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LignePeriode(
                periode: periode,
                occupee: occupee == periode.id,
                onVerrouiller: () => onVerrouiller(periode),
                onRouvrir: () => onRouvrir(periode),
              ),
              const AppDivider(),
            ],
          );
        },
      ),
    );
  }
}

/// L'ossature de trois lignes de période, jamais une roue au milieu de
/// l'écran.
class _SquelettePeriodes extends StatelessWidget {
  const _SquelettePeriodes();

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
          const SkeletonLigne(largeur: 220, hauteur: AppSpacing.xl),
          const SizedBox(height: AppSpacing.xl),
          for (int ligne = 0; ligne < 3; ligne++) ...<Widget>[
            const SkeletonLigne(largeur: 180),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonLigne(largeur: 240),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonLigne(),
            const SizedBox(height: AppSpacing.xl),
          ],
        ],
      ),
    );
  }
}
