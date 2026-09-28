import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L'issue d'une relecture **discrète** : retour au premier plan, ouverture
/// d'un écran, tirer pour actualiser, événement reçu (tickets 068 et 070).
///
/// Une relecture discrète ne passe jamais par un état de chargement : elle
/// garde l'écran à l'écran et ne publie que ce qui a changé.
enum Relecture {
  /// Rien de nouveau : rien n'a été publié.
  inchangee,

  /// Une valeur nouvelle a été publiée : ses lecteurs se reconstruisent.
  publiee,

  /// Une valeur nouvelle a été lue mais **pas publiée**, la condition de
  /// publication ayant refusé (une écriture ou un geste en cours) : elle sera
  /// relue plus tard.
  retenue,

  /// La lecture n'a pas abouti (réseau, refus) : ce qui est à l'écran reste,
  /// et le prochain retour réessaiera sans attendre le délai minimal.
  echouee,
}

/// L'horloge des relectures. Surchargée par une horloge figée dans les tests :
/// c'est elle qui décide si une relecture est « en rafale ».
///
/// Née au ticket 068 pour les périodes, elle vit dans `core` depuis le
/// ticket 070 : un seul rythme pour toutes les données relues.
final Provider<DateTime Function()> horlogeRafraichissementProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// **Le moment de la dernière lecture réseau aboutie** d'un contrôleur, première
/// lecture comprise (ticket 070).
///
/// C'est ce que le coordinateur (`core/fraicheur`) regarde avant de relire à
/// l'ouverture d'un écran : un contrôleur qui vient de naître vient de lire,
/// et le relire aussitôt serait une seconde requête pour rien.
mixin LectureHorodatee<S> on AsyncNotifier<S> {
  DateTime? _derniereLecture;

  DateTime? get derniereLecture => _derniereLecture;

  /// À appeler après chaque lecture réseau aboutie.
  void marquerLu() =>
      _derniereLecture = ref.read(horlogeRafraichissementProvider)();
}
