import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/primary_button.dart';

/// Ce que la feuille de création rend : un nom et un fuseau.
typedef CaserneASaisir = ({String nom, String fuseau});

/// Demande le nom et le fuseau d'une nouvelle caserne.
///
/// **Le slug n'est pas demandé** : un identifiant d'URL est un détail
/// technique, et le faire saisir, c'est faire porter une collision d'unicité à
/// quelqu'un qui voulait juste créer une caserne. La base le dérive du nom.
///
/// Rend `null` si la feuille a été refermée sans valider.
Future<CaserneASaisir?> afficherCreerCaserne(BuildContext context) =>
    showModalBottomSheet<CaserneASaisir>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => const _FeuilleCreerCaserne(),
    );

class _FeuilleCreerCaserne extends StatefulWidget {
  const _FeuilleCreerCaserne();

  @override
  State<_FeuilleCreerCaserne> createState() => _FeuilleCreerCaserneState();
}

class _FeuilleCreerCaserneState extends State<_FeuilleCreerCaserne> {
  static const String _fuseauParDefaut = 'Europe/Paris';

  final TextEditingController _nom = TextEditingController();
  final TextEditingController _fuseau = TextEditingController(
    text: _fuseauParDefaut,
  );

  String? _erreurNom;

  @override
  void dispose() {
    _nom.dispose();
    _fuseau.dispose();
    super.dispose();
  }

  void _valider() {
    final nom = _nom.text.trim();
    if (nom.isEmpty) {
      setState(() => _erreurNom = AppStrings.superAdminRefusNom);
      return;
    }
    final fuseau = _fuseau.text.trim();
    Navigator.of(context).pop<CaserneASaisir>((
      nom: nom,
      fuseau: fuseau.isEmpty ? _fuseauParDefaut : fuseau,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

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
                child: Text(
                  AppStrings.superAdminCreerTitre,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.superAdminCreerAide,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ChampTexte(
                libelle: AppStrings.superAdminChampNom,
                texteInvite: AppStrings.superAdminChampNomExemple,
                controleur: _nom,
                clavier: TextInputType.text,
                autofocus: true,
                longueurMax: 80,
                erreur: _erreurNom,
                onChanged: (_) {
                  if (_erreurNom != null) setState(() => _erreurNom = null);
                },
                onSoumission: (_) => _valider(),
              ),
              const SizedBox(height: AppSpacing.lg),
              ChampTexte(
                libelle: AppStrings.superAdminChampFuseau,
                controleur: _fuseau,
                clavier: TextInputType.text,
                onSoumission: (_) => _valider(),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                libelle: AppStrings.superAdminCreerValider,
                icone: Icons.add_business_outlined,
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
