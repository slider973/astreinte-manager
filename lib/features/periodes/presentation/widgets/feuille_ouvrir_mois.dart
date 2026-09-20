import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../dispos/domain/periode_saisie.dart';
import '../../domain/taux_saisie.dart';

/// Demande **quel mois** ouvrir à la saisie, et rend son année et son mois.
///
/// Rend `null` si la feuille a été refermée sans choisir.
///
/// Les douze prochains mois, à partir du mois courant. Aucun mois écoulé :
/// `create_period` les refuse (`period_month_in_past`), et proposer un choix
/// que la base rejette est une promesse qu'on ne tient pas. Les mois déjà
/// ouverts restent **visibles mais inertes**, avec leur état : montrer ce qui
/// est déjà fait évite le double appui et la question « pourquoi rien ne se
/// passe ».
Future<CleMois?> afficherOuvrirMois({
  required BuildContext context,
  required List<PeriodeSaisie> existantes,
  DateTime? maintenant,
}) => showModalBottomSheet<CleMois>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => FeuilleOuvrirMois(
    existantes: existantes,
    maintenant: maintenant ?? DateTime.now(),
  ),
);

/// Le contenu de la feuille. Public pour être monté seul dans un test.
class FeuilleOuvrirMois extends StatelessWidget {
  const FeuilleOuvrirMois({
    required this.existantes,
    required this.maintenant,
    super.key,
  });

  /// Le nombre de mois proposés : une année, à partir du mois courant.
  static const int moisProposes = 12;

  final List<PeriodeSaisie> existantes;
  final DateTime maintenant;

  PeriodeSaisie? _existante(int annee, int mois) {
    for (final periode in existantes) {
      if (periode.annee == annee && periode.mois == mois) return periode;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return Semantics(
      namesRoute: true,
      label: AppStrings.periodeCreerTitre,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  AppStrings.periodeCreerTitre,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppStrings.periodeCreerAide,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (var decalage = 0;
                    decalage < FeuilleOuvrirMois.moisProposes;
                    decalage++)
                  _rangee(context, decalage),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rangee(BuildContext context, int decalage) {
    // `DateTime` normalise un mois > 12 : décembre + 1 est bien janvier de
    // l'année suivante, sans arithmétique maison.
    final jour = DateTime(maintenant.year, maintenant.month + decalage);
    final deja = _existante(jour.year, jour.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _RangeeMois(
          libelle: AppStrings.moisNomEtAnnee(jour.month, jour.year),
          etat: deja?.statut,
          onChoisir: deja != null
              ? null
              : () => Navigator.of(context).pop<CleMois>(
                  (annee: jour.year, mois: jour.month),
                ),
        ),
        const AppDivider(),
      ],
    );
  }
}

/// Une rangée de 56 dp : le mois, et ce qu'il en est déjà.
class _RangeeMois extends StatelessWidget {
  const _RangeeMois({
    required this.libelle,
    required this.etat,
    required this.onChoisir,
  });

  final String libelle;

  /// `null` quand le mois n'existe pas encore : c'est le seul cas où la
  /// rangée est actionnable.
  final PeriodeEtat? etat;

  final VoidCallback? onChoisir;

  String? get _mention => switch (etat) {
    null => null,
    PeriodeEtat.ouverte => AppStrings.periodeCreerDejaOuvert,
    PeriodeEtat.verrouillee => AppStrings.periodeCreerDejaVerrouille,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mention = _mention;

    final contenu = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.champ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                libelle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: onChoisir == null
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
            if (mention != null)
              Row(
                children: <Widget>[
                  Icon(
                    etat == PeriodeEtat.ouverte ? Icons.lock_open : Icons.lock,
                    size: AppTouch.iconePetite,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    mention,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );

    if (onChoisir == null) {
      return Semantics(
        label: '$libelle, $mention',
        excludeSemantics: true,
        child: contenu,
      );
    }

    return Semantics(
      button: true,
      label: libelle,
      child: InkWell(onTap: onChoisir, child: contenu),
    );
  }
}
