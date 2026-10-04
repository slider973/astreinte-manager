import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/caserne/caserne_providers.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/reseau/connectivite.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../astreintes/domain/astreinte.dart';
import '../../../astreintes/domain/astreintes_providers.dart';
import '../../domain/demande_echange.dart';
import '../../domain/echange.dart';
import '../../domain/echanges_providers.dart';
import 'carte_echange.dart';
import 'detail_echange.dart';

/// Le point d'entrée d'un échange, **dans chaque bloc de créneau** de la
/// feuille d'astreinte, sous « Ajouter à mon calendrier » (`design/073 § 6.1`).
///
/// - absent sur une astreinte qui n'est pas proposable (passée, planning
///   archivé) : il n'y a rien à proposer ;
/// - remplacé par **la carte d'échange** quand une demande est déjà en cours
///   sur cette garde ;
/// - grisé avec sa raison écrite dessous : trop tard, hors ligne, caserne
///   suspendue.
class BoutonEchangeAstreinte extends ConsumerWidget {
  const BoutonEchangeAstreinte({
    required this.astreinte,
    required this.heures,
    super.key,
  });

  final Astreinte astreinte;
  final HeuresAffichage heures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maintenant = ref.watch(horlogeAstreintesProvider)();
    if (!proposable(astreinte, maintenant)) return const SizedBox.shrink();

    final etat = ref.watch(echangesControllerProvider).value;
    final enCours = etat?.enCoursSur(astreinte.id);
    if (etat != null && enCours != null) {
      return CarteEchange(
        echange: enCours,
        moi: etat.moi,
        heures: heures,
        maintenant: maintenant,
        onOuvrir: () => unawaited(ouvrirDetailEchange(context, enCours.id)),
      );
    }

    final reglages =
        ref.watch(reglagesEchangeProvider).value ?? ReglagesEchange.defaut;
    final blocage = blocageProposition(
      astreinte: astreinte,
      reglages: reglages,
      maintenant: maintenant,
      enLigne: ref.watch(enLigneProvider).value ?? true,
      lectureSeule: ref.watch(lectureSeuleCaserneProvider),
    );
    final String? raison;
    switch (blocage) {
      case BlocageProposition.lectureSeule:
        raison = AppStrings.echangeLectureSeuleRaison;
      case BlocageProposition.horsLigne:
        raison = AppStrings.echangeHorsLigneRaison;
      case BlocageProposition.tropTard:
        final echeance = reglages.echeance(<GardeEchange>[gardeDe(astreinte)]);
        raison = AppStrings.echangeTropTard(
          dateAvecJourSemaine(echeance),
          heureMinute(echeance),
        );
      case null:
        raison = null;
    }

    return PrimaryButton(
      libelle: AppStrings.echangeProposer,
      icone: Icons.swap_horiz,
      variante: PrimaryButtonVariante.secondaire,
      pleineLargeur: true,
      onPressed: raison == null
          ? () {
              final routeur = GoRouter.of(context);
              Navigator.of(context).pop();
              unawaited(
                routeur.pushNamed<void>(
                  AppRoutes.demandeEchangeName,
                  queryParameters: AppRoutes.parametresDemandeEchange(
                    attribution: astreinte.id,
                    etape: EtapeDemande.qui,
                  ),
                ),
              );
            }
          : null,
      raisonDesactivation: raison,
    );
  }
}
