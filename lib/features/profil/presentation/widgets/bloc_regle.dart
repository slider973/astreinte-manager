import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Un **bloc réglé** (`DESIGN.md § Cards / Containers`) : fond `surface`, filet
/// 1 dp `outline-variant`, rayon 8, aucune ombre. Les blocs ne s'imbriquent
/// jamais.
///
/// L'écran de profil en empile quatre. Les composer à la main quatre fois
/// aurait garanti quatre divergences au premier réglage de contraste — c'est
/// exactement la raison pour laquelle `ReglageNotifications` porte déjà la même
/// décoration en dur depuis le ticket 024, et pourquoi elle est extraite ici.
class BlocRegle extends StatelessWidget {
  const BlocRegle({required this.titre, required this.enfants, super.key});

  /// Annoncé comme un en-tête : c'est ce qui permet de sauter de bloc en bloc
  /// avec un lecteur d'écran plutôt que de tout lire.
  final String titre;

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: AppRadius.controleRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(titre, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: AppSpacing.md),
            ...enfants,
          ],
        ),
      ),
    );
  }
}

/// Une ligne « libellé au-dessus, valeur en dessous », et la raison de son
/// inertie quand elle en a une.
///
/// `DESIGN.md § Do's` : « Expliquer pourquoi un contrôle est désactivé, à côté
/// du contrôle ». Deux usages sur cet écran — l'adresse de connexion et la
/// langue — et dans les deux cas la valeur n'est pas modifiable ici.
class LigneLecture extends StatelessWidget {
  const LigneLecture({
    required this.libelle,
    required this.valeur,
    super.key,
    this.raison,
    this.icone,
    this.style,
    this.libelleVisible = true,
  });

  final String libelle;
  final String valeur;

  /// Pourquoi cette valeur ne se règle pas ici. `null` quand la ligne n'est
  /// qu'un fait à lire.
  final String? raison;

  /// Icône de 20 dp devant la valeur. Décorative : elle double le libellé,
  /// elle ne le remplace jamais.
  final IconData? icone;

  final TextStyle? style;

  /// À faux quand le titre du bloc dit déjà ce que le libellé dirait : « Ta
  /// caserne » deux fois de suite est une redondance à l'œil **et** à
  /// l'oreille. Le libellé reste dans la sémantique — c'est lui qui nomme la
  /// valeur pour un lecteur d'écran.
  final bool libelleVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glyphe = icone;

    return Semantics(
      label: libelle,
      value: raison == null ? valeur : '$valeur. $raison',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (libelleVisible) ...<Widget>[
            Text(
              libelle,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (glyphe != null) ...<Widget>[
                Icon(
                  glyphe,
                  size: AppTouch.icone,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(valeur, style: style ?? theme.textTheme.bodyLarge),
              ),
            ],
          ),
          if (raison case final String texte) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
