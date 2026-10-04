import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/primary_button.dart';

/// Ce que la confirmation rend : la décision, et le motif s'il y en avait un.
typedef ConfirmationEchange = ({String? motif});

/// La confirmation d'un geste d'échange **qui fait sonner un téléphone et ne
/// se défait pas** : annuler sa demande, valider, refuser (patron du ticket
/// 020). Rien d'autre n'en ouvre une : accepter, refuser côté B et envoyer
/// une demande se font sans (`design/073 § 4`).
///
/// [avecMotif] ajoute le champ « Motif (facultatif) » du refus de
/// l'administrateur, 120 caractères. Rend `null` quand on revient.
Future<ConfirmationEchange?> confirmerEchange(
  BuildContext context, {
  required String titre,
  required String texte,
  required String libelleConfirmer,
  required String libelleRevenir,
  required IconData icone,
  PrimaryButtonVariante variante = PrimaryButtonVariante.primaire,
  bool avecMotif = false,
}) => showDialog<ConfirmationEchange>(
  context: context,
  builder: (BuildContext context) => _Confirmation(
    titre: titre,
    texte: texte,
    libelleConfirmer: libelleConfirmer,
    libelleRevenir: libelleRevenir,
    icone: icone,
    variante: variante,
    avecMotif: avecMotif,
  ),
);

class _Confirmation extends StatefulWidget {
  const _Confirmation({
    required this.titre,
    required this.texte,
    required this.libelleConfirmer,
    required this.libelleRevenir,
    required this.icone,
    required this.variante,
    required this.avecMotif,
  });

  final String titre;
  final String texte;
  final String libelleConfirmer;
  final String libelleRevenir;
  final IconData icone;
  final PrimaryButtonVariante variante;
  final bool avecMotif;

  @override
  State<_Confirmation> createState() => _ConfirmationState();
}

class _ConfirmationState extends State<_Confirmation> {
  final TextEditingController _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.titre),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.texte, style: theme.textTheme.bodyLarge),
            if (widget.avecMotif) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              ChampTexte(
                libelle: AppStrings.echangesMotif,
                controleur: _motif,
                clavier: TextInputType.text,
                longueurMax: AppStrings.echangesMotifLongueurMax,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppStrings.echangesMotifAide,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsOverflowButtonSpacing: AppSpacing.entreCibles,
      actions: <Widget>[
        PrimaryButton(
          libelle: widget.libelleRevenir,
          variante: PrimaryButtonVariante.secondaire,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(
          libelle: widget.libelleConfirmer,
          icone: widget.icone,
          variante: widget.variante,
          pleineLargeur: false,
          onPressed: () {
            final motif = _motif.text.trim();
            Navigator.of(
              context,
            ).pop((motif: motif.isEmpty ? null : motif));
          },
        ),
      ],
    );
  }
}
