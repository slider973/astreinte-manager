import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/reseau/connectivite.dart';
import '../../../../core/session/session_providers.dart';
import '../../../../core/theme/app_status.dart';
import '../../data/dispos_repository.dart';
import '../../data/file_locale.dart';
import '../../domain/creneau_cle.dart';
import '../../domain/disponibilite_mois.dart';
import '../../domain/dispos_providers.dart';
import '../../domain/periode_saisie.dart';
import '../../domain/preferences_mois.dart';
import '../../domain/raccourci.dart';

/// Ce que la ligne d'un jour a besoin de savoir, et **rien d'autre**.
///
/// C'est la tranche d'état qu'une ligne observe (`select`) : le mouvement du
/// doigt sur le 14 ne reconstruit pas les soixante et une autres cases.
@immutable
class EtatJour {
  const EtatJour({
    required this.jour,
    required this.nuit,
    required this.erreurJour,
    required this.erreurNuit,
    required this.verrouille,
    this.origineJour = false,
    this.origineNuit = false,
  });

  static const EtatJour vide = EtatJour(
    jour: DisponibiliteEtat.nonSaisi,
    nuit: DisponibiliteEtat.nonSaisi,
    erreurJour: false,
    erreurNuit: false,
    verrouille: true,
  );

  final DisponibiliteEtat jour;
  final DisponibiliteEtat nuit;
  final bool erreurJour;
  final bool erreurNuit;
  final bool verrouille;

  /// Case d'où part la peinture en cours : contour 2 dp `primary`. C'est
  /// elle qui annonce, au moment exact où le geste devient disponible, que
  /// le doigt a pris la case.
  final bool origineJour;
  final bool origineNuit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EtatJour &&
          other.jour == jour &&
          other.nuit == nuit &&
          other.erreurJour == erreurJour &&
          other.erreurNuit == erreurNuit &&
          other.verrouille == verrouille &&
          other.origineJour == origineJour &&
          other.origineNuit == origineNuit;

  @override
  int get hashCode => Object.hash(
    jour,
    nuit,
    erreurJour,
    erreurNuit,
    verrouille,
    origineJour,
    origineNuit,
  );
}

/// L'état complet de l'écran « Mon mois ».
@immutable
class EtatSaisie {
  const EtatSaisie({
    required this.periode,
    required this.mois,
    this.enErreur = const <CreneauCle>{},
    this.sync = SyncEtat.repos,
    this.pinceau,
    this.origine,
    this.casesPeintes = 0,
    this.horsLigne = false,
    this.lectureSeule = false,
    this.refusServeur,
    this.echecPersistant = false,
    this.filePerimee = false,
    this.annonce,
    this.dernierRaccourci,
    this.raccourciEnCours,
    this.messageRaccourci,
    this.preferences = const EtatPreferences(),
  });

  final PeriodeSaisie periode;

  /// Ce que l'écran affiche. Optimiste : c'est la valeur que l'utilisateur
  /// vient de poser, jamais celle du serveur en attente.
  final DisponibiliteMois mois;

  /// Les cases dont l'écriture a échoué : contour 2 dp `error`, et elles
  /// seules.
  final Set<CreneauCle> enErreur;

  final SyncEtat sync;

  /// Non nul pendant une peinture : la valeur en cours de pose.
  final DisponibiliteEtat? pinceau;

  /// La case d'où part la peinture en cours.
  final CreneauCle? origine;

  /// Le nombre de cases que le geste courant a changées.
  final int casesPeintes;

  final bool horsLigne;

  /// Vrai quand le serveur a refusé une écriture pour une raison autre que le
  /// verrouillage du mois : caserne suspendue.
  final bool lectureSeule;

  /// La phrase du refus serveur, avec son bouton « Recharger ».
  final String? refusServeur;

  /// La relance automatique a échoué à son tour : la bannière apparaît.
  final bool echecPersistant;

  /// Des écritures gardées sur l'appareil visaient un mois qui s'est
  /// verrouillé entre-temps : elles ont été abandonnées, et il faut le dire.
  final bool filePerimee;

  /// La dernière phrase à annoncer sans déplacer le focus.
  final String? annonce;

  /// Le dernier raccourci appliqué, tant qu'il est annulable.
  ///
  /// Non nul veut dire exactement une chose : **la ligne de résultat et son
  /// bouton « Annuler » sont à l'écran**. La première retouche à la main le
  /// remet à `null` — l'utilisateur est passé à autre chose, et une annulation
  /// qui emporterait sa retouche serait pire que pas d'annulation du tout.
  final RaccourciApplique? dernierRaccourci;

  /// La portée dont la lecture du mois précédent est en vol. Le bouton garde
  /// son libellé et sa largeur, un indicateur de 20 dp prend la place de son
  /// icône.
  final PorteeRaccourci? raccourciEnCours;

  /// Ce qu'un raccourci a à dire quand il n'a rien changé, ou qu'il n'a pas
  /// pu : « Rien à changer », « Impossible de lire le mois précédent ».
  ///
  /// Visible à l'écran, à la place de la ligne de résultat. Une annonce
  /// `Semantics` seule laisserait un voyant devant un bouton muet.
  final String? messageRaccourci;

  /// **Ce que le membre veut faire ce mois-ci**, à côté de ce qu'il peut
  /// faire. La moitié du produit qui manquait (ticket 013).
  final EtatPreferences preferences;

  bool get enPeinture => pinceau != null;

  /// Vrai quand la grille accepte une saisie.
  bool get modifiable => periode.ouverte && !lectureSeule;

  /// L'état affiché d'une case.
  DisponibiliteEtat etat(CreneauCle cle) => mois.etat(cle);

  CompteursMois get compteurs => mois.compteurs;

  /// La tranche d'état d'un jour.
  EtatJour pourJour(DateTime date) {
    final jour = CreneauCle(date, CreneauType.jour);
    final nuit = CreneauCle(date, CreneauType.nuit);
    return EtatJour(
      jour: mois.etat(jour),
      nuit: mois.etat(nuit),
      erreurJour: enErreur.contains(jour),
      erreurNuit: enErreur.contains(nuit),
      verrouille: !modifiable,
      origineJour: origine == jour,
      origineNuit: origine == nuit,
    );
  }

  EtatSaisie copyWith({
    PeriodeSaisie? periode,
    DisponibiliteMois? mois,
    Set<CreneauCle>? enErreur,
    SyncEtat? sync,
    DisponibiliteEtat? Function()? pinceau,
    CreneauCle? Function()? origine,
    int? casesPeintes,
    bool? horsLigne,
    bool? lectureSeule,
    String? Function()? refusServeur,
    bool? echecPersistant,
    bool? filePerimee,
    String? Function()? annonce,
    RaccourciApplique? Function()? dernierRaccourci,
    PorteeRaccourci? Function()? raccourciEnCours,
    String? Function()? messageRaccourci,
    EtatPreferences? preferences,
  }) => EtatSaisie(
    periode: periode ?? this.periode,
    mois: mois ?? this.mois,
    enErreur: enErreur ?? this.enErreur,
    sync: sync ?? this.sync,
    pinceau: pinceau == null ? this.pinceau : pinceau(),
    origine: origine == null ? this.origine : origine(),
    casesPeintes: casesPeintes ?? this.casesPeintes,
    horsLigne: horsLigne ?? this.horsLigne,
    lectureSeule: lectureSeule ?? this.lectureSeule,
    refusServeur: refusServeur == null ? this.refusServeur : refusServeur(),
    echecPersistant: echecPersistant ?? this.echecPersistant,
    filePerimee: filePerimee ?? this.filePerimee,
    annonce: annonce == null ? this.annonce : annonce(),
    dernierRaccourci: dernierRaccourci == null
        ? this.dernierRaccourci
        : dernierRaccourci(),
    raccourciEnCours: raccourciEnCours == null
        ? this.raccourciEnCours
        : raccourciEnCours(),
    messageRaccourci: messageRaccourci == null
        ? this.messageRaccourci
        : messageRaccourci(),
    preferences: preferences ?? this.preferences,
  );
}

/// **Le contrôleur de la saisie** : le cycle, la peinture, la file.
///
/// Deux invariants tiennent tout le reste :
///
/// 1. **Rien ne part sur le réseau pendant un geste.** Le délai de 500 ms ne
///    démarre qu'au relâchement. C'est ce qui rend l'annulation gratuite, et
///    c'est ce qui fait qu'un mois peint est **une** transition d'indicateur
///    au lieu de quarante.
/// 2. **La file est une `Map<CreneauCle, …>`**, donc coalescée par
///    construction : la dernière valeur d'une case gagne, et quarante touches
///    sur la même case ne produisent qu'une ligne. Elle part en **deux
///    requêtes au plus** — un envoi groupé, une suppression groupée.
/// 3. **Il n'y a qu'un chemin d'écriture** : `_poser`. La touche, la peinture,
///    les raccourcis du ticket 012 et leur annulation y descendent tous. Un
///    raccourci de soixante-deux cases n'est donc pas un cas particulier du
///    réseau : c'est une seule `_poser` de soixante-deux entrées, qui paie le
///    même délai et les mêmes deux requêtes qu'une case unique.
class SaisieController extends AsyncNotifier<EtatSaisie?> {
  /// Le calme après lequel la file part.
  static const Duration delaiEnvoi = Duration(milliseconds: 500);

  /// Une relance automatique à 1 s, une à 4 s, puis on s'arrête et on attend
  /// l'humain ou le retour du réseau.
  static const List<Duration> relances = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 4),
  ];

  /// Le dernier état connu du serveur. C'est lui qui dit si une case revenue
  /// à « non saisi » a une ligne à supprimer, ou n'en a jamais eu.
  Map<CreneauCle, DisponibiliteEtat> _serveur =
      <CreneauCle, DisponibiliteEtat>{};

  /// La file d'écriture : une entrée par case, la dernière valeur gagne.
  final Map<CreneauCle, DisponibiliteEtat> _file =
      <CreneauCle, DisponibiliteEtat>{};

  /// Les valeurs d'**avant** le dernier raccourci, pour les seules cases
  /// qu'il a changées. C'est tout ce que coûte l'annulation : une carte d'au
  /// plus soixante-deux entrées, rejouée par le même chemin d'écriture.
  Map<CreneauCle, DisponibiliteEtat>? _annulationRaccourci;

  /// Les mois dont une tranche de file est **gardée sur l'appareil**.
  /// Sert à oublier une tranche dès qu'elle est confirmée par le serveur.
  Set<String> _moisPersistes = <String>{};

  /// Les préférences de charge en attente d'écriture, par `period_id`.
  ///
  /// **Même file, même délai, même indicateur que les cases** : un maximum
  /// posé et dix cases peintes dans la même seconde partent ensemble, et
  /// l'écran ne dit qu'une fois « Enregistrement… ».
  final Map<String, PreferencesMois> _preferencesEnAttente =
      <String, PreferencesMois>{};

  /// Les périodes dont une préférence est gardée sur l'appareil.
  Set<String> _preferencesPersistees = <String>{};

  Timer? _minuteur;
  bool _envoiEnCours = false;
  int _relance = 0;

  /// La caserne est passée en lecture seule pendant la session. Gardé hors de
  /// l'état parce qu'il doit survivre à un rechargement : sans lui, chaque
  /// `recharger()` retenterait d'écrire la reprise et récolterait le même
  /// refus.
  bool _lectureSeuleConnue = false;

  bool _gesteActif = false;
  DisponibiliteMois? _moisAvantGeste;
  Map<CreneauCle, DisponibiliteEtat>? _fileAvantGeste;

  String? _stationId;
  String? _userId;

  @override
  Future<EtatSaisie?> build() async {
    ref.onDispose(() {
      _minuteur?.cancel();
      _minuteur = null;
    });

    // Le retour du réseau rejoue la file tout seul.
    ref.listen<AsyncValue<bool>>(enLigneProvider, (_, suivant) {
      final enLigne = suivant.value;
      if (enLigne == null) return;
      _appliquerReseau(enLigne: enLigne);
    });

    final appartenance = ref.watch(appartenanceCouranteProvider);
    final session = ref.watch(sessionProvider).value;
    final periodes =
        ref.watch(periodesProvider).value ?? const <PeriodeSaisie>[];
    final periode = ref.watch(periodeCouranteProvider);
    if (appartenance == null || session == null || periode == null) return null;

    // Un changement de caserne ou d'utilisateur invalide tout : la file
    // contient les créneaux d'un autre registre. Un changement de **mois**,
    // lui, n'invalide rien — chaque clé porte sa date, et le dépôt écrit
    // indifféremment des créneaux de plusieurs mois dans le même lot.
    final autreCompte =
        (_stationId != null && _stationId != appartenance.stationId) ||
        (_userId != null && _userId != session.userId);
    final premiereOuverture = _stationId == null;

    // L'annulation ne traverse ni un changement de mois, ni un rechargement :
    // elle porte sur des cases d'un registre qui n'est plus à l'écran.
    _annulationRaccourci = null;

    if (autreCompte) {
      _file.clear();
      _serveur.clear();
      _moisPersistes.clear();
      _preferencesEnAttente.clear();
      _preferencesPersistees.clear();
      _lectureSeuleConnue = false;
    }
    _stationId = appartenance.stationId;
    _userId = session.userId;

    // Ce que l'appareil a gardé d'une session précédente. La mémoire vive
    // prime : elle est forcément plus récente que le disque.
    if (premiereOuverture || autreCompte) {
      final gardee = await ref
          .read(fileLocaleProvider)
          .lire(stationId: appartenance.stationId, userId: session.userId);
      for (final entree in gardee.entries) {
        _file.putIfAbsent(entree.key, () => entree.value);
      }
      _moisPersistes = await ref
          .read(fileLocaleProvider)
          .moisEnAttente(
            stationId: appartenance.stationId,
            userId: session.userId,
          );

      final prefsGardees = await ref
          .read(fileLocaleProvider)
          .lirePreferences(
            stationId: appartenance.stationId,
            userId: session.userId,
          );
      for (final entree in prefsGardees.entries) {
        _preferencesEnAttente.putIfAbsent(entree.key, () => entree.value);
      }
      _preferencesPersistees = prefsGardees.keys.toSet();
    }

    // Une file gardée peut viser un mois qui s'est verrouillé entre-temps —
    // le cron `lock_periods` tourne toutes les heures. La rejouer ne ferait
    // que collectionner des refus : on l'abandonne, et on le dit.
    final ouverts = <String>{
      for (final ouverte in periodes)
        if (ouverte.ouverte) ouverte.cle,
    };
    var perimee = false;
    _file.removeWhere((cle, _) {
      final abandonnee = !ouverts.contains(cle.cleMois);
      perimee = perimee || abandonnee;
      return abandonnee;
    });
    // Un maximum posé sur un mois qui s'est verrouillé depuis subit le même
    // sort, et pour la même raison : le rejouer ne collectionnerait que des
    // refus.
    final periodesOuvertes = <String>{
      for (final ouverte in periodes)
        if (ouverte.ouverte) ouverte.id,
    };
    _preferencesEnAttente.removeWhere((id, _) {
      final abandonnee = !periodesOuvertes.contains(id);
      perimee = perimee || abandonnee;
      return abandonnee;
    });
    if (perimee) unawaited(_persister());

    final lues = await ref
        .read(disposRepositoryProvider)
        .lireMois(
          stationId: appartenance.stationId,
          userId: session.userId,
          annee: periode.annee,
          mois: periode.mois,
        );

    // Le mois lu fait autorité pour ses propres créneaux ; on garde de ce
    // qu'on savait des autres mois les seules clés encore en attente, parce
    // que c'est cet état-là qui dit si un « non saisi » a une ligne à
    // supprimer ou n'en a jamais eu.
    _serveur = <CreneauCle, DisponibiliteEtat>{
      for (final connu in _serveur.entries)
        if (_file.containsKey(connu.key) && connu.key.cleMois != periode.cle)
          connu.key: connu.value,
      ...lues,
    };
    _relance = 0;

    final horsLigne = !ref.read(connectiviteProvider).enLigne;

    final preferences = await _chargerPreferences(
      stationId: appartenance.stationId,
      userId: session.userId,
      periode: periode,
      periodes: periodes,
    );

    // Une file héritée d'un autre mois, d'une session précédente ou d'un
    // envoi échoué ne dort pas : elle repart d'elle-même. Une préférence en
    // attente non plus — y compris celle que la reprise vient de poser.
    if (_file.isNotEmpty || _preferencesEnAttente.isNotEmpty) _planifier();

    final enAttente = _file.isNotEmpty || _preferencesEnAttente.isNotEmpty;

    return EtatSaisie(
      periode: periode,
      // La file en attente prime sur ce que le serveur vient de rendre : elle
      // porte ce que l'utilisateur a voulu et que la base n'a pas encore.
      mois: DisponibiliteMois(
        annee: periode.annee,
        mois: periode.mois,
        valeurs: <CreneauCle, DisponibiliteEtat>{...lues, ..._file},
      ),
      sync: !enAttente
          ? SyncEtat.repos
          : horsLigne
          ? SyncEtat.horsLigne
          : SyncEtat.enregistrement,
      horsLigne: horsLigne,
      filePerimee: perimee,
      preferences: preferences,
    );
  }

  /// Lit les préférences du mois affiché **et de son précédent**, en une
  /// requête, puis applique la règle de reprise du `PRD § 6.3`.
  ///
  /// Trois cas, et trois seulement :
  ///
  /// 1. une ligne existe pour ce mois → elle fait foi ;
  /// 2. pas de ligne, le mois précédent en a une, le mois est modifiable →
  ///    les valeurs sont reprises, **écrites par la file ordinaire**, et
  ///    annoncées à l'écran. Sans l'écriture, le membre verrait « 1 weekend »
  ///    et l'admin ne verrait rien : deux vérités pour le même mois, et c'est
  ///    celle de l'admin qui construit le planning ;
  /// 3. sinon → autant que nécessaire, et **aucune ligne écrite**.
  Future<EtatPreferences> _chargerPreferences({
    required String stationId,
    required String userId,
    required PeriodeSaisie periode,
    required List<PeriodeSaisie> periodes,
  }) async {
    final veille = DateTime(periode.annee, periode.mois - 1);
    final clePrecedente = PeriodeSaisie.cleDe(veille.year, veille.month);
    PeriodeSaisie? precedente;
    for (final candidate in periodes) {
      if (candidate.cle == clePrecedente) precedente = candidate;
    }

    Map<String, PreferencesMois> lues;
    try {
      lues = await ref
          .read(disposRepositoryProvider)
          .lirePreferences(
            stationId: stationId,
            userId: userId,
            periodIds: <String>[
              periode.id,
              if (precedente != null) precedente.id,
            ],
          );
    } on Object {
      // Injoignable : on n'invente ni reprise ni valeur. La grille, elle, a
      // déjà été lue ; perdre l'écran entier pour un quota serait pire.
      lues = const <String, PreferencesMois>{};
    }

    // Une préférence gardée sur l'appareil prime sur ce que le serveur rend :
    // elle porte ce que le membre a voulu et que la base n'a pas encore.
    final enAttente = _preferencesEnAttente[periode.id];
    if (enAttente != null) {
      return EtatPreferences(
        valeurs: enAttente,
        ligneAuChargement: lues.containsKey(periode.id),
      );
    }

    final existante = lues[periode.id];
    if (existante != null) {
      return EtatPreferences(valeurs: existante, ligneAuChargement: true);
    }

    final heritee = precedente == null ? null : lues[precedente.id];
    // Une reprise est une écriture que le membre n'a pas demandée : on ne la
    // déclenche que si elle porte une information. Une ligne à « sans limite »
    // et sans commentaire n'apprend rien à l'admin du ticket 016 et ne vaut pas
    // une écriture non sollicitée.
    if (heritee == null ||
        heritee.vide ||
        !periode.ouverte ||
        _lectureSeuleConnue) {
      return const EtatPreferences();
    }

    _preferencesEnAttente[periode.id] = heritee;
    return EtatPreferences(valeurs: heritee, repriseDe: precedente!.mois);
  }

  /// L'état courant, ou `null` si le provider a été disposé entre-temps.
  ///
  /// Toute reprise après un `await` passe par là : une requête peut revenir
  /// alors que l'écran est fermé ou que le mois a changé, et écrire dans un
  /// `state` démonté est une erreur de programmation, pas un cas limite.
  EtatSaisie? get _etat => ref.mounted ? state.value : null;

  void _publier(EtatSaisie etat) {
    if (!ref.mounted) return;
    state = AsyncValue<EtatSaisie?>.data(etat);
  }

  // -------------------------------------------------------------------
  // La touche
  // -------------------------------------------------------------------

  /// Fait avancer une case d'un cran :
  /// `non saisi → disponible → absent → non saisi`.
  void basculer(CreneauCle cle) {
    final etat = _etat;
    if (etat == null || !etat.modifiable) return;
    _poser(<CreneauCle, DisponibiliteEtat>{cle: cranSuivant(etat.etat(cle))});
    _planifier();
  }

  // -------------------------------------------------------------------
  // La peinture
  // -------------------------------------------------------------------

  /// Le geste est accepté. L'instantané d'avant-geste est pris ici, et c'est
  /// ce qui rend l'annulation exacte.
  void debutGeste() {
    final etat = _etat;
    if (etat == null || !etat.modifiable || _gesteActif) return;

    // **Le minuteur déjà armé est désarmé ici.** Sans cela, une relance
    // programmée à une seconde, ou le délai d'une touche simple faite deux
    // cents millisecondes plus tôt, partiraient au beau milieu du geste : la
    // base garderait des cases que l'annulation vient d'effacer de l'écran.
    _minuteur?.cancel();
    _minuteur = null;

    _gesteActif = true;
    _moisAvantGeste = etat.mois;
    _fileAvantGeste = Map<CreneauCle, DisponibiliteEtat>.of(_file);
    _publier(etat.copyWith(casesPeintes: 0, annonce: () => null));
  }

  /// Une case passe sous le doigt.
  ///
  /// La **première** avance d'un cran et devient le pinceau ; toutes les
  /// suivantes sont **mises** à la valeur du pinceau, jamais cyclées. C'est ce
  /// qui rend un aller-retour inoffensif.
  void toucherPendantGeste(CreneauCle cle) {
    final etat = _etat;
    if (etat == null || !etat.modifiable || !_gesteActif) return;

    final premiere = etat.pinceau == null;
    final pinceau = etat.pinceau ?? cranSuivant(etat.etat(cle));
    if (!premiere && etat.etat(cle) == pinceau) return;

    _poser(
      <CreneauCle, DisponibiliteEtat>{cle: pinceau},
      pinceau: pinceau,
      origine: premiere ? cle : null,
      casesPeintes: etat.casesPeintes + 1,
    );
  }

  /// Le doigt se lève : les valeurs peintes sont confirmées et le délai part.
  void finGeste() {
    final etat = _etat;
    _gesteActif = false;
    _moisAvantGeste = null;
    _fileAvantGeste = null;
    if (etat == null) return;

    final pinceau = etat.pinceau;
    _publier(
      etat.copyWith(
        pinceau: () => null,
        origine: () => null,
        annonce: () => pinceau == null || etat.casesPeintes == 0
            ? null
            : AppStrings.peintureResultat(
                etat.casesPeintes,
                ref.read(statutsDisponibiliteProvider)(pinceau),
              ),
      ),
    );
    _planifier();
  }

  /// Un second doigt, ou Échap : tout ce que ce geste a posé reprend sa
  /// valeur d'avant-geste, case d'origine comprise.
  void annulerGeste() {
    final etat = _etat;
    final avant = _moisAvantGeste;
    final fileAvant = _fileAvantGeste;
    _gesteActif = false;
    _moisAvantGeste = null;
    _fileAvantGeste = null;
    if (etat == null || avant == null || fileAvant == null) return;

    _file
      ..clear()
      ..addAll(fileAvant);

    _publier(
      etat.copyWith(
        mois: avant,
        pinceau: () => null,
        origine: () => null,
        casesPeintes: 0,
        sync: _file.isEmpty && etat.sync == SyncEtat.enregistrement
            ? SyncEtat.repos
            : etat.sync,
        annonce: () => AppStrings.peintureAnnulee,
      ),
    );

    // Le geste a désarmé le minuteur en s'ouvrant : ce qui attendait
    // **avant** lui doit repartir, sinon une annulation emporterait une
    // saisie qui n'avait rien à voir avec elle.
    _planifier();
  }

  // -------------------------------------------------------------------
  // Les raccourcis
  // -------------------------------------------------------------------

  /// Applique un raccourci : `portee` × `cible`.
  ///
  /// **Aucun chemin d'écriture nouveau.** Le lot calculé descend dans le même
  /// `_poser` qu'une touche unique, donc dans la même file coalescée : les
  /// soixante-deux modifications d'un « tout le mois, jour et nuit » forment
  /// **une** entrée par case dans une `Map`, partent après le même délai de
  /// 500 ms, et coûtent **une requête par type d'opération** — un envoi
  /// groupé, une suppression groupée.
  ///
  /// La seule lecture supplémentaire du ticket est celle du mois précédent,
  /// et elle n'a lieu que pour [PorteeRaccourci.copieMoisPrecedent].
  Future<void> appliquerRaccourci(
    PorteeRaccourci portee,
    CibleCreneau cible,
  ) async {
    final etat = _etat;
    // Une période verrouillée, une caserne suspendue : le raccourci est aussi
    // inerte que les cases. Le bouton est déjà désactivé à l'écran ; ce garde
    // est là pour l'appel qui arriverait par un autre chemin.
    if (etat == null || !etat.modifiable) return;
    if (etat.raccourciEnCours != null) return;

    var moisPrecedent = const <CreneauCle, DisponibiliteEtat>{};
    if (portee.litLeMoisPrecedent) {
      final lu = await _lireMoisPrecedent(portee);
      if (lu == null) return;
      moisPrecedent = lu;
    }

    final courant = _etat;
    if (courant == null || !courant.modifiable) return;

    final modifications = modificationsRaccourci(
      periode: courant.periode,
      portee: portee,
      cible: cible,
      courant: courant.mois,
      moisPrecedent: moisPrecedent,
    );

    // Rien à changer : pas de file, pas de requête, pas d'annulation à
    // proposer — mais une phrase, parce qu'un bouton qui ne fait rien sans le
    // dire passe pour cassé.
    if (modifications.isEmpty) {
      _publier(
        courant.copyWith(
          raccourciEnCours: () => null,
          dernierRaccourci: () => null,
          messageRaccourci: () => AppStrings.raccourciAucunChangement,
          annonce: () => AppStrings.raccourciAucunChangement,
        ),
      );
      _annulationRaccourci = null;
      return;
    }

    final avant = <CreneauCle, DisponibiliteEtat>{
      for (final cle in modifications.keys) cle: courant.etat(cle),
    };

    _poser(
      modifications,
      raccourci: RaccourciApplique(
        portee: portee,
        cible: cible,
        cases: modifications.length,
      ),
      annonce: AppStrings.raccourciResultatSemantique(
        portee.libelle,
        modifications.length,
      ),
    );
    _annulationRaccourci = avant;
    _planifier();
  }

  /// Remet les cases du dernier raccourci dans l'état exact d'avant.
  ///
  /// Ce n'est pas un historique : **un seul cran**, celui du dernier
  /// raccourci, et il tombe dès qu'une case est touchée à la main. Les
  /// anciennes valeurs repartent par la file ordinaire — l'annulation coûte
  /// donc le même prix que le raccourci, y compris quand il est déjà arrivé
  /// en base.
  void annulerRaccourci() {
    final etat = _etat;
    final avant = _annulationRaccourci;
    if (etat == null || avant == null || !etat.modifiable) return;

    _poser(avant, annonce: AppStrings.raccourciAnnule);
    _planifier();
  }

  Future<Map<CreneauCle, DisponibiliteEtat>?> _lireMoisPrecedent(
    PorteeRaccourci portee,
  ) async {
    final etat = _etat;
    final stationId = _stationId;
    final userId = _userId;
    if (etat == null || stationId == null || userId == null) return null;

    _publier(
      etat.copyWith(
        raccourciEnCours: () => portee,
        messageRaccourci: () => null,
      ),
    );
    final precedent = DateTime(etat.periode.annee, etat.periode.mois - 1);

    try {
      final lues = await ref
          .read(disposRepositoryProvider)
          .lireMois(
            stationId: stationId,
            userId: userId,
            annee: precedent.year,
            mois: precedent.month,
          );
      final courant = _etat;
      if (courant == null) return null;
      _publier(courant.copyWith(raccourciEnCours: () => null));
      return lues;
    } on Object {
      final courant = _etat;
      if (courant == null) return null;
      _publier(
        courant.copyWith(
          raccourciEnCours: () => null,
          messageRaccourci: () => AppStrings.raccourciCopieIllisible,
          annonce: () => AppStrings.raccourciCopieIllisible,
        ),
      );
      return null;
    }
  }

  // -------------------------------------------------------------------
  // Les préférences de charge
  // -------------------------------------------------------------------

  /// Le nombre maximal d'astreintes voulu ce mois-ci. `null` : autant que
  /// nécessaire.
  void definirPlafondAstreintes(int? valeur) =>
      _poserPreferences((p) => p.avecAstreintes(valeur));

  /// Le nombre maximal de weekends voulu ce mois-ci. `null` : autant que
  /// nécessaire.
  void definirPlafondWeekends(int? valeur) =>
      _poserPreferences((p) => p.avecWeekends(valeur));

  /// Le mot du mois pour le chef de centre.
  void definirCommentaire(String texte) =>
      _poserPreferences((p) => p.avecCommentaire(texte));

  /// Pose une préférence sur l'écran et dans la file.
  ///
  /// **Le même chemin que la case** : état optimiste, délai de 500 ms,
  /// persistance sur l'appareil, envoi groupé, relances, refus. Taper un
  /// commentaire lettre par lettre ne produit donc qu'une requête — chaque
  /// frappe réarme le même minuteur.
  ///
  /// Le cran d'annulation d'un raccourci n'est **pas** désarmé ici : régler un
  /// maximum n'est pas toucher une case, et le membre a le droit de faire les
  /// deux dans n'importe quel ordre.
  void _poserPreferences(PreferencesMois Function(PreferencesMois) changement) {
    final etat = _etat;
    if (etat == null || !etat.modifiable) return;

    final voulues = changement(etat.preferences.valeurs);
    if (voulues == etat.preferences.valeurs) return;

    _preferencesEnAttente[etat.periode.id] = voulues;

    _publier(
      etat.copyWith(
        preferences: etat.preferences.copyWith(
          valeurs: voulues,
          // La valeur n'est plus celle du mois précédent : c'est la sienne.
          repriseDe: () => null,
          enErreur: false,
        ),
        sync: etat.horsLigne ? SyncEtat.horsLigne : SyncEtat.enregistrement,
        echecPersistant: false,
      ),
    );
    _planifier();
  }

  // -------------------------------------------------------------------
  // La file
  // -------------------------------------------------------------------

  /// Pose [modifications] sur l'écran et dans la file. **Le seul chemin
  /// d'écriture** : une touche, une case peinte, un raccourci de soixante-deux
  /// cases et son annulation passent tous par ici, et bénéficient donc de la
  /// même coalescence, de la même persistance locale et du même traitement des
  /// refus.
  ///
  /// [raccourci] non nul arme la ligne de résultat et son bouton « Annuler ».
  /// Nul — c'est-à-dire pour toute saisie à la main — la **désarme** : voir
  /// [EtatSaisie.dernierRaccourci].
  void _poser(
    Map<CreneauCle, DisponibiliteEtat> modifications, {
    DisponibiliteEtat? pinceau,
    CreneauCle? origine,
    int? casesPeintes,
    RaccourciApplique? raccourci,
    String? annonce,
  }) {
    final etat = _etat;
    if (etat == null) return;

    if (raccourci == null) _annulationRaccourci = null;
    _file.addAll(modifications);

    _publier(
      etat.copyWith(
        mois: etat.mois.avec(modifications),
        // Une case qu'on vient de reposer n'est plus en échec : sa nouvelle
        // valeur repart dans la file.
        enErreur: etat.enErreur.difference(modifications.keys.toSet()),
        // Deux transitions par session, pas quarante : la première
        // modification annonce « Enregistrement… », les suivantes rejoignent
        // une file dont l'état est déjà annoncé.
        sync: etat.horsLigne ? SyncEtat.horsLigne : SyncEtat.enregistrement,
        echecPersistant: false,
        pinceau: pinceau == null ? null : () => pinceau,
        origine: origine == null ? null : () => origine,
        casesPeintes: casesPeintes,
        dernierRaccourci: () => raccourci,
        raccourciEnCours: () => null,
        messageRaccourci: () => null,
        annonce: annonce == null ? null : () => annonce,
      ),
    );
  }

  void _planifier() {
    // Rien ne part pendant un geste : la file est retenue tant que le doigt
    // est posé.
    if (_gesteActif || (_file.isEmpty && _preferencesEnAttente.isEmpty)) {
      return;
    }
    _relance = 0;
    _minuteur?.cancel();
    _minuteur = Timer(delaiEnvoi, () => unawaited(_envoyer()));
    // Ce qui vient d'être posé est gardé sur l'appareil avant même d'être
    // envoyé : c'est ce que promet la bannière hors ligne.
    unawaited(_persister());
  }

  /// Vide la file **immédiatement**, sans attendre le délai. Appelée quand on
  /// quitte l'écran, qu'on change de mois, ou que l'application passe en
  /// arrière-plan.
  /// Rend **vrai si la file est effectivement partie**. Un appelant qui
  /// enchaîne sur autre chose — quitter l'écran, changer de mois — doit
  /// savoir que l'envoi a échoué plutôt que de le supposer réussi.
  Future<bool> viderMaintenant() async {
    _minuteur?.cancel();
    _minuteur = null;
    if (_gesteActif) finGeste();
    await _envoyer();
    return _file.isEmpty && _preferencesEnAttente.isEmpty;
  }

  /// « Réessayer » : rejoue toute la file en attente.
  Future<void> reessayer() async {
    _relance = 0;
    _minuteur?.cancel();
    await _envoyer();
  }

  Future<void> _envoyer() async {
    // **Rien ne part pendant un geste**, quelle que soit l'origine de
    // l'appel : un minuteur de relance, un délai encore en vol. Le geste se
    // termine par `_planifier`, qui reprogramme ce qui a été retenu.
    if (_gesteActif) return;

    final etat = _etat;
    if (etat == null ||
        _envoiEnCours ||
        (_file.isEmpty && _preferencesEnAttente.isEmpty)) {
      return;
    }

    final stationId = _stationId;
    final userId = _userId;
    if (stationId == null || userId == null) return;

    final lot = Map<CreneauCle, DisponibiliteEtat>.of(_file);
    final lotPreferences = Map<String, PreferencesMois>.of(
      _preferencesEnAttente,
    );

    final ecritures = <LigneDisponibilite>[
      for (final entree in lot.entries)
        if (entree.value != DisponibiliteEtat.nonSaisi)
          LigneDisponibilite(cle: entree.key, etat: entree.value),
    ];
    // Une case revenue à « non saisi » sans jamais avoir eu de ligne n'a rien
    // à supprimer : ne pas l'envoyer, c'est une requête de moins **et** un
    // « 0 ligne affectée » de moins à interpréter.
    final suppressions = <CreneauCle>[
      for (final entree in lot.entries)
        if (entree.value == DisponibiliteEtat.nonSaisi &&
            _serveur.containsKey(entree.key))
          entree.key,
    ];

    if (ecritures.isEmpty && suppressions.isEmpty && lotPreferences.isEmpty) {
      _retirerDeLaFile(lot);
      _appliquerAuServeur(lot);
      _publier(etat.copyWith(sync: SyncEtat.enregistre));
      return;
    }

    _envoiEnCours = true;
    if (!etat.horsLigne && etat.sync != SyncEtat.enregistrement) {
      _publier(etat.copyWith(sync: SyncEtat.enregistrement));
    }

    final depot = ref.read(disposRepositoryProvider);
    final periodesPreferences = lotPreferences.keys.toList();
    try {
      // Trois requêtes au plus, et elles partent ensemble : les jeux de clés
      // sont disjoints, l'ordre n'a aucune conséquence.
      final resultats = await Future.wait<int>(<Future<int>>[
        if (ecritures.isNotEmpty)
          depot.enregistrerLot(
            stationId: stationId,
            userId: userId,
            lignes: ecritures,
          ),
        if (suppressions.isNotEmpty)
          depot.supprimerLot(
            stationId: stationId,
            userId: userId,
            cles: suppressions,
          ),
        for (final periodId in periodesPreferences)
          depot.enregistrerPreferences(
            stationId: stationId,
            userId: userId,
            periodId: periodId,
            preferences: lotPreferences[periodId]!,
          ),
      ]);

      var index = 0;
      if (ecritures.isNotEmpty) {
        // Une écriture refusée par la clause `using` d'une politique ne lève
        // pas : elle n'affecte aucune ligne. Le compte est la seule preuve.
        if (resultats[index++] != ecritures.length) {
          throw const EchecDispos(ErreurDispos.verrouille);
        }
      }
      final indexPreferences = index + (suppressions.isNotEmpty ? 1 : 0);
      for (var rang = 0; rang < periodesPreferences.length; rang++) {
        // Zéro ligne rendue par l'`upsert` : la politique a filtré. Même
        // preuve, même conclusion que pour une case.
        if (resultats[indexPreferences + rang] == 0) {
          throw const EchecDispos(ErreurDispos.verrouille);
        }
      }
      if (suppressions.isNotEmpty && resultats[index] == 0) {
        // Zéro ligne supprimée a deux causes très différentes : la RLS a
        // filtré — mois verrouillé, caserne suspendue —, ou les lignes
        // avaient déjà disparu. Un envoi accepté dans le même lot tranche
        // tout de suite : la période n'est pas verrouillée, sinon il aurait
        // été refusé lui aussi. Sans envoi pour trancher, on relit avant de
        // conclure : accuser le verrouillage à tort coûte une bannière
        // d'erreur et une file qui tourne en rond.
        if (ecritures.isEmpty && await _lignesEncorePresentes(suppressions)) {
          throw const EchecDispos(ErreurDispos.verrouille);
        }
      }

      _envoiEnCours = false;
      _retirerDeLaFile(lot);
      _retirerDesPreferences(lotPreferences);
      _appliquerAuServeur(lot);
      _relance = 0;
      // Confirmé par le serveur : l'entrée gardée sur l'appareil n'a plus
      // de raison d'être, et rejouer une écriture déjà passée en aurait une
      // mauvaise.
      unawaited(_persister());

      final courant = _etat;
      if (courant == null) return;
      final resteEnAttente =
          _file.isNotEmpty || _preferencesEnAttente.isNotEmpty;
      _publier(
        courant.copyWith(
          sync: resteEnAttente ? SyncEtat.enregistrement : SyncEtat.enregistre,
          enErreur: courant.enErreur.difference(lot.keys.toSet()),
          preferences: courant.preferences.copyWith(
            // La ligne existe désormais en base : plus rien à reprendre.
            ligneAuChargement: lotPreferences.containsKey(courant.periode.id)
                ? true
                : null,
            enErreur: false,
          ),
          echecPersistant: false,
        ),
      );
      // Une modification est arrivée pendant l'envoi : elle repart.
      if (resteEnAttente) _planifier();
    } on EchecDispos catch (echec) {
      _envoiEnCours = false;
      await _traiterEchec(echec.erreur, lot, lotPreferences.keys.toSet());
    } on Object {
      _envoiEnCours = false;
      await _traiterEchec(
        ErreurDispos.inconnue,
        lot,
        lotPreferences.keys.toSet(),
      );
    }
  }

  Future<void> _traiterEchec(
    ErreurDispos erreur,
    Map<CreneauCle, DisponibiliteEtat> lot, [
    Set<String> preferences = const <String>{},
  ]) async {
    final etat = _etat;
    if (etat == null) return;

    // Hors ligne n'est pas un échec, c'est une attente : aucune case n'est
    // marquée, rien n'est bloqué, la file reste pleine.
    if (erreur == ErreurDispos.reseau) {
      _publier(etat.copyWith(sync: SyncEtat.horsLigne, horsLigne: true));
      return;
    }

    if (erreur.estRefus) {
      // Le serveur a refusé : reste à savoir si c'est le mois qui s'est
      // verrouillé ou la caserne qui est passée en lecture seule. Les deux
      // arrivent en 42501 ; seule la relecture des périodes les sépare.
      final verrouille = await _moisVerrouilleMaintenant();
      final courant = _etat;
      if (courant == null) return;

      _lectureSeuleConnue = _lectureSeuleConnue || !verrouille;
      _publier(
        courant.copyWith(
          sync: SyncEtat.echec,
          enErreur: <CreneauCle>{...courant.enErreur, ...lot.keys},
          preferences: courant.preferences.copyWith(
            enErreur: preferences.contains(courant.periode.id),
          ),
          lectureSeule: !verrouille,
          refusServeur: () => verrouille
              ? AppStrings.moisErreurVerrouilleEnCours
              : AppStrings.moisErreurSuspendueEnCours,
        ),
      );
      return;
    }

    final derniere = _relance >= relances.length;
    _publier(
      etat.copyWith(
        sync: SyncEtat.echec,
        enErreur: <CreneauCle>{...etat.enErreur, ...lot.keys},
        preferences: etat.preferences.copyWith(
          enErreur: preferences.contains(etat.periode.id),
        ),
        // Un raté ne mérite pas un bandeau ; un blocage, si.
        echecPersistant: derniere,
      ),
    );

    if (derniere) return;
    final attente = relances[_relance++];
    _minuteur?.cancel();
    _minuteur = Timer(attente, () => unawaited(_envoyer()));
  }

  /// Relit les périodes pour savoir si le mois affiché vient de se verrouiller.
  Future<bool> _moisVerrouilleMaintenant() async {
    final etat = _etat;
    final stationId = _stationId;
    if (etat == null || stationId == null) return true;

    try {
      final periodes = await ref
          .read(disposRepositoryProvider)
          .periodes(stationId);
      for (final periode in periodes) {
        if (periode.cle == etat.periode.cle) return !periode.ouverte;
      }
      return true;
    } on Object {
      // Injoignable : on ne sait pas. Le verrouillage est la cause de très
      // loin la plus fréquente, et sa phrase renvoie vers le chef de centre.
      return true;
    }
  }

  /// Vrai si l'une au moins des lignes qu'on voulait supprimer est encore en
  /// base — c'est-à-dire si la suppression a bien été **refusée**.
  ///
  /// Une lecture de plus, payée seulement dans le cas ambigu : un lot fait
  /// uniquement de suppressions qui n'a rien affecté.
  Future<bool> _lignesEncorePresentes(List<CreneauCle> cles) async {
    final stationId = _stationId;
    final userId = _userId;
    if (stationId == null || userId == null || !ref.mounted) return true;

    final parMois = <String, CreneauCle>{
      for (final cle in cles) cle.cleMois: cle,
    };

    try {
      final depot = ref.read(disposRepositoryProvider);
      for (final exemple in parMois.values) {
        final lues = await depot.lireMois(
          stationId: stationId,
          userId: userId,
          annee: exemple.date.year,
          mois: exemple.date.month,
        );
        final restantes = cles.where(
          (cle) => cle.cleMois == exemple.cleMois && lues.containsKey(cle),
        );
        if (restantes.isNotEmpty) return true;
      }
    } on Object {
      // Injoignable : on ne conclut pas à un succès. La file garde ses
      // entrées et l'écran dit qu'il n'a pas pu.
      return true;
    }
    return false;
  }

  /// Garde la file sur l'appareil, une tranche par mois.
  ///
  /// Appelée à chaque fois que la file change de façon durable : une saisie
  /// confirmée, un geste terminé, un envoi réussi. Un mois qui n'a plus rien
  /// en attente est **oublié**, pas réécrit vide.
  Future<void> _persister() async {
    final stationId = _stationId;
    final userId = _userId;
    if (stationId == null || userId == null || !ref.mounted) return;

    final parMois = <String, Map<CreneauCle, DisponibiliteEtat>>{};
    for (final entree in _file.entries) {
      (parMois[entree.key.cleMois] ??=
              <CreneauCle, DisponibiliteEtat>{})[entree.key] =
          entree.value;
    }

    final depot = ref.read(fileLocaleProvider);
    for (final oublie in _moisPersistes.difference(parMois.keys.toSet())) {
      await depot.enregistrer(
        stationId: stationId,
        userId: userId,
        mois: oublie,
        entrees: const <CreneauCle, DisponibiliteEtat>{},
      );
    }
    for (final tranche in parMois.entries) {
      await depot.enregistrer(
        stationId: stationId,
        userId: userId,
        mois: tranche.key,
        entrees: tranche.value,
      );
    }
    _moisPersistes = parMois.keys.toSet();

    // Les maximums voyagent avec la file, et pour la même raison : la
    // bannière hors ligne les promet aussi.
    for (final oubliee in _preferencesPersistees.difference(
      _preferencesEnAttente.keys.toSet(),
    )) {
      await depot.enregistrerPreferences(
        stationId: stationId,
        userId: userId,
        periodId: oubliee,
        preferences: null,
      );
    }
    for (final attente in _preferencesEnAttente.entries) {
      await depot.enregistrerPreferences(
        stationId: stationId,
        userId: userId,
        periodId: attente.key,
        preferences: attente.value,
      );
    }
    _preferencesPersistees = _preferencesEnAttente.keys.toSet();
  }

  /// Retire de l'attente les préférences que le serveur vient de confirmer.
  /// Une période remodifiée pendant l'envoi y reste.
  void _retirerDesPreferences(Map<String, PreferencesMois> lot) {
    for (final entree in lot.entries) {
      if (_preferencesEnAttente[entree.key] == entree.value) {
        _preferencesEnAttente.remove(entree.key);
      }
    }
  }

  void _retirerDeLaFile(Map<CreneauCle, DisponibiliteEtat> lot) {
    for (final entree in lot.entries) {
      // Une case modifiée à nouveau pendant l'envoi reste dans la file.
      if (_file[entree.key] == entree.value) _file.remove(entree.key);
    }
  }

  void _appliquerAuServeur(Map<CreneauCle, DisponibiliteEtat> lot) {
    for (final entree in lot.entries) {
      if (entree.value == DisponibiliteEtat.nonSaisi) {
        _serveur.remove(entree.key);
      } else {
        _serveur[entree.key] = entree.value;
      }
    }
  }

  // -------------------------------------------------------------------
  // Réseau et rechargement
  // -------------------------------------------------------------------

  void _appliquerReseau({required bool enLigne}) {
    final etat = _etat;
    if (etat == null) return;

    final enAttente = _file.isNotEmpty || _preferencesEnAttente.isNotEmpty;
    _publier(
      etat.copyWith(
        horsLigne: !enLigne,
        sync: enLigne
            ? (enAttente ? SyncEtat.enregistrement : etat.sync)
            : SyncEtat.horsLigne,
      ),
    );

    if (enLigne && enAttente) {
      _relance = 0;
      unawaited(_envoyer());
    }
  }

  /// Change de mois.
  ///
  /// La file est vidée **avant** : le mois quitté ne laisse pas de
  /// modification derrière lui. Mais si l'envoi échoue — hors ligne, serveur
  /// muet — le changement a lieu quand même et **la file est conservée** :
  /// chaque clé porte sa date, le dépôt écrit indifféremment des créneaux de
  /// plusieurs mois dans le même lot, et le membre a le droit d'aller
  /// regarder un autre mois sans perdre ce qu'il vient de déclarer.
  Future<void> choisirMois(String cle) async {
    if (!ref.mounted || ref.read(moisSelectionneProvider) == cle) return;

    final partie = await viderMaintenant();
    if (!ref.mounted) return;
    // Rien n'est parti : la file reste en attente, et elle est déjà gardée
    // sur l'appareil. `build` la reprogrammera pour le nouveau mois.
    if (!partie) await _persister();

    ref.read(moisSelectionneProvider.notifier).definir(cle);
  }

  /// Relit tout depuis le serveur, **sans jeter la file**.
  ///
  /// C'est ce que fait « Recharger » après un refus. La file n'est pas vidée
  /// ici : `build` en retire les seules entrées qui visent un mois devenu
  /// verrouillé, et le dit. Les autres — un mois toujours ouvert, une panne
  /// passagère — sont exactement ce qu'il ne faut pas perdre.
  void recharger() {
    _minuteur?.cancel();
    _relance = 0;
    if (!ref.mounted) return;
    ref.invalidate(periodesProvider);
    ref.invalidateSelf();
  }

  /// Accuse réception de la bannière « file périmée » : les entrées sont
  /// déjà parties, il ne reste que la phrase à retirer.
  void accuserFilePerimee() {
    final etat = _etat;
    if (etat == null || !etat.filePerimee) return;
    _publier(etat.copyWith(filePerimee: false));
  }

  /// Retire l'annonce déjà lue, pour qu'une seconde peinture identique soit
  /// bien annoncée de nouveau.
  void annonceLue() {
    final etat = _etat;
    if (etat == null || etat.annonce == null) return;
    _publier(etat.copyWith(annonce: () => null));
  }
}

final AsyncNotifierProvider<SaisieController, EtatSaisie?>
saisieControllerProvider = AsyncNotifierProvider<SaisieController, EtatSaisie?>(
  SaisieController.new,
);

/// Le libellé d'un état de disponibilité, tel que le thème le nomme.
///
/// Passé par un provider pour que le contrôleur compose ses annonces sans
/// dépendre d'un `BuildContext` : « 14 cases mises à jour, disponible ».
final Provider<String Function(DisponibiliteEtat)>
statutsDisponibiliteProvider = Provider<String Function(DisponibiliteEtat)>(
  (ref) =>
      (etat) => switch (etat) {
        DisponibiliteEtat.disponible => AppStrings.etatDisponible,
        DisponibiliteEtat.absent => AppStrings.etatAbsent,
        DisponibiliteEtat.nonSaisi => AppStrings.etatNonSaisi,
      },
);
