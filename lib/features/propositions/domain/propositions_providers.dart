import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/caserne/caserne_providers.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/theme/app_status.dart';
import '../data/propositions_repository.dart';
import 'proposition.dart';

/// Le dépôt des propositions. Surchargé par un faux dans les tests.
final Provider<PropositionsRepository> propositionsRepositoryProvider =
    Provider<PropositionsRepository>(
      (ref) =>
          SupabasePropositionsRepository(ref.watch(supabaseClientProvider)),
    );

/// Ce que l'écran a à dire en plus de sa liste, et qui vient de se produire.
///
/// Trois nouvelles, trois surfaces différentes, **une seule à la fois** :
/// l'écran affiche la plus récente.
sealed class NouvellePropositions {
  const NouvellePropositions();
}

/// La réponse est partie. Le message passager le dit, et rien d'autre.
final class ReponseEnvoyee extends NouvellePropositions {
  const ReponseEnvoyee({required this.proposition, required this.accepte});

  final Proposition proposition;
  final bool accepte;
}

/// L'attribution n'était plus proposée. Elle a été annulée ou confiée à
/// quelqu'un d'autre pendant que le pompier lisait sa notification.
final class PropositionDisparue extends NouvellePropositions {
  const PropositionDisparue(this.proposition);

  final Proposition proposition;
}

/// La réponse n'est pas partie : la ligne est revenue à sa place.
final class ReponseEchouee extends NouvellePropositions {
  const ReponseEchouee({required this.proposition, required this.message});

  final Proposition proposition;
  final String message;
}

/// Cette acceptation était la dernière que le planning attendait : il vient de
/// se valider tout seul (`schedule_auto_validate`, migration 0019).
final class PlanningValide extends NouvellePropositions {
  const PlanningValide(this.nomMois);

  /// « octobre » — le mois du **créneau**, qui est celui du planning par
  /// construction. Pas le mois courant : une réponse donnée le 31 octobre sur
  /// un créneau de novembre nommerait sinon le mauvais mois.
  final String nomMois;
}

/// Ce que l'écran des propositions affiche.
@immutable
class EtatPropositions {
  const EtatPropositions({
    this.propositions = const <Proposition>[],
    this.lectureSeule = false,
    this.nouvelle,
  });

  final List<Proposition> propositions;

  /// La caserne est suspendue : on lit, on ne répond plus.
  final bool lectureSeule;

  /// La dernière nouvelle, ou `null`. L'écran la consomme et l'efface.
  final NouvellePropositions? nouvelle;

  bool get vide => propositions.isEmpty;

  /// Le nombre porté par la pastille de l'onglet. **C'est la liste affichée
  /// qui le donne**, jamais une seconde requête : deux sources pour un nombre,
  /// ce sont deux nombres différents un jour sur dix.
  int get enAttente => propositions.length;

  EtatPropositions copie({
    List<Proposition>? propositions,
    bool? lectureSeule,
    NouvellePropositions? nouvelle,
    bool effacerNouvelle = false,
  }) => EtatPropositions(
    propositions: propositions ?? this.propositions,
    lectureSeule: lectureSeule ?? this.lectureSeule,
    nouvelle: effacerNouvelle ? null : nouvelle ?? this.nouvelle,
  );
}

/// Les propositions du membre connecté : lecture, réponse, rafraîchissement.
///
/// **Non auto-disposé, volontairement** : la pastille de l'onglet lit ce même
/// état depuis la coquille d'accueil, donc depuis tous les écrans. Auto-
/// disposé, le compte repartirait de zéro — donc disparaîtrait une fraction de
/// seconde — à chaque changement d'onglet. Même raisonnement que le centre de
/// notifications (ticket 026).
class PropositionsController extends AsyncNotifier<EtatPropositions> {
  @override
  Future<EtatPropositions> build() async {
    final session = ref.watch(sessionProvider).value;
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (session == null || appartenance == null) {
      return const EtatPropositions();
    }

    return EtatPropositions(
      propositions: await _lire(
        userId: session.userId,
        stationId: appartenance.stationId,
      ),
      // Su **avant** la première réponse depuis le ticket 030 : les deux
      // boutons de chaque ligne naissent grisés avec leur raison, au lieu de le
      // devenir après un refus du serveur.
      lectureSeule: ref.watch(lectureSeuleCaserneProvider),
    );
  }

  Future<List<Proposition>> _lire({
    required String userId,
    required String stationId,
  }) => ref
      .read(propositionsRepositoryProvider)
      .lister(userId: userId, stationId: stationId);

  /// Relit la liste **en la gardant à l'écran** : un rafraîchissement ne vide
  /// pas la page sous les yeux de qui la lit.
  Future<void> rafraichir() async {
    final session = ref.read(sessionProvider).value;
    final appartenance = ref.read(appartenanceCouranteProvider);
    if (session == null || appartenance == null) return;

    final courant = state.value ?? const EtatPropositions();
    try {
      final propositions = await _lire(
        userId: session.userId,
        stationId: appartenance.stationId,
      );
      if (!ref.mounted) return;
      state = AsyncValue<EtatPropositions>.data(
        courant.copie(propositions: propositions, effacerNouvelle: true),
      );
    } on EchecProposition catch (echec) {
      if (!ref.mounted) return;
      // Une liste déjà à l'écran ne se remplace pas par une erreur : elle
      // reste, et la nouvelle le dit.
      if (courant.propositions.isEmpty) {
        state = AsyncValue<EtatPropositions>.error(
          echec,
          StackTrace.current,
        );
      } else {
        state = AsyncValue<EtatPropositions>.data(
          courant.copie(
            lectureSeule:
                echec.erreur == ErreurProposition.lectureSeule ||
                courant.lectureSeule,
          ),
        );
      }
    }
  }

  /// Accepte ou refuse.
  ///
  /// **Optimiste** : la ligne part tout de suite et l'écriture suit. En 4G
  /// rurale, un aller-retour coûte de 300 ms à 3 s, et un écran qui attend
  /// transforme « deux touches » en « deux touches et une attente »
  /// (`design/021 § 7.1`).
  Future<void> repondre(
    Proposition proposition, {
    required bool accepte,
    String? motif,
  }) async {
    final courant = state.value;
    if (courant == null) return;

    // Le geste est déjà parti : une seconde touche sur la même ligne ne doit
    // rien renvoyer.
    final index = courant.propositions.indexWhere(
      (Proposition autre) => autre.id == proposition.id,
    );
    if (index < 0) return;

    final restantes = <Proposition>[...courant.propositions]..removeAt(index);
    state = AsyncValue<EtatPropositions>.data(
      courant.copie(propositions: restantes, effacerNouvelle: true),
    );

    try {
      final resultat = await ref
          .read(propositionsRepositoryProvider)
          .repondre(
            attributionId: proposition.id,
            accepte: accepte,
            motif: motif,
          );
      if (!ref.mounted) return;

      if (resultat == ResultatReponse.disparue) {
        _annoncer(PropositionDisparue(proposition));
        return;
      }

      _annoncer(
        ReponseEnvoyee(proposition: proposition, accepte: accepte),
      );

      // La dernière acceptation d'un planning est la seule qui puisse l'avoir
      // validé. Inutile d'aller le demander pour les autres.
      if (accepte &&
          !restantes.any(
            (Proposition autre) => autre.planningId == proposition.planningId,
          )) {
        await _constaterValidation(proposition);
      }
    } on EchecProposition catch (echec) {
      if (!ref.mounted) return;
      _restaurer(proposition, index);
      if (echec.erreur == ErreurProposition.lectureSeule) {
        final apres = state.value;
        if (apres != null) {
          state = AsyncValue<EtatPropositions>.data(
            apres.copie(lectureSeule: true),
          );
        }
        return;
      }
      _annoncer(
        ReponseEchouee(proposition: proposition, message: echec.message),
      );
    }
  }

  /// Remet une ligne à **sa place exacte**. Une réponse qui échoue ne doit pas
  /// renvoyer le créneau en bas de liste : le pouce le cherche là où il était.
  void _restaurer(Proposition proposition, int index) {
    final courant = state.value;
    if (courant == null) return;
    if (courant.propositions.any(
      (Proposition autre) => autre.id == proposition.id,
    )) {
      return;
    }

    final liste = <Proposition>[...courant.propositions];
    liste.insert(index.clamp(0, liste.length), proposition);
    state = AsyncValue<EtatPropositions>.data(
      courant.copie(propositions: liste),
    );
  }

  Future<void> _constaterValidation(Proposition proposition) async {
    final etat = await ref
        .read(propositionsRepositoryProvider)
        .etatPlanning(proposition.planningId);
    if (!ref.mounted || etat != PlanningEtat.valide) return;
    _annoncer(PlanningValide(proposition.nomMois));
  }

  void _annoncer(NouvellePropositions nouvelle) {
    final courant = state.value;
    if (courant == null) return;
    state = AsyncValue<EtatPropositions>.data(
      courant.copie(nouvelle: nouvelle),
    );
  }

  /// L'écran a montré la nouvelle : elle ne doit pas revenir au prochain
  /// rendu.
  void nouvelleLue() {
    final courant = state.value;
    if (courant?.nouvelle == null) return;
    state = AsyncValue<EtatPropositions>.data(
      courant!.copie(effacerNouvelle: true),
    );
  }
}

final AsyncNotifierProvider<PropositionsController, EtatPropositions>
propositionsControllerProvider =
    AsyncNotifierProvider<PropositionsController, EtatPropositions>(
      PropositionsController.new,
    );

/// Le nombre affiché par la pastille de l'onglet « Propositions ».
///
/// Zéro tant que la liste n'est pas arrivée : une pastille qui apparaît vaut
/// mieux qu'une pastille qui ment.
final Provider<int> propositionsEnAttenteProvider = Provider<int>(
  (ref) => ref.watch(propositionsControllerProvider).value?.enAttente ?? 0,
);

/// Les éléments réellement affichés — en-têtes de mois compris — construits
/// **une fois par état** et mémorisés. Le tri de soixante-deux propositions
/// n'a aucune raison de se refaire à chaque image de défilement.
final Provider<List<ElementListe>> elementsPropositionsProvider =
    Provider<List<ElementListe>>((ref) {
      final etat = ref.watch(propositionsControllerProvider).value;
      if (etat == null) return const <ElementListe>[];
      return aplatir(etat.propositions);
    });
