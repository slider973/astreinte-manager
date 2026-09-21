import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appartenance.dart';

/// **La caserne du membre, gardée sur l'appareil.**
///
/// Sans elle, aucun écran de consultation ne survit à un démarrage à froid
/// sans réseau : la session se restaure toute seule depuis le stockage local,
/// mais la lecture de `memberships` échoue, `etatAuthProvider` reste en
/// chargement et l'application s'arrête sur « Pas de connexion ». Constaté
/// dans Chrome, API coupée (`design/027 § 11`).
///
/// C'est donc la pièce qui rend vraie la promesse du ticket 027 — « sans
/// réseau, l'écran affiche les dernières données connues » — sur le seul
/// appareil qui compte : un téléphone qu'on rouvre dans une remise.
///
/// Mécanique du ticket 011 : `shared_preferences` (`localStorage` sur le web),
/// clé préfixée par domaine, toute panne de stockage avalée.
abstract interface class AppartenancesLocales {
  /// Ce qui a été gardé pour cet utilisateur, ou une liste vide.
  Future<List<Appartenance>> lire(String userId);

  /// Remplace ce qui est gardé. Instantané, pas file : il n'y a ni fusion ni
  /// conflit.
  Future<void> ecrire(String userId, List<Appartenance> appartenances);

  /// Oublie tout ce qui est gardé pour cet utilisateur.
  ///
  /// Appelée à la déconnexion, **avant** la fermeture de session : après, il
  /// n'y a plus d'identifiant à qui rattacher la clé. Le nom de la caserne est
  /// une donnée de la personne qui part ; sur un téléphone prêté ou dans un
  /// véhicule partagé, il n'a rien à faire là pour la suivante
  /// (`DESIGN.md § Écarts, ticket 024`).
  Future<void> effacer(String userId);
}

/// Implémentation `shared_preferences`.
class AppartenancesLocalesPartagees implements AppartenancesLocales {
  const AppartenancesLocalesPartagees();

  /// Préfixé par domaine pour ne jamais entrer en collision avec la session
  /// Supabase, qui partage le même `localStorage`.
  static const String prefixe = 'session.appartenances';

  /// Un document d'une version inconnue est ignoré, jamais réparé.
  static const int version = 1;

  static String cleDe(String userId) => '$prefixe.$userId';

  @override
  Future<List<Appartenance>> lire(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return relire(prefs.getString(cleDe(userId)));
    } on Object {
      return const <Appartenance>[];
    }
  }

  @override
  Future<void> ecrire(String userId, List<Appartenance> appartenances) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (appartenances.isEmpty) {
        await prefs.remove(cleDe(userId));
        return;
      }
      await prefs.setString(cleDe(userId), jsonEncode(composer(appartenances)));
    } on Object {
      // Rien à faire : l'application reste juste, elle ne survivra simplement
      // pas à une ouverture sans réseau.
    }
  }

  @override
  Future<void> effacer(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cleDe(userId));
    } on Object {
      // Même politique que partout : une panne de stockage ne fait pas échouer
      // une déconnexion. La session, elle, est bien fermée.
    }
  }

  /// Le document rangé. Public pour que les tests vérifient le format sans
  /// passer par le stockage de plateforme.
  static Map<String, dynamic> composer(List<Appartenance> appartenances) =>
      <String, dynamic>{
        'v': version,
        'a': <Map<String, dynamic>>[
          for (final appartenance in appartenances)
            <String, dynamic>{
              'id': appartenance.id,
              's': appartenance.stationId,
              'n': appartenance.nomCaserne,
              // **Le rôle n'est pas gardé.** Voir [relire].
              'st': appartenance.statut.valeurSql,
              if (appartenance.nomAffiche case final String nom) 'd': nom,
            },
        ],
      };

  /// Relit un document.
  ///
  /// **Tout ce qui sort d'ici est un simple membre**, puisque le rôle n'y est
  /// même pas écrit. C'est la seconde ceinture : la première est
  /// `appartenancesProvider`, qui rétrograde tout ce qui vient du stockage
  /// quelle que soit l'implémentation branchée (`Appartenance.commeMembre`).
  /// Conséquence assumée : un chef de centre hors ligne perd l'onglet
  /// « Admin », qui ne lui servirait de toute façon qu'à ouvrir des listes
  /// vides et des formulaires qui échouent (`DESIGN.md § Écarts, ticket 024`).
  /// Il revient dès que le réseau revient.
  static List<Appartenance> relire(String? brut) {
    if (brut == null) return const <Appartenance>[];
    try {
      final document = jsonDecode(brut);
      if (document is! Map<String, dynamic>) return const <Appartenance>[];
      if (document['v'] != version) return const <Appartenance>[];

      final entrees = document['a'];
      if (entrees is! List) return const <Appartenance>[];

      return <Appartenance>[
        for (final entree in entrees)
          if (entree is Map<String, dynamic> &&
              entree['id'] is String &&
              entree['s'] is String)
            Appartenance(
              id: entree['id']! as String,
              stationId: entree['s']! as String,
              nomCaserne: entree['n'] as String? ?? '',
              role: RoleMembre.membre,
              statut: StatutMembre.depuisSql(entree['st'] as String?),
              nomAffiche: entree['d'] as String?,
            ),
      ];
    } on Object {
      return const <Appartenance>[];
    }
  }
}

/// Implémentation en mémoire, pour les tests.
///
/// **Elle range par utilisateur, exactement comme la vraie.** Une mémoire qui
/// rendrait le même contenu à n'importe qui ne pourrait attraper aucune
/// régression de cloisonnement — et c'est précisément le cloisonnement qu'on
/// vérifie ici.
class AppartenancesLocalesMemoire implements AppartenancesLocales {
  AppartenancesLocalesMemoire([
    List<Appartenance>? gardees,
    String userId = sessionMembreDeTestUserId,
  ]) : _parUtilisateur = <String, List<Appartenance>>{
         if (gardees != null && gardees.isNotEmpty)
           userId: <Appartenance>[...gardees],
       };

  /// L'utilisateur auquel le raccourci de construction rattache ses
  /// appartenances. C'est celui des jeux de test du projet
  /// (`test/support/faux_auth.dart`) ; tout autre identifiant ne lit rien.
  static const String sessionMembreDeTestUserId =
      'aaaaaaaa-0000-4000-8000-000000000101';

  final Map<String, List<Appartenance>> _parUtilisateur;

  int ecritures = 0;
  int effacements = 0;

  /// Les clés encore occupées. Un test de déconnexion vérifie qu'elle est
  /// vide.
  Set<String> get utilisateursGardes => _parUtilisateur.keys.toSet();

  @override
  Future<List<Appartenance>> lire(String userId) async =>
      List<Appartenance>.unmodifiable(
        _parUtilisateur[userId] ?? const <Appartenance>[],
      );

  @override
  Future<void> ecrire(String userId, List<Appartenance> appartenances) async {
    ecritures++;
    if (appartenances.isEmpty) {
      _parUtilisateur.remove(userId);
      return;
    }
    _parUtilisateur[userId] = <Appartenance>[...appartenances];
  }

  @override
  Future<void> effacer(String userId) async {
    effacements++;
    _parUtilisateur.remove(userId);
  }
}

/// Le dépôt local des appartenances. Surchargé dans les tests.
final Provider<AppartenancesLocales> appartenancesLocalesProvider =
    Provider<AppartenancesLocales>(
      (ref) => const AppartenancesLocalesPartagees(),
    );
