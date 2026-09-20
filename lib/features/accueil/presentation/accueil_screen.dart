import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';
import '../../../core/session/deconnexion.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';

/// L'accueil minimal d'après-connexion (ticket 005).
///
/// Il montre ce que la connexion a rapporté — la caserne et le rôle — et offre
/// la sortie. La navigation est celle du produit (`DESIGN.md § Navigation`),
/// avec la destination « Admin » réservée aux administrateurs ; les écrans qui
/// la suivent arrivent aux tickets suivants et le disent, plutôt que de rester
/// muets sous le doigt.
class AccueilScreen extends ConsumerStatefulWidget {
  const AccueilScreen({super.key});

  @override
  ConsumerState<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends ConsumerState<AccueilScreen> {
  int _destination = 0;

  @override
  Widget build(BuildContext context) {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    final destinations = AppDestination.pour(
      admin: appartenance?.estAdmin ?? false,
    );
    final index = _destination.clamp(0, destinations.length - 1);

    return AppScaffold(
      titre: AppStrings.appTitle,
      destinations: destinations,
      indexSelectionne: index,
      onDestination: (nouvelle) => setState(() => _destination = nouvelle),
      child: index == 0
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
