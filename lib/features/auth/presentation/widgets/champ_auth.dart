import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';

/// Un champ de saisie du système, avec son libellé **au-dessus** et son
/// message d'erreur annoncé.
///
/// `DESIGN.md § Inputs / Fields` : libellé toujours visible (jamais un simple
/// texte d'invite), texte à 16 sp minimum, erreur avec filet 2 dp, icône
/// `error_outline`, message sous le champ et annonce sans déplacer le focus.
/// Le libellé et le champ sont fusionnés en un seul nœud d'accessibilité.
class ChampAuth extends StatelessWidget {
  const ChampAuth({
    required this.libelle,
    required this.controleur,
    required this.clavier,
    super.key,
    this.texteInvite,
    this.erreur,
    this.indicesRemplissage,
    this.longueurMax,
    this.formateurs,
    this.style,
    this.alignement = TextAlign.start,
    this.onChanged,
    this.onSoumission,
    this.autofocus = false,
    this.actif = true,
  });

  final String libelle;
  final TextEditingController controleur;
  final TextInputType clavier;

  /// Exemple de valeur. Jamais le seul porteur du libellé.
  final String? texteInvite;

  /// Message d'erreur, déjà en français. `null` : aucun défaut.
  final String? erreur;

  final Iterable<String>? indicesRemplissage;
  final int? longueurMax;
  final List<TextInputFormatter>? formateurs;
  final TextStyle? style;
  final TextAlign alignement;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSoumission;
  final bool autofocus;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(libelle, style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: controleur,
            keyboardType: clavier,
            autofillHints: actif ? indicesRemplissage : null,
            maxLength: longueurMax,
            inputFormatters: formateurs,
            style: style,
            textAlign: alignement,
            autofocus: autofocus,
            enabled: actif,
            onChanged: onChanged,
            onSubmitted: onSoumission,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: texteInvite,
              counterText: '',
              error: erreur == null ? null : _MessageErreur(texte: erreur!),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le problème et la sortie, sous le champ, annoncés sans bouger le focus.
class _MessageErreur extends StatelessWidget {
  const _MessageErreur({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: AppSpacing.lg,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
