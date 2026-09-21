import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/candidat.dart';

/// La confirmation d'une **réattribution**.
///
/// `DESIGN.md § Don't` interdit la modale « pour une tâche qui ne demande ni
/// interruption ni protection ». Celle-ci demande une protection : le geste
/// sort de l'application — un téléphone sonne — et **ne se défait pas**. On ne
/// rappelle pas un push. C'est la différence exacte avec l'attribution en
/// brouillon, qui n'en ouvre aucune parce qu'elle se défait d'un clic.
///
/// **Une seule feuille pour tous les avertissements.** La non-disponibilité du
/// candidat et l'annulation de la garde du titulaire sortant s'y ajoutent en
/// lignes, au lieu d'ouvrir une seconde confirmation : deux dialogues d'affilée
/// apprennent à cliquer « Oui » sans lire.
Future<bool> confirmerReattribution(
  BuildContext context, {
  required Candidat candidat,
  required DateTime jour,
  required CreneauType creneau,
  String? titulaireSortant,
}) async {
  final libelleCreneau = context.statuts.creneau(creneau).libelle.toLowerCase();
  final jourEtDate = dateAvecJourSemaine(jour);

  final confirme = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text(AppStrings.reattribuerTitre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AppStrings.reattribuerTexte(
              membre: candidat.membre.nomAffiche,
              jourEtDate: jourEtDate,
              creneau: libelleCreneau,
            ),
          ),
          if (!candidat.estDisponible) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _Avertissement(
              icone: context.statuts
                  .disponibilite(candidat.disponibilite)
                  .icone,
              texte: AppStrings.reattribuerHorsDispo(
                candidat.membre.nomAffiche,
              ),
            ),
          ],
          if (titulaireSortant != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _Avertissement(
              icone: Icons.swap_horiz,
              texte: AppStrings.reattribuerRemplace(titulaireSortant),
            ),
          ],
        ],
      ),
      actionsOverflowButtonSpacing: AppSpacing.entreCibles,
      actions: <Widget>[
        PrimaryButton(
          libelle: AppStrings.reattribuerAnnuler,
          variante: PrimaryButtonVariante.secondaire,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(
          libelle: AppStrings.reattribuerConfirmer,
          icone: Icons.published_with_changes,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirme ?? false;
}

/// Un fait à peser, pas une alarme : icône + texte, encre de surface, sans
/// vermillon. « L'app avertit, l'admin décide » (`docs/PRD.md § 7.4`).
class _Avertissement extends StatelessWidget {
  const _Avertissement({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Icon(
            icone,
            size: AppTouch.iconePetite,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: AppTextStyles.corpsSecondaire.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
