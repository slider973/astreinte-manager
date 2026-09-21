import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/session/appartenance.dart';
import '../../../../core/session/caserne_choisie.dart';
import '../../../../core/session/session_providers.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import 'bloc_regle.dart';

/// La caserne où l'on travaille, et le moyen d'en changer quand il y en a
/// plusieurs.
///
/// **Le sélecteur n'apparaît qu'à partir de deux appartenances actives** : un
/// contrôle à un seul choix est un contrôle de trop, et la très grande majorité
/// des pompiers n'appartient qu'à une caserne (`design/007-profil.md § 5.2`).
class BlocCaserne extends ConsumerWidget {
  const BlocCaserne({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courante = ref.watch(appartenanceCouranteProvider);
    final actives = ref.watch(appartenancesActivesProvider);
    final plusieurs = ref.watch(plusieursCasernesProvider);

    return BlocRegle(
      titre: AppStrings.profilCaserneTitre,
      enfants: <Widget>[
        LigneLecture(
          libelle: AppStrings.accueilCaserneLabel,
          // Le titre du bloc dit déjà « Ta caserne » : le répéter au-dessus du
          // nom ferait lire deux fois la même chose.
          libelleVisible: false,
          valeur: courante?.nomCaserne ?? AppStrings.valueUndefined,
          icone: Icons.local_fire_department_outlined,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        LigneLecture(
          libelle: AppStrings.accueilRoleLabel,
          valeur: courante?.role.libelle ?? AppStrings.valueUndefined,
        ),
        if (plusieurs) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const AppDivider(),
          const SizedBox(height: AppSpacing.lg),
          _Selecteur(appartenances: actives, courante: courante),
        ],
      ],
    );
  }
}

/// Un groupe de boutons radio, **jamais un menu déroulant** : deux ou trois
/// entrées tiennent à l'écran, et un menu cache jusqu'à l'existence du choix.
class _Selecteur extends ConsumerWidget {
  const _Selecteur({required this.appartenances, required this.courante});

  final List<Appartenance> appartenances;
  final Appartenance? courante;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            AppStrings.profilCaserneChoixTitre,
            style: theme.textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          AppStrings.profilCaserneChoixAide,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // `RadioGroup` porte la valeur et le geste pour tout le groupe : les
        // tuiles n'ont plus qu'à se nommer.
        RadioGroup<String>(
          groupValue: courante?.stationId,
          onChanged: (String? stationId) {
            if (stationId == null) return;
            unawaited(
              ref.read(caserneChoisieProvider.notifier).choisir(stationId),
            );
          },
          child: Column(
            children: <Widget>[
              for (final appartenance in appartenances)
                _Choix(
                  appartenance: appartenance,
                  choisie: appartenance.stationId == courante?.stationId,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Choix extends StatelessWidget {
  const _Choix({required this.appartenance, required this.choisie});

  final Appartenance appartenance;
  final bool choisie;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // La caserne active porte `selected`, pas seulement une couleur : l'état
      // n'est jamais porté par la seule teinte (`DESIGN.md § Do's`).
      selected: choisie,
      child: RadioListTile<String>(
        value: appartenance.stationId,
        title: Text(appartenance.nomCaserne),
        subtitle: Text(
          AppStrings.profilCaserneRole(appartenance.role.libelle),
        ),
        contentPadding: EdgeInsets.zero,
        // 48 dp au minimum, comme toute cible de cet écran.
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}
