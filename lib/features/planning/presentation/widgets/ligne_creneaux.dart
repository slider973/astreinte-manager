import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/hachures.dart';
import '../../../../core/widgets/slot_chip.dart';
import '../../domain/creneau_planning.dart';
import '../../domain/planning_mois.dart';
import 'geometrie_matrice.dart';

/// L'état de couverture, prêt à afficher : marque, icône, libellé, encre.
///
/// **Aucune couleur n'est écrite ici** : les trois encres sont empruntées à
/// des familles du thème qui disent déjà la même chose — l'ocre de ce qui
/// attend une action humaine, le vert de ce qui est acquis, le bleu de
/// réglure des faits neutres. Les icônes, elles, sont propres à cette famille :
/// aucune ne se confond avec celles de la disponibilité ou de l'attribution.
///
/// [personne] ajoute les hachures : le créneau que **personne** ne couvre se
/// voit à un mètre et en noir et blanc, comme le « 0 disponible » du
/// ticket 016.
StatusDescriptor descripteurCouverture(
  BuildContext context,
  EtatCouverture etat, {
  bool personne = false,
}) {
  final statuts = context.statuts;
  return switch (etat) {
    EtatCouverture.aPourvoir => StatusDescriptor(
      icone: Icons.person_search,
      libelle: AppStrings.planningAPourvoir,
      encre: statuts.attribution(AttributionEtat.propose).encre,
      fond: statuts.attribution(AttributionEtat.propose).fond,
      hachure: personne,
    ),
    EtatCouverture.pourvu => StatusDescriptor(
      icone: Icons.done_all,
      libelle: AppStrings.planningPourvu,
      encre: statuts.attribution(AttributionEtat.accepte).encre,
      fond: statuts.attribution(AttributionEtat.accepte).fond,
    ),
    EtatCouverture.surPourvu => StatusDescriptor(
      icone: Icons.group_add,
      libelle: AppStrings.planningSurPourvu,
      encre: statuts.planning(PlanningEtat.publie).encre,
      fond: statuts.planning(PlanningEtat.publie).fond,
    ),
  };
}

/// **La ligne des créneaux** — ce qu'il reste à faire, avant tout défilement.
///
/// Un chiffre sur un chiffre par colonne : combien de pompiers sont attribués,
/// sur combien sont requis. La **fraction est la marque** : la ligne
/// « Disponibles », juste en dessous, porte un chiffre nu. `4` et `1/2` ne se
/// confondent pas, même à 28 px, même en niveaux de gris (`design/017 § 3`).
///
/// Elle ne se dessine pas tant que le planning du mois n'existe pas : une
/// fraction sur un mois sans créneaux ne voudrait rien dire.
class CasesCreneaux extends StatelessWidget {
  const CasesCreneaux({
    required this.planning,
    required this.jour,
    required this.date,
    required this.selectionne,
    required this.onCreneau,
    super.key,
  });

  final PlanningMois planning;

  /// Le jour du mois, en base 1.
  final int jour;

  final DateTime date;

  /// L'identifiant du créneau ouvert dans le panneau, ou `null`.
  final String? selectionne;

  final ValueChanged<String> onCreneau;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: GeoMatrice.hauteurCreneaux,
      child: Row(
        children: <Widget>[
          _CaseCreneau(
            couverture: planning.couverture(jour, CreneauType.jour),
            date: date,
            creneau: CreneauType.jour,
            selectionne: selectionne,
            onCreneau: onCreneau,
          ),
          const SizedBox(width: GeoMatrice.ecartCreneaux),
          _CaseCreneau(
            couverture: planning.couverture(jour, CreneauType.nuit),
            date: date,
            creneau: CreneauType.nuit,
            selectionne: selectionne,
            onCreneau: onCreneau,
          ),
        ],
      ),
    );
  }
}

class _CaseCreneau extends StatelessWidget {
  const _CaseCreneau({
    required this.couverture,
    required this.date,
    required this.creneau,
    required this.selectionne,
    required this.onCreneau,
  });

  final ({CreneauPlanning creneau, int pourvus, EtatCouverture etat})?
  couverture;
  final DateTime date;
  final CreneauType creneau;
  final String? selectionne;
  final ValueChanged<String> onCreneau;

  @override
  Widget build(BuildContext context) {
    final valeur = couverture;
    if (valeur == null) {
      return const SizedBox.square(dimension: GeoMatrice.colonne);
    }

    final theme = Theme.of(context);
    final descripteur = descripteurCouverture(
      context,
      valeur.etat,
      personne: valeur.pourvus == 0 && valeur.etat == EtatCouverture.aPourvoir,
    );
    final choisi = selectionne == valeur.creneau.id;

    // **28 px, donc pointeur seulement** : même règle que la case dense de la
    // matrice, sans exception. Au doigt, la ligne se lit et le panneau s'ouvre
    // depuis la vue par jour, en cibles de 48 dp.
    final actionnable = SlotChipDensite.dense.actionnableDans(context);

    final corps = PastilleCouverture(
      descripteur: descripteur,
      pourvus: valeur.pourvus,
      requis: valeur.creneau.effectifRequis,
      filet: choisi ? theme.colorScheme.primary : null,
    );

    return Semantics(
      // La clé nomme le créneau : c'est ce qui permet à un test de désigner
      // une colonne précise parmi soixante-deux.
      key: ValueKey<String>('creneau-${valeur.creneau.id}'),
      button: actionnable,
      selected: choisi,
      label: AppStrings.planningCouvertureSemantique(
        jourEtDate: dateAvecJourSemaine(date),
        creneau: context.statuts.creneau(creneau).libelle,
        pourvus: valeur.pourvus,
        requis: valeur.creneau.effectifRequis,
        etat: descripteur.libelle,
      ),
      onTapHint: actionnable ? AppStrings.planningCouvertureAction : null,
      excludeSemantics: true,
      child: actionnable
          ? InkWell(
              onTap: () => onCreneau(valeur.creneau.id),
              borderRadius: AppRadius.caseRegistreRadius,
              child: corps,
            )
          : corps,
    );
  }
}

/// La marque de couverture : la fraction sur son fond d'état, 28 px de côté.
///
/// Partagée par la ligne des créneaux et par la vue par jour, pour que les
/// deux compositions disent la même chose de la même façon. Elle ne porte ni
/// sémantique ni geste : son parent sait ce qu'elle désigne, elle non.
class PastilleCouverture extends StatelessWidget {
  const PastilleCouverture({
    required this.descripteur,
    required this.pourvus,
    required this.requis,
    super.key,
    this.filet,
  });

  final StatusDescriptor descripteur;
  final int pourvus;
  final int requis;

  /// Le contour 2 dp de la sélection, ou `null`.
  final Color? filet;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: GeoMatrice.colonne,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: descripteur.fond,
          borderRadius: AppRadius.caseRegistreRadius,
          border: filet == null
              ? null
              : Border.all(color: filet!, width: AppStroke.etat),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (descripteur.hachure)
              Positioned.fill(
                child: Hachures(
                  encre: descripteur.encre,
                  borderRadius: AppRadius.caseRegistreRadius,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: FittedBox(
                // Un effectif requis à deux chiffres reste lisible plutôt que
                // tronqué : même arbitrage que le compteur du ticket 004.
                fit: BoxFit.scaleDown,
                child: Text(
                  AppStrings.planningFraction(pourvus, requis),
                  style: AppTextStyles.etiquette.copyWith(
                    color: descripteur.encre,
                    fontFamily: AppFonts.nombre,
                    fontFeatures: AppTextStyles.chiffresTabulaires,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
