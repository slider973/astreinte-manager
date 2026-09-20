import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/theme/app_status.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../data/suivi_repository.dart';
import 'matrice_providers.dart';
import 'suivi_planning.dart';

/// Le dépôt du suivi. Surchargé par un faux dans les tests.
final Provider<SuiviRepository> suiviRepositoryProvider =
    Provider<SuiviRepository>(
      (ref) => SupabaseSuiviRepository(ref.watch(supabaseClientProvider)),
    );

/// Les puces de filtre retenues.
///
/// **Vide veut dire « tous »** : une liste qui se vide quand on désélectionne
/// la dernière puce cacherait tout l'écran pour un clic de trop.
class FiltresSuivi extends Notifier<Set<FiltreSuivi>> {
  @override
  Set<FiltreSuivi> build() {
    // Changer de mois remet les filtres à plat : un filtre hérité d'octobre
    // afficherait une liste vide en novembre sans dire pourquoi.
    ref.watch(moisMatriceProvider);
    return const <FiltreSuivi>{};
  }

  void basculer(FiltreSuivi filtre) {
    if (filtre == FiltreSuivi.tous) {
      state = const <FiltreSuivi>{};
      return;
    }
    final suivant = <FiltreSuivi>{...state};
    if (!suivant.remove(filtre)) suivant.add(filtre);
    state = suivant;
  }

  void tout() => state = const <FiltreSuivi>{};
}

final NotifierProvider<FiltresSuivi, Set<FiltreSuivi>> filtresSuiviProvider =
    NotifierProvider<FiltresSuivi, Set<FiltreSuivi>>(FiltresSuivi.new);

/// Ce que l'écran de suivi affiche.
@immutable
class EtatSuivi {
  const EtatSuivi({
    required this.periode,
    required this.suivi,
    this.canalBranche = false,
    this.relance = false,
    this.publication = false,
    this.sync = SyncEtat.repos,
    this.messageErreur,
    this.lectureSeule = false,
    this.valideSousNosYeux = false,
  });

  final PeriodeSaisie periode;
  final SuiviPlanning suivi;

  /// Le canal temps réel est abonné. Faux tant qu'il ne l'est pas, et dès
  /// qu'il tombe : l'état est **affiché**, jamais supposé.
  final bool canalBranche;

  /// Une relance est en vol.
  final bool relance;

  /// Une publication est en vol.
  final bool publication;

  final SyncEtat sync;
  final String? messageErreur;
  final bool lectureSeule;

  /// Vrai quand le planning est passé à « Validé » **pendant** que l'écran
  /// était ouvert. C'est le seul moment chorégraphié de l'application
  /// (`DESIGN.md § Motion`) : le tampon ne se pose qu'une fois, pas à chaque
  /// ouverture d'un planning déjà validé.
  final bool valideSousNosYeux;

  EtatSuivi copie({
    PeriodeSaisie? periode,
    SuiviPlanning? suivi,
    bool? canalBranche,
    bool? relance,
    bool? publication,
    SyncEtat? sync,
    String? messageErreur,
    bool effacerMessage = false,
    bool? lectureSeule,
    bool? valideSousNosYeux,
  }) => EtatSuivi(
    periode: periode ?? this.periode,
    suivi: suivi ?? this.suivi,
    canalBranche: canalBranche ?? this.canalBranche,
    relance: relance ?? this.relance,
    publication: publication ?? this.publication,
    sync: sync ?? this.sync,
    messageErreur: effacerMessage ? null : messageErreur ?? this.messageErreur,
    lectureSeule: lectureSeule ?? this.lectureSeule,
    valideSousNosYeux: valideSousNosYeux ?? this.valideSousNosYeux,
  );
}

/// Le suivi d'un planning publié : lecture, temps réel, relance.
class SuiviController extends AsyncNotifier<EtatSuivi?> {
  /// Le délai d'apaisement avant de relire l'avancement.
  ///
  /// Trente réponses en dix minutes, ce sont trente événements ; relire la vue
  /// à chacun serait trente requêtes pour six nombres. On attend que la salve
  /// se taise.
  static const Duration fenetreAvancement = Duration(milliseconds: 400);

  Timer? _apaisement;
  bool _canalBranche = false;

  /// Les événements reçus entre l'abonnement et la première image. Ils sont
  /// rejoués dès que l'état existe : la fenêtre est étroite, mais une réponse
  /// perdue est un pompier qu'on croit muet.
  final List<EvenementSuivi> _enAttente = <EvenementSuivi>[];

  @override
  Future<EtatSuivi?> build() async {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (appartenance == null || !appartenance.estAdmin) return null;

    final periode = await ref.watch(periodeAdminProvider.future);
    if (periode == null) return null;

    ref.onDispose(() => _apaisement?.cancel());
    _brancher(appartenance.stationId);

    final suivi = await ref
        .read(suiviRepositoryProvider)
        .lire(
          stationId: appartenance.stationId,
          periodeId: periode.id,
          annee: periode.annee,
          mois: periode.mois,
        );

    final etat = EtatSuivi(
      periode: periode,
      suivi: suivi,
      canalBranche: _canalBranche,
    );

    if (_enAttente.isEmpty) return etat;

    state = AsyncValue<EtatSuivi?>.data(etat);
    final differes = <EvenementSuivi>[..._enAttente];
    _enAttente.clear();
    differes.forEach(_recevoir);
    return state.value ?? etat;
  }

  // -------------------------------------------------------------------
  // Le temps réel
  // -------------------------------------------------------------------

  void _brancher(String stationId) {
    final abonnement = ref
        .read(suiviRepositoryProvider)
        .ecouter(stationId: stationId)
        .listen(_recevoir, onError: (Object _) => _canal(branche: false));

    ref.onDispose(abonnement.cancel);
  }

  void _canal({required bool branche}) {
    _canalBranche = branche;
    final courant = state.value;
    if (courant == null || courant.canalBranche == branche) return;
    state = AsyncValue<EtatSuivi?>.data(courant.copie(canalBranche: branche));
  }

  /// Ce qui arrive du dehors.
  ///
  /// **Rien ne bouge sous la main** : le défilement ne saute pas, aucun message
  /// passager ne s'ouvre par événement. Les chiffres changent, une ligne change
  /// d'état, et c'est tout — sauf la validation, qui est *le* moment du mois.
  void _recevoir(EvenementSuivi evenement) {
    final courant = state.value;
    if (courant == null) {
      if (evenement case EtatCanalSuivi(:final branche)) {
        _canalBranche = branche;
      } else {
        _enAttente.add(evenement);
      }
      return;
    }

    switch (evenement) {
      case EtatCanalSuivi(:final branche):
        _canal(branche: branche);

      case ReponseRecue(:final AttributionSuivi attribution):
        // Un créneau inconnu : une attribution d'un autre mois. Rien à
        // redessiner.
        if (courant.suivi.creneauParId(attribution.creneauId) == null) return;

        // **Le nom ne voyage pas dans le canal** : `postgres_changes` diffuse
        // les colonnes de la table, pas la jointure sur `profiles`. Celui qu'on
        // connaît déjà vaut mieux qu'une ligne anonyme.
        final connue = courant.suivi.attributionParId(attribution.id);
        final fusionnee = connue == null || attribution.nom.isNotEmpty
            ? attribution
            : AttributionSuivi(
                id: attribution.id,
                creneauId: attribution.creneauId,
                userId: attribution.userId,
                nom: connue.nom,
                etat: attribution.etat,
                proposeeLe: attribution.proposeeLe,
                repondueLe: attribution.repondueLe,
                motifRefus: attribution.motifRefus,
                relances: attribution.relances,
                derniereRelance: attribution.derniereRelance,
              );

        if (connue == fusionnee) return;
        state = AsyncValue<EtatSuivi?>.data(
          courant.copie(suivi: courant.suivi.avecAttribution(fusionnee)),
        );
        _relireAvancement();

      case ReponseSupprimee(:final String id):
        if (courant.suivi.attributionParId(id) == null) return;
        state = AsyncValue<EtatSuivi?>.data(
          courant.copie(suivi: courant.suivi.sansAttribution(id)),
        );
        _relireAvancement();

      case PlanningRecu(:final planning):
        if (courant.suivi.planning?.id != planning.id) return;
        final devientValide =
            courant.suivi.etat != PlanningEtat.valide &&
            planning.etat == PlanningEtat.valide;
        state = AsyncValue<EtatSuivi?>.data(
          courant.copie(
            suivi: courant.suivi.avecPlanning(planning),
            valideSousNosYeux: courant.valideSousNosYeux || devientValide,
          ),
        );
        _relireAvancement();
    }
  }

  /// Relit `v_schedule_progress` une fois la salve retombée.
  void _relireAvancement() {
    _apaisement?.cancel();
    _apaisement = Timer(fenetreAvancement, () {
      unawaited(_avancement());
    });
  }

  Future<void> _avancement() async {
    final courant = state.value;
    final planning = courant?.suivi.planning;
    if (courant == null || planning == null) return;

    try {
      final avancement = await ref
          .read(suiviRepositoryProvider)
          .lireProgression(planningId: planning.id);
      final apres = state.value;
      if (!ref.mounted || apres == null) return;
      state = AsyncValue<EtatSuivi?>.data(
        apres.copie(suivi: apres.suivi.avecProgression(avancement)),
      );
    } on EchecSuivi {
      // L'avancement est un confort : un échec de relecture ne doit pas
      // remplacer un écran juste par une bannière rouge. « Rafraîchir »
      // rattrape.
    }
  }

  // -------------------------------------------------------------------
  // Les actions
  // -------------------------------------------------------------------

  /// Relit tout, **en gardant l'écran à l'écran**.
  Future<void> rafraichir() async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    final courant = state.value;
    if (stationId == null || courant == null) return;

    try {
      final suivi = await ref
          .read(suiviRepositoryProvider)
          .lire(
            stationId: stationId,
            periodeId: courant.periode.id,
            annee: courant.periode.annee,
            mois: courant.periode.mois,
          );
      if (!ref.mounted) return;
      state = AsyncValue<EtatSuivi?>.data(
        courant.copie(suivi: suivi, effacerMessage: true, sync: SyncEtat.repos),
      );
    } on EchecSuivi catch (echec) {
      _echouer(echec);
    }
  }

  /// Relance les retardataires. Rend le compte rendu, ou `null` en cas
  /// d'échec — c'est l'écran qui choisit la surface.
  Future<ResultatRelance?> relancer() async {
    final courant = state.value;
    final planning = courant?.suivi.planning;
    if (courant == null || planning == null || courant.relance) return null;

    state = AsyncValue<EtatSuivi?>.data(
      courant.copie(relance: true, effacerMessage: true),
    );

    try {
      final resultat = await ref
          .read(suiviRepositoryProvider)
          .relancer(planningId: planning.id);
      final apres = state.value;
      if (!ref.mounted || apres == null) return resultat;
      state = AsyncValue<EtatSuivi?>.data(apres.copie(relance: false));
      // Les compteurs de relance viennent de changer en base : la liste doit le
      // dire (« relancé il y a 20 min »).
      unawaited(rafraichir());
      return resultat;
    } on EchecSuivi catch (echec) {
      _echouer(echec, relance: false);
      return null;
    }
  }

  /// Le mois vient d'être publié depuis la matrice : l'écran doit repartir de
  /// la base plutôt que de deviner l'état du planning.
  void invalider() => ref.invalidateSelf();

  void _echouer(EchecSuivi echec, {bool? relance}) {
    final courant = state.value;
    if (!ref.mounted || courant == null) return;

    final suspendue = echec.erreur == ErreurSuivi.lectureSeule;
    state = AsyncValue<EtatSuivi?>.data(
      courant.copie(
        sync: SyncEtat.echec,
        relance: relance,
        publication: false,
        messageErreur: suspendue ? null : echec.message,
        effacerMessage: suspendue,
        lectureSeule: courant.lectureSeule || suspendue,
      ),
    );
  }
}

final AsyncNotifierProvider<SuiviController, EtatSuivi?> suiviControllerProvider =
    AsyncNotifierProvider<SuiviController, EtatSuivi?>(
      SuiviController.new,
      isAutoDispose: true,
    );

/// Les journées du mois, construites **une fois par état** et mémorisées.
///
/// La liste est virtualisée ; le tri de soixante-deux créneaux n'a aucune
/// raison de se refaire à chaque image de défilement.
final Provider<List<JourneeSuivi>> journeesSuiviProvider =
    Provider<List<JourneeSuivi>>((ref) {
      final etat = ref.watch(suiviControllerProvider).value;
      if (etat == null || !etat.suivi.existe) return const <JourneeSuivi>[];
      return etat.suivi.journees();
    });

/// Les journées réellement affichées, filtrées, **sans requête**.
final Provider<List<JourneeSuivi>> journeesVisiblesProvider =
    Provider<List<JourneeSuivi>>((ref) {
      final journees = ref.watch(journeesSuiviProvider);
      final filtres = ref.watch(filtresSuiviProvider);
      if (journees.isEmpty || filtres.isEmpty) return journees;

      return <JourneeSuivi>[
        for (final journee in journees)
          if (journee.creneaux.any(
            (CreneauSuivi creneau) => creneau.correspond(filtres),
          ))
            JourneeSuivi(
              date: journee.date,
              creneaux: <CreneauSuivi>[
                for (final creneau in journee.creneaux)
                  if (creneau.correspond(filtres)) creneau,
              ],
            ),
      ];
    });

/// Le compte affiché dans chaque puce de filtre.
final Provider<Map<FiltreSuivi, int>> comptesSuiviProvider =
    Provider<Map<FiltreSuivi, int>>((ref) {
      final etat = ref.watch(suiviControllerProvider).value;
      final journees = ref.watch(journeesSuiviProvider);
      if (etat == null) return const <FiltreSuivi, int>{};
      return <FiltreSuivi, int>{
        for (final filtre in FiltreSuivi.values)
          filtre: etat.suivi.compte(filtre, journees),
      };
    });

/// Les retardataires, recalculés à chaque changement d'état.
final Provider<List<Retardataire>> retardatairesProvider =
    Provider<List<Retardataire>>((ref) {
      final etat = ref.watch(suiviControllerProvider).value;
      if (etat == null || !etat.suivi.existe) return const <Retardataire>[];
      return etat.suivi.retardataires();
    });
