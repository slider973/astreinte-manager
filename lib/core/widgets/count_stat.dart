import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Un compteur : une valeur, éventuellement un plafond.
///
/// Employé pour les quotas du membre (« 2 sur 3 astreintes ») et pour les
/// totaux de la matrice admin. Le nombre est en **chasse fixe avec chiffres
/// tabulaires** : il change en place sans faire sauter la mise en page, et une
/// colonne de compteurs s'aligne au pixel (`DESIGN.md § Typography`).
///
/// Ce n'est pas une « métrique héroïque » : le libellé est au moins aussi
/// lisible que le nombre, et le compteur ne vit jamais seul sur une page.
class CountStat extends StatelessWidget {
  const CountStat({
    required this.libelle,
    required this.valeur,
    super.key,
    this.plafond,
    this.grand = false,
    this.plafondAttendu = true,
    this.nombreEnTete = false,
  });

  /// « Jours », « Nuits », « Weekends ».
  final String libelle;

  final int valeur;

  /// `null` signifie **illimité**, et c'est écrit en toutes lettres : un
  /// symbole `∞` seul n'est pas lisible pour tout le monde.
  final int? plafond;

  /// Compteur du mois, gros total : `display-nombre` au lieu de `nombre`.
  final bool grand;

  /// Vrai quand l'absence de plafond doit être **dite** (« illimité »).
  ///
  /// Faux pour un total qui n'a pas de plafond par nature : les compteurs du
  /// mois (ticket 011) ne sont pas des quotas, et « 12 illimité » ne veut
  /// rien dire — en plus de coûter la largeur de trois colonnes sur un
  /// téléphone. Le ticket 013 remplira [plafond] et le mot disparaîtra de
  /// lui-même.
  final bool plafondAttendu;

  /// Le nombre **au-dessus** du libellé, et non en dessous.
  ///
  /// Pour une rangée de compteurs côte à côte dont les libellés n'ont pas la
  /// même longueur : « Réponses en attente » se replie sur deux lignes là où
  /// « À pourvoir » tient sur une, et le nombre placé dessous descend d'une
  /// ligne pendant que ses voisins restent en haut. Les trois nombres
  /// doivent se lire d'un seul balayage ; mis en tête, ils partagent la même
  /// ligne quel que soit le repli des libellés.
  ///
  /// Un compteur seul, ou une colonne de compteurs aux libellés de même
  /// gabarit — les quotas du membre — garde l'ordre naturel : on y lit
  /// d'abord de quoi on parle.
  final bool nombreEnTete;

  /// Vrai si le quota est atteint ou dépassé.
  bool get atteint => plafond != null && valeur >= plafond!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limite = plafond;

    final styleValeur =
        (grand ? AppTextStyles.displayNombre : AppTextStyles.nombre).copyWith(
          color: theme.colorScheme.onSurface,
        );
    final stylePlafond = AppTextStyles.nombre.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final texteLibelle = Text(
      libelle,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    // À très grande échelle de texte, un gros total peut dépasser la colonne.
    // On le réduit jusqu'à la largeur disponible plutôt que de le tronquer :
    // un compteur à moitié lu est pire qu'un compteur un peu plus petit. Le
    // libellé, lui, garde sa taille.
    final texteValeur = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('$valeur', style: styleValeur),
          if (limite != null) ...<Widget>[
            Text(' / ', style: stylePlafond),
            Text('$limite', style: stylePlafond),
          ] else if (plafondAttendu) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Text(
              AppStrings.compteurIllimite,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      label: libelle,
      value: limite != null
          ? AppStrings.compteurSurPlafond(valeur, limite)
          : plafondAttendu
          ? AppStrings.compteurSansPlafond(valeur)
          : '$valeur',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // L'ordre change, l'annonce non : la sémantique dit le libellé puis
          // sa valeur dans les deux cas.
          if (nombreEnTete) ...<Widget>[
            texteValeur,
            const SizedBox(height: AppSpacing.xxs),
            texteLibelle,
          ] else ...<Widget>[
            texteLibelle,
            const SizedBox(height: AppSpacing.xxs),
            texteValeur,
          ],
        ],
      ),
    );
  }
}
