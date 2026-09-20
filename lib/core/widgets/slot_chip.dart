import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status.dart';
import 'hachures.dart';

/// Les trois densités de la case.
enum SlotChipDensite {
  /// 48 dp — téléphone. La densité par défaut, celle des gants.
  confortable,

  /// 40 dp — tablette et listes. Interactive, elle est portée à 44 dp pour
  /// respecter le plancher tactile ; en lecture seule elle reste à 40.
  compacte,

  /// 28 px — **matrice admin, pointeur uniquement**. Jamais servie au
  /// tactile : sur tablette tactile, la matrice reste en [compacte] et défile
  /// (`DESIGN.md § Cibles tactiles`, brief § 7.6, aucune exception).
  dense;

  /// Côté de la case en dp.
  double get taille => switch (this) {
    SlotChipDensite.confortable => AppTouch.caseConfortable,
    SlotChipDensite.compacte => AppTouch.caseCompacte,
    SlotChipDensite.dense => AppTouch.caseDense,
  };

  /// Taille du glyphe d'état centré.
  double get glyphe => switch (this) {
    SlotChipDensite.confortable => AppTouch.glypheConfortable,
    SlotChipDensite.compacte => AppTouch.glypheCompact,
    SlotChipDensite.dense => AppTouch.glypheDense,
  };

  /// Hauteur minimale de la cible tactile quand la case est actionnable.
  double get cibleTactile => this == SlotChipDensite.dense
      ? taille
      : taille < AppTouch.plancher
      ? AppTouch.plancher
      : taille;

  /// Vrai si cette densité peut être servie à un doigt.
  bool get estTactile => this != SlotChipDensite.dense;
}

/// **La case du registre** — le composant signature du système.
///
/// Une case = un créneau (date + jour/nuit) + un état de disponibilité. Les
/// trois états se distinguent d'abord par le **remplissage et la texture**,
/// ensuite par l'icône, et seulement en dernier par la teinte : cochée pleine,
/// hachurée bordée, vide au filet tireté. Elles restent distinguables
/// photocopiées en noir et blanc, et à 40 cm au soleil.
///
/// La distinction entre « absent » et « non saisi » est le mécanisme qui
/// sépare ce produit de l'intranet remplacé. Si ces deux cases se ressemblent,
/// le système a échoué (brief § 2).
///
/// Le glissement continu de sélection (ticket 011) est pris en charge par le
/// parent : la case expose [onDragEnter] mais ne gère aucun geste multi-cases.
class SlotChip extends StatefulWidget {
  const SlotChip({
    required this.etat,
    required this.creneau,
    required this.libelleSemantique,
    super.key,
    this.densite = SlotChipDensite.confortable,
    this.selectionne = false,
    this.verrouille = false,
    this.enEnregistrement = false,
    this.erreur = false,
    this.onTap,
    this.onDragEnter,
    this.actionSemantique,
  });

  final DisponibiliteEtat etat;
  final CreneauType creneau;

  /// **Phrase complète française**, jamais un code :
  /// « Samedi 4 octobre, nuit, disponible ». Composée par le parent, qui seul
  /// connaît la date.
  final String libelleSemantique;

  /// Ce que l'appui va faire : « Appuie pour te marquer absent ».
  final String? actionSemantique;

  final SlotChipDensite densite;

  /// Contour 2 dp `primary` en plus de l'état.
  final bool selectionne;

  /// Mois verrouillé : hachures grises, non focalisable, non actionnable.
  /// La valeur reste parfaitement lisible ; seule l'interaction disparaît.
  final bool verrouille;

  /// Le contour pulse une fois. Supprimé sous Reduce Motion.
  final bool enEnregistrement;

  /// Contour 2 dp `error` : l'enregistrement a échoué pour cette case.
  final bool erreur;

  final VoidCallback? onTap;

  /// Appelé quand un glissement de sélection entre dans la case.
  ///
  /// La case ne démarre **jamais** un glissement elle-même : elle publie ce
  /// rappel dans un `MetaData`, et la grille du ticket 011 le retrouve en
  /// testant le point sous le doigt pendant son propre geste.
  final VoidCallback? onDragEnter;

  @override
  State<SlotChip> createState() => _SlotChipState();
}

class _SlotChipState extends State<SlotChip> {
  bool _focalise = false;

  bool get _actionnable =>
      widget.onTap != null && !widget.verrouille && widget.densite.estTactile;

  @override
  Widget build(BuildContext context) {
    assert(
      widget.densite != SlotChipDensite.dense ||
          widget.onTap == null ||
          context.estPointeurFin,
      'La densité dense est réservée au pointeur fin : sur tactile, utilise '
      'SlotChipDensite.compacte et laisse la matrice défiler.',
    );

    final theme = Theme.of(context);
    final statuts = context.statuts;
    final descripteur = statuts.disponibilite(widget.etat);
    final verrouillee = statuts.periode(PeriodeEtat.verrouillee);

    // Un seul contour à la fois, par ordre de priorité : erreur, puis
    // sélection, puis le filet propre à l'état.
    final (Color? filet, double epaisseur, bool tirete) = switch (widget) {
      _ when widget.erreur => (theme.colorScheme.error, AppStroke.etat, false),
      _ when _focalise || widget.selectionne => (
        theme.colorScheme.primary,
        AppStroke.etat,
        false,
      ),
      _ when widget.etat == DisponibiliteEtat.nonSaisi => (
        descripteur.filet,
        AppStroke.filet,
        true,
      ),
      _ => (descripteur.filet, AppStroke.etat, false),
    };

    // Le créneau ne porte aucune teinte : il ne se voit que là où l'état ne
    // remplit pas la case, c'est-à-dire sur « non saisi ». L'écart jour/nuit
    // est volontairement faible (1.18:1) — un repère de lecture, pas un état.
    final fond = widget.verrouille
        ? verrouillee.fond
        : widget.etat == DisponibiliteEtat.nonSaisi
        ? statuts.creneau(widget.creneau).fond
        : descripteur.fond;

    final case_ = _Case(
      fond: fond,
      filet: filet,
      epaisseurFilet: epaisseur,
      tirete: tirete,
      hachure: widget.verrouille || descripteur.hachure,
      encreHachure: widget.verrouille
          ? verrouillee.encre
          : descripteur.filet ?? descripteur.encre,
      glyphe: descripteur.iconeCase,
      tailleGlyphe: widget.densite.glyphe,
      encreGlyphe: widget.verrouille ? verrouillee.encre : descripteur.encre,
      pulse: widget.enEnregistrement && !AppMotion.reduit(context),
    );

    final dimensionnee = widget.densite == SlotChipDensite.dense
        ? SizedBox.square(dimension: widget.densite.taille, child: case_)
        : ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.densite.taille,
              minHeight: _actionnable
                  ? widget.densite.cibleTactile
                  : widget.densite.taille,
            ),
            child: case_,
          );

    return Semantics(
      label: widget.libelleSemantique,
      hint: widget.verrouille
          ? AppStrings.slotVerrouille
          : _actionnable
          ? widget.actionSemantique
          : null,
      button: _actionnable,
      enabled: _actionnable,
      toggled: widget.etat == DisponibiliteEtat.disponible,
      selected: widget.selectionne,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _actionnable,
        onShowFocusHighlight: (focalise) {
          if (focalise != _focalise) setState(() => _focalise = focalise);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        mouseCursor: _actionnable
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _actionnable ? widget.onTap : null,
          child: MetaData(
            metaData: widget.onDragEnter,
            behavior: HitTestBehavior.opaque,
            child: dimensionnee,
          ),
        ),
      ),
    );
  }
}

/// Le dessin de la case : remplissage, hachures, filet, glyphe centré.
class _Case extends StatelessWidget {
  const _Case({
    required this.fond,
    required this.filet,
    required this.epaisseurFilet,
    required this.tirete,
    required this.hachure,
    required this.encreHachure,
    required this.glyphe,
    required this.tailleGlyphe,
    required this.encreGlyphe,
    required this.pulse,
  });

  final Color fond;
  final Color? filet;
  final double epaisseurFilet;
  final bool tirete;
  final bool hachure;
  final Color encreHachure;
  final IconData glyphe;
  final double tailleGlyphe;
  final Color encreGlyphe;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final contenu = CustomPaint(
      painter: _CasePainter(
        fond: fond,
        filet: filet,
        epaisseurFilet: epaisseurFilet,
        tirete: tirete,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (hachure)
            Positioned.fill(
              child: Hachures(
                encre: encreHachure,
                borderRadius: AppRadius.caseRegistreRadius,
              ),
            ),
          Icon(glyphe, size: tailleGlyphe, color: encreGlyphe),
        ],
      ),
    );

    if (!pulse) return contenu;

    // Le contour pulse **une fois** : l'enregistrement est parti. Pas de
    // boucle, pas de respiration perpétuelle.
    return TweenAnimationBuilder<double>(
      key: const ValueKey<String>('pulse'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDuration.courant,
      curve: AppCurves.sortie,
      builder: (context, t, enfant) =>
          Opacity(opacity: 0.55 + 0.45 * t, child: enfant),
      child: contenu,
    );
  }
}

class _CasePainter extends CustomPainter {
  const _CasePainter({
    required this.fond,
    required this.filet,
    required this.epaisseurFilet,
    required this.tirete,
  });

  final Color fond;
  final Color? filet;
  final double epaisseurFilet;

  /// Filet tireté 3/3 : la signature graphique de « non saisi ».
  final bool tirete;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadius.caseRegistre),
    );
    canvas.drawRRect(rect, Paint()..color = fond);

    final couleurFilet = filet;
    if (couleurFilet == null) return;

    final trait = Paint()
      ..color = couleurFilet
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseurFilet;

    final demi = epaisseurFilet / 2;
    final contour = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        demi,
        demi,
        size.width - epaisseurFilet,
        size.height - epaisseurFilet,
      ),
      const Radius.circular(AppRadius.caseRegistre),
    );

    if (!tirete) {
      canvas.drawRRect(contour, trait);
      return;
    }

    const tiret = 3.0;
    for (final metrique in (Path()..addRRect(contour)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metrique.length) {
        canvas.drawPath(
          metrique.extractPath(distance, distance + tiret),
          trait,
        );
        distance += tiret * 2;
      }
    }
  }

  @override
  bool shouldRepaint(_CasePainter oldDelegate) =>
      oldDelegate.fond != fond ||
      oldDelegate.filet != filet ||
      oldDelegate.epaisseurFilet != epaisseurFilet ||
      oldDelegate.tirete != tirete;
}
