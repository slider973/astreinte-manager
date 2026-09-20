import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/app_spacing.dart';

/// **Le pinceau du registre**, isolé du métier.
///
/// Ce widget ne connaît que deux choses : « il y a une case sous ce point »
/// et « applique-lui quelque chose ». Il ne sait pas ce qu'est une
/// disponibilité, ni ce qu'est un mois. La case, elle, publie son rappel dans
/// un `MetaData` (voir `SlotChip.onDragEnter`) ; la grille le retrouve en
/// testant le point sous le doigt.
///
/// **Ce qu'il ne vole jamais.**
///
/// - *Le défilement vertical.* Un doigt posé et tiré fait défiler la page,
///   partout, y compris sur une case. Seul un **appui maintenu** ouvre la
///   peinture, via un [DelayedMultiDragGestureRecognizer] qui ne réclame
///   l'arène qu'après [delaiAppuiLong] sans mouvement — exactement le
///   mécanisme d'une liste réordonnable.
/// - *Le geste retour depuis le bord gauche de l'iPhone.* Une peinture ne
///   peut pas **démarrer** à moins de [margeGaucheInerte] du bord. Une touche
///   simple y fonctionne normalement, et une peinture déjà en cours couvre
///   tout l'écran : le geste système a alors déjà perdu l'arène.
///
/// Au pointeur fin, la pression et le mouvement suffisent : une souris ne
/// fait pas défiler la page en tirant le contenu, il n'y a rien à départager.
class PeintureGrille extends StatefulWidget {
  const PeintureGrille({
    required this.child,
    required this.onDebut,
    required this.onFin,
    required this.onAnnulation,
    super.key,
    this.actif = true,
    this.pointeurFin = false,
    this.controleurDefilement,
    this.margeGaucheInerte = 0,
  });

  /// Le délai d'appui avant qu'un doigt n'ouvre la peinture.
  ///
  /// 300 ms plutôt que les 500 ms de `kLongPressTimeout` : c'est un geste de
  /// production répété soixante fois, pas une découverte de menu contextuel.
  static const Duration delaiAppuiLong = Duration(milliseconds: 300);

  /// Le segment entre deux positions de pointeur est échantillonné au plus
  /// tous les 16 dp — un tiers de hauteur de case — pour qu'un glissement
  /// rapide ne saute aucune case.
  static const double pasEchantillonnage = 16;

  /// Bande haute et basse où la peinture entraîne le défilement.
  static const double bandeDefilement = 72;

  /// Vitesse maximale du défilement automatique, au bord de l'écran.
  ///
  /// 400 dp/s, soit 3,5 lignes de jour par seconde : assez rapide pour
  /// couvrir un mois de 31 jours en 4,3 s, assez lent pour qu'on voie les
  /// cases se remplir.
  static const double vitesseDefilementMax = 400;

  final Widget child;

  /// Le geste est accepté. Appelée **avant** le premier point appliqué.
  final VoidCallback onDebut;

  /// Le doigt s'est levé, ou le geste a été interrompu sans annulation.
  final VoidCallback onFin;

  /// Un second doigt s'est posé, ou Échap a été frappé : tout ce que ce geste
  /// a posé doit reprendre sa valeur d'avant-geste.
  final VoidCallback onAnnulation;

  /// Faux quand il n'y a rien à peindre : mois verrouillé, caserne suspendue.
  /// Aucun reconnaisseur n'est alors installé.
  final bool actif;

  /// Vrai quand la pression seule suffit à démarrer (souris, stylet).
  final bool pointeurFin;

  /// Le défilant de la grille, pour le défilement automatique aux bords.
  final ScrollController? controleurDefilement;

  /// Largeur de la bande du bord gauche où une peinture ne peut pas démarrer.
  final double margeGaucheInerte;

  @override
  State<PeintureGrille> createState() => _PeintureGrilleState();
}

class _PeintureGrilleState extends State<PeintureGrille>
    with SingleTickerProviderStateMixin {
  // Créé dès initState, jamais paresseusement : un Ticker instancié pendant
  // dispose() irait chercher son TickerMode dans un arbre déjà démonté.
  late final Ticker _ticker;

  bool _enCours = false;

  /// Le nombre de contacts posés sur la grille. Une peinture ne démarre
  /// jamais à deux doigts — sinon un pincement annulerait la peinture en
  /// cours puis en ouvrirait aussitôt une autre.
  int _contacts = 0;

  /// Vrai quand le geste courant a été annulé : ses dernières mises à jour ne
  /// doivent plus rien peindre, et sa fin ne doit plus rien confirmer.
  bool _annule = false;

  Offset? _position;
  double _vitesse = 0;
  Duration _dernierTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_defiler);
  }

  @override
  void dispose() {
    _relacherClavier();
    if (_ticker.isActive) _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PeintureGrille oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Une bannière d'erreur, un verrouillage arrivé du serveur : le geste
    // s'arrête net, sans annuler ce qui est déjà peint.
    if (!widget.actif && _enCours) _terminer();
  }

  // -------------------------------------------------------------------
  // Cycle du geste
  // -------------------------------------------------------------------

  Drag? _demarrer(Offset global) {
    if (!widget.actif || _contacts > 1) return null;

    // Un second doigt pendant une peinture : annulation. C'est gratuit, parce
    // que rien n'est encore parti sur le réseau.
    if (_enCours) {
      _annuler();
      return null;
    }

    if (global.dx < widget.margeGaucheInerte) return null;

    _enCours = true;
    _annule = false;
    _position = global;
    _dernierTick = Duration.zero;
    _prendreClavier();
    widget.onDebut();
    _appliquer(global);
    _reglerVitesse(global);
    if (!_ticker.isActive) unawaited(_ticker.start());
    return _Pinceau(this);
  }

  void _glisser(Offset global) {
    if (!_enCours || _annule) return;

    final depart = _position ?? global;
    // Chaque point du segment est testé : un doigt rapide ne saute pas de
    // case, et un aller-retour reste inoffensif puisque repeindre la même
    // valeur ne fait rien.
    final distance = (global - depart).distance;
    final pas = (distance / PeintureGrille.pasEchantillonnage).ceil();
    for (var index = 1; index <= pas; index++) {
      _appliquer(Offset.lerp(depart, global, index / pas)!);
    }

    _position = global;
    _reglerVitesse(global);
  }

  void _terminer() {
    if (!_enCours) return;
    _arreter();
    if (_annule) return;
    widget.onFin();
  }

  void _annuler() {
    if (!_enCours || _annule) return;
    _annule = true;
    _arreter();
    widget.onAnnulation();
  }

  void _relacher() {
    if (_contacts > 0) _contacts--;
  }

  void _arreter() {
    _enCours = false;
    _vitesse = 0;
    _position = null;
    _relacherClavier();
    if (_ticker.isActive) _ticker.stop();
  }

  // -------------------------------------------------------------------
  // Échap
  // -------------------------------------------------------------------

  bool _ecouteClavier = false;

  /// Échap annule, comme le second doigt — la convention du bureau rejoint
  /// celle du doigt.
  ///
  /// L'écoute est posée sur le clavier matériel **le temps du geste**, et non
  /// sur un `Focus` : pendant une peinture, le focus est là où l'utilisateur
  /// l'a laissé, parfois nulle part, et une touche d'annulation qui ne marche
  /// qu'après un Tab ne serait pas une sortie.
  void _prendreClavier() {
    if (_ecouteClavier) return;
    _ecouteClavier = true;
    HardwareKeyboard.instance.addHandler(_toucheClavier);
  }

  void _relacherClavier() {
    if (!_ecouteClavier) return;
    _ecouteClavier = false;
    HardwareKeyboard.instance.removeHandler(_toucheClavier);
  }

  bool _toucheClavier(KeyEvent evenement) {
    if (!_enCours ||
        evenement is! KeyDownEvent ||
        evenement.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    _annuler();
    return true;
  }

  /// Applique la case qui se trouve sous [global], s'il y en a une.
  ///
  /// La case est reconnue à son `MetaData` porteur d'un [VoidCallback] : les
  /// cases inertes — hors du mois, mois verrouillé — n'en publient pas, et
  /// sont donc traversées sans effet.
  void _appliquer(Offset global) {
    final vue = View.maybeOf(context);
    if (vue == null) return;

    final resultat = HitTestResult();
    WidgetsBinding.instance.hitTestInView(resultat, global, vue.viewId);

    for (final entree in resultat.path) {
      final cible = entree.target;
      if (cible is RenderMetaData) {
        final rappel = cible.metaData;
        if (rappel is VoidCallback) {
          rappel();
          return;
        }
      }
    }
  }

  // -------------------------------------------------------------------
  // Défilement automatique aux bords
  // -------------------------------------------------------------------

  void _reglerVitesse(Offset global) {
    final boite = context.findRenderObject() as RenderBox?;
    if (boite == null ||
        !boite.hasSize ||
        widget.controleurDefilement == null) {
      _vitesse = 0;
      return;
    }

    final local = boite.globalToLocal(global);
    final hauteur = boite.size.height;
    const bande = PeintureGrille.bandeDefilement;
    const maximum = PeintureGrille.vitesseDefilementMax;

    if (local.dy < bande) {
      _vitesse = -maximum * ((bande - local.dy).clamp(0.0, bande) / bande);
    } else if (local.dy > hauteur - bande) {
      _vitesse =
          maximum * ((local.dy - (hauteur - bande)).clamp(0.0, bande) / bande);
    } else {
      _vitesse = 0;
    }
  }

  /// Le défilement automatique est **maintenu sous Reduce Motion** : ce n'est
  /// pas une décoration, c'est le déplacement du document sous le doigt.
  void _defiler(Duration horodatage) {
    final precedent = _dernierTick;
    _dernierTick = horodatage;
    if (_vitesse == 0 || precedent == Duration.zero) return;

    final controleur = widget.controleurDefilement;
    if (controleur == null || !controleur.hasClients) return;

    final secondes =
        (horodatage - precedent).inMicroseconds /
        Duration.microsecondsPerSecond;
    final position = controleur.position;
    final cible = (position.pixels + _vitesse * secondes).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (cible == position.pixels) return;

    position.jumpTo(cible);

    // Les cases qui passent sous le doigt pendant le défilement sont peintes.
    final point = _position;
    if (point != null) _appliquer(point);
  }

  // -------------------------------------------------------------------
  // Rendu
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // La sélection de texte est neutralisée sur la grille : sur le web, un
    // glissement surlignerait la moitié du mois en bleu système.
    final contenu = SelectionContainer.disabled(child: widget.child);

    if (!widget.actif) return contenu;

    return Listener(
      // **Le second doigt annule, dès qu'il touche.**
      //
      // Le reconnaisseur d'appui long ne rapporte un second contact qu'après
      // 300 ms d'immobilité : un vrai pincement, qui bouge tout de suite, ne
      // l'atteint jamais. On écoute donc le contact brut. Tant qu'une
      // peinture est en cours, le doigt qui l'a ouverte est encore posé :
      // tout nouveau contact est forcément un second doigt.
      onPointerDown: (_) {
        _contacts++;
        if (_enCours) _annuler();
      },
      onPointerUp: (_) => _relacher(),
      onPointerCancel: (_) => _relacher(),
      child: MouseRegion(
        cursor: _enCours ? SystemMouseCursors.cell : MouseCursor.defer,
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            DelayedMultiDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  DelayedMultiDragGestureRecognizer
                >(
                  () => DelayedMultiDragGestureRecognizer(
                    delay: PeintureGrille.delaiAppuiLong,
                    supportedDevices: const <PointerDeviceKind>{
                      PointerDeviceKind.touch,
                      PointerDeviceKind.unknown,
                    },
                    debugOwner: this,
                  ),
                  (instance) => instance.onStart = _demarrer,
                ),
            if (widget.pointeurFin)
              ImmediateMultiDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    ImmediateMultiDragGestureRecognizer
                  >(
                    () => ImmediateMultiDragGestureRecognizer(
                      supportedDevices: const <PointerDeviceKind>{
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.stylus,
                        PointerDeviceKind.invertedStylus,
                        PointerDeviceKind.trackpad,
                      },
                      debugOwner: this,
                    ),
                    (instance) => instance.onStart = _demarrer,
                  ),
          },
          child: contenu,
        ),
      ),
    );
  }
}

/// Le contact courant. Il ne décide de rien : il relaie.
class _Pinceau extends Drag {
  _Pinceau(this._grille);

  final _PeintureGrilleState _grille;

  @override
  void update(DragUpdateDetails details) =>
      _grille._glisser(details.globalPosition);

  @override
  void end(DragEndDetails details) => _grille._terminer();

  @override
  void cancel() => _grille._terminer();
}

/// La bande du bord gauche où une peinture ne peut pas démarrer.
///
/// `MediaQuery.systemGestureInsets` quand le système en déclare une, et au
/// minimum les 24 dp que `DESIGN.md § Zones sûres` réserve au geste retour
/// iOS.
double margeGesteRetour(BuildContext context) {
  final systeme = MediaQuery.maybeOf(context)?.systemGestureInsets.left ?? 0;
  return systeme > AppTouch.bandeGesteRetour
      ? systeme
      : AppTouch.bandeGesteRetour;
}
