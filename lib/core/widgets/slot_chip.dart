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
  ///
  /// Elle **est** actionnable, mais seulement au pointeur fin : l'admin du
  /// ticket 016 clique ses cellules. C'est le doigt qui lui est interdit, pas
  /// la souris.
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

  /// Hauteur minimale de la cible quand la case est actionnable.
  ///
  /// Le plancher de 44 dp ne s'applique qu'au doigt : en [dense], la cible
  /// reste à 28 px, ce qui dépasse le minimum WCAG de 24 px pour un pointeur.
  double get cibleTactile => this == SlotChipDensite.dense
      ? taille
      : taille < AppTouch.plancher
      ? AppTouch.plancher
      : taille;

  /// Vrai si cette densité peut être servie à un doigt.
  bool get estTactile => this != SlotChipDensite.dense;

  /// Vrai si cette densité peut être actionnée dans ce contexte.
  ///
  /// [dense] exige un pointeur fin ; les deux autres acceptent tout.
  bool actionnableDans(BuildContext context) =>
      estTactile || context.estPointeurFin;
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
/// **Sans état.** La case ne crée aucun `State` : le halo de focus est lu
/// depuis le `Focus` qui l'enveloppe, et ce `Focus` n'existe que si la case est
/// actionnable. En densité [SlotChipDensite.dense] et en lecture seule, il ne
/// reste qu'un `Semantics` et un `CustomPaint` — c'est le budget de la matrice
/// du ticket 016, qui monte à 3 720 cases (voir `DESIGN.md § Écarts`).
///
/// Le glissement continu de sélection (ticket 011) est pris en charge par le
/// parent : la case expose [onDragEnter] mais ne gère aucun geste multi-cases.
class SlotChip extends StatelessWidget {
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
    this.saisiParAdmin = false,
    this.onTap,
    this.onDragEnter,
    this.onRefus,
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

  /// **Saisie faite par un administrateur à la place du membre** (ticket 016).
  ///
  /// Contour 2 dp `tertiary`, priorité après [erreur] et [selectionne], et
  /// avant le filet propre à l'état. La valeur de disponibilité est la même
  /// qu'une saisie du membre : ce drapeau dit **qui a écrit**, pas quoi.
  ///
  /// C'est une valeur, jamais un état interne : la case reste sans `State`.
  /// La marque est doublée d'un mot dans la sémantique — la couleur n'est
  /// jamais seule (`DESIGN.md § Named Rules`).
  final bool saisiParAdmin;

  final VoidCallback? onTap;

  /// Appelé quand la case est **verrouillée** et qu'on appuie dessus.
  ///
  /// La case reste non modifiable : elle ne prend pas le focus, n'a pas
  /// d'état pressé et ne s'annonce pas comme une bascule. Mais elle
  /// **répond** — une case inerte qui ne dit rien laisse croire à une panne,
  /// et le doigt recommence (ticket 014).
  final VoidCallback? onRefus;

  /// Appelé quand un glissement de sélection entre dans la case.
  ///
  /// La case ne démarre **jamais** un glissement elle-même : elle publie ce
  /// rappel dans un `MetaData`, et la grille du ticket 011 le retrouve en
  /// testant le point sous le doigt pendant son propre geste. Le `MetaData`
  /// n'existe que si ce rappel est fourni : la matrice admin ne paie pas un
  /// objet de rendu par case pour un geste qu'elle n'utilise pas.
  final VoidCallback? onDragEnter;

  bool _actionnable(BuildContext context) =>
      onTap != null && !verrouille && densite.actionnableDans(context);

  @override
  Widget build(BuildContext context) {
    assert(
      densite != SlotChipDensite.dense ||
          onTap == null ||
          context.estPointeurFin,
      'La densité dense est réservée au pointeur fin : sur tactile, utilise '
      'SlotChipDensite.compacte et laisse la matrice défiler.',
    );

    final actionnable = _actionnable(context);
    final refus = verrouille ? onRefus : null;
    final apparence = _Apparence.resoudre(
      context,
      etat: etat,
      creneau: creneau,
      verrouille: verrouille,
      selectionne: selectionne,
      erreur: erreur,
      saisiParAdmin: saisiParAdmin,
      pulse: enEnregistrement && !AppMotion.reduit(context),
    );

    Widget dessiner({required bool focalise, bool presse = false}) {
      final case_ = _Case(
        apparence: apparence
            .avecFocus(context, focalise: focalise)
            .avecAppui(presse: presse),
        tailleGlyphe: densite.glyphe,
      );

      final dimensionnee = densite == SlotChipDensite.dense
          ? SizedBox.square(dimension: densite.taille, child: case_)
          : ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: densite.taille,
                minHeight: actionnable ? densite.cibleTactile : densite.taille,
              ),
              child: case_,
            );

      if (onDragEnter == null) return dimensionnee;
      return MetaData(
        metaData: onDragEnter,
        behavior: HitTestBehavior.opaque,
        child: dimensionnee,
      );
    }

    return Semantics(
      // La marque « saisi par un administrateur » est un contour : elle se
      // double d'un mot, sinon elle ne serait qu'une couleur.
      label: saisiParAdmin
          ? '$libelleSemantique, ${AppStrings.matriceCaseSaisieParAdmin}'
          : libelleSemantique,
      hint: verrouille
          ? AppStrings.slotVerrouille
          : actionnable
          ? actionSemantique
          : null,
      button: actionnable,
      enabled: actionnable,
      toggled: etat == DisponibiliteEtat.disponible,
      selected: selectionne,
      // Une case verrouillée reste activable par un lecteur d'écran : c'est
      // par là qu'arrive l'explication du refus, comme au doigt.
      onTap: refus,
      excludeSemantics: true,
      // Hors interaction, il ne reste que le Semantics et la peinture : pas de
      // Focus, pas de MouseRegion, pas de GestureDetector — et pour une case
      // verrouillée qui explique son refus, un seul détecteur d'appui.
      child: actionnable
          ? _Actionnable(onTap: onTap!, dessiner: dessiner)
          : refus == null
          ? dessiner(focalise: false)
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: refus,
              child: dessiner(focalise: false),
            ),
    );
  }
}

/// La couche d'interaction : focus clavier, curseur, appui.
///
/// Le halo de focus est relu depuis le `Focus` englobant via un `Builder` :
/// `Focus` publie son nœud dans un `InheritedNotifier`, donc le `Builder` se
/// reconstruit seul quand le focus entre ou sort.
///
/// Le seul `State` de cette couche porte l'**état pressé** (brief 011 § 6.1) :
/// la case s'assombrit sous le doigt dès le contact, sans que rien ne bouge —
/// ni taille, ni bordure. Il n'existe que sur une case actionnable : une
/// matrice en lecture seule n'en paie pas un seul.
///
/// `onTapCancel` est ce qui rend l'effet honnête pendant un défilement : le
/// doigt posé sur une case puis tiré rend la case à son état normal au moment
/// exact où le `Scrollable` gagne l'arène.
class _Actionnable extends StatefulWidget {
  const _Actionnable({required this.onTap, required this.dessiner});

  final VoidCallback onTap;
  final Widget Function({required bool focalise, bool presse}) dessiner;

  @override
  State<_Actionnable> createState() => _ActionnableState();
}

class _ActionnableState extends State<_Actionnable> {
  bool _presse = false;

  void _marquer({required bool presse}) {
    if (_presse == presse) return;
    setState(() => _presse = presse);
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        // Entrée et Espace activent la case comme un clic.
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Focus(
        child: Builder(
          builder: (context) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onTapDown: (_) => _marquer(presse: true),
              onTapUp: (_) => _marquer(presse: false),
              onTapCancel: () => _marquer(presse: false),
              child: widget.dessiner(
                focalise: Focus.of(context).hasFocus,
                presse: _presse,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tout ce qu'il faut peindre une case, résolu une fois depuis le thème.
@immutable
class _Apparence {
  const _Apparence({
    required this.fond,
    required this.filet,
    required this.epaisseurFilet,
    required this.tirete,
    required this.hachure,
    required this.encreHachure,
    required this.glyphe,
    required this.encreGlyphe,
    required this.pulse,
    required this.contourImpose,
  });

  final Color fond;
  final Color? filet;
  final double epaisseurFilet;
  final bool tirete;
  final bool hachure;
  final Color encreHachure;
  final IconData glyphe;
  final Color encreGlyphe;
  final bool pulse;

  /// Vrai quand le contour est déjà réservé à l'erreur ou à la sélection : le
  /// focus ne peut alors plus le réclamer.
  final bool contourImpose;

  static _Apparence resoudre(
    BuildContext context, {
    required DisponibiliteEtat etat,
    required CreneauType creneau,
    required bool verrouille,
    required bool selectionne,
    required bool erreur,
    required bool saisiParAdmin,
    required bool pulse,
  }) {
    final theme = Theme.of(context);
    final statuts = context.statuts;
    final descripteur = statuts.disponibilite(etat);
    final verrouillee = statuts.periode(PeriodeEtat.verrouillee);

    // Sur un mois verrouillé, **le contour devient gris comme le reste**.
    // Le filet vermillon d'« absent » y serait lu comme une alarme alors que
    // le verrouillage est un fait (`DESIGN.md § Do's`) ; la valeur, elle,
    // reste parfaitement lisible, portée par son glyphe et par sa texture.
    final filetEtat = verrouille ? verrouillee.encre : descripteur.filet;

    // Un seul contour à la fois, par ordre de priorité : erreur, puis
    // sélection, puis la saisie par un administrateur, puis le filet propre à
    // l'état. Le contour de procuration n'est **pas** imposé : l'anneau de
    // focus peut encore le prendre, et il n'est jamais supprimé.
    final (
      Color? filet,
      double epaisseur,
      bool tirete,
      bool impose,
    ) = switch (0) {
      _ when erreur => (theme.colorScheme.error, AppStroke.etat, false, true),
      _ when selectionne => (
        theme.colorScheme.primary,
        AppStroke.etat,
        false,
        true,
      ),
      _ when saisiParAdmin && !verrouille => (
        theme.colorScheme.tertiary,
        AppStroke.etat,
        false,
        false,
      ),
      _ when etat == DisponibiliteEtat.nonSaisi => (
        filetEtat,
        AppStroke.filet,
        true,
        false,
      ),
      _ => (filetEtat, AppStroke.etat, false, false),
    };

    // Le créneau ne porte aucune teinte : il ne se voit que là où l'état ne
    // remplit pas la case, c'est-à-dire sur « non saisi ». L'écart jour/nuit
    // est volontairement faible (1.18:1) — un repère de lecture, pas un état.
    final fond = verrouille
        ? verrouillee.fond
        : etat == DisponibiliteEtat.nonSaisi
        ? statuts.creneau(creneau).fond
        : descripteur.fond;

    return _Apparence(
      fond: fond,
      filet: filet,
      epaisseurFilet: epaisseur,
      tirete: tirete,
      hachure: verrouille || descripteur.hachure,
      encreHachure: verrouille
          ? verrouillee.encre
          : descripteur.filet ?? descripteur.encre,
      glyphe: descripteur.iconeCase,
      encreGlyphe: verrouille ? verrouillee.encre : descripteur.encre,
      pulse: pulse,
      contourImpose: impose,
    );
  }

  /// L'anneau de focus, 2 dp `primary`, jamais supprimé — sauf quand le
  /// contour dit déjà une erreur ou une sélection, qui priment.
  _Apparence avecFocus(BuildContext context, {required bool focalise}) {
    if (!focalise || contourImpose) return this;
    return _Apparence(
      fond: fond,
      filet: Theme.of(context).colorScheme.primary,
      epaisseurFilet: AppStroke.etat,
      tirete: false,
      hachure: hachure,
      encreHachure: encreHachure,
      glyphe: glyphe,
      encreGlyphe: encreGlyphe,
      pulse: pulse,
      contourImpose: true,
    );
  }

  /// L'état pressé : **8 % de l'encre d'état versés dans le fond**, et rien
  /// d'autre. Ni taille, ni bordure, ni ombre : rien ne doit bouger sous un
  /// doigt ganté, sous peine de rater la case voisine.
  _Apparence avecAppui({required bool presse}) {
    if (!presse) return this;
    return _Apparence(
      fond: Color.alphaBlend(encreGlyphe.withValues(alpha: 0.08), fond),
      filet: filet,
      epaisseurFilet: epaisseurFilet,
      tirete: tirete,
      hachure: hachure,
      encreHachure: encreHachure,
      glyphe: glyphe,
      encreGlyphe: encreGlyphe,
      pulse: pulse,
      contourImpose: contourImpose,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Apparence &&
          other.fond == fond &&
          other.filet == filet &&
          other.epaisseurFilet == epaisseurFilet &&
          other.tirete == tirete &&
          other.hachure == hachure &&
          other.encreHachure == encreHachure &&
          other.glyphe == glyphe &&
          other.encreGlyphe == encreGlyphe &&
          other.pulse == pulse &&
          other.contourImpose == contourImpose;

  @override
  int get hashCode => Object.hash(
    fond,
    filet,
    epaisseurFilet,
    tirete,
    hachure,
    encreHachure,
    glyphe,
    encreGlyphe,
    pulse,
    contourImpose,
  );
}

/// Le dessin de la case : remplissage, hachures, filet, glyphe centré.
class _Case extends StatelessWidget {
  const _Case({required this.apparence, required this.tailleGlyphe});

  final _Apparence apparence;
  final double tailleGlyphe;

  @override
  Widget build(BuildContext context) {
    // Sans hachures, la case entière tient dans un seul CustomPaint : pas de
    // Stack, pas de Positioned, un objet de rendu au lieu de quatre.
    final contenu = CustomPaint(
      painter: _CasePainter(
        fond: apparence.fond,
        filet: apparence.filet,
        epaisseurFilet: apparence.epaisseurFilet,
        tirete: apparence.tirete,
      ),
      child: apparence.hachure
          ? Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Positioned.fill(
                  child: Hachures(
                    encre: apparence.encreHachure,
                    borderRadius: AppRadius.caseRegistreRadius,
                  ),
                ),
                _Glyphe(apparence: apparence, taille: tailleGlyphe),
              ],
            )
          // `widthFactor`/`heightFactor` à 1 : la case se dimensionne sur son
          // glyphe, exactement comme le faisait le Stack, et c'est le
          // ConstrainedBox du parent qui impose ensuite la densité.
          : Align(
              widthFactor: 1,
              heightFactor: 1,
              child: _Glyphe(apparence: apparence, taille: tailleGlyphe),
            ),
    );

    if (!apparence.pulse) return contenu;

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

class _Glyphe extends StatelessWidget {
  const _Glyphe({required this.apparence, required this.taille});

  final _Apparence apparence;
  final double taille;

  @override
  Widget build(BuildContext context) =>
      Icon(apparence.glyphe, size: taille, color: apparence.encreGlyphe);
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
