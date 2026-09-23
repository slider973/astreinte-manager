import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/case_attribution.dart';
import '../../../../core/widgets/slot_chip.dart';
import '../../domain/cle_cellule.dart';
import '../../domain/creneau_planning.dart';
import '../../domain/ligne_matrice.dart';
import '../../domain/matrice_mois.dart';
import '../../domain/planning_mois.dart';
import 'entete_dates.dart';
import 'entete_ligne_membre.dart';
import 'fond_jour.dart';
import 'geometrie_matrice.dart';
import 'ligne_creneaux.dart';
import 'ligne_disponibles.dart';
import 'ruban_jours.dart';

/// **La matrice** : deux axes figés, un seul objet mobile.
///
/// La colonne des noms ne bouge jamais horizontalement, l'en-tête des dates ne
/// bouge jamais verticalement, et le coin où les deux se croisent ne bouge pas
/// du tout. Ce qui défile, c'est la feuille.
///
/// **Virtualisée sur les deux axes** (brief § 6.9) : un `ListView` construit
/// les lignes visibles, un [RubanJours] construit les journées visibles. Sur
/// un poste de 1 920 px, cela fait ~1 100 cases au lieu de 3 720 — et surtout,
/// le coût ne dépend plus de l'effectif de la caserne.
///
/// **Le bloc épinglé et la colonne figée sont hors du défilement.** C'est ce
/// qui garantit qu'une case focalisée au clavier ne peut jamais se cacher
/// dessous (WCAG 2.4.11) : la zone qui défile commence là où ils finissent.
///
/// Les quatre défilements sont liés deux à deux par [_lier] : un décalage d'un
/// seul pixel entre le nom et sa ligne rendrait l'écran faux.
class GrilleMatrice extends StatefulWidget {
  const GrilleMatrice({
    required this.matrice,
    required this.lignes,
    required this.annee,
    required this.mois,
    required this.commentaires,
    required this.aujourdhui,
    required this.erreurs,
    required this.saisieActive,
    required this.onCase,
    required this.planning,
    required this.creneauSelectionne,
    required this.onCreneau,
    super.key,
  });

  /// La matrice entière — c'est elle qui porte les comptes de disponibles,
  /// **hors filtres**.
  final MatriceMois matrice;

  /// Les lignes réellement affichées : filtrées et triées.
  final List<LigneMatrice> lignes;

  final int annee;
  final int mois;

  final bool commentaires;
  final DateTime aujourdhui;

  /// Les cases dont l'enregistrement a échoué.
  final Set<CleCellule> erreurs;

  /// Le mode armé **et** la densité dense actionnable dans ce contexte.
  final bool saisieActive;

  final ValueChanged<CleCellule> onCase;

  /// Le planning du mois. Sa ligne de créneaux s'insère dans le bloc épinglé
  /// **entre l'en-tête des dates et la ligne « Disponibles »** ; elle n'existe
  /// pas tant que le planning n'a pas été créé.
  final PlanningMois planning;

  /// L'identifiant du créneau ouvert dans le panneau, ou `null`.
  final String? creneauSelectionne;

  final ValueChanged<String> onCreneau;

  @override
  State<GrilleMatrice> createState() => _GrilleMatriceState();
}

class _GrilleMatriceState extends State<GrilleMatrice> {
  final ScrollController _hEntete = ScrollController();
  final ScrollController _hGrille = ScrollController();
  final ScrollController _vColonne = ScrollController();
  final ScrollController _vGrille = ScrollController();

  /// La première journée visible. Un `ValueNotifier` et non un `setState` :
  /// seules les lignes se reconstruisent au franchissement d'une journée, pas
  /// l'écran.
  final ValueNotifier<int> _fenetre = ValueNotifier<int>(0);

  /// Les commentaires dépliés, par identifiant de membre.
  final Set<String> _deplies = <String>{};

  bool _synchro = false;

  /// Les dates du mois, composées une fois : « samedi 4 octobre » revient
  /// dans la sémantique de chaque case, soixante fois par colonne.
  List<String> _libelles = const <String>[];
  int _libellesPour = 0;

  /// La table `(membre, jour, créneau) → attribution`, construite une fois par
  /// planning et non une recherche par case : à soixante membres et
  /// soixante-deux créneaux, un balayage linéaire par case ferait 3 720
  /// parcours de la liste des attributions à chaque image.
  Map<CleCellule, Attribution> _attributions = const <CleCellule, Attribution>{};
  PlanningMois? _attributionsPour;

  @override
  void initState() {
    super.initState();
    _lier(_hEntete, _hGrille);
    _lier(_hGrille, _hEntete);
    _lier(_vColonne, _vGrille);
    _lier(_vGrille, _vColonne);
    _hGrille.addListener(_suivreFenetre);
  }

  @override
  void dispose() {
    _hEntete.dispose();
    _hGrille.dispose();
    _vColonne.dispose();
    _vGrille.dispose();
    _fenetre.dispose();
    super.dispose();
  }

  /// Lie deux défilements : ce que l'un fait, l'autre le refait.
  ///
  /// Le garde-fou [_synchro] coupe l'aller-retour ; le seuil d'un demi-pixel
  /// évite un `jumpTo` pour un arrondi. Aucun paquet n'est ajouté pour ça :
  /// un lien de deux contrôleurs tient en douze lignes.
  void _lier(ScrollController source, ScrollController cible) {
    source.addListener(() {
      if (_synchro || !source.hasClients || !cible.hasClients) return;
      _synchro = true;
      final position = cible.position;
      final vise = source.offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((position.pixels - vise).abs() > 0.5) cible.jumpTo(vise);
      _synchro = false;
    });
  }

  void _suivreFenetre() {
    if (!_hGrille.hasClients) return;
    _fenetre.value = GeoMatrice.premierJourVisible(_hGrille.offset);
  }

  void _deplier(String userId) => setState(() {
    if (!_deplies.remove(userId)) _deplies.add(userId);
  });

  void _allerA(double cible) {
    if (!_hGrille.hasClients) return;
    _hGrille.jumpTo(
      cible.clamp(
        _hGrille.position.minScrollExtent,
        _hGrille.position.maxScrollExtent,
      ),
    );
  }

  double _hauteur(int index) => GeoMatrice.hauteurDe(
    widget.lignes[index],
    commentaires: widget.commentaires,
    deplie: _deplies.contains(widget.lignes[index].userId),
  );

  List<String> _libellesJours() {
    final clef = widget.annee * 100 + widget.mois;
    if (_libellesPour == clef) return _libelles;
    _libelles = <String>[
      for (var jour = 1; jour <= widget.matrice.nombreDeJours; jour++)
        dateAvecJourSemaine(DateTime(widget.annee, widget.mois, jour)),
    ];
    _libellesPour = clef;
    return _libelles;
  }

  /// Les attributions du mois, rangées par case.
  ///
  /// **Aucune lecture de plus** : tout est déjà en mémoire (`PlanningMois`),
  /// et la table se refait seulement quand le planning change d'objet — une
  /// attribution posée, retirée, ou reçue du temps réel.
  ///
  /// **La case suit le dépôt, elle ne le devance pas.** Seules les
  /// attributions actives — proposées et acceptées — occupent une case : ce
  /// sont les seules que le dépôt du planning lit, à la lecture comme en temps
  /// réel. Une astreinte refusée, remplacée ou annulée ne compte plus, et rien
  /// à l'écran ne doit laisser croire qu'elle tient encore la place.
  ///
  /// `CaseAttribution` sait dessiner le bloc rose du refus, et son contraste
  /// est mesuré : c'est un jeton du système, pas une promesse d'écran. Le jour
  /// où le dépôt rendra les refus, ce filtre s'allongera d'une ligne et le
  /// bloc s'allumera sans qu'une autre ligne bouge (chantier 061c-2).
  Map<CleCellule, Attribution> _tableAttributions() {
    if (identical(_attributionsPour, widget.planning)) return _attributions;

    final table = <CleCellule, Attribution>{};
    for (final attribution in widget.planning.attributions) {
      if (!_affichee(attribution.etat)) continue;
      final creneau = widget.planning.creneauParId(attribution.creneauId);
      if (creneau == null) continue;
      table[CleCellule(
        userId: attribution.userId,
        jour: creneau.jour,
        creneau: creneau.creneau,
      )] = attribution;
    }

    _attributions = table;
    _attributionsPour = widget.planning;
    return table;
  }

  static bool _affichee(AttributionEtat etat) => switch (etat) {
    AttributionEtat.propose || AttributionEtat.accepte => true,
    AttributionEtat.refuse ||
    AttributionEtat.remplace ||
    AttributionEtat.annule => false,
  };

  @override
  Widget build(BuildContext context) {
    final classe = AppWindowClass.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints contraintes) {
        final largeurFigee = math.min(
          GeoMatrice.colonneFigee(classe),
          contraintes.maxWidth / 2,
        );
        final largeurGrille = math.max(
          0.0,
          contraintes.maxWidth - largeurFigee - AppStroke.etat,
        );
        final visibles = GeoMatrice.joursVisibles(largeurGrille);

        // **Le bloc épinglé ne déborde jamais sa fenêtre, et ne disparaît
        // jamais non plus.** Sur un navigateur à demi hauteur, la grille peut
        // recevoir moins que ses 116 points d'en-tête : le bloc se resserre
        // alors jusqu'à la rangée de dates, son plancher, et la colonne
        // entière est rognée par le bas plutôt que de signaler un
        // débordement. Une grille sans ses dates ne se lit pas.
        final hauteurEpingle = math.max(
          GeoMatrice.hauteurEntete,
          math.min(
            GeoMatrice.hauteurBlocEpingle(avecCreneaux: widget.planning.existe),
            contraintes.maxHeight - AppStroke.etat - GeoMatrice.hauteurLigne,
          ),
        );

        /// Ce qu'il faut à la grille pour dire encore quelque chose : la
        /// rangée de dates et le filet qui la suit.
        const hauteurMinimale = GeoMatrice.hauteurEntete + AppStroke.etat;

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            // La colonne se construit sur son plancher quand la fenêtre est
            // plus courte, et le surplus est rogné : c'est un `RenderFlex`
            // qui n'a plus rien à signaler, pas un défaut caché.
            maxHeight: math.max(contraintes.maxHeight, hauteurMinimale),
            child: Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.home): _DebutDuMoisIntent(),
                SingleActivator(LogicalKeyboardKey.end): _FinDuMoisIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  _DebutDuMoisIntent: CallbackAction<_DebutDuMoisIntent>(
                    onInvoke: (_) {
                      _allerA(0);
                      return null;
                    },
                  ),
                  _FinDuMoisIntent: CallbackAction<_FinDuMoisIntent>(
                    onInvoke: (_) {
                      _allerA(double.infinity);
                      return null;
                    },
                  ),
                },
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: hauteurEpingle,
                      // Le bloc garde sa géométrie et se laisse rogner par le
                      // bas : le coin figé et l'en-tête des dates restent en
                      // face l'un de l'autre au pixel près, même quand la
                      // fenêtre ne leur donne pas leurs 116 points.
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          maxHeight: GeoMatrice.hauteurBlocEpingle(
                            avecCreneaux: widget.planning.existe,
                          ),
                          child: Row(
                            children: <Widget>[
                              CoinFige(
                                largeur: largeurFigee,
                                avecCreneaux: widget.planning.existe,
                              ),
                              const AppDivider.colonneFigee(),
                              Expanded(child: _entete(visibles)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const AppDivider.enTete(),
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: largeurFigee,
                            child: _colonneFigee(largeurFigee),
                          ),
                          const AppDivider.colonneFigee(),
                          Expanded(child: _corps(visibles)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Le bloc épinglé : les dates, la ligne des créneaux à pourvoir, puis la
  /// ligne « Disponibles ».
  ///
  /// Les deux lignes se suivent et ne se confondent pas : la première porte
  /// une **fraction** (« 0/1 »), la seconde un **chiffre nu** (« 4 »). La
  /// marque distingue avant la couleur (`design/017 § 3`).
  Widget _entete(int visibles) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _hEntete,
      physics: const ClampingScrollPhysics(),
      child: RubanJours(
        fenetre: _fenetre,
        nombreDeJours: widget.matrice.nombreDeJours,
        joursVisibles: visibles,
        construire: (BuildContext context, int jour) {
          final date = DateTime(widget.annee, widget.mois, jour);
          return FondJour(
            date: date,
            aujourdhui: widget.aujourdhui,
            child: Column(
              children: <Widget>[
                EnteteJour(date: date, aujourdhui: widget.aujourdhui),
                if (widget.planning.existe)
                  CasesCreneaux(
                    planning: widget.planning,
                    jour: jour,
                    date: date,
                    selectionne: widget.creneauSelectionne,
                    onCreneau: widget.onCreneau,
                  ),
                CasesDisponibles(
                  matrice: widget.matrice,
                  jour: jour,
                  date: date,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _colonneFigee(double largeur) {
    return ListView.builder(
      controller: _vColonne,
      physics: const ClampingScrollPhysics(),
      itemCount: widget.lignes.length,
      itemExtentBuilder: (int index, SliverLayoutDimensions _) =>
          _hauteur(index),
      itemBuilder: (BuildContext context, int index) {
        final ligne = widget.lignes[index];
        return EnteteLigneMembre(
          key: ValueKey<String>('entete-${ligne.userId}'),
          ligne: ligne,
          largeur: largeur,
          commentaires: widget.commentaires,
          deplie: _deplies.contains(ligne.userId),
          onDeplier: () => _deplier(ligne.userId),
        );
      },
    );
  }

  Widget _corps(int visibles) {
    final libelles = _libellesJours();
    final attributions = _tableAttributions();

    return Scrollbar(
      controller: _hGrille,
      // Sur macOS, une barre qui s'efface au repos transforme un défilement de
      // deux mille pixels en découverte par accident.
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _hGrille,
        physics: const ClampingScrollPhysics(),
        child: SizedBox(
          width: GeoMatrice.largeurTotale(widget.matrice.nombreDeJours),
          child: Scrollbar(
            controller: _vGrille,
            child: ListView.builder(
              controller: _vGrille,
              physics: const ClampingScrollPhysics(),
              itemCount: widget.lignes.length,
              itemExtentBuilder: (int index, SliverLayoutDimensions _) =>
                  _hauteur(index),
              itemBuilder: (BuildContext context, int index) => RubanJours(
                key: ValueKey<String>(widget.lignes[index].userId),
                fenetre: _fenetre,
                nombreDeJours: widget.matrice.nombreDeJours,
                joursVisibles: visibles,
                construire: (BuildContext context, int jour) => _cellules(
                  ligne: widget.lignes[index],
                  jour: jour,
                  libelle: libelles[jour - 1],
                  attributions: attributions,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cellules({
    required LigneMatrice ligne,
    required int jour,
    required String libelle,
    required Map<CleCellule, Attribution> attributions,
  }) {
    final date = DateTime(widget.annee, widget.mois, jour);
    return FondJour(
      date: date,
      aujourdhui: widget.aujourdhui,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _case(ligne, jour, CreneauType.jour, libelle, attributions),
              const SizedBox(width: GeoMatrice.ecartCreneaux),
              _case(ligne, jour, CreneauType.nuit, libelle, attributions),
            ],
          ),
        ),
      ),
    );
  }

  Widget _case(
    LigneMatrice ligne,
    int jour,
    CreneauType creneau,
    String libelle,
    Map<CleCellule, Attribution> attributions,
  ) {
    final statuts = context.statuts;
    final cellule = ligne.cellule(jour, creneau);
    final cle = CleCellule(userId: ligne.userId, jour: jour, creneau: creneau);
    final suivant = CelluleMatrice.suivant(cellule.etat);

    // **L'attribution passe devant la déclaration.** Un membre posé sur un
    // créneau se lit dans sa propre ligne, et non seulement dans la fraction
    // du bloc épinglé ou dans le panneau : c'est ce que la référence du
    // propriétaire montre d'un coup d'œil. La disponibilité déclarée n'est pas
    // perdue — elle est dite entre parenthèses dans la sémantique.
    final attribution = attributions[cle];
    if (attribution != null) {
      return CaseAttribution(
        etat: attribution.etat,
        erreur: widget.erreurs.contains(cle),
        libelleSemantique: AppStrings.matriceCaseAttributionSemantique(
          membre: ligne.nomAffiche,
          jourEtDate: libelle,
          creneau: statuts.creneau(creneau).libelle,
          etat: statuts.attribution(attribution.etat).libelle,
          disponibilite: statuts.disponibilite(cellule.etat).libelle,
        ),
        // **Le mode de saisie garde la main.** Armé, l'appui cycle la
        // disponibilité comme partout ailleurs et le bloc reste affiché ;
        // au repos, il ouvre le créneau, exactement comme la ligne des
        // créneaux au-dessus de la même colonne.
        actionSemantique: widget.saisieActive
            ? AppStrings.matriceCaseAction(
                statuts.disponibilite(suivant).libelle,
              )
            : AppStrings.planningCouvertureAction,
        onTap: widget.saisieActive
            ? () => widget.onCase(cle)
            : () => widget.onCreneau(attribution.creneauId),
      );
    }

    return SlotChip(
      densite: SlotChipDensite.dense,
      etat: cellule.etat,
      creneau: creneau,
      saisiParAdmin: cellule.parAdmin,
      erreur: widget.erreurs.contains(cle),
      libelleSemantique: AppStrings.matriceCaseSemantique(
        membre: ligne.nomAffiche,
        jourEtDate: libelle,
        creneau: statuts.creneau(creneau).libelle,
        etat: statuts.disponibilite(cellule.etat).libelle,
      ),
      actionSemantique: widget.saisieActive
          ? AppStrings.matriceCaseAction(statuts.disponibilite(suivant).libelle)
          : null,
      onTap: widget.saisieActive ? () => widget.onCase(cle) : null,
    );
  }
}

class _DebutDuMoisIntent extends Intent {
  const _DebutDuMoisIntent();
}

class _FinDuMoisIntent extends Intent {
  const _FinDuMoisIntent();
}
