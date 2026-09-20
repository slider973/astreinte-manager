import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status.dart';

/// L'indicateur d'enregistrement automatique.
///
/// L'application enregistre en continu : ce composant est le seul endroit où
/// l'utilisateur lit où en est son travail. Il suit la séquence du brief § 6 :
/// la case change d'état optimistement, l'indicateur passe en
/// « Enregistrement… », puis « Enregistré ». En cas d'échec, il affiche
/// « Non enregistré » **et** « Réessayer » — jamais un échec sans sortie.
///
/// L'échec est annoncé (`liveRegion`) : un lecteur d'écran l'entend sans que
/// le focus bouge.
class SaveIndicator extends StatelessWidget {
  const SaveIndicator({
    required this.etat,
    super.key,
    this.onReessayer,
    this.compact = false,
  });

  final SyncEtat etat;

  /// Obligatoire quand [etat] vaut [SyncEtat.echec] : un état d'échec sans
  /// action est un défaut de revue.
  final VoidCallback? onReessayer;

  /// Version réduite pour une barre d'application : l'icône seule, le libellé
  /// restant dans les semantics et dans l'info-bulle.
  final bool compact;

  bool get _enEchec => etat == SyncEtat.echec;

  @override
  Widget build(BuildContext context) {
    assert(
      !_enEchec || onReessayer != null,
      'SyncEtat.echec exige onReessayer : un échec doit toujours proposer '
      'une sortie.',
    );

    final theme = Theme.of(context);
    final descripteur = context.statuts.sync(etat);
    final annonce = _enEchec || etat == SyncEtat.horsLigne;

    final icone = etat == SyncEtat.enregistrement
        ? _IconeRotative(
            icone: descripteur.icone,
            couleur: descripteur.encre,
            anime: !AppMotion.reduit(context),
          )
        : Icon(
            descripteur.icone,
            size: AppTouch.icone,
            color: descripteur.encre,
          );

    final libelle = _enEchec ? AppStrings.saveEchecDetail : descripteur.libelle;

    if (compact) {
      return Semantics(
        liveRegion: annonce,
        label: libelle,
        excludeSemantics: true,
        child: Tooltip(message: libelle, child: icone),
      );
    }

    return Semantics(
      liveRegion: annonce,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: descripteur.fond,
          borderRadius: AppRadius.caseRegistreRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              icone,
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  libelle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: descripteur.encre,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onReessayer != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: onReessayer,
                  style: TextButton.styleFrom(
                    foregroundColor: descripteur.encre,
                  ),
                  child: const Text(AppStrings.actionReessayer),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Le seul mouvement continu toléré du système : il dit qu'un échange réseau
/// est en cours, et il s'arrête dès qu'il est fini. Supprimé sous Reduce
/// Motion, où l'icône reste fixe et le libellé suffit.
class _IconeRotative extends StatefulWidget {
  const _IconeRotative({
    required this.icone,
    required this.couleur,
    required this.anime,
  });

  final IconData icone;
  final Color couleur;
  final bool anime;

  @override
  State<_IconeRotative> createState() => _IconeRotativeState();
}

class _IconeRotativeState extends State<_IconeRotative>
    with SingleTickerProviderStateMixin {
  // Créé dès initState, jamais paresseusement : un contrôleur instancié
  // pendant dispose() irait chercher son TickerMode dans un arbre déjà
  // démonté.
  late final AnimationController _controleur;

  @override
  void initState() {
    super.initState();
    _controleur = AnimationController(
      vsync: this,
      duration: AppDuration.balayage,
    );
    if (widget.anime) unawaited(_controleur.repeat());
  }

  @override
  void didUpdateWidget(_IconeRotative oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.anime && !_controleur.isAnimating) {
      unawaited(_controleur.repeat());
    } else if (!widget.anime && _controleur.isAnimating) {
      _controleur
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icone = Icon(
      widget.icone,
      size: AppTouch.icone,
      color: widget.couleur,
    );
    if (!widget.anime) return icone;

    return RotationTransition(turns: _controleur, child: icone);
  }
}
