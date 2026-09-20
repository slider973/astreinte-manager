import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_spacing.dart';

/// Un champ de saisie du système, avec son libellé **au-dessus** et son
/// message d'erreur annoncé.
///
/// `DESIGN.md § Inputs / Fields` : libellé toujours visible (jamais un simple
/// texte d'invite), texte à 16 sp minimum, erreur avec filet 2 dp, icône
/// `error_outline`, message sous le champ et annonce sans déplacer le focus.
/// Le libellé et le champ sont fusionnés en un seul nœud d'accessibilité.
class ChampTexte extends StatelessWidget {
  const ChampTexte({
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
    this.lignes = 1,
    this.icone,
    this.suffixe,
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

  /// Nombre de lignes visibles. Au-delà d'une, le champ accepte les retours à
  /// la ligne : la touche entrée saute une ligne au lieu de valider.
  final int lignes;

  /// Icône de 20 dp à gauche du texte saisi. Décorative : elle double le
  /// libellé, elle ne le remplace jamais.
  final IconData? icone;

  /// Contrôle posé à droite du champ — un « effacer » par exemple. C'est une
  /// cible tactile : il lui faut ses 48 dp et son libellé annoncé.
  final Widget? suffixe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final multiligne = lignes > 1;

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(libelle, style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: controleur,
            keyboardType: multiligne ? TextInputType.multiline : clavier,
            autofillHints: actif ? indicesRemplissage : null,
            maxLength: longueurMax,
            maxLines: lignes,
            minLines: multiligne ? lignes : null,
            inputFormatters: formateurs,
            style: style,
            textAlign: alignement,
            autofocus: autofocus,
            enabled: actif,
            onChanged: onChanged,
            onSubmitted: onSoumission,
            textInputAction: multiligne
                ? TextInputAction.newline
                : TextInputAction.done,
            decoration: InputDecoration(
              hintText: texteInvite,
              counterText: '',
              alignLabelWithHint: multiligne,
              prefixIcon: icone == null
                  ? null
                  : Icon(icone, size: AppTouch.icone),
              suffixIcon: suffixe,
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
