import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/plateforme/telechargement.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/astreinte.dart';
import '../../domain/calendrier_providers.dart';

/// **« Ajouter à mon agenda »** — un créneau, un fichier.
///
/// La réponse à qui ne veut pas s'abonner, ou à qui vient d'accepter une garde
/// et veut la voir tout de suite dans son agenda. L'abonnement du profil reste
/// la vraie réponse : celui-ci ne suit pas les réattributions
/// (`design/028-export-ics.md § 1`).
///
/// **Il ne charge rien.** Le fichier est composé sur l'appareil à partir de ce
/// que la feuille a déjà en main — c'est ce qui le fait marcher hors ligne,
/// comme le reste du détail (ticket 027). L'enregistrement passe par
/// `telechargementProvider` et rien d'autre : le mécanisme éprouvé du
/// ticket 034, partage système sur iPhone et ancre `download` ailleurs.
class BoutonAjoutCalendrier extends ConsumerWidget {
  const BoutonAjoutCalendrier({
    required this.astreinte,
    required this.heures,
    super.key,
    this.nomCaserne = '',
  });

  final Astreinte astreinte;
  final HeuresAffichage heures;
  final String nomCaserne;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(ajoutCalendrierControllerProvider);
    // **Seul le bouton concerné parle.** Sans ce filtre, appuyer sur « jour »
    // ferait apparaître une confirmation sous « nuit » dans la feuille d'une
    // journée à deux créneaux.
    final mien = etat.concerne(astreinte.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PrimaryButton(
          libelle: AppStrings.calendrierAjouterUne,
          libelleAnnonce: AppStrings.calendrierAjouterUneDit(
            dateAvecJourSemaine(astreinte.jour),
            astreinte.creneau == CreneauType.nuit
                ? AppStrings.creneauNuit
                : AppStrings.creneauJour,
          ),
          variante: PrimaryButtonVariante.secondaire,
          icone: Icons.event_available_outlined,
          chargement: mien && etat.enCours,
          onPressed: () => unawaited(
            ref
                .read(ajoutCalendrierControllerProvider.notifier)
                .ajouter(
                  astreinte: astreinte,
                  heures: heures,
                  nomCaserne: nomCaserne,
                ),
          ),
        ),
        if (mien)
          if (_phrase(etat) case final String phrase) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _Resultat(
              texte: phrase,
              enErreur: etat.resultat == ResultatTelechargement.impossible,
              enCours: etat.enCours,
            ),
          ],
      ],
    );
  }

  /// Ce qu'il y a à dire, ou `null` quand il n'y a rien à dire.
  ///
  /// **Un partage refermé ne dit rien** : ce n'est pas une panne, c'est un
  /// choix, et annoncer une erreur à qui vient d'annuler lui apprend à ne plus
  /// lire les messages (`design/034-rgpd-export.md § 4`).
  static String? _phrase(EtatAjoutCalendrier etat) {
    if (etat.enCours) return AppStrings.calendrierAjoutEnCours;
    return switch (etat.resultat) {
      ResultatTelechargement.enregistre => AppStrings.calendrierAjoutEnregistre(
        etat.nomFichier ?? '',
      ),
      ResultatTelechargement.partage => AppStrings.calendrierAjoutPartage,
      ResultatTelechargement.impossible => AppStrings.calendrierAjoutImpossible,
      ResultatTelechargement.annule => null,
      null => null,
    };
  }
}

/// Le résultat, **sur place**, sous le bouton — jamais dans un message passager
/// qui part avant qu'on ait fini de le lire. Porté par icône + libellé, la
/// couleur en quatrième (`DESIGN.md § Do's`).
class _Resultat extends StatelessWidget {
  const _Resultat({
    required this.texte,
    required this.enErreur,
    required this.enCours,
  });

  final String texte;
  final bool enErreur;
  final bool enCours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = enErreur
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            switch ((enErreur, enCours)) {
              (true, _) => Icons.error_outline,
              (false, true) => Icons.hourglass_top,
              (false, false) => Icons.check_circle_outline,
            },
            size: AppTouch.icone,
            color: encre,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(color: encre),
            ),
          ),
        ],
      ),
    );
  }
}
