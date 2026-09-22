import 'package:flutter/material.dart';

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';

/// Un segment d'une [BasculeDeux].
@immutable
class SegmentBascule {
  const SegmentBascule({
    required this.libelle,
    required this.icone,
    required this.choisi,
    required this.onChoisir,
    this.raison,
  });

  final String libelle;
  final IconData icone;
  final bool choisi;

  /// `null` rend le segment inerte. [raison] dit alors pourquoi.
  final VoidCallback? onChoisir;

  /// Pourquoi ce segment est inerte. Un contrôle désactivé sans raison est un
  /// défaut (`DESIGN.md § Buttons`).
  final String? raison;
}

/// Un contrôle à deux choix, **fait de deux blocs et jamais d'une gélule**.
///
/// `DESIGN.md § Shapes` proscrit la pastille sur un contrôle, et le
/// `SegmentedButton` Material est en `StadiumBorder`. La composition est celle
/// du sélecteur de mois du ticket 011 : deux blocs à rayon `controle`, le
/// choisi en `primary-container` — la pastille indigo de la sélection
/// (ticket 061), et non le vert, qui dit « accepté, couvert, publié ».
///
/// Trois signaux pour l'état choisi — la coche, le fond, `Semantics(selected:)`
/// — jamais la couleur seule.
///
/// Extrait de la bascule « Liste » / « Calendrier » du ticket 027 quand le
/// ticket 023 en a demandé une seconde : deux copies auraient divergé au
/// premier réglage de contraste.
class BasculeDeux extends StatelessWidget {
  const BasculeDeux({
    required this.label,
    required this.premier,
    required this.second,
    super.key,
    this.dessous,
  });

  /// Le nom du groupe, annoncé avant les deux segments.
  final String label;

  final SegmentBascule premier;
  final SegmentBascule second;

  /// Une phrase posée sous les deux boutons — typiquement la raison d'un
  /// segment inerte, affichée **à côté du contrôle** et pas seulement supposée.
  final String? dessous;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      // Bornée comme la liste qu'elle commande : sur un portable, deux boutons
      // de 580 dp pour deux mots sont un défaut, pas une aération.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child: Padding(
            // La **même** marge de page que la liste qu'elle commande : à 16
            // sur un portable où la liste en prend 32, les deux boîtes de
            // 720 dp ne s'alignent pas et le décalage se voit.
            padding: EdgeInsets.symmetric(
              horizontal: AppWindowClass.of(context).margePage,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: _Bouton(segment: premier)),
                    const SizedBox(width: AppSpacing.entreCibles),
                    Expanded(child: _Bouton(segment: second)),
                  ],
                ),
                if (dessous case final String raison) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    raison,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  const _Bouton({required this.segment});

  final SegmentBascule segment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choisi = segment.choisi;
    final inerte = segment.onChoisir == null;

    final encre = inerte
        ? theme.colorScheme.outline
        : choisi
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      selected: choisi,
      enabled: !inerte,
      hint: segment.raison,
      child: Material(
        color: inerte
            ? theme.colorScheme.surfaceContainerHighest
            : choisi
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        borderRadius: AppRadius.controleRadius,
        child: InkWell(
          onTap: segment.onChoisir,
          borderRadius: AppRadius.controleRadius,
          child: Container(
            height: AppTouch.cible,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.controleRadius,
              border: Border.all(
                color: choisi && !inerte
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.outline,
                width: choisi && !inerte ? AppStroke.etat : AppStroke.filet,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // La coche est le signal robuste : elle survit à une capture en
                // niveaux de gris, le fond non.
                Icon(
                  choisi ? Icons.check : segment.icone,
                  size: AppTouch.icone,
                  color: encre,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    segment.libelle,
                    style: theme.textTheme.labelLarge?.copyWith(color: encre),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
