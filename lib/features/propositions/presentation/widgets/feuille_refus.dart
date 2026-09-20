import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/primary_button.dart';

/// Ce que la feuille de refus rend : le motif saisi, ou `null` si on a gardé
/// le créneau. Une chaîne vide est un refus **sans** motif, ce qui est permis.
typedef ResultatRefus = String?;

/// Demande le refus d'un créneau, motif court facultatif.
///
/// Feuille de bas d'écran en compact, medium et expanded ; dialogue en large
/// — `DESIGN.md § Don't` interdit la modale pour une tâche qui ne demande ni
/// interruption ni protection, mais **un refus en demande une** : il est
/// irréversible (`declined --> [*]`, `docs/WORKFLOWS.md § 3`) et il fait
/// sonner le téléphone du chef de centre.
///
/// C'est l'asymétrie assumée du ticket : accepter coûte une touche, refuser en
/// coûte deux (`design/021 § 6.3`). Rend `null` quand rien n'est refusé.
Future<ResultatRefus?> demanderRefus(
  BuildContext context, {
  required String creneau,
}) {
  final grand = AppWindowClass.of(context).estLarge;

  if (grand) {
    return showDialog<ResultatRefus>(
      context: context,
      builder: (BuildContext context) =>
          Dialog(child: _CorpsRefus(creneau: creneau, dansUneFeuille: false)),
    );
  }

  return showModalBottomSheet<ResultatRefus>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) =>
        _CorpsRefus(creneau: creneau, dansUneFeuille: true),
  );
}

class _CorpsRefus extends StatefulWidget {
  const _CorpsRefus({required this.creneau, required this.dansUneFeuille});

  final String creneau;
  final bool dansUneFeuille;

  @override
  State<_CorpsRefus> createState() => _CorpsRefusState();
}

class _CorpsRefusState extends State<_CorpsRefus> {
  final TextEditingController _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  void _refuser() => Navigator.of(context).pop(_motif.text.trim());

  void _garder() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: widget.dansUneFeuille ? 0 : AppSpacing.xl,
          // Le clavier logiciel pousse la feuille : les deux boutons restent
          // visibles au-dessus de lui.
          bottom:
              AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                AppStrings.refusTitre(widget.creneau),
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppStrings.refusDefinitif,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            ChampTexte(
              libelle: AppStrings.refusMotifLibelle,
              controleur: _motif,
              clavier: TextInputType.text,
              texteInvite: AppStrings.refusMotifInvite,
              longueurMax: AppStrings.refusMotifLongueurMax,
              // **Pas d'autofocus.** Ouvrir un clavier logiciel sur un écran
              // qu'on consulte en marchant pousse les deux boutons hors de
              // vue. Qui veut écrire touche le champ.
              onSoumission: (_) => _refuser(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppStrings.refusMotifAide,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _Boutons(onGarder: _garder, onRefuser: _refuser),
          ],
        ),
      ),
    );
  }
}

/// Les deux sorties de la feuille.
///
/// **Empilées sur téléphone, côte à côte au-delà.** Côte à côte à 390 dp,
/// « Garder le créneau » s'écrivait « Garder le crén… » : un libellé d'action
/// tronqué est un défaut, et raccourcir le libellé aurait coûté ce qu'il nomme
/// (`DESIGN.md § Buttons`). Vu dans Chrome.
///
/// Empilées, l'ordre est délibéré : **la sortie inoffensive est la plus
/// proche du pouce.** Un refus est irréversible ; il ne doit pas être le
/// bouton qu'on atteint sans viser.
class _Boutons extends StatelessWidget {
  const _Boutons({required this.onGarder, required this.onRefuser});

  final VoidCallback onGarder;
  final VoidCallback onRefuser;

  @override
  Widget build(BuildContext context) {
    final refuser = PrimaryButton(
      libelle: AppStrings.refusConfirmer,
      variante: PrimaryButtonVariante.danger,
      icone: Icons.cancel,
      pleineLargeur: true,
      onPressed: onRefuser,
    );
    final garder = PrimaryButton(
      libelle: AppStrings.refusGarder,
      variante: PrimaryButtonVariante.secondaire,
      pleineLargeur: true,
      onPressed: onGarder,
    );

    if (AppWindowClass.of(context).estCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          refuser,
          const SizedBox(height: AppSpacing.entreCibles),
          garder,
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: garder),
        const SizedBox(width: AppSpacing.entreCibles),
        Expanded(child: refuser),
      ],
    );
  }
}
