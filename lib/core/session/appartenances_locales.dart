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
  /// **Tout ce qui sort d'ici est un simple membre.** Un rôle qu'on n'a pas pu
  /// revérifier n'accorde aucun privilège : c'est la règle déjà écrite dans
  /// `RoleMembre.depuisSql`, appliquée à une valeur qu'on ne peut pas
  /// confirmer plutôt qu'à une valeur qu'on ne comprend pas. Conséquence
  /// assumée : un chef de centre hors ligne perd l'onglet « Admin », qui ne
  /// lui servirait de toute façon qu'à ouvrir des listes vides et des
  /// formulaires qui échouent (`DESIGN.md § Écarts, ticket 024`). Il revient
  /// dès que le réseau revient.
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
class AppartenancesLocalesMemoire implements AppartenancesLocales {
  AppartenancesLocalesMemoire([List<Appartenance>? gardees])
    : _gardees = <Appartenance>[...?gardees];

  List<Appartenance> _gardees;

  int ecritures = 0;

  List<Appartenance> get gardees => List<Appartenance>.unmodifiable(_gardees);

  @override
  Future<List<Appartenance>> lire(String userId) async => gardees;

  @override
  Future<void> ecrire(String userId, List<Appartenance> appartenances) async {
    ecritures++;
    _gardees = <Appartenance>[...appartenances];
  }
}

/// Le dépôt local des appartenances. Surchargé dans les tests.
final Provider<AppartenancesLocales> appartenancesLocalesProvider =
    Provider<AppartenancesLocales>(
      (ref) => const AppartenancesLocalesPartagees(),
    );
