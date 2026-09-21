import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/membre_caserne.dart';
import 'marqueur_statut.dart';

/// Une ligne de la liste des membres : le nom, l'adresse, ce que la caserne
/// sait de lui, et le bouton qui ouvre ses actions.
///
/// Ce n'est pas un bloc réglé et encore moins une carte : une liste de blocs
/// identiques « icône + titre + texte » est interdite comme structure de page
/// (`DESIGN.md § Cards / Containers`). Les lignes sont séparées par le filet.
class LigneMembre extends StatelessWidget {
  const LigneMembre({
    required this.membre,
    super.key,
    this.onActions,
    this.lectureSeule = false,
    this.occupee = false,
  });

  final MembreCaserne membre;

  /// Ouvre la feuille d'actions. `null` : la ligne est en lecture seule.
  final VoidCallback? onActions;

  /// La caserne est suspendue : le bouton reste visible et inerte, et
  /// **l'info-bulle dit pourquoi** (ticket 030). Un `⋮` qui ne répond pas est
  /// la version muette du refus qu'on cherche justement à expliquer.
  final bool lectureSeule;

  /// Une écriture est en cours sur ce membre : le bouton n'est plus
  /// actionnable, mais il reste là et garde sa place.
  final bool occupee;

  /// La troisième ligne : le rôle s'il y a lieu, puis la dernière saisie.
  String get _faits {
    final saisie = membre.derniereSaisie;
    return <String>[
      if (membre.estAdmin) membre.role.libelle,
      saisie == null
          ? AppStrings.membreAucuneSaisie
          : AppStrings.membreDerniereSaisie(formaterDateLongue(saisie)),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaire = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.cible),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Semantics(
              label: membre.libelle,
              value: <String>[
                membre.email,
                if (membre.estDesactive) AppStrings.membreStatutDesactive,
                _faits,
              ].join(', '),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Entete(membre: membre),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(membre.email, style: secondaire),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (membre.estAdmin) ...<Widget>[
                          Padding(
                            // Aligne le glyphe sur la ligne de base du texte.
                            padding: const EdgeInsets.only(top: AppSpacing.xxs),
                            child: Icon(
                              Icons.admin_panel_settings_outlined,
                              size: AppTouch.iconePetite,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Expanded(child: Text(_faits, style: secondaire)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onActions != null) ...<Widget>[
            const SizedBox(width: AppSpacing.entreCibles),
            IconButton(
              onPressed: occupee || lectureSeule ? null : onActions,
              icon: const Icon(Icons.more_vert),
              tooltip: lectureSeule
                  ? AppStrings.membresSuspendue
                  : AppStrings.membreActions(membre.libelle),
            ),
          ],
        ],
      ),
    );
  }
}

/// Le nom, et le marqueur de statut quand il y a quelque chose à signaler.
///
/// Pas de marqueur « Actif » : l'absence de marqueur **est** l'état normal, et
/// un badge sur chacune des quatre-vingt-dix-neuf lignes ne dirait plus rien.
class _Entete extends StatelessWidget {
  const _Entete({required this.membre});

  final MembreCaserne membre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nom = Text(membre.libelle, style: theme.textTheme.titleMedium);
    if (!membre.estDesactive) return nom;

    // `Wrap` et non `Row` : à grande échelle de texte, le marqueur passe sous
    // le nom au lieu de le rogner.
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[nom, const MarqueurDesactive()],
    );
  }
}
