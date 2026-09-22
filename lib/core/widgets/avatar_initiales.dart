import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Un disque d'initiales, pour dire une personne sans sa photo.
///
/// **Pas de photo, et c'est une décision** (`design/061 § 7`) : les pompiers
/// n'en ont pas dans ce produit, et en demander une serait une donnée
/// personnelle de plus à garder. Les initiales suffisent à distinguer deux
/// lignes voisines.
///
/// Le disque est le seul emploi de `pastille` avec la pastille de compteur
/// (`DESIGN.md § Shapes`). Il porte `primary-container` sur
/// `on-primary-container`, 6,74:1.
class AvatarInitiales extends StatelessWidget {
  const AvatarInitiales({
    required this.nom,
    super.key,
    this.taille = AppTouch.icone + AppSpacing.lg,
  });

  /// Le nom d'usage, tel que la caserne l'affiche. Vide : le disque montre un
  /// glyphe de personne plutôt que deux lettres inventées.
  final String nom;

  final double taille;

  /// Les deux premières initiales du nom, en majuscules. « Dubois Jean-Marc »
  /// donne « DJ », « Marie L. » donne « ML », « ana » donne « A ».
  static String initiales(String nom) {
    final mots = nom
        .split(RegExp(r'[\s\-]+'))
        .where((String mot) => mot.trim().isNotEmpty)
        .toList(growable: false);
    final lettres = <String>[
      for (final mot in mots.take(2)) mot.characters.first.toUpperCase(),
    ];
    return lettres.join();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lettres = initiales(nom);

    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: AppRadius.pastilleRadius,
      ),
      child: lettres.isEmpty
          ? Icon(
              Icons.person_outline,
              size: AppTouch.icone,
              color: scheme.onPrimaryContainer,
            )
          : Text(
              lettres,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
              maxLines: 1,
            ),
    );
  }
}
