import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status.dart';

/// Les trois variantes du bouton, à dimensions identiques.
enum PrimaryButtonVariante {
  /// Fond `primary` (l'encre), texte `on-primary`. L'action principale.
  primaire,

  /// Fond `surface`, texte `primary`, filet 1 dp `outline`.
  secondaire,

  /// Fond `error`, texte `on-error`. Une action destructrice, jamais un
  /// simple « Annuler ».
  danger,
}

/// Le bouton du système : un bloc à rayon 8, jamais une gélule.
///
/// `DESIGN.md § Components — Buttons`. Hauteur 52 dp, libellé à 16 sp (et non
/// 14 comme Material par défaut), icône facultative de 20 dp à gauche.
///
/// Deux règles portées par le type :
/// - **Un bouton désactivé affiche sa raison.** [onPressed] à `null` sans
///   [raisonDesactivation] déclenche une assertion : « un bouton grisé sans
///   explication est un défaut » (`DESIGN.md`).
/// - **Le libellé nomme l'action.** « Enregistrer le mois », jamais « OK ».
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.libelle,
    required this.onPressed,
    super.key,
    this.variante = PrimaryButtonVariante.primaire,
    this.icone,
    this.chargement = false,
    this.raisonDesactivation,
    this.raisonVisible = true,
    this.pleineLargeur,
    this.libelleAnnonce,
  });

  /// Libellé de l'action. Reste visible pendant le chargement.
  final String libelle;

  /// Ce que le lecteur d'écran annonce à la place de [libelle].
  ///
  /// Réservé aux listes où le même verbe se répète : quatre boutons
  /// « Accepter » sur un écran ne se distinguent pas à l'oreille. Le libellé
  /// visible reste court, l'annoncé porte la phrase entière — « Accepter
  /// samedi 12 octobre, nuit » (`DESIGN.md § Chips`, même règle que
  /// `SlotChip`).
  final String? libelleAnnonce;

  /// `null` désactive le bouton — et exige alors [raisonDesactivation].
  final VoidCallback? onPressed;

  final PrimaryButtonVariante variante;

  /// Icône de 20 dp à gauche du libellé, de la même couleur que lui.
  final IconData? icone;

  /// Pendant le chargement, le libellé reste, un indicateur de 20 dp le
  /// précède et le bouton n'est plus actionnable.
  ///
  /// Pour qu'un bouton susceptible de charger ne change pas de largeur, donne
  /// lui une icône (l'indicateur en prend la place) ou laisse-le en pleine
  /// largeur : sans icône et en largeur intrinsèque, l'apparition de
  /// l'indicateur élargit le bloc de 28 dp.
  final bool chargement;

  /// Phrase courte affichée **sous** le bouton quand il est désactivé.
  /// Elle dit pourquoi, et si possible comment en sortir.
  final String? raisonDesactivation;

  /// La raison s'écrit sous le bouton. À passer à faux pour le **second** de
  /// deux boutons appairés, qui partagent la même raison : l'écrire deux fois
  /// sous une même ligne est du bruit, pas une explication.
  ///
  /// La raison reste obligatoire et reste **annoncée** (`hint`) dans les deux
  /// cas : ce qui change est l'affichage, pas l'invariant.
  final bool raisonVisible;

  /// Pleine largeur. Par défaut : vrai en `compact`, faux au-delà, où le
  /// bouton prend sa largeur intrinsèque avec un plancher de 160 dp.
  final bool? pleineLargeur;

  bool get _actif => onPressed != null && !chargement;

  @override
  Widget build(BuildContext context) {
    assert(
      onPressed != null || raisonDesactivation != null || chargement,
      'Un bouton désactivé doit afficher sa raison : renseigne '
      'raisonDesactivation.',
    );

    final theme = Theme.of(context);
    final compact = AppWindowClass.of(context).estCompact;
    final large = pleineLargeur ?? compact;

    final encre = switch (variante) {
      PrimaryButtonVariante.primaire => theme.colorScheme.onPrimary,
      PrimaryButtonVariante.secondaire => context.statuts.accentTexte,
      PrimaryButtonVariante.danger => theme.colorScheme.onError,
    };
    final encreEffective = _actif ? encre : theme.colorScheme.outline;

    final contenu = Row(
      mainAxisSize: large ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (chargement)
          _IndicateurBouton(couleur: encreEffective)
        else if (icone != null)
          Icon(icone, size: AppTouch.icone, color: encreEffective),
        if (chargement || icone != null) const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            libelle,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    final bouton = switch (variante) {
      PrimaryButtonVariante.primaire => FilledButton(
        onPressed: _actif ? onPressed : null,
        child: contenu,
      ),
      PrimaryButtonVariante.secondaire => OutlinedButton(
        onPressed: _actif ? onPressed : null,
        child: contenu,
      ),
      PrimaryButtonVariante.danger => FilledButton(
        onPressed: _actif ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: theme.colorScheme.onError,
          disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
          disabledForegroundColor: theme.colorScheme.outline,
        ),
        child: contenu,
      ),
    };

    final dimensionne = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: large ? double.infinity : 160,
        minHeight: AppTouch.bouton,
      ),
      child: bouton,
    );

    final semantique = Semantics(
      button: true,
      enabled: _actif,
      label: libelleAnnonce ?? libelle,
      hint: _actif ? null : raisonDesactivation,
      excludeSemantics: true,
      child: dimensionne,
    );

    if (_actif || raisonDesactivation == null || !raisonVisible) {
      return semantique;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        semantique,
        const SizedBox(height: AppSpacing.sm),
        _RaisonDesactivation(texte: raisonDesactivation!),
      ],
    );
  }
}

/// Indicateur de 20 dp, à la place exacte de l'icône : la largeur ne bouge pas.
class _IndicateurBouton extends StatelessWidget {
  const _IndicateurBouton({required this.couleur});

  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: AppTouch.icone,
      child: CircularProgressIndicator(strokeWidth: 2, color: couleur),
    );
  }
}

/// Pourquoi ce contrôle est désactivé, à côté du contrôle. Jamais un bouton
/// gris muet.
class _RaisonDesactivation extends StatelessWidget {
  const _RaisonDesactivation({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.info_outline,
          size: AppTouch.icone,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
