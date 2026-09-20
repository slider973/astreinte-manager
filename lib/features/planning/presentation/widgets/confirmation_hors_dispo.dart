import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/candidat.dart';

/// La confirmation d'une attribution **hors des disponibilités**.
///
/// Le seul dialogue de cet écran, et il est mérité. Le quota, lui, n'en ouvre
/// aucun : c'est un réglage du membre, affiché en clair sur sa ligne avant le
/// geste, et un dialogue de plus n'apprendrait rien au chef qu'il n'ait déjà
/// sous les yeux. Une non-disponibilité est un **refus explicite**, qui sera
/// tracé en base (`was_available = false`) et dans le journal de la caserne.
///
/// La phrase distingue les deux cas que le produit refuse de confondre :
/// **s'être déclaré absent n'est pas ne pas avoir répondu.**
Future<bool> confirmerHorsDispo(
  BuildContext context, {
  required Candidat candidat,
  required DateTime jour,
  required CreneauType creneau,
}) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text(AppStrings.planningHorsDispoTitre),
      content: Text(
        AppStrings.planningHorsDispoTexte(
          membre: candidat.membre.nomAffiche,
          jourEtDate: dateAvecJourSemaine(jour),
          creneau: context.statuts.creneau(creneau).libelle,
          absent: candidat.disponibilite == DisponibiliteEtat.absent,
        ),
      ),
      actionsOverflowButtonSpacing: AppSpacing.entreCibles,
      actions: <Widget>[
        PrimaryButton(
          libelle: AppStrings.planningHorsDispoAnnuler,
          variante: PrimaryButtonVariante.secondaire,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(
          libelle: AppStrings.planningHorsDispoValider,
          icone: Icons.person_add_alt_1,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirme ?? false;
}
