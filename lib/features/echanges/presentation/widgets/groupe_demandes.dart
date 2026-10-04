import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/entete_section.dart';
import '../../domain/echange.dart';
import 'carte_demande_recue.dart';

/// Le groupe **« Demandes de collègues · N »**, en tête de l'onglet
/// « Propositions » de la Boîte (`design/073 § 7.1`) : une demande humaine
/// expire plus vite qu'une proposition de planning, elle passe devant.
///
/// Quand le pompier suit lui-même des demandes, une ligne le mène à la
/// section « Échanges » d'Astreintes : c'est là que vivent les siennes, et le
/// lien `/exchanges` des notifications arrive ici.
class GroupeDemandes extends StatelessWidget {
  const GroupeDemandes({
    required this.demandes,
    required this.maintenant,
    required this.onOuvrir,
    required this.suivies,
    required this.onSuivre,
    super.key,
  });

  final List<Echange> demandes;
  final DateTime maintenant;
  final ValueChanged<Echange> onOuvrir;

  /// Le nombre de demandes que je suis.
  final int suivies;
  final VoidCallback onSuivre;

  @override
  Widget build(BuildContext context) {
    if (demandes.isEmpty && suivies == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (demandes.isNotEmpty) ...<Widget>[
          EnteteSection(
            titre: AppStrings.echangeGroupeRecues(demandes.length),
            premiere: true,
            discret: true,
          ),
          for (final echange in demandes)
            Padding(
              key: ValueKey<String>('demande-${echange.id}'),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: CarteDemandeRecue(
                echange: echange,
                maintenant: maintenant,
                onOuvrir: () => onOuvrir(echange),
              ),
            ),
        ],
        if (suivies > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(AppTouch.cible, AppTouch.cible),
              ),
              onPressed: onSuivre,
              icon: const Icon(Icons.swap_horiz),
              label: Text(
                '${AppStrings.echangeSuivreMesDemandes} · '
                '${AppStrings.echangeMesDemandes(suivies)}',
              ),
            ),
          ),
      ],
    );
  }
}
