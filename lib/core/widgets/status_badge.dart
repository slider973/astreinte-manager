import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status.dart';
import 'hachures.dart';

/// Taille d'un badge d'état.
enum StatusBadgeTaille {
  /// 28 dp de haut, libellé en `libelle-champ`. La taille par défaut.
  normale,

  /// 22 dp de haut, libellé en `etiquette`. Réservée aux listes denses et aux
  /// en-têtes de colonne, jamais à une information isolée.
  compacte,
}

/// Badge d'état : la marque, l'icône et le libellé, indissociables.
///
/// Le badge ne sait rien des couleurs : il reçoit un [StatusDescriptor] résolu
/// par le thème, qui porte déjà l'icône et le libellé. Il est donc **impossible
/// d'afficher un état sans son icône ni son libellé** — la règle de
/// `DESIGN.md § Named Rules` est tenue par le type, pas par la discipline.
///
/// Signaux rendus, dans l'ordre de robustesse : le remplissage et la marque
/// ([StatusDescriptor.hachure], [StatusDescriptor.barre],
/// [StatusDescriptor.filet]), puis l'icône, puis le libellé, et la couleur en
/// quatrième. Une capture en niveaux de gris reste interprétable.
class StatusBadge extends StatelessWidget {
  /// Badge d'un état de disponibilité (« Disponible », « Absent », …).
  const StatusBadge.disponibilite(
    DisponibiliteEtat etat, {
    super.key,
    this.taille = StatusBadgeTaille.normale,
    this.libelle,
    this.tampon = false,
  }) : _valeur = etat;

  /// Badge d'un créneau (« Jour », « Nuit »).
  const StatusBadge.creneau(
    CreneauType type, {
    super.key,
    this.taille = StatusBadgeTaille.normale,
    this.libelle,
    this.tampon = false,
  }) : _valeur = type;

  /// Badge d'un état d'attribution (« En attente », « Accepté », …).
  const StatusBadge.attribution(
    AttributionEtat etat, {
    super.key,
    this.taille = StatusBadgeTaille.normale,
    this.libelle,
    this.tampon = false,
  }) : _valeur = etat;

  /// Badge d'un état de planning (« Brouillon », « Publié », …).
  const StatusBadge.planning(
    PlanningEtat etat, {
    super.key,
    this.taille = StatusBadgeTaille.normale,
    this.libelle,
    this.tampon = false,
  }) : _valeur = etat;

  /// Badge d'un état de période (« Saisie ouverte », « Mois verrouillé »).
  const StatusBadge.periode(
    PeriodeEtat etat, {
    super.key,
    this.taille = StatusBadgeTaille.normale,
    this.libelle,
    this.tampon = false,
  }) : _valeur = etat;

  /// Badge d'un état de synchronisation.
  const StatusBadge.sync(
    SyncEtat etat, {
    super.key,
    this.taille = StatusBadgeTaille.normale,
    this.libelle,
    this.tampon = false,
  }) : _valeur = etat;

  /// Badge d'un état qui n'a pas de famille dans le thème, mais dont le
  /// descripteur est **composé à partir des encres du thème** — la couverture
  /// d'un créneau, au ticket 017.
  ///
  /// Le descripteur est alors construit par l'appelant, à chaque rendu, depuis
  /// `context.statuts` : il suit donc le mode clair/sombre comme les autres.
  /// Ce que le type continue de garantir est l'essentiel : pas de badge sans
  /// icône ni libellé.
  const StatusBadge.descripteur(
    StatusDescriptor descripteur, {
    super.key,
    this.taille = StatusBadgeTaille.normale,
    this.libelle,
    this.tampon = false,
  }) : _valeur = descripteur;

  /// Valeur d'énumération portée par ce badge. Le thème la résout en
  /// [StatusDescriptor] au moment du rendu, pour suivre le mode clair/sombre.
  final Object _valeur;

  final StatusBadgeTaille taille;

  /// Libellé de remplacement, quand le contexte demande une formulation plus
  /// précise que celle du descripteur (« En attente de ta réponse » au lieu de
  /// « En attente »). Ne peut pas être vide : un badge muet n'existe pas.
  final String? libelle;

  /// **Le seul moment chorégraphié de l'application** : le tampon.
  ///
  /// Quand une proposition passe à « Accepté » ou qu'un planning passe à
  /// « Validé », le badge se pose en `scale 1.06 → 1.00` + opacité sur 180 ms,
  /// une fois. Supprimé sous Reduce Motion. Nulle part ailleurs.
  final bool tampon;

  StatusDescriptor _descripteur(AppStatusColors statuts) => switch (_valeur) {
    final StatusDescriptor d => d,
    final DisponibiliteEtat e => statuts.disponibilite(e),
    final CreneauType e => statuts.creneau(e),
    final AttributionEtat e => statuts.attribution(e),
    final PlanningEtat e => statuts.planning(e),
    final PeriodeEtat e => statuts.periode(e),
    final SyncEtat e => statuts.sync(e),
    _ => throw StateError('Famille d\'état inconnue : $_valeur'),
  };

  @override
  Widget build(BuildContext context) {
    assert(libelle != '', 'Un badge sans libellé est interdit.');

    final descripteur = _descripteur(context.statuts);
    final texte = libelle ?? descripteur.libelle;
    final compact = taille == StatusBadgeTaille.compacte;
    final theme = Theme.of(context);

    final style =
        (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
            ?.copyWith(
              color: descripteur.encre,
              decoration: descripteur.barre
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              decorationColor: descripteur.encre,
            );

    final badge = Semantics(
      label: texte,
      container: true,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: compact ? AppTouch.badgeCompact : AppTouch.badge,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: descripteur.fond,
            borderRadius: AppRadius.caseRegistreRadius,
            border: descripteur.filet == null
                ? null
                : Border.all(color: descripteur.filet!, width: AppStroke.etat),
          ),
          child: Stack(
            children: <Widget>[
              if (descripteur.hachure)
                Positioned.fill(
                  child: Hachures(
                    encre: descripteur.encre,
                    borderRadius: AppRadius.caseRegistreRadius,
                  ),
                ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? AppSpacing.xs + 2 : AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      descripteur.icone,
                      size: compact ? AppTouch.iconePetite : AppTouch.icone - 2,
                      color: descripteur.encre,
                    ),
                    SizedBox(
                      width: compact ? AppSpacing.xs : AppSpacing.xs + 2,
                    ),
                    Flexible(
                      child: Text(
                        texte,
                        style: style,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Le libellé tronqué reste atteignable au pointeur ; les lecteurs d'écran
    // reçoivent de toute façon le texte complet par le Semantics ci-dessus.
    final avecInfoBulle = Tooltip(message: texte, child: badge);

    if (!tampon || AppMotion.reduit(context)) return avecInfoBulle;

    return _Tampon(child: avecInfoBulle);
  }
}

/// Le geste du tampon qui se pose : une fois, 180 ms, jamais en boucle.
class _Tampon extends StatelessWidget {
  const _Tampon({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDuration.courant,
      curve: AppCurves.sortie,
      builder: (context, t, enfant) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 1.06 - 0.06 * t, child: enfant),
      ),
      child: child,
    );
  }
}
