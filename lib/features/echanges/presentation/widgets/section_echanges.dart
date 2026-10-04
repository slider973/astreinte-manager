import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/entete_section.dart';
import '../../../../core/widgets/loading_skeleton.dart';
import '../../../astreintes/domain/astreintes_providers.dart';
import '../../domain/echanges_providers.dart';
import 'carte_echange.dart';
import 'detail_echange.dart';

/// **La section « Échanges · N »** en tête des Astreintes (portée « Moi »,
/// vue « Liste », `design/073 § 6.3`).
///
/// Présente **seulement** quand le pompier a une demande à suivre, comme
/// demandeur ou comme repreneur : pas d'en-tête vide. Au-delà de trois
/// cartes, elle se replie sur les trois premières et « Voir les N échanges »
/// la déplie en place.
class SectionEchanges extends ConsumerStatefulWidget {
  const SectionEchanges({super.key});

  /// Le nombre de cartes montrées repliée.
  static const int repliee = 3;

  @override
  ConsumerState<SectionEchanges> createState() => _SectionEchangesState();
}

class _SectionEchangesState extends ConsumerState<SectionEchanges> {
  bool _deplie = false;

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(echangesControllerProvider);
    final suivis = ref.watch(echangesSuivisProvider);
    final maintenant = ref.watch(horlogeAstreintesProvider)();

    if (etat.isLoading && !etat.hasValue) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.lg),
        child: LoadingSkeleton(child: SkeletonBloc(hauteur: 120)),
      );
    }
    if (etat.hasError && (etat.value?.vide ?? true)) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: EmptyState.erreur(
          texte: AppStrings.echangeSectionErreur,
          onAction: () => unawaited(
            ref.read(echangesControllerProvider.notifier).rafraichir(),
          ),
        ),
      );
    }
    if (suivis.isEmpty) return const SizedBox.shrink();

    final montres = _deplie || suivis.length <= SectionEchanges.repliee
        ? suivis
        : suivis.take(SectionEchanges.repliee).toList();
    final moi = etat.value?.moi ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EnteteSection(
          titre: AppStrings.echangeSection(suivis.length),
          premiere: true,
          discret: true,
        ),
        for (final echange in montres)
          Padding(
            key: ValueKey<String>('echange-${echange.id}'),
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: CarteEchange(
              echange: echange,
              moi: moi,
              heures: heuresCaserne(ref),
              maintenant: maintenant,
              onOuvrir: () => unawaited(ouvrirDetailEchange(context, echange.id)),
            ),
          ),
        if (suivis.length > SectionEchanges.repliee)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(AppTouch.cible, AppTouch.cible),
              ),
              onPressed: () => setState(() => _deplie = !_deplie),
              child: Text(
                _deplie
                    ? AppStrings.echangeVoirMoins
                    : AppStrings.echangeVoirTous(suivis.length),
              ),
            ),
          ),
      ],
    );
  }
}
