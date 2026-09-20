import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/membre_caserne.dart';

/// Le nom affiché saisi par l'admin. `null` dans le champ [nom] veut dire
/// « efface le surnom et rends-lui le nom de son profil ».
typedef NomAffiche = ({String? nom});

/// Demande le nouveau nom affiché d'un membre, et le rend.
///
/// Rend `null` si la feuille a été refermée sans enregistrer — ce qui n'est
/// **pas** la même chose qu'un nom effacé, d'où l'enveloppe [NomAffiche].
Future<NomAffiche?> afficherRenommerMembre({
  required BuildContext context,
  required MembreCaserne membre,
}) => showModalBottomSheet<NomAffiche>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => _FeuilleRenommer(membre: membre),
);

class _FeuilleRenommer extends StatefulWidget {
  const _FeuilleRenommer({required this.membre});

  final MembreCaserne membre;

  @override
  State<_FeuilleRenommer> createState() => _FeuilleRenommerState();
}

class _FeuilleRenommerState extends State<_FeuilleRenommer> {
  late final TextEditingController _controleur = TextEditingController(
    text: widget.membre.nomAffiche ?? '',
  );

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _enregistrer() {
    final saisi = _controleur.text.trim();
    Navigator.of(context).pop<NomAffiche>((nom: saisi.isEmpty ? null : saisi));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return Padding(
      // Le clavier ne recouvre jamais le champ : la feuille monte avec lui.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(widget.membre.libelle, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.membreRenommerAide,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ChampTexte(
                libelle: AppStrings.membreRenommerTitre,
                controleur: _controleur,
                clavier: TextInputType.name,
                autofocus: true,
                longueurMax: 60,
                onSoumission: (_) => _enregistrer(),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                libelle: AppStrings.membreRenommerEnregistrer,
                icone: Icons.check,
                onPressed: _enregistrer,
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
