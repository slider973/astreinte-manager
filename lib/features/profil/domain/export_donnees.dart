import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';

/// Ce que l'Edge Function `export-user-data` a rendu, et de quoi en faire un
/// fichier.
///
/// Le contenu n'est **pas** modélisé champ par champ, et c'est volontaire : ce
/// n'est pas une donnée que l'application affiche, c'est une donnée qu'elle
/// **rend**. Écrire douze classes Dart pour les recopier telles quelles
/// obligerait à les maintenir à chaque migration, sans que l'écran gagne une
/// ligne. Ce que l'application doit savoir de ce fichier tient en deux faits :
/// son nom, et son poids.
@immutable
class ExportDonnees {
  const ExportDonnees(this.contenu);

  /// Le corps de la réponse, tel quel.
  final Map<String, dynamic> contenu;

  /// Le fichier, mis en forme pour être **lu**, pas seulement analysé.
  ///
  /// Deux espaces d'indentation : un export RGPD est fait pour être ouvert par
  /// une personne, éventuellement par le service juridique d'une mairie, et un
  /// JSON sur une seule ligne de 20 000 caractères ne se lit pas.
  String get texte => const JsonEncoder.withIndent('  ').convert(contenu);

  /// `astreinte-sp-export-2026-09-21.json`.
  ///
  /// La date, pas l'heure : deux exports le même jour donnent deux fichiers du
  /// même nom, et c'est le navigateur qui numérote — comportement attendu
  /// partout ailleurs. La date vient du serveur (`export.genere_le`) quand il
  /// l'a donnée, parce que c'est elle qui fait foi ; l'horloge de l'appareil
  /// n'est qu'un repli.
  String nomFichier({DateTime? maintenant}) {
    final jour = _genereLe() ?? maintenant ?? DateTime.now();
    final mois = jour.month.toString().padLeft(2, '0');
    final date = jour.day.toString().padLeft(2, '0');
    return 'astreinte-sp-export-${jour.year}-$mois-$date.json';
  }

  DateTime? _genereLe() {
    final dynamic entete = contenu['export'];
    if (entete is! Map) return null;
    final dynamic quand = entete['genere_le'];
    return quand is String ? DateTime.tryParse(quand)?.toLocal() : null;
  }
}

/// Ce qui peut faire échouer un export
/// (`supabase/functions/README.md § export-user-data`).
enum ErreurExport {
  /// Le profil est introuvable — session périmée, le plus souvent.
  profilIntrouvable('profile_missing'),

  /// Session expirée pendant le geste.
  nonAuthentifie('unauthenticated'),

  reseau('__reseau'),

  /// Le serveur a répondu, mais la plateforme n'a pas su ranger le fichier.
  /// C'est la seule erreur qui n'est pas celle du serveur, et elle se dit
  /// autrement : les données existent, c'est l'enregistrement qui a manqué.
  enregistrementImpossible('__fichier'),

  inconnue('__inconnue');

  const ErreurExport(this.code);

  final String code;

  static ErreurExport depuisCode(String? code) => values.firstWhere(
    (ErreurExport erreur) => erreur.code == code,
    orElse: () => ErreurExport.inconnue,
  );

  /// Le message affiché sous le bouton. Il nomme le problème **et** la sortie
  /// (`DESIGN.md § Do's`).
  String get message => switch (this) {
    ErreurExport.profilIntrouvable => AppStrings.exportProfilIntrouvable,
    ErreurExport.nonAuthentifie => AppStrings.exportNonAuthentifie,
    ErreurExport.reseau => AppStrings.exportReseau,
    ErreurExport.enregistrementImpossible => AppStrings.exportFichierImpossible,
    ErreurExport.inconnue => AppStrings.exportEchec,
  };
}

/// L'échec d'un export.
@immutable
class EchecExport implements Exception {
  const EchecExport(this.erreur);

  final ErreurExport erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecExport(${erreur.code})';
}
