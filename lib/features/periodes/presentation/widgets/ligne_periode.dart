import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../dispos/domain/periode_saisie.dart';
import '../../domain/taux_saisie.dart';
import 'jauge_saisie.dart';

/// Une ligne de la liste des mois : ce que la caserne sait du mois, et
/// **l'action qui lui correspond**, nommée.
///
/// Un mois ouvert se verrouille, un mois verrouillé se rouvre : il n'y a
/// jamais deux choix, donc jamais de menu `⋮`. Le bouton porte le verbe.
///
/// Ce n'est pas une carte : les lignes sont séparées par le filet du registre
/// (`DESIGN.md § Cards / Containers`).
class LignePeriode extends StatelessWidget {
  const LignePeriode({
    required this.periode,
    required this.onVerrouiller,
    required this.onRouvrir,
    super.key,
    this.taux,
    this.occupee = false,
  });

  final PeriodeSaisie periode;

  /// Le taux de saisie du mois, compté en base. `null` quand la lecture de
  /// `v_period_completion` a échoué : la ligne le dit, elle n'invente pas.
  final TauxSaisie? taux;

  /// Une écriture est en vol sur ce mois : le bouton garde sa place et son
  /// libellé, et porte l'indicateur.
  final bool occupee;

  final VoidCallback onVerrouiller;
  final VoidCallback onRouvrir;

  /// La ligne de faits : jusqu'à quand c'est ouvert, ou depuis quand c'est
  /// fermé.
  String get _faits => periode.ouverte
      ? AppStrings.moisOuvertJusquAuCourt(formaterDateLongue(periode.dateLimite))
      : AppStrings.periodeLigneVerrouillee(
          formaterDateCourte(periode.verrouilleeLe ?? periode.dateLimite),
          formaterDateCourte(periode.dateLimite),
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // `Wrap` et non `Row` : à grande échelle de texte, le badge passe
          // sous le nom du mois au lieu de le rogner.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(periode.libelle, style: theme.textTheme.titleMedium),
              StatusBadge.periode(
                periode.statut,
                taille: StatusBadgeTaille.compacte,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _faits,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Taux(taux: taux),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: PrimaryButton(
              libelle: periode.ouverte
                  ? AppStrings.periodeActionVerrouiller
                  : AppStrings.periodeActionRouvrir,
              variante: PrimaryButtonVariante.secondaire,
              icone: periode.ouverte ? Icons.lock_outline : Icons.lock_open,
              chargement: occupee,
              pleineLargeur: false,
              onPressed: periode.ouverte ? onVerrouiller : onRouvrir,
            ),
          ),
        ],
      ),
    );
  }
}

/// Le taux, ou son absence.
///
/// Il n'y a plus d'attente par ligne : les taux arrivent avec la liste, en une
/// requête pour tout l'écran. Reste le cas où la vue n'a pas pu être lue —
/// la ligne le dit, plutôt que d'afficher un zéro qui ressemblerait à
/// « personne n'a saisi ».
class _Taux extends StatelessWidget {
  const _Taux({required this.taux});

  final TauxSaisie? taux;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valeur = taux;

    if (valeur != null) return JaugeSaisie(taux: valeur);

    return Text(
      AppStrings.periodeTauxIndisponible,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
