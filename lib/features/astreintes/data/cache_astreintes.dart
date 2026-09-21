import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/astreinte.dart';

/// **Le dernier état connu, gardé sur l'appareil.**
///
/// Une caserne est un bâtiment de béton dans une zone rurale ; une remise n'a
/// pas de couverture. Un écran de consultation qui répond « Impossible de
/// charger » dans la caserne elle-même n'a pas d'excuse : la réponse était
/// déjà connue la veille, et elle n'a pas changé (`design/027 § 3`).
///
/// La mécanique est celle de `FileLocale` au ticket 011 — `shared_preferences`
/// (`localStorage` sur le web), clé préfixée par domaine, toute panne de
/// stockage avalée. Ce qui change est la **forme** : ce n'est pas une file à
/// fusionner mais un instantané qui se remplace en bloc, donc **une entrée par
/// caserne et par membre**, pas une par mois.
abstract interface class CacheAstreintes {
  /// Ce qui a été gardé, ou `null` s'il n'y a rien de lisible.
  Future<MesAstreintes?> lire({
    required String stationId,
    required String userId,
  });

  /// Remplace l'instantané. Il n'y a ni fusion ni conflit : c'est une copie du
  /// serveur, pas un brouillon local.
  Future<void> ecrire({
    required String stationId,
    required String userId,
    required MesAstreintes donnees,
  });

  /// Oublie l'instantané de ce membre dans cette caserne.
  ///
  /// Appelée à la déconnexion, **avant** la fermeture de session : après, ni
  /// l'identifiant du membre ni celui de la caserne ne sont plus lisibles. Ce
  /// document porte des dates de garde **et les noms des autres membres du
  /// créneau** : des données de tiers, qui n'ont rien à faire sur le téléphone
  /// une fois la personne partie (`DESIGN.md § Écarts, ticket 024`).
  Future<void> effacer({required String stationId, required String userId});
}

/// Implémentation `shared_preferences` — `localStorage` sur le web.
class CacheAstreintesPartage implements CacheAstreintes {
  const CacheAstreintesPartage();

  /// Préfixé par domaine pour ne jamais entrer en collision avec la session
  /// Supabase ni avec la file des disponibilités, qui partagent le même
  /// `localStorage`.
  static const String prefixe = 'astreintes.cache';

  /// **Le numéro de version du format.** Un document d'une version inconnue
  /// est ignoré, jamais réparé : un cache illisible vaut un cache vide, et
  /// migrer un instantané qui se reconstruit en une requête serait du travail
  /// pour rien.
  static const int version = 1;

  static String cleDe({required String stationId, required String userId}) =>
      '$prefixe.$stationId.$userId';

  @override
  Future<MesAstreintes?> lire({
    required String stationId,
    required String userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return relire(
        prefs.getString(cleDe(stationId: stationId, userId: userId)),
      );
    } on Object {
      // Navigation privée, quota plein, canal de plateforme absent : perdre le
      // cache est un défaut, empêcher un pompier de lire son planning en
      // serait un vrai.
      return null;
    }
  }

  @override
  Future<void> ecrire({
    required String stationId,
    required String userId,
    required MesAstreintes donnees,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cleDe(stationId: stationId, userId: userId),
        jsonEncode(composer(donnees)),
      );
    } on Object {
      // Rien à faire : l'écran reste juste, il ne survivra simplement pas à
      // une fermeture de l'onglet sans réseau.
    }
  }

  @override
  Future<void> effacer({
    required String stationId,
    required String userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cleDe(stationId: stationId, userId: userId));
    } on Object {
      // Même politique que partout : une panne de stockage ne fait pas échouer
      // une déconnexion. La session, elle, est bien fermée.
    }
  }

  /// Le document rangé. Public pour que les tests puissent vérifier ce qui est
  /// gardé sans passer par le stockage de plateforme.
  static Map<String, dynamic> composer(MesAstreintes donnees) =>
      <String, dynamic>{
        'v': version,
        // L'horodatage de la **lecture réussie**, en UTC : c'est lui que le
        // bandeau de fraîcheur affiche.
        'le': (donnees.luLe ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
        'jour': donnees.heures.debutJour,
        'nuit': donnees.heures.finJour,
        'a': <Map<String, dynamic>>[
          for (final astreinte in donnees.astreintes) astreinte.versCache(),
        ],
      };

  /// Relit un document. Rend `null` sur tout ce qui n'est pas exactement le
  /// format attendu.
  static MesAstreintes? relire(String? brut) {
    if (brut == null) return null;
    try {
      final document = jsonDecode(brut);
      if (document is! Map<String, dynamic>) return null;
      if (document['v'] != version) return null;

      final luLe = DateTime.tryParse(document['le'] as String? ?? '');
      if (luLe == null) return null;

      final entrees = document['a'];
      return MesAstreintes(
        astreintes: <Astreinte>[
          if (entrees is List)
            for (final entree in entrees)
              if (Astreinte.depuisCache(entree) case final Astreinte gardee)
                gardee,
        ],
        heures: HeuresAffichage(
          debutJour:
              document['jour'] as String? ?? HeuresAffichage.defaut.debutJour,
          finJour:
              document['nuit'] as String? ?? HeuresAffichage.defaut.finJour,
        ),
        luLe: luLe.toLocal(),
      );
    } on Object {
      return null;
    }
  }
}

/// Implémentation en mémoire, pour les tests.
///
/// **Elle range par caserne et par membre, exactement comme la vraie.** Une
/// mémoire qui rendrait le même instantané à n'importe qui ne pourrait
/// attraper aucune régression de cloisonnement — et ce document porte les noms
/// des autres membres du créneau.
class CacheAstreintesMemoire implements CacheAstreintes {
  CacheAstreintesMemoire([
    MesAstreintes? garde,
    String stationId = stationDeTestId,
    String userId = membreDeTestUserId,
  ]) : _parMembre = <String, MesAstreintes>{
         _cle(stationId, userId): ?garde,
       };

  /// La caserne et le membre des jeux de test du projet
  /// (`test/support/faux_auth.dart`). Tout autre couple ne lit rien.
  static const String stationDeTestId =
      'aaaaaaaa-0000-4000-8000-000000000001';
  static const String membreDeTestUserId =
      'aaaaaaaa-0000-4000-8000-000000000101';

  static String _cle(String stationId, String userId) => '$stationId.$userId';

  final Map<String, MesAstreintes> _parMembre;

  int lectures = 0;
  int ecritures = 0;
  int effacements = 0;

  /// L'instantané du couple par défaut, tel que les tests l'inspectent.
  MesAstreintes? get garde =>
      _parMembre[_cle(stationDeTestId, membreDeTestUserId)];

  /// Les clés encore occupées. Un test de déconnexion vérifie qu'elle est
  /// vide.
  Set<String> get clesGardees => _parMembre.keys.toSet();

  @override
  Future<MesAstreintes?> lire({
    required String stationId,
    required String userId,
  }) async {
    lectures++;
    return _parMembre[_cle(stationId, userId)];
  }

  @override
  Future<void> ecrire({
    required String stationId,
    required String userId,
    required MesAstreintes donnees,
  }) async {
    ecritures++;
    _parMembre[_cle(stationId, userId)] = donnees;
  }

  @override
  Future<void> effacer({
    required String stationId,
    required String userId,
  }) async {
    effacements++;
    _parMembre.remove(_cle(stationId, userId));
  }
}

/// Le cache local. Surchargé par [CacheAstreintesMemoire] dans les tests.
final Provider<CacheAstreintes> cacheAstreintesProvider =
    Provider<CacheAstreintes>((ref) => const CacheAstreintesPartage());
