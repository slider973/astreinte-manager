import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/theme/app_status.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../data/planning_repository.dart';
import 'candidat.dart';
import 'creneau_planning.dart';
import 'ligne_matrice.dart';
import 'matrice_providers.dart';
import 'planning_mois.dart';

/// Le dépôt du planning. Surchargé par un faux dans les tests.
final Provider<PlanningRepository> planningRepositoryProvider =
    Provider<PlanningRepository>(
      (ref) => SupabasePlanningRepository(ref.watch(supabaseClientProvider)),
    );

/// Le créneau ouvert dans le panneau, ou `null`.
///
/// **Il se referme au changement de mois** : un panneau qui survivrait au mois
/// quitté montrerait les candidats d'un créneau qui n'est plus à l'écran.
class CreneauSelectionne extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(moisMatriceProvider);
    return null;
  }

  void choisir(String? creneauId) {
    if (state == creneauId) return;
    state = creneauId;
  }

  void fermer() => state = null;
}

final NotifierProvider<CreneauSelectionne, String?>
creneauSelectionneProvider = NotifierProvider<CreneauSelectionne, String?>(
  CreneauSelectionne.new,
);

/// Un changement arrivé par le canal temps réel, sur le créneau ouvert.
///
/// [auteurId] est nul quand on ne peut pas le savoir : une suppression ne
/// diffuse que la clé primaire, jamais qui l'a faite.
@immutable
class ChangementDistant {
  const ChangementDistant({required this.creneauId, this.auteurId});

  final String creneauId;
  final String? auteurId;
}

/// Ce que la construction du planning affiche.
@immutable
class EtatPlanning {
  const EtatPlanning({
    required this.periode,
    required this.planning,
    this.canalBranche = false,
    this.creation = false,
    this.sync = SyncEtat.repos,
    this.messageErreur,
    this.lectureSeule = false,
    this.distant,
  });

  final PeriodeSaisie periode;
  final PlanningMois planning;

  /// Le canal temps réel est abonné. Faux tant qu'il ne l'est pas, et dès
  /// qu'il tombe : l'état est **affiché**, jamais supposé.
  final bool canalBranche;

  /// La création du planning est en vol.
  final bool creation;

  final SyncEtat sync;
  final String? messageErreur;

  /// La caserne est suspendue : la base refuse toute écriture.
  final bool lectureSeule;

  /// Le dernier changement reçu d'un autre poste, s'il porte sur un créneau
  /// encore affiché.
  final ChangementDistant? distant;

  EtatPlanning copie({
    PeriodeSaisie? periode,
    PlanningMois? planning,
    bool? canalBranche,
    bool? creation,
    SyncEtat? sync,
    String? messageErreur,
    bool effacerMessage = false,
    bool? lectureSeule,
    ChangementDistant? distant,
    bool effacerDistant = false,
  }) => EtatPlanning(
    periode: periode ?? this.periode,
    planning: planning ?? this.planning,
    canalBranche: canalBranche ?? this.canalBranche,
    creation: creation ?? this.creation,
    sync: sync ?? this.sync,
    messageErreur: effacerMessage ? null : messageErreur ?? this.messageErreur,
    lectureSeule: lectureSeule ?? this.lectureSeule,
    distant: effacerDistant ? null : distant ?? this.distant,
  );
}

/// La construction du planning : création, attributions, effectif, temps réel.
///
/// **Séparé du contrôleur de la matrice, et pas par goût de la symétrie.** Les
/// deux lisent le même mois mais pas les mêmes données : saisir une case de
/// disponibilité n'a aucune raison de relire soixante-deux créneaux, et poser
/// une attribution n'a aucune raison de relire soixante lignes de matrice.
class PlanningController extends AsyncNotifier<EtatPlanning?> {
  /// Les retraits que ce poste vient de faire. Le canal nous renvoie nos
  /// propres suppressions : sans ce registre, l'écran s'annoncerait à lui-même
  /// « modifié par un autre administrateur ».
  final Set<String> _retraitsLocaux = <String>{};

  var _compteurLocal = 0;

  /// L'état du canal, gardé **hors de l'état d'écran**. L'abonnement se fait
  /// avant la première lecture : sans ce champ, l'annonce « abonné » arriverait
  /// alors qu'il n'y a encore rien à mettre à jour, et l'écran afficherait
  /// « Direct interrompu » sur un canal parfaitement vivant.
  bool _canalBranche = false;

  /// Les événements reçus entre l'abonnement et la première image. Ils sont
  /// rejoués sur l'état dès qu'il existe : la fenêtre est étroite, mais une
  /// attribution perdue est une garde qu'on croit pourvue.
  final List<EvenementPlanning> _enAttente = <EvenementPlanning>[];

  @override
  Future<EtatPlanning?> build() async {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (appartenance == null || !appartenance.estAdmin) return null;

    final periode = await ref.watch(periodeAdminProvider.future);
    if (periode == null) return null;

    _brancher(appartenance.stationId);

    final planning = await ref
        .read(planningRepositoryProvider)
        .lire(stationId: appartenance.stationId, periodeId: periode.id);

    final etat = EtatPlanning(
      periode: periode,
      planning: planning,
      canalBranche: _canalBranche,
    );

    if (_enAttente.isEmpty) return etat;

    // L'état doit exister avant d'être modifié : on le pose, puis on rejoue.
    state = AsyncValue<EtatPlanning?>.data(etat);
    final differes = <EvenementPlanning>[..._enAttente];
    _enAttente.clear();
    differes.forEach(_recevoir);
    return state.value ?? etat;
  }

  // -------------------------------------------------------------------
  // Le temps réel
  // -------------------------------------------------------------------

  void _brancher(String stationId) {
    final abonnement = ref
        .read(planningRepositoryProvider)
        .ecouter(stationId: stationId)
        .listen(_recevoir, onError: (Object _) => _canal(branche: false));

    ref.onDispose(abonnement.cancel);
  }

  void _canal({required bool branche}) {
    _canalBranche = branche;
    final courant = state.value;
    if (courant == null || courant.canalBranche == branche) return;
    state = AsyncValue<EtatPlanning?>.data(
      courant.copie(canalBranche: branche),
    );
  }

  /// Ce qui arrive de l'autre poste.
  ///
  /// **Rien ne bouge sous la main** : le défilement, le panneau ouvert et la
  /// sélection ne changent pas. Seuls les chiffres changent, et une mention
  /// s'affiche dans le panneau quand c'est le créneau ouvert qui a bougé.
  void _recevoir(EvenementPlanning evenement) {
    final courant = state.value;
    if (courant == null) {
      // Avant la première lecture : l'état du canal se retient, le reste
      // attend.
      if (evenement case EtatCanalPlanning(:final branche)) {
        _canalBranche = branche;
      } else {
        _enAttente.add(evenement);
      }
      return;
    }

    switch (evenement) {
      case EtatCanalPlanning(:final branche):
        _canal(branche: branche);

      case AttributionRecue(:final Attribution attribution):
        // Un créneau inconnu : une attribution d'un autre mois, ou d'un
        // planning qui n'est pas à l'écran. Rien à redessiner.
        if (courant.planning.creneauParId(attribution.creneauId) == null) {
          return;
        }
        if (courant.planning.attributionParId(attribution.id) == attribution) {
          return;
        }
        state = AsyncValue<EtatPlanning?>.data(
          courant.copie(
            planning: courant.planning.avecAttribution(attribution),
            distant: _distant(
              creneauId: attribution.creneauId,
              auteurId: attribution.auteurId,
            ),
          ),
        );

      case AttributionSupprimee(:final String id):
        final connue = courant.planning.attributionParId(id);
        if (connue == null) return;
        final propre = _retraitsLocaux.remove(id);
        state = AsyncValue<EtatPlanning?>.data(
          courant.copie(
            planning: courant.planning.sansAttribution(id),
            distant: propre
                ? null
                : _distant(creneauId: connue.creneauId),
          ),
        );
    }
  }

  /// La mention « modifié par… », et seulement si elle sert : le créneau doit
  /// être celui qui est ouvert, et l'auteur ne doit pas être nous.
  ChangementDistant? _distant({required String creneauId, String? auteurId}) {
    if (ref.read(creneauSelectionneProvider) != creneauId) return null;
    final moi = ref.read(sessionProvider).value?.userId;
    if (auteurId != null && auteurId == moi) return null;
    return ChangementDistant(creneauId: creneauId, auteurId: auteurId);
  }

  // -------------------------------------------------------------------
  // Les actions
  // -------------------------------------------------------------------

  /// Relit le planning **en le gardant à l'écran**.
  Future<void> rafraichir() async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    final courant = state.value;
    if (stationId == null || courant == null) return;

    try {
      final planning = await ref
          .read(planningRepositoryProvider)
          .lire(stationId: stationId, periodeId: courant.periode.id);
      if (!ref.mounted) return;
      state = AsyncValue<EtatPlanning?>.data(
        courant.copie(planning: planning, effacerMessage: true),
      );
    } on EchecPlanning catch (echec) {
      _echouer(echec);
    }
  }

  /// Crée le planning du mois et ses créneaux.
  Future<void> creer() async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    final courant = state.value;
    if (stationId == null || courant == null || courant.planning.existe) {
      return;
    }

    state = AsyncValue<EtatPlanning?>.data(
      courant.copie(creation: true, effacerMessage: true),
    );

    try {
      final planning = await ref
          .read(planningRepositoryProvider)
          .creer(stationId: stationId, periodeId: courant.periode.id);
      final apres = state.value;
      if (!ref.mounted || apres == null) return;
      state = AsyncValue<EtatPlanning?>.data(
        apres.copie(planning: planning, creation: false),
      );
    } on EchecPlanning catch (echec) {
      _echouer(echec, creation: false);
    }
  }

  /// Attribue un membre à un créneau.
  ///
  /// L'attribution apparaît **tout de suite**, avec un identifiant local, et
  /// prend celui de la base à la réponse. Si le serveur refuse, elle disparaît
  /// : la ligne des créneaux ne garde jamais un chiffre que la base ignore.
  /// Rend `null` si tout s'est bien passé, l'erreur sinon : c'est l'écran qui
  /// décide de la surface — une bannière pour un échec, une phrase passagère
  /// pour un doublon, qui n'est pas une panne mais l'autre administrateur.
  Future<ErreurPlanning?> attribuer({
    required String creneauId,
    required String userId,
  }) async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    final courant = state.value;
    if (stationId == null || courant == null || !courant.planning.modifiable) {
      return null;
    }

    final locale = Attribution(
      id: 'local:${_compteurLocal++}',
      creneauId: creneauId,
      userId: userId,
      locale: true,
    );

    state = AsyncValue<EtatPlanning?>.data(
      courant.copie(
        planning: courant.planning.avecAttribution(locale),
        sync: SyncEtat.enregistrement,
        effacerMessage: true,
        effacerDistant: true,
      ),
    );

    try {
      final posee = await ref
          .read(planningRepositoryProvider)
          .attribuer(
            stationId: stationId,
            creneauId: creneauId,
            userId: userId,
          );

      final apres = state.value;
      if (!ref.mounted || apres == null) return null;
      state = AsyncValue<EtatPlanning?>.data(
        apres.copie(
          planning: apres.planning
              .sansAttribution(locale.id)
              .avecAttribution(posee),
          sync: SyncEtat.enregistre,
        ),
      );
      return null;
    } on EchecPlanning catch (echec) {
      final apres = state.value;
      if (!ref.mounted || apres == null) return echec.erreur;
      state = AsyncValue<EtatPlanning?>.data(
        apres.copie(planning: apres.planning.sansAttribution(locale.id)),
      );
      _echouer(echec);
      return echec.erreur;
    }
  }

  /// Retire une attribution. **En brouillon, retirer supprime** : rien n'est
  /// parti, il n'y a rien à conserver (`docs/WORKFLOWS.md § 3`).
  ///
  /// Rend l'attribution retirée pour que l'écran puisse offrir « Annuler ».
  Future<Attribution?> retirer(String attributionId) async {
    final courant = state.value;
    final retiree = courant?.planning.attributionParId(attributionId);
    if (courant == null || retiree == null) return null;

    _retraitsLocaux.add(attributionId);
    state = AsyncValue<EtatPlanning?>.data(
      courant.copie(
        planning: courant.planning.sansAttribution(attributionId),
        sync: SyncEtat.enregistrement,
        effacerMessage: true,
        effacerDistant: true,
      ),
    );

    try {
      // Une attribution qui n'a jamais atteint la base n'a rien à y retirer.
      final accepte =
          retiree.locale ||
          await ref
              .read(planningRepositoryProvider)
              .retirer(attributionId: attributionId);
      if (!accepte) throw const EchecPlanning(ErreurPlanning.planningPublie);

      final apres = state.value;
      if (!ref.mounted || apres == null) return retiree;
      state = AsyncValue<EtatPlanning?>.data(
        apres.copie(sync: SyncEtat.enregistre),
      );
      return retiree;
    } on EchecPlanning catch (echec) {
      _retraitsLocaux.remove(attributionId);
      final apres = state.value;
      if (!ref.mounted || apres == null) return null;
      // La ligne revient : un retrait refusé n'a pas eu lieu.
      state = AsyncValue<EtatPlanning?>.data(
        apres.copie(planning: apres.planning.avecAttribution(retiree)),
      );
      _echouer(echec);
      return null;
    }
  }

  /// Change l'effectif requis d'un **seul** créneau.
  Future<void> definirEffectif({
    required String creneauId,
    required int effectif,
  }) async {
    final courant = state.value;
    final creneau = courant?.planning.creneauParId(creneauId);
    if (courant == null || creneau == null || effectif < 0) return;
    if (effectif == creneau.effectifRequis) return;

    state = AsyncValue<EtatPlanning?>.data(
      courant.copie(
        planning: courant.planning.avecEffectif(creneauId, effectif),
        sync: SyncEtat.enregistrement,
        effacerMessage: true,
      ),
    );

    try {
      final accepte = await ref
          .read(planningRepositoryProvider)
          .definirEffectif(creneauId: creneauId, effectif: effectif);
      if (!accepte) throw const EchecPlanning(ErreurPlanning.lectureSeule);

      final apres = state.value;
      if (!ref.mounted || apres == null) return;
      state = AsyncValue<EtatPlanning?>.data(
        apres.copie(sync: SyncEtat.enregistre),
      );
    } on EchecPlanning catch (echec) {
      final apres = state.value;
      if (!ref.mounted || apres == null) return;
      state = AsyncValue<EtatPlanning?>.data(
        apres.copie(
          planning: apres.planning.avecEffectif(
            creneauId,
            creneau.effectifRequis,
          ),
        ),
      );
      _echouer(echec);
    }
  }

  /// La mention de changement distant s'efface au geste suivant.
  void effacerDistant() {
    final courant = state.value;
    if (courant == null || courant.distant == null) return;
    state = AsyncValue<EtatPlanning?>.data(
      courant.copie(effacerDistant: true),
    );
  }

  void _echouer(EchecPlanning echec, {bool? creation}) {
    final courant = state.value;
    if (!ref.mounted || courant == null) return;

    // Une caserne suspendue a sa propre bannière : la doubler d'une bannière
    // d'erreur dirait deux fois la même chose. Un doublon d'attribution non
    // plus : il se dit d'une phrase passagère, à l'endroit du geste.
    final suspendue = echec.erreur == ErreurPlanning.lectureSeule;
    final passagere = echec.erreur == ErreurPlanning.dejaAttribue;
    state = AsyncValue<EtatPlanning?>.data(
      courant.copie(
        sync: SyncEtat.echec,
        creation: creation,
        messageErreur: suspendue || passagere ? null : echec.message,
        effacerMessage: suspendue || passagere,
        lectureSeule: courant.lectureSeule || suspendue,
      ),
    );
  }
}

final AsyncNotifierProvider<PlanningController, EtatPlanning?>
planningControllerProvider =
    AsyncNotifierProvider<PlanningController, EtatPlanning?>(
      PlanningController.new,
      isAutoDispose: true,
    );

/// Les lignes de la matrice, **avec la charge du mois telle qu'elle est à
/// l'écran**.
///
/// C'est le critère d'acceptation du ticket : « les quotas de la ligne membre
/// se mettent à jour à chaque attribution ». Ils se mettent à jour **sans
/// relire la matrice** — le compte est le même que celui de `v_member_load`,
/// fait sur les attributions déjà chargées.
final Provider<List<LigneMatrice>> lignesAvecChargeProvider =
    Provider<List<LigneMatrice>>((ref) {
      final matrice = ref.watch(matriceControllerProvider).value;
      if (matrice == null) return const <LigneMatrice>[];

      final etat = ref.watch(planningControllerProvider).value;
      if (etat == null || !etat.planning.existe) return matrice.matrice.lignes;

      final charges = etat.planning.charges(
        annee: etat.periode.annee,
        mois: etat.periode.mois,
      );

      return <LigneMatrice>[
        for (final ligne in matrice.matrice.lignes)
          ligne.avecCharge(
            astreintes: charges[ligne.userId]?.astreintes ?? 0,
            unitesWeekend: charges[ligne.userId]?.unitesWeekend ?? 0,
          ),
      ];
    });

/// Les lignes réellement affichées : filtrées, triées, **sans requête**.
///
/// Elle vit ici et non avec les autres providers de la matrice parce qu'elle
/// dépend désormais des deux : la charge d'un membre change avec les
/// attributions, et le tri « Astreintes restantes » doit suivre.
///
/// Mémorisé par Riverpod : le tri de soixante lignes n'est refait que si la
/// matrice, le planning ou les filtres changent, pas à chaque image.
final Provider<List<LigneMatrice>> lignesVisiblesProvider =
    Provider<List<LigneMatrice>>((ref) {
      final lignes = ref.watch(lignesAvecChargeProvider);
      if (lignes.isEmpty) return const <LigneMatrice>[];
      return ref.watch(filtresMatriceProvider).appliquer(lignes);
    });

/// Ce que le panneau du créneau ouvert affiche, ou `null` si rien n'est
/// ouvert.
///
/// **Mémorisé par Riverpod** : le tri des candidats n'est refait que si la
/// sélection, le planning ou la matrice changent — pas à chaque image.
final Provider<PanneauCandidats?> panneauCandidatsProvider =
    Provider<PanneauCandidats?>((ref) {
      final creneauId = ref.watch(creneauSelectionneProvider);
      if (creneauId == null) return null;

      final etat = ref.watch(planningControllerProvider).value;
      final creneau = etat?.planning.creneauParId(creneauId);
      if (etat == null || creneau == null) return null;

      final membres = ref.watch(lignesAvecChargeProvider);
      if (membres.isEmpty) return null;

      return PanneauCandidats.construire(
        creneau: creneau,
        jour: DateTime(etat.periode.annee, etat.periode.mois, creneau.jour),
        // **Les lignes entières, pas les lignes filtrées** : chercher
        // « Dubois » dans la matrice ne doit pas faire disparaître les
        // candidats des autres créneaux.
        membres: membres,
        planning: etat.planning,
        modifiable: etat.planning.modifiable && !etat.lectureSeule,
      );
    });
