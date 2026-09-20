import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';

/// Un réglage numérique qui se règle **avec des gants**.
///
/// Deux cibles carrées de 48 dp — « moins » et « plus » — encadrent la valeur,
/// écrite en chasse fixe (`DESIGN.md § Typography`, style `nombre`) parce
/// qu'elle change en place. La valeur reste un champ de saisie : personne ne
/// doit appuyer trois cents fois sur « plus » pour écrire 336.
///
/// Ni curseur ni `Slider` : un curseur ne se vise pas avec un gant et ne dit
/// pas sa valeur exacte.
class ChampNombre extends StatefulWidget {
  const ChampNombre({
    required this.libelle,
    required this.valeur,
    required this.min,
    required this.max,
    required this.onChange,
    super.key,
    this.suffixe,
    this.note,
    this.erreur,
    this.actif = true,
    this.onQuitte,
  });

  final String libelle;
  final int valeur;
  final int min;
  final int max;
  final ValueChanged<int> onChange;

  /// Unité écrite à droite du nombre : « heures ». Jamais un symbole seul.
  final String? suffixe;

  /// Phrase de contexte sous le contrôle — la conséquence du réglage, ou son
  /// exemple daté.
  final String? note;

  final String? erreur;
  final bool actif;

  /// Appelé quand le champ est quitté : c'est le moment où son erreur devient
  /// montrable sans harceler qui est en train de taper.
  final VoidCallback? onQuitte;

  @override
  State<ChampNombre> createState() => _ChampNombreState();
}

class _ChampNombreState extends State<ChampNombre> {
  late final TextEditingController _controleur = TextEditingController(
    text: '${widget.valeur}',
  );
  late final FocusNode _focus = FocusNode()..addListener(_surFocus);

  @override
  void didUpdateWidget(ChampNombre ancien) {
    super.didUpdateWidget(ancien);
    // La valeur a changé ailleurs (relecture, retour au défaut) : le champ
    // suit, sauf s'il est en train d'être écrit.
    if (!_focus.hasFocus && int.tryParse(_controleur.text) != widget.valeur) {
      _controleur.text = '${widget.valeur}';
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_surFocus)
      ..dispose();
    _controleur.dispose();
    super.dispose();
  }

  void _surFocus() {
    if (_focus.hasFocus) return;
    // Au relâchement seulement : borner pendant la frappe empêcherait
    // d'effacer « 24 » pour écrire « 4 ».
    _poser(int.tryParse(_controleur.text) ?? widget.valeur);
    widget.onQuitte?.call();
  }

  void _poser(int valeur) {
    final borne = valeur.clamp(widget.min, widget.max);
    if (_controleur.text != '$borne') _controleur.text = '$borne';
    if (borne != widget.valeur) widget.onChange(borne);
  }

  void _saisir(String texte) {
    final lu = int.tryParse(texte);
    if (lu == null) return;
    if (lu >= widget.min && lu <= widget.max && lu != widget.valeur) {
      widget.onChange(lu);
    }
  }

  void _pas(int delta) {
    _focus.unfocus();
    _poser(widget.valeur + delta);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enErreur = widget.erreur != null;

    // Pas de `Semantics` sur tout le bloc : il engloberait les deux boutons et
    // leur ferait perdre leur propre libellé. Le nom du réglage est porté par
    // le champ lui-même (voir plus bas), ses deux pas par leurs info-bulles.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: Text(widget.libelle, style: theme.textTheme.labelMedium),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            _BoutonPas(
              icone: Icons.remove,
              libelle: AppStrings.parametresDiminuer(widget.libelle),
              onPressed: widget.actif && widget.valeur > widget.min
                  ? () => _pas(-1)
                  : null,
            ),
            const SizedBox(width: AppSpacing.entreCibles),
            // Le libellé est **sur le champ**, pas sur un groupe qui
            // l'entoure : au clavier comme au lecteur d'écran, on arrive
            // directement dans la valeur, et elle doit dire ce qu'elle
            // compte.
            MergeSemantics(
              child: Semantics(
                label: widget.libelle,
                child: SizedBox(
                  width: 88,
                  child: TextField(
                    controller: _controleur,
                    focusNode: _focus,
                    enabled: widget.actif,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    onChanged: _saisir,
                    onSubmitted: (String texte) =>
                        _poser(int.tryParse(texte) ?? widget.valeur),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.md,
                      ),
                      errorText: enErreur ? '' : null,
                      errorStyle: const TextStyle(height: 0, fontSize: 0),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.entreCibles),
            _BoutonPas(
              icone: Icons.add,
              libelle: AppStrings.parametresAugmenter(widget.libelle),
              onPressed: widget.actif && widget.valeur < widget.max
                  ? () => _pas(1)
                  : null,
            ),
            if (widget.suffixe != null) ...<Widget>[
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.suffixe!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (widget.note != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.note!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (enErreur) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Semantics(
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
                    widget.erreur!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Un pas : une case carrée de 48 dp, filet 1 dp, rayon 4 — la forme du
/// registre, pas une gélule.
///
/// C'est un `IconButton` habillé, et non un `InkWell` dans un `Tooltip` :
/// vérifié au navigateur, un nœud `Semantics(button: true)` posé **à côté** du
/// geste ne porte aucune action, et Flutter web le rend en simple texte. Le
/// lecteur d'écran lisait « Diminuer : Requis en journée » sans rien pouvoir
/// actionner. L'`IconButton` porte le rôle, l'action, l'état désactivé et
/// l'info-bulle d'un seul tenant.
class _BoutonPas extends StatelessWidget {
  const _BoutonPas({
    required this.icone,
    required this.libelle,
    required this.onPressed,
  });

  final IconData icone;
  final String libelle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: onPressed,
      tooltip: libelle,
      icon: Icon(icone, size: AppTouch.glypheCompact),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(AppTouch.cible),
        minimumSize: const Size.square(AppTouch.cible),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.outline),
          borderRadius: AppRadius.caseRegistreRadius,
        ),
        backgroundColor: theme.colorScheme.surface,
        disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundColor: theme.colorScheme.onSurface,
        disabledForegroundColor: theme.colorScheme.outline,
      ),
    );
  }
}
