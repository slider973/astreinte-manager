import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'appartenance.dart';
import 'session_providers.dart';

/// L'identifiant de la caserne ouverte, ou `null` sans caserne.
///
/// Un `select` sur l'appartenance courante : un rôle ou un nom d'usage relu
/// (ticket 070) ne le fait pas changer, seule une bascule le fait.
final Provider<String?> caserneOuverteIdProvider = Provider<String?>(
  (ref) => ref.watch(
    appartenanceCouranteProvider.select(
      (Appartenance? appartenance) => appartenance?.stationId,
    ),
  ),
);

/// La caserne de la dernière valeur **établie** d'une source, par conteneur.
class _Memoire {
  String? caserne;
}

/// **Une source, sans rien de ce qui a été lu dans une autre caserne**
/// (ticket 072).
///
/// Riverpod garde la valeur précédente d'un fournisseur asynchrone pendant
/// qu'il se recalcule (`AsyncLoading` qui `hasValue`), et la garde encore sur
/// l'erreur qui suit. C'est voulu d'ordinaire — un mois qui change ne vide pas
/// l'écran —, mais pas après une bascule : l'accueil de la caserne Sud
/// afficherait les propositions de la caserne Nord jusqu'à la première réponse,
/// et, hors ligne, pour toujours. Le constat iOS (`AppStore.swift:259-263`) est
/// exactement ce défaut.
///
/// Le fournisseur rendu :
///
/// - laisse passer toute valeur **établie** (donnée sans chargement en cours),
///   et retient qu'elle appartient à la caserne ouverte à cet instant ;
/// - tant que la source se recalcule ou échoue avec une valeur d'une **autre**
///   caserne, rend un chargement nu, ou l'erreur seule : l'écran montre son
///   squelette ou son « Réessayer », jamais l'ancienne caserne ;
/// - une valeur dont la caserne n'est pas connue (le fournisseur dérivé est né
///   après elle) n'est retenue que si la source ne se recalcule pas.
///
/// La mémoire est rangée par conteneur : deux tests, deux mémoires.
///
/// Pour les écrans. Un fournisseur dérivé lit plutôt [caserneOuverteSeulement]
/// en place : un maillon de plus dans une chaîne que seul un écran recouvert
/// lit se recalculerait pendant la construction de son retour, ce dont Riverpod
/// 3.3 se plaint (`composition_accueil.dart`).
///
/// [autoDispose] pour une source auto-disposée (les écrans d'administration) :
/// un dérivé permanent la garderait en vie, et avec elle ses lectures.
Provider<AsyncValue<T>> dansLaCaserneOuverte<T>(
  ProviderListenable<AsyncValue<T>> source, {
  bool autoDispose = false,
}) => Provider<AsyncValue<T>>(
  (ref) => caserneOuverteSeulement<T>(ref, source),
  isAutoDispose: autoDispose,
);

/// [source] lue par [ref], filtrée comme le dit [dansLaCaserneOuverte].
AsyncValue<T> caserneOuverteSeulement<T>(
  Ref ref,
  ProviderListenable<AsyncValue<T>> source,
) {
  final ouverte = ref.watch(caserneOuverteIdProvider);
  final valeur = ref.watch<AsyncValue<T>>(source);
  final parSource = _memoires[ref.container] ??= <Object, _Memoire>{};
  final memoire = parSource[source] ??= _Memoire();
  return _filtrer<T>(valeur, ouverte: ouverte, memoire: memoire);
}

final Expando<Map<Object, _Memoire>> _memoires = Expando<Map<Object, _Memoire>>(
  'caserne des données',
);

AsyncValue<T> _filtrer<T>(
  AsyncValue<T> valeur, {
  required String? ouverte,
  required _Memoire memoire,
}) {
  final souvenir = memoire;
  if (valeur is AsyncData<T> && !valeur.isLoading) {
    souvenir.caserne = ouverte;
    return valeur;
  }
  if (!valeur.hasValue) return valeur;

  final connue = souvenir.caserne;
  final etrangere = connue == null ? valeur.isReloading : connue != ouverte;
  if (!etrangere) return valeur;

  final erreur = valeur.error;
  if (erreur != null && !valeur.isLoading) {
    return AsyncError<T>(erreur, valeur.stackTrace ?? StackTrace.current);
  }
  return AsyncLoading<T>();
}
