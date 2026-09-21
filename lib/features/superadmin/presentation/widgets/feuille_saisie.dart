import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/primary_button.dart';

/// Une feuille à un champ : l'adresse du premier administrateur, la raison
/// d'une suspension, la raison d'une consultation de support.
///
/// Trois gestes, une seule feuille. Ils ont la même forme — un titre, une
/// phrase qui dit la conséquence, un champ, deux boutons — et en faire trois
/// widgets aurait donné trois occasions de diverger sur la hauteur du champ ou
/// sur la place du bouton « Annuler ».
///
/// `ui-ux-pro-max --domain ux` : « confirmer avant une action irréversible ».
/// La suspension passe donc ici, en `danger` ; la réactivation, non — elle ne
/// détruit rien et se refait d'un geste.
Future<String?> afficherFeuilleSaisie({
  required BuildContext context,
  required String titre,
  required String aide,
  required String libelleChamp,
  required String exemple,
  required String libelleValider,
  required String erreurSiVide,
  String? mention,
  TextInputType clavier = TextInputType.text,
  int longueurMinimale = 1,
  int lignes = 1,
  IconData? icone,
  PrimaryButtonVariante variante = PrimaryButtonVariante.primaire,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => _FeuilleSaisie(
    titre: titre,
    aide: aide,
    mention: mention,
    libelleChamp: libelleChamp,
    exemple: exemple,
    libelleValider: libelleValider,
    erreurSiVide: erreurSiVide,
    clavier: clavier,
    longueurMinimale: longueurMinimale,
    lignes: lignes,
    icone: icone,
    variante: variante,
  ),
);

class _FeuilleSaisie extends StatefulWidget {
  const _FeuilleSaisie({
    required this.titre,
    required this.aide,
    required this.mention,
    required this.libelleChamp,
    required this.exemple,
    required this.libelleValider,
    required this.erreurSiVide,
    required this.clavier,
    required this.longueurMinimale,
    required this.lignes,
    required this.icone,
    required this.variante,
  });

  final String titre;
  final String aide;
  final String? mention;
  final String libelleChamp;
  final String exemple;
  final String libelleValider;
  final String erreurSiVide;
  final TextInputType clavier;
  final int longueurMinimale;
  final int lignes;
  final IconData? icone;
  final PrimaryButtonVariante variante;

  @override
  State<_FeuilleSaisie> createState() => _FeuilleSaisieState();
}

class _FeuilleSaisieState extends State<_FeuilleSaisie> {
  final TextEditingController _controleur = TextEditingController();
  String? _erreur;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _valider() {
    final valeur = _controleur.text.trim();
    // Le contrôle est **aussi** côté serveur (`reason_required`, migration
    // `0025`) : celui-ci n'est là que pour éviter un aller-retour.
    if (valeur.length < widget.longueurMinimale) {
      setState(() => _erreur = widget.erreurSiVide);
      return;
    }
    Navigator.of(context).pop<String>(valeur);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;
    final mention = widget.mention;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            marge,
            AppSpacing.lg,
            marge,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(widget.titre, style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(widget.aide, style: theme.textTheme.bodyMedium),
              if (mention != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  mention,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              ChampTexte(
                libelle: widget.libelleChamp,
                texteInvite: widget.exemple,
                controleur: _controleur,
                clavier: widget.clavier,
                autofocus: true,
                lignes: widget.lignes,
                erreur: _erreur,
                onChanged: (_) {
                  if (_erreur != null) setState(() => _erreur = null);
                },
                onSoumission: widget.lignes == 1 ? (_) => _valider() : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                libelle: widget.libelleValider,
                icone: widget.icone,
                variante: widget.variante,
                onPressed: _valider,
              ),
              const SizedBox(height: AppSpacing.entreCibles),
              PrimaryButton(
                libelle: AppStrings.actionAnnuler,
                variante: PrimaryButtonVariante.secondaire,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
