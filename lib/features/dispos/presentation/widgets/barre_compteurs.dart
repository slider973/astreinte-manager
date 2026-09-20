import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/count_stat.dart';
import '../../../../core/widgets/save_indicator.dart';
import '../../domain/disponibilite_mois.dart';

/// La barre du bas : l'état de l'enregistrement, puis les trois compteurs.
///
/// **Elle n'est pas une `liveRegion`** : elle changerait à chaque case peinte
/// et noierait les annonces utiles. C'est l'annonce de fin de geste qui porte
/// le résultat (brief 011 § 6.4). Elle est en revanche un conteneur
/// sémantique unique, étiqueté en phrase.
///
/// Pendant un geste, la fente de gauche laisse la place au pinceau : la
/// peinture devient visible pendant qu'elle a lieu, le pinceau est nommé, et
/// l'indicateur d'enregistrement ne peut pas bouger au moment le plus agité.
class BarreCompteurs extends StatelessWidget {
  const BarreCompteurs({
    required this.compteurs,
    required this.sync,
    super.key,
    this.pinceau,
    this.onReessayer,
    this.montrerIndicateur = true,
    this.grand = false,
  });

  /// Au-delà de ce facteur d'échelle, la barre passe sur deux lignes —
  /// indicateur au-dessus, compteurs en dessous — plutôt que de rogner quoi
  /// que ce soit.
  static const double seuilDeuxLignes = 1.3;

  final CompteursMois compteurs;
  final SyncEtat sync;

  /// Non nul pendant une peinture : la valeur en cours de pose.
  final DisponibiliteEtat? pinceau;

  final VoidCallback? onReessayer;

  /// Faux sur un mois verrouillé : il n'y a plus rien à enregistrer.
  final bool montrerIndicateur;

  /// Compteurs en `grand` pour le panneau latéral des grands écrans.
  final bool grand;

  @override
  Widget build(BuildContext context) {
    final echelle = MediaQuery.textScalerOf(context).scale(16) / 16;
    final empile = grand || echelle > seuilDeuxLignes;

    final fenteGauche = montrerIndicateur
        ? pinceau == null
              ? SaveIndicator(
                  etat: sync,
                  onReessayer: sync == SyncEtat.echec ? onReessayer : null,
                )
              : _Pinceau(etat: pinceau!)
        : const SizedBox.shrink();

    final chiffres = <Widget>[
      // `plafond: null` dès aujourd'hui : le ticket 013 n'aura qu'à le
      // remplir pour obtenir « 4 / 2 weekends », sans toucher à la barre.
      CountStat(
        libelle: AppStrings.compteurJours,
        valeur: compteurs.jours,
        grand: grand,
        plafondAttendu: false,
      ),
      CountStat(
        libelle: AppStrings.compteurNuits,
        valeur: compteurs.nuits,
        grand: grand,
        plafondAttendu: false,
      ),
      CountStat(
        libelle: AppStrings.compteurWeekends,
        valeur: compteurs.weekends,
        grand: grand,
        plafondAttendu: false,
      ),
    ];

    return Semantics(
      container: true,
      label: AppStrings.compteursResume(
        compteurs.jours,
        compteurs.nuits,
        compteurs.weekends,
      ),
      child: empile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                fenteGauche,
                const SizedBox(height: AppSpacing.md),
                _Chiffres(chiffres: chiffres),
              ],
            )
          // `Wrap` plutôt qu'un seuil de largeur deviné : quand l'indicateur
          // et les trois compteurs ne tiennent plus côte à côte — téléphone
          // de 320 dp, phrase d'échec, grande échelle de texte —, les
          // compteurs passent **entiers** sur une seconde ligne. Rien n'est
          // jamais rogné, et aucune largeur n'est codée en dur.
          : Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.md,
              children: <Widget>[
                fenteGauche,
                _Chiffres(chiffres: chiffres),
              ],
            ),
    );
  }
}

/// Les trois compteurs, groupés.
///
/// Ils passent à la ligne **ensemble** quand l'indicateur ne leur laisse plus
/// la place ; et entre eux, aux très grandes échelles de texte, ils se
/// répartissent sur plusieurs rangs plutôt que d'être rognés.
class _Chiffres extends StatelessWidget {
  const _Chiffres({required this.chiffres});

  final List<Widget> chiffres;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.lg,
    runSpacing: AppSpacing.md,
    children: chiffres,
  );
}

/// « Tu peins : Disponible » — la marque, l'icône et le libellé de l'état.
class _Pinceau extends StatelessWidget {
  const _Pinceau({required this.etat});

  final DisponibiliteEtat etat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripteur = context.statuts.disponibilite(etat);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: descripteur.fond,
        borderRadius: AppRadius.caseRegistreRadius,
        border: Border.all(color: descripteur.filet ?? descripteur.encre),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              descripteur.iconeCase,
              size: AppTouch.icone,
              color: descripteur.encre,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                AppStrings.peintureEnCours(descripteur.libelle),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: descripteur.encre,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
