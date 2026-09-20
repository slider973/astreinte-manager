import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/hachures.dart';
import '../../domain/matrice_mois.dart';
import 'geometrie_matrice.dart';

/// La ligne « Disponibles » — **le premier regard** (brief § 6.4).
///
/// Un chiffre par colonne : combien de pompiers sont disponibles ce jour-là,
/// sur ce créneau. C'est la première chose que le chef lit, avant d'avoir
/// défilé d'un pixel, et c'est elle qui lui dit où regarder.
///
/// **Le compte ignore les filtres.** Masquer les non-saisis ou chercher
/// « Dubois » ne change jamais ce chiffre : c'est le nombre de pompiers
/// disponibles dans la caserne, pas dans la vue.
///
/// Deux seuils seulement, et ils se justifient seuls : personne, ou personne
/// en réserve. L'effectif requis par créneau appartient au ticket 017.
class CasesDisponibles extends StatelessWidget {
  const CasesDisponibles({
    required this.matrice,
    required this.jour,
    required this.date,
    super.key,
  });

  final MatriceMois matrice;

  /// Le jour du mois, en base 1.
  final int jour;

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: GeoMatrice.hauteurDisponibles,
      child: Row(
        children: <Widget>[
          _CaseCompte(
            compte: matrice.disponibles(jour, CreneauType.jour),
            date: date,
            creneau: CreneauType.jour,
          ),
          const SizedBox(width: GeoMatrice.ecartCreneaux),
          _CaseCompte(
            compte: matrice.disponibles(jour, CreneauType.nuit),
            date: date,
            creneau: CreneauType.nuit,
          ),
        ],
      ),
    );
  }
}

class _CaseCompte extends StatelessWidget {
  const _CaseCompte({
    required this.compte,
    required this.date,
    required this.creneau,
  });

  final int compte;
  final DateTime date;
  final CreneauType creneau;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // L'ocre d'attente du système : la même encre et le même fond que
    // « en attente d'une action humaine », qui est exactement ce que dit une
    // journée sans personne.
    final ocre = context.statuts.attribution(AttributionEtat.propose);

    final (Color fond, Color encre, bool hachure) = switch (compte) {
      0 => (ocre.fond, ocre.encre, true),
      1 => (ocre.fond, ocre.encre, false),
      _ => (
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.onSurfaceVariant,
        false,
      ),
    };

    final jourEtDate = dateAvecJourSemaine(date);
    final libelle = compte == 0
        ? AppStrings.matriceDisponiblesAucun(
            jourEtDate: jourEtDate,
            creneau: context.statuts.creneau(creneau).libelle,
          )
        : AppStrings.matriceDisponiblesSemantique(
            jourEtDate: jourEtDate,
            creneau: context.statuts.creneau(creneau).libelle,
            n: compte,
          );

    return Semantics(
      label: libelle,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: GeoMatrice.colonne,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fond,
            borderRadius: AppRadius.caseRegistreRadius,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Un zéro est **hachuré** : il se voit à un mètre et il se voit
              // en noir et blanc. La couleur n'est jamais seule.
              if (hachure)
                Positioned.fill(
                  child: Hachures(
                    encre: encre,
                    borderRadius: AppRadius.caseRegistreRadius,
                  ),
                ),
              Text(
                // Au-delà de 99 — impossible à soixante membres — le nombre
                // est tronqué plutôt que de déborder sa case.
                compte > 99 ? '99' : '$compte',
                style: AppTextStyles.etiquette.copyWith(
                  color: encre,
                  fontFamily: AppFonts.nombre,
                  fontFeatures: AppTextStyles.chiffresTabulaires,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
