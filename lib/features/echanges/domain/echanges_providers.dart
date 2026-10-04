import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fraicheur/fraicheur.dart';
import '../../../core/fraicheur/relecture.dart';
import '../../../core/session/caserne_ouverte.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../astreintes/domain/astreintes_providers.dart';
import '../data/echanges_repository.dart';
import 'echange.dart';
import 'issue_echange.dart';

/// Le dépôt des échanges. Surchargé par un faux dans les tests.
final Provider<EchangesRepository> echangesRepositoryProvider =
    Provider<EchangesRepository>(
      (ref) => SupabaseEchangesRepository(ref.watch(supabaseClientProvider)),
    );

/// Ce que les écrans d'échange affichent : toutes les demandes que la RLS
/// montre à ce compte dans la caserne courante.
///
/// Une seule liste pour trois lectures — la section « Échanges »
/// d'Astreintes, le groupe « Demandes de collègues » de la Boîte, la file de
/// l'administrateur — parce qu'une seule requête les nourrit : la RLS fait
/// déjà le tri entre le pompier et l'administrateur (`docs/SCHEMA.md § 9`).
@immutable
class EtatEchanges {
  const EtatEchanges({this.echanges = const <Echange>[], this.moi = ''});

  final List<Echange> echanges;

  /// L'identifiant du lecteur, pour composer les vues.
  final String moi;

  bool get vide => echanges.isEmpty;

  /// Les demandes auxquelles je dois répondre : adressées à moi, ou « à la
  /// caserne » et montrées par la base. La plus récente en premier.
  List<Echange> get recues => <Echange>[
    for (final echange in echanges)
      if (echange.aRepondre(moi)) echange,
  ]..sort((Echange a, Echange b) => b.creeLe.compareTo(a.creeLe));

  /// Les demandes que je suis — faites, ou acceptées — tant qu'elles sont en
  /// cours ou que leur garde est à venir (`design/073 § 6.3`).
  ///
  /// L'ordre : à valider, puis ouvertes, puis terminées par date de décision
  /// décroissante.
  List<Echange> suivies(DateTime aujourdhui) =>
      <Echange>[
        for (final echange in echanges)
          if (echange.suivie(moi) &&
              (echange.statut.enCours || echange.aVenir(aujourdhui)))
            echange,
      ]..sort((Echange a, Echange b) {
        final rangA = _rang(a.statut);
        final rangB = _rang(b.statut);
        if (rangA != rangB) return rangA.compareTo(rangB);
        return b.finLe.compareTo(a.finLe);
      });

  static int _rang(StatutEchange statut) => switch (statut) {
    StatutEchange.accepteParPair => 0,
    StatutEchange.ouvert => 1,
    _ => 2,
  };

  /// La demande en cours qui engage l'attribution [attributionId] — cédée
  /// ou rendue —, ou `null`. Une seule possible (`shift_exchanges_open_uniq`
  /// et la vérification de `request_exchange`).
  Echange? enCoursSur(String attributionId) {
    for (final echange in echanges) {
      if (!echange.statut.enCours) continue;
      if (echange.garde.attributionId == attributionId ||
          echange.gardeRendue?.attributionId == attributionId) {
        return echange;
      }
    }
    return null;
  }

  /// La file de l'administrateur : accord du collègue reçu, décision due. La
  /// plus ancienne d'abord : elle expire la première.
  List<Echange> get aValider => <Echange>[
    for (final echange in echanges)
      if (echange.statut == StatutEchange.accepteParPair) echange,
  ]..sort((Echange a, Echange b) => a.expireLe.compareTo(b.expireLe));

  /// Les demandes qui attendent encore un collègue.
  List<Echange> get enAttente => <Echange>[
    for (final echange in echanges)
      if (echange.statut == StatutEchange.ouvert) echange,
  ]..sort((Echange a, Echange b) => a.expireLe.compareTo(b.expireLe));

  /// Les demandes closes (relues sur trente jours par le dépôt), les plus
  /// récentes en tête.
  List<Echange> get termines => <Echange>[
    for (final echange in echanges)
      if (echange.statut.terminal) echange,
  ]..sort((Echange a, Echange b) => b.finLe.compareTo(a.finLe));

  Echange? parId(String id) {
    for (final echange in echanges) {
      if (echange.id == id) return echange;
    }
    return null;
  }
}

/// Les échanges de la caserne courante, et les quatre gestes.
///
/// **Non auto-disposé**, comme les propositions : la Boîte, l'accueil et
/// Astreintes le lisent, et le relire à chaque changement d'onglet ferait
/// trois requêtes pour rien. **Aucun cache sur l'appareil** : la liste porte
/// des noms de tiers, elle vit en mémoire vive avec la page et disparaît avec
/// elle — rien à brancher dans `deconnexion.dart`.
///
/// **Pas de temps réel** (`shift_exchanges` n'est pas dans
/// `supabase_realtime`) : la liste se relit après chaque geste, au retour au
/// premier plan, à l'ouverture d'un écran qui l'affiche et à l'arrivée d'un
/// push, par le coordinateur du ticket 070 (`Donnee.echanges`).
class EchangesController extends AsyncNotifier<EtatEchanges>
    with LectureHorodatee<EtatEchanges> {
  @override
  Future<EtatEchanges> build() async {
    final session = ref.watch(sessionProvider).value;
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (session == null || appartenance == null) return const EtatEchanges();

    final echanges = await ref
        .read(echangesRepositoryProvider)
        .lister(
          stationId: appartenance.stationId,
          moi: session.userId,
          admin: appartenance.estAdmin,
        );
    if (ref.mounted) marquerLu();
    return EtatEchanges(echanges: echanges, moi: session.userId);
  }

  int _enVol = 0;

  /// Vrai tant qu'un geste est parti et pas revenu : une relecture publiée à
  /// ce moment remettrait à l'écran ce que le geste vient de changer.
  bool get ecritureEnAttente => _enVol > 0;

  /// Relit **en gardant l'écran à l'écran**. Une relecture qui échoue garde
  /// la liste lisible ; elle ne devient une erreur que sur un écran vide.
  Future<Relecture> rafraichir({bool Function()? publierSi}) async {
    final session = ref.read(sessionProvider).value;
    final appartenance = ref.read(appartenanceCouranteProvider);
    if (session == null || appartenance == null) return Relecture.inchangee;

    try {
      final echanges = await ref
          .read(echangesRepositoryProvider)
          .lister(
            stationId: appartenance.stationId,
            moi: session.userId,
            admin: appartenance.estAdmin,
          );
      if (!ref.mounted) return Relecture.inchangee;
      marquerLu();
      if (ecritureEnAttente || (publierSi != null && !publierSi())) {
        return Relecture.retenue;
      }
      state = AsyncValue<EtatEchanges>.data(
        EtatEchanges(echanges: echanges, moi: session.userId),
      );
      return Relecture.publiee;
    } on EchecEchange catch (echec) {
      if (!ref.mounted) return Relecture.echouee;
      if (state.value?.echanges.isEmpty ?? true) {
        state = AsyncValue<EtatEchanges>.error(echec, StackTrace.current);
      }
      return Relecture.echouee;
    }
  }

  /// A propose sa garde.
  Future<IssueEchange> demander({
    required String attributionId,
    required GardeEchange garde,
    Collegue? cible,
    GardeProposable? rendue,
  }) => _geste(
    () => ref
        .read(echangesRepositoryProvider)
        .demander(
          attributionId: attributionId,
          cibleId: cible?.userId,
          attributionRendueId: rendue?.attributionId,
        ),
    (ResultatEchange r) => issueDemande(r, cible: cible),
    astreintesChangees: false,
  );

  /// B accepte ou refuse.
  Future<IssueEchange> repondre(Echange echange, {required bool accepte}) =>
      _geste(
        () => ref
            .read(echangesRepositoryProvider)
            .repondre(echangeId: echange.id, accepte: accepte),
        (ResultatEchange r) => issueReponse(r, echange, accepte: accepte),
        astreintesChangees: true,
      );

  /// A retire sa demande.
  Future<IssueEchange> annuler(Echange echange) => _geste(
    () => ref.read(echangesRepositoryProvider).annuler(echangeId: echange.id),
    issueAnnulation,
    astreintesChangees: false,
  );

  /// L'administrateur valide ou refuse.
  Future<IssueEchange> decider(
    Echange echange, {
    required bool valide,
    String? motif,
  }) => _geste(
    () => ref
        .read(echangesRepositoryProvider)
        .decider(echangeId: echange.id, valide: valide, motif: motif),
    (ResultatEchange r) => issueDecision(r, echange, valide: valide),
    astreintesChangees: true,
  );

  /// Un geste : l'appel, la phrase, puis **la relecture**, réussie ou non —
  /// un refus aussi dit que la liste a bougé (demande prise, expirée,
  /// échouée).
  Future<IssueEchange> _geste(
    Future<ResultatEchange> Function() appel,
    IssueEchange Function(ResultatEchange) traduire, {
    required bool astreintesChangees,
  }) async {
    _enVol++;
    final IssueEchange issue;
    try {
      issue = traduire(await appel());
    } on EchecEchange catch (echec) {
      _enVol--;
      return IssueEchange.panne(echec.message);
    } on Object {
      _enVol--;
      rethrow;
    }
    _enVol--;
    if (!ref.mounted) return issue;

    await rafraichir();
    if (!ref.mounted) return issue;
    // Une garde qui a changé de main change « Mes astreintes » (l'accueil,
    // Astreintes) et, côté administrateur, le suivi et le planning du mois.
    if (issue.ok && (astreintesChangees || issue.valideMaintenant)) {
      unawaited(
        ref.read(fraicheurProvider).maintenant(const <Donnee>{
          Donnee.astreintes,
          Donnee.planningCaserne,
          Donnee.suivi,
          Donnee.planningAdmin,
        }),
      );
    }
    return issue;
  }
}

final AsyncNotifierProvider<EchangesController, EtatEchanges>
echangesControllerProvider =
    AsyncNotifierProvider<EchangesController, EtatEchanges>(
      EchangesController.new,
    );

/// La même source, **sans rien de ce qui a été lu dans une autre caserne**
/// (ticket 072, `core/session/caserne_ouverte.dart`). C'est elle que les
/// écrans lisent : après une bascule, ils montrent leur squelette jusqu'à la
/// première réponse de la nouvelle caserne, jamais ses demandes à elle.
final Provider<AsyncValue<EtatEchanges>> echangesOuvertsProvider =
    dansLaCaserneOuverte(echangesControllerProvider);

/// Les demandes auxquelles je dois répondre, pour la Boîte et l'accueil.
final Provider<List<Echange>> echangesRecusProvider = Provider<List<Echange>>(
  (ref) =>
      caserneOuverteSeulement(ref, echangesControllerProvider).value?.recues ??
      const <Echange>[],
);

/// Les demandes que je suis, pour la section « Échanges » d'Astreintes.
final Provider<List<Echange>> echangesSuivisProvider = Provider<List<Echange>>(
  (ref) =>
      ref
          .watch(echangesOuvertsProvider)
          .value
          ?.suivies(ref.watch(horlogeAstreintesProvider)()) ??
      const <Echange>[],
);

/// Le nombre de demandes à valider, pour le bloc du Suivi et le filtre.
final Provider<int> echangesAValiderProvider = Provider<int>(
  (ref) =>
      caserneOuverteSeulement(
        ref,
        echangesControllerProvider,
      ).value?.aValider.length ??
      0,
);

// ---------------------------------------------------------------------------
// Le parcours de demande (A)
// ---------------------------------------------------------------------------

/// Les collègues de la caserne, pour l'étape « À qui ? ». Relus à chaque
/// ouverture du parcours : la liste change rarement, et une demande se fait
/// en ligne.
final FutureProvider<List<Collegue>> colleguesEchangeProvider =
    FutureProvider.autoDispose<List<Collegue>>((ref) async {
      final session = ref.watch(sessionProvider).value;
      final caserne = ref.watch(caserneOuverteIdProvider);
      if (session == null || caserne == null) return const <Collegue>[];
      return ref
          .read(echangesRepositoryProvider)
          .collegues(stationId: caserne, moi: session.userId);
    });

/// Les gardes à venir d'un collègue, que je peux prendre en retour.
final gardesProposablesProvider = FutureProvider.autoDispose
    .family<List<GardeProposable>, String>((ref, String pairId) async {
      final caserne = ref.watch(caserneOuverteIdProvider);
      if (caserne == null) return const <GardeProposable>[];
      return ref
          .read(echangesRepositoryProvider)
          .gardesDe(pairId: pairId, stationId: caserne);
    });

/// Les réglages d'échange de la caserne, pour annoncer l'échéance et la
/// validation automatique. Un confort : en cas d'échec, les défauts.
final FutureProvider<ReglagesEchange> reglagesEchangeProvider =
    FutureProvider.autoDispose<ReglagesEchange>((ref) async {
      final caserne = ref.watch(caserneOuverteIdProvider);
      if (caserne == null) return ReglagesEchange.defaut;
      return ref.read(echangesRepositoryProvider).reglages(caserne);
    });
