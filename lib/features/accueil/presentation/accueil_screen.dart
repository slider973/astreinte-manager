import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/appartenance.dart';
import '../../../core/session/deconnexion.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../dispos/presentation/mois_screen.dart';
import '../../notifications/presentation/widgets/reglage_notifications.dart';

/// La coquille des destinations de premier niveau.
///
/// Depuis le ticket 011, l'onglet 0 **est** l'écran « Mon mois » : il porte
/// sa propre bannière, sa barre de compteurs et son panneau latéral, donc
/// c'est lui qui construit l'`AppScaffold`. La coquille ne garde que le choix
/// de destination et l'identité, reportée sur l'onglet « Profil » jusqu'à ce
/// qu'il ait son propre écran.
class AccueilScreen extends ConsumerStatefulWidget {
  const AccueilScreen({super.key, this.ongletInitial = 0, this.mois});

  /// L'onglet ouvert à l'arrivée. Porté par l'URL : revenir depuis l'écran
  /// « Membres », qui a sa propre route, ne ramène pas sur « Mon mois » quand
  /// on a demandé « Planning ».
  final int ongletInitial;

  /// Le mois affiché par « Mon mois », au format `AAAA-MM`.
  final String? mois;

  @override
  ConsumerState<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends ConsumerState<AccueilScreen> {
  late int _destination = widget.ongletInitial;

  /// La destination « Admin » n'est pas un onglet local : c'est une route.
  static const String _routeAdmin = 'admin';

  /// L'onglet qui porte l'identité et la sortie, en attendant son écran.
  static const String _routeProfil = 'profil';

  void _choisir(int index, List<AppDestination> destinations) {
    if (destinations[index].route == _routeAdmin) {
      context.goNamed(AppRoutes.membresName);
      return;
    }
    setState(() => _destination = index);
  }

  /// Le mois voyage dans l'URL. `goNamed` empile une entrée d'historique :
  /// le retour du navigateur ramène au mois précédemment consulté.
  void _changerMois(String cle) {
    context.goNamed(
      AppRoutes.accueilName,
      queryParameters: <String, String>{
        AppRoutes.parametreOnglet: '$_destination',
        AppRoutes.parametreMois: cle,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    final destinations = AppDestination.pour(
      admin: appartenance?.estAdmin ?? false,
    );
    final index = _destination.clamp(0, destinations.length - 1);
    final route = destinations[index].route;

    if (index == 0) {
      return MoisScreen(
        destinations: destinations,
        indexSelectionne: index,
        onDestination: (nouvelle) => _choisir(nouvelle, destinations),
        moisInitial: widget.mois,
        onMoisChange: _changerMois,
      );
    }

    return AppScaffold(
      titre: AppStrings.appTitle,
      destinations: destinations,
      indexSelectionne: index,
      onDestination: (nouvelle) => _choisir(nouvelle, destinations),
      child: route == _routeProfil
          ? _Contenu(appartenance: appartenance)
          : EmptyState(
              titre: AppStrings.accueilAVenirTitre,
              texte: AppStrings.accueilAVenirTexte,
              icone: Icons.construction_outlined,
              libelleAction: AppStrings.accueilRetour,
              onAction: () => setState(() => _destination = 0),
            ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({required this.appartenance});

  final Appartenance? appartenance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            AppStrings.accueilTitre,
            style: theme.textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.sousTitre),
        Text(
          AppStrings.accueilTexte,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.auDessusTitre),
        _BlocIdentite(appartenance: appartenance),
        const SizedBox(height: AppSpacing.auDessusTitre),
        // Le réglage des notifications se pose ici en attendant l'écran de
        // profil du ticket 007, où il déménagera tel quel (ticket 024).
        const ReglageNotifications(),
        const SizedBox(height: AppSpacing.auDessusTitre),
        const BoutonDeconnexion(),
      ],
    );
  }
}

/// Un bloc réglé (`DESIGN.md § Cards / Containers`) : filet 1 dp, rayon 8,
/// aucune ombre. La caserne et le rôle, chacun avec son libellé.
class _BlocIdentite extends StatelessWidget {
  const _BlocIdentite({required this.appartenance});

  final Appartenance? appartenance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final courante = appartenance;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: AppRadius.controleRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Ligne(
              libelle: AppStrings.accueilCaserneLabel,
              valeur: courante?.nomCaserne ?? AppStrings.valueUndefined,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            _Ligne(
              libelle: AppStrings.accueilRoleLabel,
              valeur: courante?.role.libelle ?? AppStrings.valueUndefined,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.libelle, required this.valeur, this.style});

  final String libelle;
  final String valeur;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: libelle,
      value: valeur,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            libelle,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(valeur, style: style),
        ],
      ),
    );
  }
}
