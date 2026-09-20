import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/day_cell.dart';
import '../../domain/creneau_cle.dart';
import '../controllers/saisie_controller.dart';

/// Un jour de la grille, **abonné à sa seule tranche d'état**.
///
/// C'est la pièce qui tient la promesse « aucun clignotement pendant la
/// peinture » : le sélecteur ne rend que l'[EtatJour] de cette date, donc le
/// doigt qui traverse le 14 ne reconstruit pas les soixante et une autres
/// cases. Une case qui change ne fait pas bouger ses voisines.
class JourDeGrille extends ConsumerWidget {
  const JourDeGrille({
    required this.date,
    required this.orientation,
    super.key,
    this.horsMois = false,
    this.aujourdhui = false,
    this.deuxNiveaux = false,
  });

  final DateTime date;
  final DayCellOrientation orientation;

  /// Jour d'un mois voisin, dans la vue calendaire : atténué et inerte.
  final bool horsMois;

  final bool aujourdhui;

  /// Registre à deux niveaux, aux très grandes échelles de texte.
  final bool deuxNiveaux;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(
      saisieControllerProvider.select(
        (valeur) => valeur.value?.pourJour(date) ?? EtatJour.vide,
      ),
    );

    final controleur = ref.read(saisieControllerProvider.notifier);
    final cleJour = CreneauCle(date, CreneauType.jour);
    final cleNuit = CreneauCle(date, CreneauType.nuit);
    final actionnable = !etat.verrouille && !horsMois;
    final ferie = nomJourFerie(date);

    return DayCell(
      numero: date.day,
      nomJour: nomJourCourt(date),
      dateLongue: dateAvecJourSemaine(date),
      orientation: orientation,
      deuxNiveaux: deuxNiveaux,
      weekend:
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday,
      nomJourFerie: ferie,
      aujourdhui: aujourdhui,
      horsMois: horsMois,
      verrouille: etat.verrouille,
      jour: DaySlot(
        etat: etat.jour,
        erreur: etat.erreurJour,
        onTap: actionnable ? () => controleur.basculer(cleJour) : null,
        onDragEnter: actionnable
            ? () => controleur.toucherPendantGeste(cleJour)
            : null,
      ),
      nuit: DaySlot(
        etat: etat.nuit,
        erreur: etat.erreurNuit,
        onTap: actionnable ? () => controleur.basculer(cleNuit) : null,
        onDragEnter: actionnable
            ? () => controleur.toucherPendantGeste(cleNuit)
            : null,
      ),
    );
  }
}

/// La réglure du registre, peinte **sans coûter de hauteur**.
///
/// Filet 1 dp entre deux jours, et filet 2 dp `outline` au-dessus de chaque
/// lundi : c'est ce qui donne au mois son rythme hebdomadaire sans numéro de
/// semaine (brief 011 § 6.5). Un `DecoratedBox` peint par-dessus le contenu,
/// donc la ligne garde exactement sa hauteur fixe.
class ReglureJour extends StatelessWidget {
  const ReglureJour({
    required this.date,
    required this.premiere,
    required this.child,
    super.key,
  });

  final DateTime date;
  final bool premiere;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (premiere) return child;

    final theme = Theme.of(context);
    final lundi = date.weekday == DateTime.monday;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: lundi
                ? theme.colorScheme.outline
                : context.statuts.filetDecoratif,
            width: lundi ? AppStroke.etat : AppStroke.filet,
          ),
        ),
      ),
      child: child,
    );
  }
}
