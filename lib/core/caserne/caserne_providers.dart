import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fraicheur/relecture.dart';
import '../session/caserne_ouverte.dart';
import '../session/session_providers.dart';
import '../supabase/supabase_bootstrap.dart';
import 'caserne_repository.dart';
import 'etat_caserne.dart';

/// Le dépôt de l'état de caserne. Surchargé par un faux dans les tests.
final Provider<CaserneRepository> caserneRepositoryProvider =
    Provider<CaserneRepository>(
      (ref) => SupabaseCaserneRepository(ref.watch(supabaseClientProvider)),
    );

/// L'horloge des bannières d'échéance, pour que « il reste 3 jours » se teste
/// sans attendre trois jours.
final Provider<DateTime Function()> horlogeCaserneProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// L'état d'abonnement de la caserne courante.
///
/// Lu à l'ouverture de la session, puis **relu** par [EtatCaserneController.relire]
/// — la `relireEtatCaserne` que ce commentaire promettait avant le ticket 070
/// sans qu'elle existe. Trois moments la demandent :
///
/// - le **retour au premier plan** (coordinateur `core/fraicheur`) : un
///   paiement fait dans l'onglet de Stripe, ou une suspension tombée pendant
///   que la PWA était rangée, ne doivent pas attendre un redémarrage ;
/// - le **retour de la page de paiement** (`AbonnementController`) ;
/// - un **refus `42501`** : avant de dire « lecture seule », l'écran demande à
///   `station_access` si c'est vrai (même règle que l'app iOS au ticket 068,
///   `docs/IOS.md § 4 sexies`). Un refus sur une caserne qui écrit n'est pas
///   une suspension.
///
/// Ne rend jamais d'erreur : [CaserneRepository.lire] absorbe tout et retombe
/// sur [EtatCaserne.inconnue]. C'est ce qui permet aux écrans de lire
/// `.value ?? EtatCaserne.inconnue` sans traiter un troisième cas.
class EtatCaserneController extends AsyncNotifier<EtatCaserne> {
  @override
  Future<EtatCaserne> build() async {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (appartenance == null) return EtatCaserne.inconnue;
    return ref.watch(caserneRepositoryProvider).lire(appartenance.stationId);
  }

  /// Relit `station_access` **sans passer par un état de chargement**.
  ///
  /// Ne publie que si l'état a changé : la saisie, la matrice, les
  /// propositions et le suivi le lisent tous, et le republier à l'identique
  /// les reconstruirait pour rien. Une lecture qui n'aboutit pas garde l'état
  /// connu — une caserne suspendue ne redevient pas ouverte dans un tunnel.
  ///
  /// [publierSi] est consulté **après** la lecture, juste avant de publier :
  /// un changement reconstruit la saisie, et un doigt a pu se poser pendant
  /// l'attente.
  Future<Relecture> relire({bool Function()? publierSi}) async {
    if (state.isLoading) return Relecture.inchangee;
    final appartenance = ref.read(appartenanceCouranteProvider);
    if (appartenance == null) return Relecture.inchangee;

    EtatCaserne? lu;
    try {
      lu = await ref
          .read(caserneRepositoryProvider)
          .essayer(appartenance.stationId);
    } on Object {
      // `essayer` ne lève pas ; un dépôt qui n'a pas pu naître, si.
      lu = null;
    }
    if (!ref.mounted ||
        ref.read(appartenanceCouranteProvider)?.stationId !=
            appartenance.stationId ||
        state.isLoading) {
      return Relecture.inchangee;
    }
    if (lu == null) return Relecture.echouee;
    if (state.value == lu) return Relecture.inchangee;
    if (publierSi != null && !publierSi()) return Relecture.retenue;

    state = AsyncData<EtatCaserne>(lu);
    return Relecture.publiee;
  }

  /// **Le verdict d'un refus `42501`** : vrai seulement si `station_access`,
  /// relu à l'instant, dit que la caserne n'écrit plus.
  ///
  /// Faux si elle écrit. Si la relecture n'aboutit pas, c'est l'état déjà
  /// connu qui répond — et il n'a jamais été « suspendu » par supposition :
  /// un refus inexpliqué reste neutre (`docs/IOS.md § 4 sexies`).
  Future<bool> suspendueApresRefus() async {
    // La première lecture est peut-être encore en vol : c'est elle qui répond.
    if (state.isLoading) {
      try {
        await future;
      } on Object {
        // `build` ne lève pas ; s'il le faisait, la relecture qui suit tranche.
      }
      if (!ref.mounted) return false;
    }
    await relire();
    if (!ref.mounted) return false;
    return state.value?.lectureSeule ?? false;
  }
}

final AsyncNotifierProvider<EtatCaserneController, EtatCaserne>
etatCaserneProvider =
    AsyncNotifierProvider<EtatCaserneController, EtatCaserne>(
      EtatCaserneController.new,
    );

/// La même source, sans rien de ce qui a été lu dans une autre caserne
/// (ticket 072, `core/session/caserne_ouverte.dart`).
final Provider<AsyncValue<EtatCaserne>> etatCaserneOuvertProvider =
    dansLaCaserneOuverte(etatCaserneProvider);

/// Vrai quand la caserne est en lecture seule.
///
/// **Faux tant qu'on ne sait pas.** Un écran qui se grise pendant la seconde
/// de chargement puis se dégrise clignote, et le clignotement ment une fois
/// sur deux ; le refus serveur reste le filet, comme avant ce ticket.
final Provider<bool> lectureSeuleCaserneProvider = Provider<bool>(
  (ref) =>
      caserneOuverteSeulement(ref, etatCaserneProvider).value?.lectureSeule ??
      false,
);
