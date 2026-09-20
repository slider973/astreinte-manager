import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/raccourci.dart';

/// Demande **quel créneau** le raccourci vise, et rend le choix.
///
/// Une feuille de bas d'écran, pas un menu : le menu Material fait des cibles
/// de 36 dp accrochées au bouton, et ce public porte des gants. La feuille
/// donne trois rangées de 56 dp au pouce, se referme au geste retour, et
/// existe à l'identique sur téléphone et sur poste — une seule apparence.
///
/// C'est ici que vivent les six raccourcis du ticket : « toutes les nuits en
/// semaine » est la portée « La semaine » choisie avec le créneau « Nuit ».
/// Le couple portée × créneau en donne quinze, tous atteignables en deux
/// touches, sans mode armé qui survivrait au geste (brief 011 § 4).
Future<CibleCreneau?> choisirCreneauRaccourci({
  required BuildContext context,
  required PorteeRaccourci portee,
  required int Function(CibleCreneau) cases,
}) => showModalBottomSheet<CibleCreneau>(
  context: context,
  useSafeArea: true,
  builder: (BuildContext context) =>
      _FeuilleRaccourci(portee: portee, cases: cases),
);

class _FeuilleRaccourci extends StatelessWidget {
  const _FeuilleRaccourci({required this.portee, required this.cases});

  final PorteeRaccourci portee;

  /// Le nombre de cases que chaque créneau changerait. Affiché avant l'acte :
  /// « 18 cases » dit au membre ce qu'il s'apprête à faire, et la différence
  /// entre 18 et 0 lui dit que c'est déjà fait.
  final int Function(CibleCreneau) cases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return Semantics(
      namesRoute: true,
      label: portee.libelle,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(portee.libelle, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                portee.detail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final cible in CibleCreneau.values)
                _LigneCible(
                  portee: portee,
                  cible: cible,
                  cases: cases(cible),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une rangée de la feuille : le créneau, son icône, et son coût en cases.
class _LigneCible extends StatelessWidget {
  const _LigneCible({
    required this.portee,
    required this.cible,
    required this.cases,
  });

  final PorteeRaccourci portee;
  final CibleCreneau cible;
  final int cases;

  static const Map<CibleCreneau, IconData> _icones = <CibleCreneau, IconData>{
    CibleCreneau.jour: Icons.light_mode,
    CibleCreneau.nuit: Icons.bedtime,
    CibleCreneau.lesDeux: Icons.brightness_4,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Le raccourci qui n'a rien à changer reste touchable : il répond « rien
    // à changer » dans la bande, ce qui est une information. Le griser
    // demanderait d'afficher une raison pour chacune des trois rangées.
    final encre = portee == PorteeRaccourci.effacer
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      label: '${portee.libelle}, ${cible.libelle}',
      hint: AppStrings.raccourciCasesConcernees(cases),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(cible),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.champ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Icon(_icones[cible], size: AppTouch.icone, color: encre),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    cible.libelle,
                    style: theme.textTheme.bodyLarge?.copyWith(color: encre),
                  ),
                ),
                Text(
                  AppStrings.raccourciCasesConcernees(cases),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: AppTextStyles.chiffresTabulaires,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Demande confirmation avant d'écraser du travail déjà fait.
///
/// **Les deux seules modales du ticket**, et elles sont dues : « tout
/// effacer » et « copier le mois précédent » sont les seuls raccourcis qui
/// détruisent une saisie existante, et une erreur y coûte soixante-deux
/// cases. Les autres ne font qu'ajouter, et l'annulation de la bande suffit.
///
/// Elle n'apparaît **que si des saisies existent** dans la portée visée :
/// effacer un mois déjà vide n'a rien à protéger.
Future<bool> confirmerRaccourci({
  required BuildContext context,
  required PorteeRaccourci portee,
  required int saisies,
}) async {
  if (saisies == 0) return true;

  final efface = portee == PorteeRaccourci.effacer;
  final confirme = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(
        efface
            ? AppStrings.raccourciConfirmerEffacerTitre(saisies)
            : AppStrings.raccourciConfirmerCopieTitre(saisies),
      ),
      content: Text(
        efface
            ? AppStrings.raccourciConfirmerEffacerTexte
            : AppStrings.raccourciConfirmerCopieTexte,
      ),
      actionsOverflowButtonSpacing: AppSpacing.entreCibles,
      actions: <Widget>[
        PrimaryButton(
          libelle: AppStrings.actionAnnuler,
          variante: PrimaryButtonVariante.secondaire,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(
          libelle: efface
              ? AppStrings.raccourciConfirmerEffacerAction
              : AppStrings.raccourciConfirmerCopieAction,
          variante: PrimaryButtonVariante.danger,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirme ?? false;
}
