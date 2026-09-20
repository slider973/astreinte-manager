import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../domain/preferences_mois.dart';

/// **Le mot du mois pour le chef de centre** — lu par l'administrateur dans la
/// matrice du ticket 016.
///
/// Replié, c'est une rangée de 56 dp. Ouvert, c'est un champ multiligne **en
/// place**, pas une feuille : sur un téléphone, le clavier couvrirait la
/// moitié d'une feuille, et le membre doit voir ce qu'il écrit.
///
/// Borné à [PreferencesMois.commentaireMax] caractères. Le compteur
/// n'apparaît que sous le seuil : un compteur permanent transforme une phrase
/// libre en épreuve.
class ChampCommentaire extends StatefulWidget {
  const ChampCommentaire({
    required this.texte,
    required this.ouvert,
    required this.onOuvrir,
    required this.onChange,
    super.key,
  });

  final String texte;
  final bool ouvert;
  final VoidCallback onOuvrir;
  final ValueChanged<String> onChange;

  @override
  State<ChampCommentaire> createState() => _ChampCommentaireState();
}

class _ChampCommentaireState extends State<ChampCommentaire> {
  late final TextEditingController _controleur = TextEditingController(
    text: widget.texte,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(ChampCommentaire ancien) {
    super.didUpdateWidget(ancien);
    // La valeur du contrôleur de saisie fait autorité — sauf pendant que le
    // membre tape, sous peine de lui déplacer le curseur sous les doigts.
    if (!_focus.hasFocus && widget.texte != _controleur.text) {
      _controleur.text = widget.texte;
    }
  }

  @override
  void dispose() {
    _controleur.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ouvert = widget.ouvert || widget.texte.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const AppDivider(),
        if (!ouvert)
          Semantics(
            button: true,
            label: AppStrings.preferencesCommentaireRangee,
            excludeSemantics: true,
            child: InkWell(
              onTap: widget.onOuvrir,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.champ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.chat_bubble_outline,
                        size: AppTouch.icone,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          AppStrings.preferencesCommentaireRangee,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: AppTouch.icone,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Focus(
                  focusNode: _focus,
                  child: ChampTexte(
                    libelle: AppStrings.preferencesCommentaireRangee,
                    controleur: _controleur,
                    clavier: TextInputType.multiline,
                    texteInvite: AppStrings.preferencesCommentaireInvite,
                    lignes: 3,
                    longueurMax: PreferencesMois.commentaireMax,
                    formateurs: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(
                        PreferencesMois.commentaireMax,
                      ),
                    ],
                    onChanged: widget.onChange,
                  ),
                ),
                _Restants(longueur: _controleur.text.length),
              ],
            ),
          ),
      ],
    );
  }
}

/// Le compteur de caractères, **seulement quand il devient utile**.
class _Restants extends StatelessWidget {
  const _Restants({required this.longueur});

  final int longueur;

  @override
  Widget build(BuildContext context) {
    final restants = PreferencesMois.commentaireMax - longueur;
    if (restants > PreferencesMois.commentaireSeuilCompteur) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        AppStrings.preferencesCommentaireRestants(restants),
        textAlign: TextAlign.end,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
