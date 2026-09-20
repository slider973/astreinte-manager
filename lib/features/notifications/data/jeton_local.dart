import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le dernier jeton push enregistré depuis **cet appareil**.
///
/// Sans cette mémoire, un navigateur qui change de jeton — cela arrive : vidage
/// du stockage, réabonnement, changement de clé VAPID — laisserait derrière lui
/// une ligne morte dans `push_tokens`. L'Edge Function d'envoi finirait par la
/// nettoyer (`docs/SCHEMA.md § 2.11`), mais entre-temps chaque notification
/// partirait en double. On garde donc l'ancien jeton le temps de le remplacer.
///
/// C'est une marque locale, comme les repères d'accueil : elle se perd avec le
/// navigateur, et ce n'est pas grave — au pire une ligne morte de plus, que
/// l'envoi nettoiera.
abstract interface class JetonLocal {
  Future<String?> lire();

  Future<void> ecrire(String jeton);

  Future<void> effacer();
}

/// Implémentation `shared_preferences` — `localStorage` sur le web.
class JetonLocalPartage implements JetonLocal {
  const JetonLocalPartage();

  /// Préfixée par domaine pour ne jamais entrer en collision avec la session
  /// Supabase, qui partage le même `localStorage`.
  static const String cle = 'notifications.jeton.appareil';

  @override
  Future<String?> lire() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final valeur = prefs.getString(cle);
      return (valeur == null || valeur.isEmpty) ? null : valeur;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> ecrire(String jeton) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cle, jeton);
    } on Object {
      // Le jeton est enregistré côté serveur : c'est ce qui compte. La
      // mémoire locale n'est qu'une commodité de ménage.
    }
  }

  @override
  Future<void> effacer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cle);
    } on Object {
      // Idem.
    }
  }
}

/// Implémentation en mémoire, pour les tests.
class JetonLocalMemoire implements JetonLocal {
  JetonLocalMemoire([this._jeton]);

  String? _jeton;

  @override
  Future<String?> lire() async => _jeton;

  @override
  Future<void> ecrire(String jeton) async => _jeton = jeton;

  @override
  Future<void> effacer() async => _jeton = null;
}

final Provider<JetonLocal> jetonLocalProvider = Provider<JetonLocal>(
  (ref) => const JetonLocalPartage(),
);
