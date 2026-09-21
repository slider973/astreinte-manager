import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_providers.dart';

/// **La caserne dans laquelle on travaille**, quand il y en a plusieurs.
///
/// Le cas est rare et réel : un regroupement de centres (`docs/PRD.md § 6.1`).
/// Jusqu'au ticket 007, l'application choisissait toute seule — la première
/// appartenance active dans l'ordre alphabétique — et rien ne permettait d'en
/// changer.
///
/// Le choix est une marque locale, comme les repères d'accueil : il ne décrit
/// aucun droit — c'est `memberships` qui les porte, et la RLS qui les fait
/// respecter — seulement une préférence d'affichage. Rien ne justifie une
/// colonne en base, et rien ne justifie de la reperdre à chaque ouverture.
///
/// Rangée **par utilisateur**, comme les appartenances (ticket 027) : sur un
/// téléphone partagé, la caserne de l'un n'est pas celle de l'autre. Et elle
/// s'efface avec le reste (`core/session/oubli_local.dart`).
abstract interface class CaserneChoisieLocale {
  /// L'identifiant de caserne gardé pour cet utilisateur, ou `null`.
  Future<String?> lire(String userId);

  Future<void> ecrire(String userId, String stationId);

  Future<void> effacer(String userId);
}

/// Implémentation `shared_preferences` — `localStorage` sur le web.
class CaserneChoisieLocalePartagee implements CaserneChoisieLocale {
  const CaserneChoisieLocalePartagee();

  /// Préfixée par domaine pour ne jamais entrer en collision avec la session
  /// Supabase, qui partage le même `localStorage`.
  static const String prefixe = 'session.caserne';

  static String cleDe(String userId) => '$prefixe.$userId';

  @override
  Future<String?> lire(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final valeur = prefs.getString(cleDe(userId));
      return (valeur == null || valeur.isEmpty) ? null : valeur;
    } on Object {
      // Une lecture qui échoue répond « pas de choix » : l'application retombe
      // sur la première caserne, ce qu'elle faisait déjà avant ce ticket.
      return null;
    }
  }

  @override
  Future<void> ecrire(String userId, String stationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cleDe(userId), stationId);
    } on Object {
      // Le choix vaut pour la session en cours ; il ne survivra simplement pas
      // à la fermeture de l'onglet.
    }
  }

  @override
  Future<void> effacer(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cleDe(userId));
    } on Object {
      // Une panne de stockage ne fait pas échouer une déconnexion.
    }
  }
}

/// Implémentation en mémoire, pour les tests. Range par utilisateur, comme la
/// vraie : c'est le cloisonnement qu'on vérifie.
class CaserneChoisieLocaleMemoire implements CaserneChoisieLocale {
  CaserneChoisieLocaleMemoire([Map<String, String>? depart])
    : _parUtilisateur = <String, String>{...?depart};

  final Map<String, String> _parUtilisateur;

  int effacements = 0;

  /// Les clés encore occupées. Un test de déconnexion vérifie qu'elle est vide.
  Set<String> get utilisateursGardes => _parUtilisateur.keys.toSet();

  @override
  Future<String?> lire(String userId) async => _parUtilisateur[userId];

  @override
  Future<void> ecrire(String userId, String stationId) async =>
      _parUtilisateur[userId] = stationId;

  @override
  Future<void> effacer(String userId) async {
    effacements++;
    _parUtilisateur.remove(userId);
  }
}

final Provider<CaserneChoisieLocale> caserneChoisieLocaleProvider =
    Provider<CaserneChoisieLocale>(
      (ref) => const CaserneChoisieLocalePartagee(),
    );

/// La caserne choisie, telle que l'application la connaît **maintenant**.
///
/// `null` tant que le stockage n'a pas répondu, et `null` s'il n'y a pas de
/// choix. Les deux se valent pour l'appelant : `appartenanceCouranteProvider`
/// retombe alors sur la première appartenance active, exactement comme avant ce
/// ticket. Il n'y a donc **aucun écran d'attente** à cause de cette lecture —
/// au pire un changement de caserne au premier cadre, sur les seuls comptes qui
/// en ont deux.
class CaserneChoisie extends Notifier<String?> {
  @override
  String? build() {
    final userId = ref.watch(sessionProvider).value?.userId;
    if (userId == null) return null;

    // Relecture en tâche de fond : le `build` d'un `Notifier` est synchrone, et
    // faire attendre toute l'application le `localStorage` pour une préférence
    // d'affichage serait disproportionné.
    unawaited(_relire(userId));
    return null;
  }

  Future<void> _relire(String userId) async {
    final gardee = await ref.read(caserneChoisieLocaleProvider).lire(userId);
    // La session a pu se fermer entre-temps : `ref.mounted` évite d'écrire dans
    // un notifier déjà disposé.
    if (gardee != null && ref.mounted) state = gardee;
  }

  /// Change de caserne, et s'en souvient.
  Future<void> choisir(String stationId) async {
    if (state == stationId) return;
    state = stationId;

    final userId = ref.read(sessionProvider).value?.userId;
    if (userId == null) return;
    await ref.read(caserneChoisieLocaleProvider).ecrire(userId, stationId);
  }
}

final NotifierProvider<CaserneChoisie, String?> caserneChoisieProvider =
    NotifierProvider<CaserneChoisie, String?>(CaserneChoisie.new);

/// Vrai quand la personne appartient à **plus d'une** caserne active.
///
/// C'est la seule condition d'apparition du sélecteur : un contrôle à un seul
/// choix est un contrôle de trop (`design/007-profil.md § 5.2`).
final Provider<bool> plusieursCasernesProvider = Provider<bool>(
  (ref) => ref.watch(appartenancesActivesProvider).length > 1,
);
