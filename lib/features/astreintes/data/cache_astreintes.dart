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
class CacheAstreintesMemoire implements CacheAstreintes {
  CacheAstreintesMemoire([this.garde]);

  MesAstreintes? garde;

  int lectures = 0;
  int ecritures = 0;

  @override
  Future<MesAstreintes?> lire({
    required String stationId,
    required String userId,
  }) async {
    lectures++;
    return garde;
  }

  @override
  Future<void> ecrire({
    required String stationId,
    required String userId,
    required MesAstreintes donnees,
  }) async {
    ecritures++;
    garde = donnees;
  }
}

/// Le cache local. Surchargé par [CacheAstreintesMemoire] dans les tests.
final Provider<CacheAstreintes> cacheAstreintesProvider =
    Provider<CacheAstreintes>((ref) => const CacheAstreintesPartage());
