import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/primary_button.dart';

/// Ce que l'annulation rend : le motif saisi, ou `null` si on a renoncé.
///
/// Un motif vide et un renoncement ne se confondent pas : le premier annule
/// sans raison, le second n'annule rien.
class DemandeAnnulation {
  const DemandeAnnulation(this.motif);

  final String? motif;
}

/// La confirmation d'une **annulation d'astreinte**.
///
/// Même justification que la réattribution : le geste sort de l'application et
/// ne se défait pas. Il porte en plus un champ que rien d'autre ne porte — le
/// **motif** —, parce qu'« annulée » sans raison est exactement le coup de
/// téléphone que cette application doit éviter. Il reste facultatif : un chef
/// pressé ne doit pas être empêché d'annuler.
///
/// [prevenu] vaut faux quand le membre n'avait pas encore répondu : rien
/// n'était acquis, personne n'est notifié, et la feuille le dit au lieu de
/// laisser croire à un envoi.
Future<DemandeAnnulation?> confirmerAnnulation(
  BuildContext context, {
  required String membre,
  required DateTime jour,
  required CreneauType creneau,
  required bool prevenu,
}) => showDialog<DemandeAnnulation>(
  context: context,
  builder: (BuildContext context) => _FeuilleAnnulation(
    membre: membre,
    jour: jour,
    creneau: creneau,
    prevenu: prevenu,
  ),
);

/// **Le contrôleur appartient à la feuille, pas à la fonction qui l'ouvre.**
///
/// Le libérer au retour de `showDialog` le libère *pendant* l'animation de
/// fermeture, alors que le champ y tient encore : Flutter lève alors
/// « A TextEditingController was used after being disposed ». Un `State` le
/// crée et le libère au bon moment, une fois l'arbre démonté.
class _FeuilleAnnulation extends StatefulWidget {
  const _FeuilleAnnulation({
    required this.membre,
    required this.jour,
    required this.creneau,
    required this.prevenu,
  });

  final String membre;
  final DateTime jour;
  final CreneauType creneau;
  final bool prevenu;

  @override
  State<_FeuilleAnnulation> createState() => _FeuilleAnnulationState();
}

class _FeuilleAnnulationState extends State<_FeuilleAnnulation> {
  final TextEditingController _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libelleCreneau = context.statuts
        .creneau(widget.creneau)
        .libelle
        .toLowerCase();
    final jourEtDate = dateAvecJourSemaine(widget.jour);

    return AlertDialog(
      title: const Text(AppStrings.annulerAstreinteTitre),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.prevenu
                  ? AppStrings.annulerAstreinteTexte(
                      membre: widget.membre,
                      jourEtDate: jourEtDate,
                      creneau: libelleCreneau,
                    )
                  : AppStrings.annulerPropositionTexte(
                      membre: widget.membre,
                      jourEtDate: jourEtDate,
                      creneau: libelleCreneau,
                    ),
            ),
            // Le motif ne sert qu'à celui qui reçoit la notification : sans
            // envoi, le champ n'a personne à informer.
            if (widget.prevenu) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              ChampTexte(
                libelle: AppStrings.annulerMotifLibelle,
                controleur: _motif,
                clavier: TextInputType.text,
                texteInvite: AppStrings.annulerMotifExemple,
                longueurMax: 120,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppStrings.annulerMotifAide,
                style: AppTextStyles.mention.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsOverflowButtonSpacing: AppSpacing.entreCibles,
      actions: <Widget>[
        PrimaryButton(
          libelle: AppStrings.annulerRenoncer,
          variante: PrimaryButtonVariante.secondaire,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(
          libelle: AppStrings.annulerConfirmer,
          icone: Icons.block,
          pleineLargeur: false,
          onPressed: () {
            final motif = _motif.text.trim();
            Navigator.of(context).pop(
              DemandeAnnulation(motif.isEmpty ? null : motif),
            );
          },
        ),
      ],
    );
  }
}
