import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/carre_creneau.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../../../core/widgets/rangee_garde.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../astreintes/domain/astreinte.dart';
import '../../domain/echange.dart';
import '../etat_echange.dart';

/// Les rangées « Tu donnes / Tu prends » d'une demande, **toujours écrites du
/// point de vue du lecteur** (`design/073 § 3`).
///
/// - A lit « Tu donnes » sa garde, puis « Tu prends » celle de B ;
/// - B lit, pour un échange, « Tu donnes » sa garde **d'abord** — ce qu'on
///   perd se lit avant ce qu'on gagne —, puis « Tu prends » ; pour une
///   cession, une seule rangée, « Tu prends » ;
/// - l'administrateur, qui n'est ni l'un ni l'autre, lit les noms :
///   « Antoine C. cède », « Chloé C. cède ».
class PaireGardes extends StatelessWidget {
  const PaireGardes({
    required this.echange,
    required this.lecteur,
    required this.heures,
    super.key,
  });

  final Echange echange;
  final LecteurEchange lecteur;
  final HeuresAffichage heures;

  @override
  Widget build(BuildContext context) {
    final rendue = echange.gardeRendue;
    final rangees = <(String, SensGarde, GardeEchange)>[
      ...switch (lecteur) {
        LecteurEchange.demandeur => <(String, SensGarde, GardeEchange)>[
          (AppStrings.echangeTuDonnes, SensGarde.donne, echange.garde),
          if (rendue != null)
            (AppStrings.echangeTuPrends, SensGarde.prend, rendue),
        ],
        LecteurEchange.pair || LecteurEchange.disponible =>
          <(String, SensGarde, GardeEchange)>[
            if (rendue != null)
              (AppStrings.echangeTuDonnes, SensGarde.donne, rendue),
            (AppStrings.echangeTuPrends, SensGarde.prend, echange.garde),
          ],
        LecteurEchange.admin => <(String, SensGarde, GardeEchange)>[
          (
            AppStrings.echangesCede(_nom(echange.demandeurNom)),
            SensGarde.neutre,
            echange.garde,
          ),
          if (rendue != null)
            (
              AppStrings.echangesCede(_nom(echange.pairNom)),
              SensGarde.neutre,
              rendue,
            ),
        ],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < rangees.length; i++) ...<Widget>[
          if (i > 0) const AppDivider(),
          _rangee(rangees[i]),
        ],
      ],
    );
  }

  Widget _rangee((String, SensGarde, GardeEchange) r) {
    final (debut, fin) = bornes(heures, r.$3.creneau);
    return RangeeGarde(
      verbe: r.$1,
      sens: r.$2,
      jour: r.$3.jour,
      creneau: r.$3.creneau,
      debut: debut,
      fin: fin,
    );
  }
}

/// **La carte d'échange** : le même objet pour A, pour B et pour
/// l'administrateur ; seul ce qui l'entoure change selon qui regarde
/// (`design/073 § 3`).
///
/// La garde cédée (ou la paire de gardes pour un échange), de qui à qui, le
/// badge d'état — marque, icône, libellé — et la ligne de détail.
class CarteEchange extends StatelessWidget {
  const CarteEchange({
    required this.echange,
    required this.moi,
    required this.heures,
    required this.maintenant,
    super.key,
    this.onOuvrir,
    this.tampon = false,
  });

  final Echange echange;
  final String moi;
  final HeuresAffichage heures;
  final DateTime maintenant;
  final VoidCallback? onOuvrir;

  /// Le tampon du système, une fois, quand la carte passe à « Validé » sous
  /// les yeux du pompier.
  final bool tampon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final descripteur = descripteurEchange(context, echange);
    final detail = ligneDetail(echange, moi: moi, maintenant: maintenant);
    final lecteur = echange.lecteur(moi);
    final noms = <String>[
      _nom(echange.demandeurNom),
      if (echange.aLaCaserne && echange.repreneurId == null)
        AppStrings.echangeCaserne
      else
        _nom(echange.pairNom),
    ].join(' · ');
    final (debut, fin) = bornes(heures, echange.garde.creneau);

    return Semantics(
      button: onOuvrir != null,
      label: '${AppStrings.echangeCarteSemantique(titreEchange(echange), descripteur.libelle)}. $detail',
      excludeSemantics: true,
      child: CarteDouce(
        onTap: onOuvrir,
        hauteurMin: AppTouch.cible,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (echange.estEchange)
              PaireGardes(echange: echange, lecteur: lecteur, heures: heures)
            else
              Row(
                children: <Widget>[
                  CarreCreneau(creneau: echange.garde.creneau),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          gardeTitre(context, echange.garde),
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          AppStrings.astreintesIntervalle(debut, fin),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              noms,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            StatusBadge.descripteur(descripteur, tampon: tampon),
            const SizedBox(height: AppSpacing.xs),
            Text(
              detail,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _nom(String? nom) => (nom ?? '').trim().isEmpty
    ? AppStrings.echangeMembreInconnu
    : nom!.trim();
