import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/session/appartenance.dart';
import '../../../../core/session/bascule_caserne.dart';
import '../../../../core/session/session_providers.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../notifications/domain/centre_providers.dart';

/// Une autre caserne active qui a des rappels non lus, et leur nombre.
typedef Passerelle = ({Appartenance caserne, int nonLues});

/// **Les passerelles de la Boîte** (ticket 072, `design/072 § 6.6`) : une par
/// autre caserne active qui a au moins un rappel non lu, dans l'ordre des
/// appartenances. Les notifications d'une caserne où l'accès n'est plus actif
/// ne mènent nulle part : elles n'ont pas de passerelle.
final Provider<List<Passerelle>> passerellesProvider =
    Provider<List<Passerelle>>((ref) {
      final ailleurs = ref.watch(nonLuesAilleursProvider);
      return <Passerelle>[
        for (final appartenance in ref.watch(appartenancesActivesProvider))
          if ((ailleurs[appartenance.stationId] ?? 0) > 0)
            (
              caserne: appartenance,
              nonLues: ailleurs[appartenance.stationId]!,
            ),
      ];
    });

/// Les passerelles, au-dessus de la première ligne de la liste. Rien quand il
/// n'y en a pas.
class Passerelles extends ConsumerWidget {
  const Passerelles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passerelles = ref.watch(passerellesProvider);
    if (passerelles.isEmpty) return const SizedBox.shrink();
    final marge = AppWindowClass.of(context).margePage;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
        child: Padding(
          padding: EdgeInsets.fromLTRB(marge, AppSpacing.md, marge, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final passerelle in passerelles)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: CartePasserelle(
                    nomCaserne: passerelle.caserne.nomCaserne,
                    nonLues: passerelle.nonLues,
                    // Un choix **manuel** : pas de bandeau, et l'on reste sur
                    // la Boîte, même onglet — l'adresse ne bouge pas.
                    onOuvrir: () => unawaited(
                      ref
                          .read(basculeCaserneProvider.notifier)
                          .choisir(passerelle.caserne.stationId),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// « CS Ury · 2 non lues — Ouvrir ».
class CartePasserelle extends StatelessWidget {
  const CartePasserelle({
    required this.nomCaserne,
    required this.nonLues,
    required this.onOuvrir,
    super.key,
  });

  final String nomCaserne;
  final int nonLues;
  final VoidCallback onOuvrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CarteDouce(
      hauteurMin: 56 - 2 * AppSpacing.sm,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(
              Icons.swap_horiz,
              size: AppTouch.icone,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                AppStrings.boitePasserelle(nomCaserne, nonLues),
                style: theme.textTheme.bodyLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          PrimaryButton(
            libelle: AppStrings.boitePasserelleAction,
            libelleAnnonce: AppStrings.boitePasserelleSemantique(
              nomCaserne,
              nonLues,
            ),
            variante: PrimaryButtonVariante.secondaire,
            pleineLargeur: false,
            onPressed: onOuvrir,
          ),
        ],
      ),
    );
  }
}
