import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/astreinte.dart';
import '../domain/planning_caserne.dart';

/// **Le planning de la caserne, gardé sur l'appareil.**
///
/// Un pompier consulte le planning de sa caserne exactement dans les mêmes
/// conditions que ses propres astreintes : dans une remise en béton, sur un
/// trajet, sans couverture. Le cache du ticket 027 couvre donc cette vue aussi,
/// sous la même mécanique — `shared_preferences` (`localStorage` sur le web),
/// clé préfixée par domaine, toute panne de stockage avalée.
///
/// **Ce qui change, c'est le découpage.** « Mes astreintes » est un instantané
/// unique ; ici, chaque mois est un document autonome qu'on visite et qu'on
/// quitte. D'où **une entrée par caserne, par membre et par mois**, plus une
/// entrée pour la liste des mois atteignables.
///
/// `CLAUDE.md § Règle des caches locaux` :
///
/// - **tout part à la déconnexion**, par [effacer], appelée par
///   `DeconnexionController` avant la fermeture de session. Ce document porte
///   **les noms de toute la caserne** : c'est le cache le plus chargé en
///   données de tiers du produit ;
/// - **il ne décide d'aucun droit**. Un mois gardé alors que le planning était
///   seulement publié ne contient que les créneaux du lecteur : il ne peut donc
///   pas révéler ce que la base refusait. L'état du planning est gardé avec, et
///   c'est ce qui rend le bloc d'attente juste hors ligne aussi.
abstract interface class CachePlanningCaserne {
  /// Les mois atteignables gardés, ou `null` s'il n'y a rien de lisible.
  Future<List<MoisPlanning>?> lireMois({
    required String stationId,
    required String userId,
  });

  Future<void> ecrireMois({
    required String stationId,
    required String userId,
    required List<MoisPlanning> mois,
  });

  /// Le planning gardé d'un mois, ou `null`. [cleMois] est `2026-10`.
  Future<PlanningCaserne?> lirePlanning({
    required String stationId,
    required String userId,
    required String cleMois,
  });

  Future<void> ecrirePlanning({
    required String stationId,
    required String userId,
    required PlanningCaserne planning,
  });

  /// Oublie **tout** ce que cet appareil garde du planning de cette caserne
  /// pour ce membre : la liste des mois et chacun des mois visités.
  ///
  /// L'effacement balaie le préfixe entier, pas une clé : un pompier qui a
  /// consulté six mois en a laissé six, et en oublier cinq reviendrait à ne
  /// rien oublier du tout.
  Future<void> effacer({required String stationId, required String userId});
}

/// Implémentation `shared_preferences` — `localStorage` sur le web.
class CachePlanningCasernePartage implements CachePlanningCaserne {
  const CachePlanningCasernePartage();

  /// Préfixé par domaine pour ne jamais entrer en collision avec la session
  /// Supabase, la file des disponibilités ni l'instantané des astreintes, qui
  /// partagent le même `localStorage`.
  static const String prefixe = 'planning.caserne';

  /// **Le numéro de version du format.** Un document d'une version inconnue est
  /// ignoré, jamais réparé : un mois se reconstruit en trois requêtes.
  static const int version = 1;

  /// Le préfixe d'un couple caserne/membre, terminé par un point. Tout ce qui
  /// commence par là est à effacer à la déconnexion.
  static String prefixeDe({
    required String stationId,
    required String userId,
  }) => '$prefixe.$stationId.$userId.';

  static String cleMoisDe({
    required String stationId,
    required String userId,
  }) => '${prefixeDe(stationId: stationId, userId: userId)}mois';

  static String clePlanningDe({
    required String stationId,
    required String userId,
    required String cleMois,
  }) => '${prefixeDe(stationId: stationId, userId: userId)}$cleMois';

  @override
  Future<List<MoisPlanning>?> lireMois({
    required String stationId,
    required String userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return relireMois(
        prefs.getString(cleMoisDe(stationId: stationId, userId: userId)),
      );
    } on Object {
      // Navigation privée, quota plein, canal de plateforme absent : perdre le
      // cache est un défaut, empêcher un pompier de lire le planning en serait
      // un vrai.
      return null;
    }
  }

  @override
  Future<void> ecrireMois({
    required String stationId,
    required String userId,
    required List<MoisPlanning> mois,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cleMoisDe(stationId: stationId, userId: userId),
        jsonEncode(composerMois(mois)),
      );
    } on Object {
      // Rien à faire : l'écran reste juste, il ne survivra simplement pas à une
      // fermeture de l'onglet sans réseau.
    }
  }

  @override
  Future<PlanningCaserne?> lirePlanning({
    required String stationId,
    required String userId,
    required String cleMois,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return relirePlanning(
        prefs.getString(
          clePlanningDe(
            stationId: stationId,
            userId: userId,
            cleMois: cleMois,
          ),
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> ecrirePlanning({
    required String stationId,
    required String userId,
    required PlanningCaserne planning,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        clePlanningDe(
          stationId: stationId,
          userId: userId,
          cleMois: planning.mois.cle,
        ),
        jsonEncode(composerPlanning(planning)),
      );
    } on Object {
      // Même politique que partout.
    }
  }

  @override
  Future<void> effacer({
    required String stationId,
    required String userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final debut = prefixeDe(stationId: stationId, userId: userId);
      for (final cle in prefs.getKeys().toList(growable: false)) {
        if (cle.startsWith(debut)) await prefs.remove(cle);
      }
    } on Object {
      // Une panne de stockage ne fait pas échouer une déconnexion. La session,
      // elle, est bien fermée.
    }
  }

  /// Le document de la liste des mois. Public pour que les tests puissent
  /// vérifier ce qui est gardé sans passer par le stockage de plateforme.
  static Map<String, dynamic> composerMois(List<MoisPlanning> mois) =>
      <String, dynamic>{
        'v': version,
        'm': <Map<String, dynamic>>[
          for (final entree in mois) entree.versCache(),
        ],
      };

  static List<MoisPlanning>? relireMois(String? brut) {
    final document = _document(brut);
    if (document == null) return null;

    final entrees = document['m'];
    if (entrees is! List) return null;

    return <MoisPlanning>[
      for (final entree in entrees)
        if (MoisPlanning.depuisCache(entree) case final MoisPlanning lu) lu,
    ]..sort((MoisPlanning a, MoisPlanning b) => a.comparer(b));
  }

  static Map<String, dynamic> composerPlanning(PlanningCaserne planning) =>
      <String, dynamic>{
        'v': version,
        // L'horodatage de la **lecture réussie** : c'est lui que le bandeau de
        // fraîcheur affiche.
        'le': (planning.luLe ?? DateTime.now()).toUtc().toIso8601String(),
        'mois': planning.mois.versCache(),
        'jour': planning.heures.debutJour,
        'nuit': planning.heures.finJour,
        'j': <Map<String, dynamic>>[
          for (final journee in planning.journees) journee.versCache(),
        ],
      };

  static PlanningCaserne? relirePlanning(String? brut) {
    final document = _document(brut);
    if (document == null) return null;

    final luLe = DateTime.tryParse(document['le'] as String? ?? '');
    if (luLe == null) return null;

    final mois = MoisPlanning.depuisCache(document['mois']);
    if (mois == null) return null;

    final journees = document['j'];
    return PlanningCaserne(
      mois: mois,
      journees: <JourneeCaserne>[
        if (journees is List)
          for (final journee in journees)
            if (JourneeCaserne.depuisCache(journee)
                case final JourneeCaserne lue)
              lue,
      ],
      heures: HeuresAffichage(
        debutJour:
            document['jour'] as String? ?? HeuresAffichage.defaut.debutJour,
        finJour: document['nuit'] as String? ?? HeuresAffichage.defaut.finJour,
      ),
      luLe: luLe.toLocal(),
    );
  }

  /// Relit un document et vérifie sa version. `null` sur tout ce qui n'est pas
  /// exactement le format attendu : un cache abîmé vaut un cache vide.
  static Map<String, dynamic>? _document(String? brut) {
    if (brut == null) return null;
    try {
      final document = jsonDecode(brut);
      if (document is! Map<String, dynamic>) return null;
      if (document['v'] != version) return null;
      return document;
    } on Object {
      return null;
    }
  }
}

/// Implémentation en mémoire, pour les tests.
///
/// **Elle range par caserne et par membre, exactement comme la vraie.** Une
/// mémoire qui rendrait le même planning à n'importe qui ne pourrait attraper
/// aucune régression de cloisonnement — et ce document porte les noms de toute
/// la caserne.
class CachePlanningCaserneMemoire implements CachePlanningCaserne {
  CachePlanningCaserneMemoire({
    List<MoisPlanning>? mois,
    List<PlanningCaserne>? plannings,
    this.stationId = stationDeTestId,
    this.userId = membreDeTestUserId,
  }) {
    if (mois != null) _mois[_cle(stationId, userId)] = mois;
    for (final planning in plannings ?? const <PlanningCaserne>[]) {
      _plannings['${_cle(stationId, userId)}.${planning.mois.cle}'] = planning;
    }
  }

  /// La caserne et le membre des jeux de test du projet
  /// (`test/support/faux_auth.dart`). Tout autre couple ne lit rien.
  static const String stationDeTestId = 'aaaaaaaa-0000-4000-8000-000000000001';
  static const String membreDeTestUserId =
      'aaaaaaaa-0000-4000-8000-000000000101';

  static String _cle(String stationId, String userId) => '$stationId.$userId';

  final String stationId;
  final String userId;

  final Map<String, List<MoisPlanning>> _mois = <String, List<MoisPlanning>>{};
  final Map<String, PlanningCaserne> _plannings = <String, PlanningCaserne>{};

  int lectures = 0;
  int ecritures = 0;
  int effacements = 0;

  /// Les clés encore occupées. Un test de déconnexion vérifie qu'elle est vide.
  Set<String> get clesGardees => <String>{..._mois.keys, ..._plannings.keys};

  @override
  Future<List<MoisPlanning>?> lireMois({
    required String stationId,
    required String userId,
  }) async {
    lectures++;
    return _mois[_cle(stationId, userId)];
  }

  @override
  Future<void> ecrireMois({
    required String stationId,
    required String userId,
    required List<MoisPlanning> mois,
  }) async {
    ecritures++;
    _mois[_cle(stationId, userId)] = mois;
  }

  @override
  Future<PlanningCaserne?> lirePlanning({
    required String stationId,
    required String userId,
    required String cleMois,
  }) async {
    lectures++;
    return _plannings['${_cle(stationId, userId)}.$cleMois'];
  }

  @override
  Future<void> ecrirePlanning({
    required String stationId,
    required String userId,
    required PlanningCaserne planning,
  }) async {
    ecritures++;
    _plannings['${_cle(stationId, userId)}.${planning.mois.cle}'] = planning;
  }

  @override
  Future<void> effacer({
    required String stationId,
    required String userId,
  }) async {
    effacements++;
    final debut = _cle(stationId, userId);
    _mois.remove(debut);
    _plannings.removeWhere((String cle, _) => cle.startsWith('$debut.'));
  }
}

/// Le cache local. Surchargé par [CachePlanningCaserneMemoire] dans les tests.
final Provider<CachePlanningCaserne> cachePlanningCaserneProvider =
    Provider<CachePlanningCaserne>(
      (ref) => const CachePlanningCasernePartage(),
    );
