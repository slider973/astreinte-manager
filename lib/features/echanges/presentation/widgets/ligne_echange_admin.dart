import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/carre_creneau.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/echange.dart';
import '../etat_echange.dart';

/// Une ligne de la file des échanges (`design/073 § 8.2`) : bloc réglé du
/// papier blanc de l'administrateur, 72 dp, une seule action — ouvrir.
///
/// En compact, elle **s'empile** plutôt que de tronquer : date et créneau,
/// noms, puis badge et mention.
class LigneEchangeAdmin extends StatelessWidget {
  const LigneEchangeAdmin({
    required this.echange,
    required this.maintenant,
    required this.onOuvrir,
    super.key,
    this.choisie = false,
  });

  final Echange echange;
  final DateTime maintenant;
  final VoidCallback onOuvrir;
  final bool choisie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final descripteur = descripteurEchange(context, echange);
    final a = _nom(echange.demandeurNom);
    final b = _nom(echange.pairNom);
    final noms = echange.aLaCaserne && echange.repreneurId == null
        ? AppStrings.echangesLigneCherche(a)
        : echange.estEchange
        ? AppStrings.echangesLigneEchange(a, b)
        : AppStrings.echangesLigneCede(a, b);
    final rendue = echange.gardeRendue;
    final accepte = echange.accepteLe;
    final mention = <String>[
      if (rendue != null)
        AppStrings.echangesLigneContre(gardeCourte(context, rendue))
      else
        AppStrings.echangesCession,
      if (accepte != null)
        AppStrings.echangesLigneAccepte(
          formaterInstantRelatif(accepte, maintenant: maintenant),
        ),
      if (echange.statut.enCours)
        AppStrings.echangesLigneExpire(
          formaterDateCourte(echange.expireLe),
          heureMinute(echange.expireLe),
        ),
    ].join(' · ');

    return Semantics(
      button: true,
      selected: choisie,
      label: '${gardeCourte(context, echange.garde)}, $noms, '
          '${descripteur.libelle}. $mention',
      excludeSemantics: true,
      child: Material(
        color: choisie ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controleRadius,
          side: BorderSide(
            color: choisie ? scheme.primary : scheme.outlineVariant,
            width: choisie ? AppStroke.etat : AppStroke.filet,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOuvrir,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CarreCreneau(creneau: echange.garde.creneau),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          gardeCourte(context, echange.garde),
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(noms, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            StatusBadge.descripteur(
                              descripteur,
                              taille: StatusBadgeTaille.compacte,
                            ),
                            Text(
                              mention,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _nom(String nom) =>
    nom.trim().isEmpty ? AppStrings.echangeMembreInconnu : nom.trim();
