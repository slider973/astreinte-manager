import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/abonnement.dart';

/// Les deux formules, **en lignes réglées et non en cartes de tarifs**.
///
/// Aucune n'est « recommandée », aucune n'a de pastille : on ne pousse pas une
/// caserne de bénévoles vers l'engagement long. Les deux boutons sont
/// `secondaire` — deux blocs d'encre pleins se disputeraient l'œil.
class FormulesBloc extends StatelessWidget {
  const FormulesBloc({
    required this.etat,
    required this.formuleEnCours,
    required this.onSouscrire,
    super.key,
  });

  final EtatAbonnement etat;

  /// La formule dont la session s'ouvre, ou `null`.
  final FormuleAbonnement? formuleEnCours;

  final ValueChanged<FormuleAbonnement> onSouscrire;

  @override
  Widget build(BuildContext context) {
    final tarifs = etat.tarifs;
    final raison = etat.raisonSouscriptionImpossible;
    final actif = etat.peutSouscrire;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _LigneFormule(
          libelle: AppStrings.abonnementFormuleMensuelle,
          montant: AppStrings.abonnementMontant(
            tarifs.mensuelCentimes,
            devise: tarifs.devise,
          ),
          periode: AppStrings.abonnementPeriodeMensuelle,
          chargement: formuleEnCours == FormuleAbonnement.mensuelle,
          raison: raison,
          onSouscrire: actif
              ? () => onSouscrire(FormuleAbonnement.mensuelle)
              : null,
        ),
        const AppDivider(),
        _LigneFormule(
          libelle: AppStrings.abonnementFormuleAnnuelle,
          montant: AppStrings.abonnementMontant(
            tarifs.annuelCentimes,
            devise: tarifs.devise,
          ),
          periode: AppStrings.abonnementPeriodeAnnuelle,
          // L'économie est **calculée**, jamais écrite en dur : elle suit un
          // changement de prix chez le prestataire sans recompilation.
          mention: tarifs.economieCentimes > 0
              ? AppStrings.abonnementEconomie(
                  AppStrings.abonnementMontant(
                    tarifs.economieCentimes,
                    devise: tarifs.devise,
                  ),
                )
              : null,
          chargement: formuleEnCours == FormuleAbonnement.annuelle,
          raison: raison,
          onSouscrire: actif
              ? () => onSouscrire(FormuleAbonnement.annuelle)
              : null,
        ),
      ],
    );
  }
}

class _LigneFormule extends StatelessWidget {
  const _LigneFormule({
    required this.libelle,
    required this.montant,
    required this.periode,
    required this.chargement,
    required this.onSouscrire,
    this.mention,
    this.raison,
  });

  final String libelle;
  final String montant;
  final String periode;
  final String? mention;
  final bool chargement;
  final String? raison;
  final VoidCallback? onSouscrire;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(libelle, style: theme.textTheme.titleMedium),
              ),
              // Le montant prend le cut Mono et les chiffres tabulaires : c'est
              // une mesure, et les deux lignes doivent s'aligner.
              Text(
                montant,
                style: AppTextStyles.nombre.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                periode,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (mention != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              mention!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            libelle: AppStrings.abonnementSouscrire,
            libelleAnnonce: AppStrings.abonnementSouscrireSemantique(libelle),
            variante: PrimaryButtonVariante.secondaire,
            icone: Icons.credit_card_outlined,
            chargement: chargement,
            onPressed: onSouscrire,
            // `DESIGN.md § Buttons` : un bouton grisé sans explication est un
            // défaut. La raison est à côté du contrôle, pas en info-bulle.
            raisonDesactivation: onSouscrire == null ? raison : null,
          ),
        ],
      ),
    );
  }
}
