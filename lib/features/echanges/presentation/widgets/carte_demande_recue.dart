import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/carre_creneau.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../domain/echange.dart';
import '../etat_echange.dart';

/// Une demande reçue ou « à reprendre », **dans la forme de
/// `CarteProposition`** (`design/073 § 7.1`) : carte douce, carré de créneau,
/// titre, ligne, ancienneté à droite. Une icône de 20 dp précède la ligne —
/// `swap_horiz` pour une demande à toi, `person_search` pour « à reprendre » —
/// et c'est, avec le texte, ce qui la sépare d'une proposition du planning.
class CarteDemandeRecue extends StatelessWidget {
  const CarteDemandeRecue({
    required this.echange,
    required this.maintenant,
    required this.onOuvrir,
    super.key,
  });

  final Echange echange;
  final DateTime maintenant;
  final VoidCallback onOuvrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nom = echange.demandeurNom.trim().isEmpty
        ? AppStrings.echangeMembreInconnu
        : echange.demandeurNom.trim();
    final rendue = echange.gardeRendue;
    final ligne = echange.aLaCaserne
        ? AppStrings.echangeLigneReprendre(nom)
        : rendue != null
        ? AppStrings.echangeLigneEchange(nom, phraseGarde(rendue))
        : AppStrings.echangeLigneCession(nom);
    final titre = gardeTitre(context, echange.garde);
    final mention = formaterInstantRelatif(echange.creeLe, maintenant: maintenant);

    return Semantics(
      button: true,
      label: '$titre, $ligne, $mention',
      excludeSemantics: true,
      child: CarteDouce(
        onTap: onOuvrir,
        hauteurMin: AppTouch.cible,
        child: Row(
          children: <Widget>[
            CarreCreneau(creneau: echange.garde.creneau),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    titre,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Icon(
                          echange.aLaCaserne
                              ? Icons.person_search
                              : Icons.swap_horiz,
                          size: AppTouch.icone,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          ligne,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              mention,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
