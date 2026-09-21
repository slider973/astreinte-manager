import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/cache_planning_caserne.dart';
import '../data/planning_caserne_repository.dart';
import 'astreintes_providers.dart';
import 'planning_caserne.dart';

/// Le dépôt du planning de la caserne. Surchargé par un faux dans les tests.
final Provider<PlanningCaserneRepository> planningCaserneRepositoryProvider =
    Provider<PlanningCaserneRepository>(
      (ref) =>
          SupabasePlanningCaserneRepository(ref.watch(supabaseClientProvider)),
    );

/// La portée de l'écran « Astreintes ».
///
/// « Moi » et « La caserne » lisent la **même** table sous la **même**
/// politique : ce sont deux filtres d'une donnée, pas deux écrans
/// (`design/027 § 4`, `design/023 § 2`).
enum PorteeAstreintes { moi, caserne }

/// La portée choisie. Un provider plutôt qu'un `setState` : la barre
/// d'application en dépend, et elle est construite par la coquille.
///
/// **« Moi » à chaque ouverture de l'application** : la question qui amène un
/// pompier ici est d'abord la sienne.
class PorteeChoisie extends Notifier<PorteeAstreintes> {
  @override
  PorteeAstreintes build() => PorteeAstreintes.moi;

  void choisir(PorteeAstreintes portee) => state = portee;
}

final NotifierProvider<PorteeChoisie, PorteeAstreintes> porteeAstreintesProvider =
    NotifierProvider<PorteeChoisie, PorteeAstreintes>(PorteeChoisie.new);

/// Ce que la vue « La caserne » affiche.
@immutable
class EtatPlanningCaserne {
  const EtatPlanningCaserne({
    this.mois = const <MoisPlanning>[],
    this.affiche,
    this.planning,
    this.chargement = false,
    this.introuvable = false,
    this.depuisCache = false,
    this.echec,
  });

  /// Les mois atteignables, dans l'ordre du calendrier. Vide quand aucun
  /// planning n'est publié — l'état vide de l'écran.
  final List<MoisPlanning> mois;

  /// Le mois affiché. `null` quand [mois] est vide.
  final MoisPlanning? affiche;

  /// Son contenu. `null` tant qu'il n'a pas été lu.
  final PlanningCaserne? planning;

  /// Vrai pendant qu'un mois se charge **sans rien à montrer** : c'est ce qui
  /// pose le squelette plutôt qu'un écran blanc.
  final bool chargement;

  /// Vrai quand le mois affiché n'a plus de planning lisible — archivé ou
  /// supprimé entre la lecture de la liste et celle du mois.
  final bool introuvable;

  /// Vrai quand ce qui est à l'écran vient du **stockage local** et n'a pas
  /// encore été confirmé par une lecture réussie.
  final bool depuisCache;

  /// La phrase de la dernière lecture qui a échoué **alors qu'il y avait déjà
  /// quelque chose à l'écran**.
  final String? echec;

  /// Vrai quand aucun planning n'est publié dans cette caserne.
  bool get aucunPlanning => mois.isEmpty;

  /// Le mois précédent atteignable, ou `null` sur la borne. Le sélecteur marche
  /// **de planning en planning**, pas de mois en mois.
  MoisPlanning? get precedent => _voisin(-1);

  MoisPlanning? get suivant => _voisin(1);

  MoisPlanning? _voisin(int pas) {
    final courant = affiche;
    if (courant == null) return null;
    final index = mois.indexWhere(
      (MoisPlanning candidat) => candidat.cle == courant.cle,
    );
    if (index < 0) return null;
    final cible = index + pas;
    return cible >= 0 && cible < mois.length ? mois[cible] : null;
  }

  EtatPlanningCaserne copie({
    List<MoisPlanning>? mois,
    MoisPlanning? affiche,
    PlanningCaserne? Function()? planning,
    bool? chargement,
    bool? introuvable,
    bool? depuisCache,
    String? Function()? echec,
  }) => EtatPlanningCaserne(
    mois: mois ?? this.mois,
    affiche: affiche ?? this.affiche,
    planning: planning == null ? this.planning : planning(),
    chargement: chargement ?? this.chargement,
    introuvable: introuvable ?? this.introuvable,
    depuisCache: depuisCache ?? this.depuisCache,
    echec: echec == null ? this.echec : echec(),
  );
}

/// Le planning de la caserne, mois par mois.
///
/// **Le cache est la première source, la requête la seconde**, exactement comme
/// « Mes astreintes » (`design/027 § 3`) : `build` rend ce qui est gardé sans
/// attendre le réseau, et l'écran demande le rafraîchissement dès sa première
/// image.
///
/// **Non auto-disposé** : passer sur « Moi » et revenir ne doit pas rejouer un
/// squelette ni perdre le mois qu'on regardait.
class PlanningCaserneController extends AsyncNotifier<EtatPlanningCaserne> {
  @override
  Future<EtatPlanningCaserne> build() async {
    final session = ref.watch(sessionProvider).value;
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (session == null || appartenance == null) {
      return const EtatPlanningCaserne();
    }

    final cache = ref.read(cachePlanningCaserneProvider);
    final gardes = await cache.lireMois(
      stationId: appartenance.stationId,
      userId: session.userId,
    );
    if (gardes == null || gardes.isEmpty) {
      return const EtatPlanningCaserne(chargement: true);
    }

    final affiche = moisDouverturePlanning(gardes, _maintenant);
    final planning = affiche == null
        ? null
        : await cache.lirePlanning(
            stationId: appartenance.stationId,
            userId: session.userId,
            cleMois: affiche.cle,
          );

    // L'écran est déjà lisible. C'est lui qui demandera mieux, à sa première
    // image : poser la requête ici, avant que `state` existe, serait courir
    // contre la fin de `build`.
    return EtatPlanningCaserne(
      mois: gardes,
      affiche: affiche,
      planning: planning,
      chargement: planning == null,
      depuisCache: true,
    );
  }

  DateTime get _maintenant => ref.read(horlogeAstreintesProvider)();

  /// Relit la liste des mois **et** le mois affiché, sans vider l'écran.
  ///
  /// Un rafraîchissement ne vide jamais la page sous les yeux de qui la lit :
  /// il remplace ou il pose un bandeau, jamais les deux, jamais rien d'autre.
  Future<void> rafraichir() async {
    final session = ref.read(sessionProvider).value;
    final appartenance = ref.read(appartenanceCouranteProvider);
    if (session == null || appartenance == null) return;

    final courant = state.value ?? const EtatPlanningCaserne();
    try {
      final mois = await ref
          .read(planningCaserneRepositoryProvider)
          .moisLisibles(stationId: appartenance.stationId);
      if (!ref.mounted) return;

      await ref
          .read(cachePlanningCaserneProvider)
          .ecrireMois(
            stationId: appartenance.stationId,
            userId: session.userId,
            mois: mois,
          );
      if (!ref.mounted) return;

      if (mois.isEmpty) {
        state = const AsyncValue<EtatPlanningCaserne>.data(
          EtatPlanningCaserne(),
        );
        return;
      }

      // Le mois regardé est gardé s'il existe toujours : un rafraîchissement ne
      // ramène personne au mois d'ouverture.
      final vise =
          mois.firstWhere(
            (MoisPlanning candidat) => candidat.cle == courant.affiche?.cle,
            orElse: () =>
                moisDouverturePlanning(mois, _maintenant) ?? mois.first,
          );

      state = AsyncValue<EtatPlanningCaserne>.data(
        courant.copie(
          mois: mois,
          affiche: vise,
          chargement: courant.planning?.mois.cle != vise.cle,
          introuvable: false,
          echec: () => null,
        ),
      );
      await _chargerMois(vise);
    } on EchecPlanningCaserne catch (echec) {
      if (!ref.mounted) return;
      _poserEchec(courant, echec);
    }
  }

  /// Va au mois demandé : **le cache d'abord**, la requête ensuite.
  Future<void> allerAu(MoisPlanning mois) async {
    final session = ref.read(sessionProvider).value;
    final appartenance = ref.read(appartenanceCouranteProvider);
    if (session == null || appartenance == null) return;

    final courant = state.value ?? const EtatPlanningCaserne();
    if (courant.affiche?.cle == mois.cle && courant.planning != null) return;

    final garde = await ref
        .read(cachePlanningCaserneProvider)
        .lirePlanning(
          stationId: appartenance.stationId,
          userId: session.userId,
          cleMois: mois.cle,
        );
    if (!ref.mounted) return;

    state = AsyncValue<EtatPlanningCaserne>.data(
      courant.copie(
        affiche: mois,
        planning: () => garde,
        chargement: garde == null,
        introuvable: false,
        depuisCache: garde != null,
        echec: () => null,
      ),
    );

    await _chargerMois(mois);
  }

  /// Lit un mois du serveur et l'affiche s'il est toujours celui qu'on regarde.
  Future<void> _chargerMois(MoisPlanning mois) async {
    final session = ref.read(sessionProvider).value;
    final appartenance = ref.read(appartenanceCouranteProvider);
    if (session == null || appartenance == null) return;

    try {
      final planning = await ref
          .read(planningCaserneRepositoryProvider)
          .lireMois(
            stationId: appartenance.stationId,
            userId: session.userId,
            mois: mois,
          );
      if (!ref.mounted) return;

      final courant = state.value ?? const EtatPlanningCaserne();
      // Le mois a changé pendant la requête : la réponse ne concerne plus
      // l'écran, et l'écrire ferait sauter la vue sous les doigts.
      if (courant.affiche?.cle != mois.cle) return;

      if (planning == null) {
        state = AsyncValue<EtatPlanningCaserne>.data(
          courant.copie(
            planning: () => null,
            chargement: false,
            introuvable: true,
            depuisCache: false,
            echec: () => null,
          ),
        );
        return;
      }

      await ref
          .read(cachePlanningCaserneProvider)
          .ecrirePlanning(
            stationId: appartenance.stationId,
            userId: session.userId,
            planning: planning,
          );
      if (!ref.mounted) return;

      state = AsyncValue<EtatPlanningCaserne>.data(
        (state.value ?? courant).copie(
          planning: () => planning,
          chargement: false,
          introuvable: false,
          depuisCache: false,
          echec: () => null,
        ),
      );
    } on EchecPlanningCaserne catch (echec) {
      if (!ref.mounted) return;
      _poserEchec(state.value ?? const EtatPlanningCaserne(), echec);
    }
  }

  /// Pose l'échec là où il se voit : en bandeau quand il reste quelque chose à
  /// l'écran, en erreur pleine quand il n'y a rien du tout.
  void _poserEchec(EtatPlanningCaserne courant, EchecPlanningCaserne echec) {
    if (courant.mois.isEmpty) {
      state = AsyncValue<EtatPlanningCaserne>.error(echec, StackTrace.current);
      return;
    }
    state = AsyncValue<EtatPlanningCaserne>.data(
      courant.copie(
        chargement: false,
        depuisCache: true,
        echec: () => echec.message,
      ),
    );
  }
}

final AsyncNotifierProvider<PlanningCaserneController, EtatPlanningCaserne>
planningCaserneControllerProvider =
    AsyncNotifierProvider<PlanningCaserneController, EtatPlanningCaserne>(
      PlanningCaserneController.new,
    );
