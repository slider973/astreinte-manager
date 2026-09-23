import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_status.dart';

/// **Le carré d'initiale d'une ligne de liste du monde du pompier**
/// (`design/064 § 2`) : 40 × 40, rayon `feuille` = 12, l'icône du créneau et
/// sa lettre — « J » ou « N » — en `on-primary-container` sur
/// `primary-container`.
///
/// L'initiale seule serait une lettre sans système : « J » et « N » ne se
/// devinent pas. L'icône du créneau la double, à la taille où elle se lit
/// encore, et la phrase annoncée de la ligne qui le porte dit « Jour » ou
/// « Nuit » en toutes lettres. Le carré lui-même est **décoratif** — il est
/// toujours posé dans une ligne qui porte sa propre sémantique, et un lecteur
/// d'écran qui épellerait « N » par-dessus « Nuit · 19:00 – 07:00 » lirait
/// deux fois la même chose.
///
/// **Écrit trois fois avant le 064d** — la ligne de proposition de l'accueil,
/// la carte de proposition de la Boîte, la ligne d'astreinte —, il vit ici
/// depuis. Trois copies d'un même carré divergent au premier réglage, et le
/// pompier lirait alors trois formes de la même marque à trois écrans
/// d'intervalle.
class CarreCreneau extends StatelessWidget {
  const CarreCreneau({required this.creneau, super.key, this.attenue = false});

  /// Côté du carré. La même valeur partout : c'est ce qui aligne les titres
  /// de toutes les lignes de liste du pompier sur une seule colonne.
  static const double cote = 40;

  final CreneauType creneau;

  /// Une astreinte **passée** : le carré descend d'un cran de surface plutôt
  /// que de garder l'indigo, réservé à ce qui vient.
  final bool attenue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final descripteur = context.statuts.creneau(creneau);
    final encre = attenue ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;

    return ExcludeSemantics(
      child: Container(
        width: cote,
        height: cote,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: attenue ? scheme.surfaceContainerHigh : scheme.primaryContainer,
          borderRadius: AppRadius.feuilleCarreeRadius,
        ),
        // Le contenu rétrécit plutôt que d'être coupé : à ×2 d'échelle de
        // texte, la lettre et son icône ne tiennent plus dans quarante points,
        // et un carré qui grandirait décalerait toute la colonne des titres.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                descripteur.icone,
                size: AppTouch.iconePetite,
                color: encre,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                descripteur.libelle.characters.first.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(color: encre),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
