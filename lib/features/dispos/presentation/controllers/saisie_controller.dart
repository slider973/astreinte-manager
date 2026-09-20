import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/reseau/connectivite.dart';
import '../../../../core/session/session_providers.dart';
import '../../../../core/theme/app_status.dart';
import '../../data/dispos_repository.dart';
import '../../domain/creneau_cle.dart';
import '../../domain/disponibilite_mois.dart';
import '../../domain/dispos_providers.dart';
import '../../domain/periode_saisie.dart';

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
    this.annonce,
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

  /// La dernière phrase à annoncer sans déplacer le focus.
  final String? annonce;

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
    String? Function()? annonce,
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
    annonce: annonce == null ? this.annonce : annonce(),
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

  Timer? _minuteur;
  bool _envoiEnCours = false;
  int _relance = 0;

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
    final periode = ref.watch(periodeCouranteProvider);
    if (appartenance == null || session == null || periode == null) return null;

    _stationId = appartenance.stationId;
    _userId = session.userId;

    final lues = await ref
        .read(disposRepositoryProvider)
        .lireMois(
          stationId: appartenance.stationId,
          userId: session.userId,
          annee: periode.annee,
          mois: periode.mois,
        );

    _serveur = Map<CreneauCle, DisponibiliteEtat>.of(lues);
    _relance = 0;

    // La file survit à un changement de caserne ou de session : elle ne doit
    // pas repartir sur un autre mois que le sien.
    _file.removeWhere(
      (cle, _) =>
          cle.date.year != periode.annee || cle.date.month != periode.mois,
    );

    final horsLigne = !ref.read(connectiviteProvider).enLigne;

    return EtatSaisie(
      periode: periode,
      // La file en attente prime sur ce que le serveur vient de rendre : elle
      // porte ce que l'utilisateur a voulu et que la base n'a pas encore.
      mois: DisponibiliteMois(
        annee: periode.annee,
        mois: periode.mois,
        valeurs: <CreneauCle, DisponibiliteEtat>{...lues, ..._file},
      ),
      sync: _file.isEmpty
          ? SyncEtat.repos
          : horsLigne
          ? SyncEtat.horsLigne
          : SyncEtat.enregistrement,
      horsLigne: horsLigne,
    );
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
  }

  // -------------------------------------------------------------------
  // La file
  // -------------------------------------------------------------------

  void _poser(
    Map<CreneauCle, DisponibiliteEtat> modifications, {
    DisponibiliteEtat? pinceau,
    CreneauCle? origine,
    int? casesPeintes,
  }) {
    final etat = _etat;
    if (etat == null) return;

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
      ),
    );
  }

  void _planifier() {
    // Rien ne part pendant un geste : la file est retenue tant que le doigt
    // est posé.
    if (_gesteActif || _file.isEmpty) return;
    _relance = 0;
    _minuteur?.cancel();
    _minuteur = Timer(delaiEnvoi, () => unawaited(_envoyer()));
  }

  /// Vide la file **immédiatement**, sans attendre le délai. Appelée quand on
  /// quitte l'écran, qu'on change de mois, ou que l'application passe en
  /// arrière-plan.
  Future<void> viderMaintenant() async {
    _minuteur?.cancel();
    _minuteur = null;
    if (_gesteActif) finGeste();
    await _envoyer();
  }

  /// « Réessayer » : rejoue toute la file en attente.
  Future<void> reessayer() async {
    _relance = 0;
    _minuteur?.cancel();
    await _envoyer();
  }

  Future<void> _envoyer() async {
    final etat = _etat;
    if (etat == null || _envoiEnCours || _file.isEmpty) return;

    final stationId = _stationId;
    final userId = _userId;
    if (stationId == null || userId == null) return;

    final lot = Map<CreneauCle, DisponibiliteEtat>.of(_file);

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

    if (ecritures.isEmpty && suppressions.isEmpty) {
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
    try {
      // Deux requêtes au plus, et elles partent ensemble : les deux jeux de
      // clés sont disjoints, l'ordre n'a aucune conséquence.
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
      ]);

      var index = 0;
      if (ecritures.isNotEmpty) {
        // Une écriture refusée par la clause `using` d'une politique ne lève
        // pas : elle n'affecte aucune ligne. Le compte est la seule preuve.
        if (resultats[index++] != ecritures.length) {
          throw const EchecDispos(ErreurDispos.verrouille);
        }
      }
      if (suppressions.isNotEmpty && resultats[index] == 0) {
        throw const EchecDispos(ErreurDispos.verrouille);
      }

      _envoiEnCours = false;
      _retirerDeLaFile(lot);
      _appliquerAuServeur(lot);
      _relance = 0;

      final courant = _etat;
      if (courant == null) return;
      _publier(
        courant.copyWith(
          sync: _file.isEmpty ? SyncEtat.enregistre : SyncEtat.enregistrement,
          enErreur: courant.enErreur.difference(lot.keys.toSet()),
          echecPersistant: false,
        ),
      );
      // Une modification est arrivée pendant l'envoi : elle repart.
      if (_file.isNotEmpty) _planifier();
    } on EchecDispos catch (echec) {
      _envoiEnCours = false;
      await _traiterEchec(echec.erreur, lot);
    } on Object {
      _envoiEnCours = false;
      await _traiterEchec(ErreurDispos.inconnue, lot);
    }
  }

  Future<void> _traiterEchec(
    ErreurDispos erreur,
    Map<CreneauCle, DisponibiliteEtat> lot,
  ) async {
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

      _publier(
        courant.copyWith(
          sync: SyncEtat.echec,
          enErreur: <CreneauCle>{...courant.enErreur, ...lot.keys},
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

    _publier(
      etat.copyWith(
        horsLigne: !enLigne,
        sync: enLigne
            ? (_file.isEmpty ? etat.sync : SyncEtat.enregistrement)
            : SyncEtat.horsLigne,
      ),
    );

    if (enLigne && _file.isNotEmpty) {
      _relance = 0;
      unawaited(_envoyer());
    }
  }

  /// Change de mois. La file est vidée **avant** : le mois quitté ne laisse
  /// jamais de modification derrière lui.
  Future<void> choisirMois(String cle) async {
    if (!ref.mounted || ref.read(moisSelectionneProvider) == cle) return;
    await viderMaintenant();
    if (!ref.mounted) return;
    ref.read(moisSelectionneProvider.notifier).definir(cle);
  }

  /// Relit tout depuis le serveur et **jette la file**. C'est ce que fait
  /// « Recharger » après un refus : reprendre depuis l'état réel est le but.
  void recharger() {
    _file.clear();
    _minuteur?.cancel();
    _relance = 0;
    if (!ref.mounted) return;
    ref.invalidate(periodesProvider);
    ref.invalidateSelf();
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
