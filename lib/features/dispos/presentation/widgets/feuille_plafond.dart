import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Un choix de plafond rendu par la feuille. Le type existe pour une seule
/// raison : `null` est une **valeur** ici (« autant que nécessaire »), et il
/// ne peut donc pas servir à dire « feuille refermée ».
@immutable
class ChoixPlafond {
  const ChoixPlafond(this.valeur);

  final int? valeur;
}

/// Demande **combien** : une feuille de bas d'écran, une rangée par valeur.
///
/// Une feuille et pas un menu : le menu Material fait des cibles de 36 dp, et
/// ce public porte des gants (décision du 012, reprise telle quelle). Ni
/// incrémenteur ni champ de nombre : « autant que nécessaire » est le *plus
/// grand* des choix et se rangerait sous zéro dans un incrémenteur, ce qui ne
/// se lit pas ; un champ ouvre le clavier et accepte l'invalide là où il n'y a
/// que sept choix réels.
Future<ChoixPlafond?> choisirPlafond({
  required BuildContext context,
  required String titre,
  required int? valeur,
  required int maximum,
  required String libelleZero,
  required String Function(int) libelleNombre,
}) => showModalBottomSheet<ChoixPlafond>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (BuildContext context) => _FeuillePlafond(
    titre: titre,
    valeur: valeur,
    maximum: maximum,
    libelleZero: libelleZero,
    libelleNombre: libelleNombre,
  ),
);

class _FeuillePlafond extends StatelessWidget {
  const _FeuillePlafond({
    required this.titre,
    required this.valeur,
    required this.maximum,
    required this.libelleZero,
    required this.libelleNombre,
  });

  final String titre;
  final int? valeur;

  /// La borne vient du mois affiché, jamais d'une constante inventée :
  /// proposer « 6 weekends » dans un mois qui en compte 5 serait un chiffre
  /// faux.
  final int maximum;

  final String libelleZero;
  final String Function(int) libelleNombre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return Semantics(
      namesRoute: true,
      label: titre,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(titre, style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                // « Autant que nécessaire » en tête : c'est le défaut du
                // produit, pas une option de repli.
                _Rangee(
                  libelle: AppStrings.preferencesSansLimite,
                  choisie: valeur == null,
                  onChoisir: () =>
                      Navigator.of(context).pop(const ChoixPlafond(null)),
                ),
                for (var nombre = 0; nombre <= maximum; nombre++)
                  _Rangee(
                    libelle: nombre == 0 ? libelleZero : libelleNombre(nombre),
                    nombre: nombre,
                    choisie: valeur == nombre,
                    onChoisir: () =>
                        Navigator.of(context).pop(ChoixPlafond(nombre)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une rangée de 56 dp : le nombre, son libellé, et la coche de la valeur
/// courante.
class _Rangee extends StatelessWidget {
  const _Rangee({
    required this.libelle,
    required this.choisie,
    required this.onChoisir,
    this.nombre,
  });

  final String libelle;
  final int? nombre;
  final bool choisie;
  final VoidCallback onChoisir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compte = nombre;

    return Semantics(
      button: true,
      selected: choisie,
      label: libelle,
      child: InkWell(
        onTap: onChoisir,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.champ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: AppSpacing.xxl,
                  child: compte == null
                      ? null
                      : Text(
                          '$compte',
                          style: AppTextStyles.nombre.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                ),
                Expanded(
                  child: Text(libelle, style: theme.textTheme.bodyLarge),
                ),
                if (choisie)
                  Icon(
                    Icons.check,
                    size: AppTouch.icone,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
