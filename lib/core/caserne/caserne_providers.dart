import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// Lu **une fois par session d'écran** et pas à chaque geste : une suspension
/// est un événement de facturation, pas un état qui change à la minute. Les
/// écrans qui essuient un refus serveur relisent, eux, par [relireEtatCaserne].
///
/// Ne rend jamais d'erreur : [CaserneRepository.lire] absorbe tout et retombe
/// sur [EtatCaserne.inconnue]. C'est ce qui permet aux écrans de lire
/// `.value ?? EtatCaserne.inconnue` sans traiter un troisième cas.
final FutureProvider<EtatCaserne> etatCaserneProvider =
    FutureProvider<EtatCaserne>((ref) async {
      final appartenance = ref.watch(appartenanceCouranteProvider);
      if (appartenance == null) return EtatCaserne.inconnue;
      return ref.watch(caserneRepositoryProvider).lire(appartenance.stationId);
    });

/// Vrai quand la caserne est en lecture seule.
///
/// **Faux tant qu'on ne sait pas.** Un écran qui se grise pendant la seconde
/// de chargement puis se dégrise clignote, et le clignotement ment une fois
/// sur deux ; le refus serveur reste le filet, comme avant ce ticket.
final Provider<bool> lectureSeuleCaserneProvider = Provider<bool>(
  (ref) => ref.watch(etatCaserneProvider).value?.lectureSeule ?? false,
);
