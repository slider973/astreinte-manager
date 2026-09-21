import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../domain/planning_caserne_providers.dart';
import 'bascule_deux.dart';

/// Les deux vues de la portée « Moi ».
enum VueAstreintes { liste, calendrier }

/// La bascule « Liste » / « Calendrier ».
///
/// **Elle appartient à la portée « Moi »** et vit dans son sous-arbre : la
/// portée « La caserne » n'a qu'une forme, et deux rangées de boutons empilées
/// coûteraient 128 dp de chrome sur un téléphone de 844 (`design/023 § 2`).
class BasculeVue extends StatelessWidget {
  const BasculeVue({
    required this.vue,
    required this.onChoisir,
    super.key,
    this.calendrierIndisponible,
  });

  final VueAstreintes vue;
  final ValueChanged<VueAstreintes> onChoisir;

  /// Pourquoi « Calendrier » est inerte, ou `null` quand il ne l'est pas. Un
  /// contrôle désactivé sans raison est un défaut (`DESIGN.md § Buttons`).
  final String? calendrierIndisponible;

  @override
  Widget build(BuildContext context) => BasculeDeux(
    label: AppStrings.astreintesVueLabel,
    dessous: calendrierIndisponible,
    premier: SegmentBascule(
      libelle: AppStrings.astreintesVueListe,
      icone: Icons.view_list_outlined,
      choisi: vue == VueAstreintes.liste,
      onChoisir: () => onChoisir(VueAstreintes.liste),
    ),
    second: SegmentBascule(
      libelle: AppStrings.astreintesVueCalendrier,
      icone: Icons.calendar_month_outlined,
      choisi: vue == VueAstreintes.calendrier,
      onChoisir: calendrierIndisponible != null
          ? null
          : () => onChoisir(VueAstreintes.calendrier),
      raison: calendrierIndisponible,
    ),
  );
}

/// La bascule « Moi » / « La caserne », en tête de l'écran.
///
/// Les deux portées lisent la **même** table sous la **même** politique : ce
/// sont deux filtres d'une donnée, pas deux écrans (`design/027 § 4`). D'où un
/// sélecteur, et non une sixième destination.
class BasculePortee extends StatelessWidget {
  const BasculePortee({
    required this.portee,
    required this.onChoisir,
    super.key,
  });

  final PorteeAstreintes portee;
  final ValueChanged<PorteeAstreintes> onChoisir;

  @override
  Widget build(BuildContext context) => BasculeDeux(
    label: AppStrings.porteeLabel,
    premier: SegmentBascule(
      libelle: AppStrings.porteeMoi,
      icone: Icons.person_outline,
      choisi: portee == PorteeAstreintes.moi,
      onChoisir: () => onChoisir(PorteeAstreintes.moi),
    ),
    second: SegmentBascule(
      libelle: AppStrings.porteeCaserne,
      icone: Icons.groups_outlined,
      choisi: portee == PorteeAstreintes.caserne,
      onChoisir: () => onChoisir(PorteeAstreintes.caserne),
    ),
  );
}
