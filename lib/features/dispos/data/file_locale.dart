import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_status.dart';
import '../domain/creneau_cle.dart';
import '../domain/preferences_mois.dart';

/// **La file d'écriture gardée sur l'appareil.**
///
/// La bannière hors ligne promet que « tes modifications sont conservées sur
/// ton téléphone ». Sans ce dépôt, la promesse est fausse : la file n'est
/// qu'un dictionnaire en mémoire, et un onglet fermé, un rechargement ou une
/// PWA tuée par le système l'emportent — exactement au moment où un membre
/// sans réseau, dans une remise, vient de lire la phrase.
///
/// Rangement : **une entrée par caserne, utilisateur et mois**. Le mois dans
/// la clé évite de relire tout l'historique pour repartir, et permet
/// d'oublier d'un coup un mois devenu verrouillé.
abstract interface class FileLocale {
  /// Tout ce qui attend d'être écrit pour ce membre dans cette caserne,
  /// tous mois confondus.
  Future<Map<CreneauCle, DisponibiliteEtat>> lire({
    required String stationId,
    required String userId,
  });

  /// Remplace ce qui est gardé pour un mois. Une carte vide **oublie** le
  /// mois : c'est ainsi qu'une entrée confirmée par le serveur disparaît.
  Future<void> enregistrer({
    required String stationId,
    required String userId,
    required String mois,
    required Map<CreneauCle, DisponibiliteEtat> entrees,
  });

  /// Les mois qui ont quelque chose en attente pour ce membre.
  Future<Set<String>> moisEnAttente({
    required String stationId,
    required String userId,
  });

  /// Les préférences de charge en attente d'écriture, rangées par
  /// `period_id`.
  ///
  /// Un maximum posé dans une remise sans réseau vaut une case cochée : la
  /// bannière hors ligne promet les deux.
  Future<Map<String, PreferencesMois>> lirePreferences({
    required String stationId,
    required String userId,
  });

  /// Remplace ce qui est gardé pour une période. `null` **oublie** la
  /// période : c'est ainsi qu'une préférence confirmée par le serveur
  /// disparaît.
  Future<void> enregistrerPreferences({
    required String stationId,
    required String userId,
    required String periodId,
    required PreferencesMois? preferences,
  });
}

/// La valeur écrite pour une case revenue à « non saisi ».
///
/// « Non saisi » n'est pas une valeur SQL (`docs/SCHEMA.md § 2.6`) mais c'est
/// bien une **intention** en attente : supprimer la ligne. La file doit donc
/// savoir l'exprimer, et ce marqueur ne peut pas entrer en collision avec un
/// `availability_status`.
const String marqueurEffacement = '-';

String _etatVersTexte(DisponibiliteEtat etat) => switch (etat) {
  DisponibiliteEtat.disponible => 'available',
  DisponibiliteEtat.absent => 'absent',
  DisponibiliteEtat.nonSaisi => marqueurEffacement,
};

DisponibiliteEtat? _etatDepuisTexte(String texte) => switch (texte) {
  'available' => DisponibiliteEtat.disponible,
  'absent' => DisponibiliteEtat.absent,
  marqueurEffacement => DisponibiliteEtat.nonSaisi,
  _ => null,
};

/// Implémentation `shared_preferences` — `localStorage` sur le web.
///
/// Toute panne de stockage est avalée : un navigateur en navigation privée,
/// un quota plein, un document JSON illisible après une mise à jour. Perdre
/// la persistance est un défaut ; empêcher un pompier de saisir ses
/// disponibilités parce que le stockage refuse en serait un vrai.
class FileLocalePartagee implements FileLocale {
  const FileLocalePartagee();

  /// Préfixé par domaine pour ne jamais entrer en collision avec la session
  /// Supabase, qui partage le même `localStorage`.
  static const String prefixe = 'dispos.file';

  static String cleDe({
    required String stationId,
    required String userId,
    required String mois,
  }) => '$prefixe.$stationId.$userId.$mois';

  /// Préfixe des préférences en attente. Distinct de celui de la file : une
  /// clé de mois et une clé de période ne se confondent jamais.
  static const String prefixePreferences = 'dispos.prefs';

  static String clePreferenceDe({
    required String stationId,
    required String userId,
    required String periodId,
  }) => '$prefixePreferences.$stationId.$userId.$periodId';

  static String _prefixeMembre({
    required String stationId,
    required String userId,
  }) => '$prefixe.$stationId.$userId.';

  static String _prefixeMembrePreferences({
    required String stationId,
    required String userId,
  }) => '$prefixePreferences.$stationId.$userId.';

  @override
  Future<Map<CreneauCle, DisponibiliteEtat>> lire({
    required String stationId,
    required String userId,
  }) async {
    final file = <CreneauCle, DisponibiliteEtat>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final debut = _prefixeMembre(stationId: stationId, userId: userId);

      for (final cle in prefs.getKeys()) {
        if (!cle.startsWith(debut)) continue;
        file.addAll(_relire(prefs.getString(cle)));
      }
    } on Object {
      return <CreneauCle, DisponibiliteEtat>{};
    }
    return file;
  }

  @override
  Future<void> enregistrer({
    required String stationId,
    required String userId,
    required String mois,
    required Map<CreneauCle, DisponibiliteEtat> entrees,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cle = cleDe(stationId: stationId, userId: userId, mois: mois);

      if (entrees.isEmpty) {
        await prefs.remove(cle);
        return;
      }
      await prefs.setString(
        cle,
        jsonEncode(<String, String>{
          for (final entree in entrees.entries)
            entree.key.toString(): _etatVersTexte(entree.value),
        }),
      );
    } on Object {
      // Rien à faire : la saisie continue, elle ne survivra simplement pas à
      // une fermeture de l'onglet.
    }
  }

  @override
  Future<Set<String>> moisEnAttente({
    required String stationId,
    required String userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final debut = _prefixeMembre(stationId: stationId, userId: userId);
      return <String>{
        for (final cle in prefs.getKeys())
          if (cle.startsWith(debut)) cle.substring(debut.length),
      };
    } on Object {
      return <String>{};
    }
  }

  @override
  Future<Map<String, PreferencesMois>> lirePreferences({
    required String stationId,
    required String userId,
  }) async {
    final attente = <String, PreferencesMois>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final debut = _prefixeMembrePreferences(
        stationId: stationId,
        userId: userId,
      );

      for (final cle in prefs.getKeys()) {
        if (!cle.startsWith(debut)) continue;
        final valeur = _relirePreference(prefs.getString(cle));
        if (valeur != null) attente[cle.substring(debut.length)] = valeur;
      }
    } on Object {
      return <String, PreferencesMois>{};
    }
    return attente;
  }

  @override
  Future<void> enregistrerPreferences({
    required String stationId,
    required String userId,
    required String periodId,
    required PreferencesMois? preferences,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cle = clePreferenceDe(
        stationId: stationId,
        userId: userId,
        periodId: periodId,
      );

      if (preferences == null) {
        await prefs.remove(cle);
        return;
      }
      await prefs.setString(cle, jsonEncode(preferences.versJson()));
    } on Object {
      // Même politique que la file : la saisie continue, elle ne survivra
      // simplement pas à une fermeture de l'onglet.
    }
  }

  static PreferencesMois? _relirePreference(String? brut) {
    if (brut == null) return null;
    try {
      final document = jsonDecode(brut);
      if (document is! Map<String, dynamic>) return null;
      return PreferencesMois.depuisJson(document);
    } on Object {
      return null;
    }
  }

  static Map<CreneauCle, DisponibiliteEtat> _relire(String? brut) {
    if (brut == null) return <CreneauCle, DisponibiliteEtat>{};
    try {
      final document = jsonDecode(brut);
      if (document is! Map<String, dynamic>) {
        return <CreneauCle, DisponibiliteEtat>{};
      }

      final file = <CreneauCle, DisponibiliteEtat>{};
      for (final entree in document.entries) {
        final cle = CreneauCle.depuisTexte(entree.key);
        final valeur = entree.value;
        if (cle == null || valeur is! String) continue;
        final etat = _etatDepuisTexte(valeur);
        if (etat != null) file[cle] = etat;
      }
      return file;
    } on Object {
      return <CreneauCle, DisponibiliteEtat>{};
    }
  }
}

/// Implémentation en mémoire, pour les tests.
class FileLocaleMemoire implements FileLocale {
  FileLocaleMemoire([Map<String, Map<CreneauCle, DisponibiliteEtat>>? depart])
    : _mois = <String, Map<CreneauCle, DisponibiliteEtat>>{...?depart};

  final Map<String, Map<CreneauCle, DisponibiliteEtat>> _mois;

  /// Le nombre d'écritures sur le stockage, pour que les tests puissent
  /// vérifier qu'une confirmation serveur purge bien l'entrée.
  int ecritures = 0;

  @override
  Future<Map<CreneauCle, DisponibiliteEtat>> lire({
    required String stationId,
    required String userId,
  }) async => <CreneauCle, DisponibiliteEtat>{
    for (final entrees in _mois.values) ...entrees,
  };

  @override
  Future<void> enregistrer({
    required String stationId,
    required String userId,
    required String mois,
    required Map<CreneauCle, DisponibiliteEtat> entrees,
  }) async {
    ecritures++;
    if (entrees.isEmpty) {
      _mois.remove(mois);
      return;
    }
    _mois[mois] = Map<CreneauCle, DisponibiliteEtat>.of(entrees);
  }

  @override
  Future<Set<String>> moisEnAttente({
    required String stationId,
    required String userId,
  }) async => _mois.keys.toSet();

  /// Les préférences gardées, par `period_id`.
  final Map<String, PreferencesMois> preferences = <String, PreferencesMois>{};

  @override
  Future<Map<String, PreferencesMois>> lirePreferences({
    required String stationId,
    required String userId,
  }) async => Map<String, PreferencesMois>.of(preferences);

  @override
  Future<void> enregistrerPreferences({
    required String stationId,
    required String userId,
    required String periodId,
    required PreferencesMois? preferences,
  }) async {
    ecritures++;
    if (preferences == null) {
      this.preferences.remove(periodId);
      return;
    }
    this.preferences[periodId] = preferences;
  }
}

/// Le dépôt local de la file. Surchargé par [FileLocaleMemoire] dans les
/// tests.
final Provider<FileLocale> fileLocaleProvider = Provider<FileLocale>(
  (ref) => const FileLocalePartagee(),
);
