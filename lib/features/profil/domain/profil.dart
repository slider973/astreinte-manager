import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';

/// Ce que l'application sait de la personne connectée (`docs/SCHEMA.md § 2.2`).
///
/// Une ligne de `profiles`, sans une colonne de plus : `created_at` et
/// `updated_at` n'ont aucun écran, `id` est déjà celui de la session.
@immutable
class Profil {
  const Profil({
    required this.prenom,
    required this.nom,
    required this.email,
    this.telephone,
    this.pushNonCritiques = true,
    this.langue = Langue.francais,
  });

  /// Construit depuis la réponse PostgREST. Les colonnes `not null` du schéma
  /// sont malgré tout lues avec un repli : une réponse illisible fait un profil
  /// vide, jamais une exception dans un écran de réglages.
  factory Profil.depuisJson(Map<String, dynamic> ligne) {
    final numero = (ligne['phone'] as String? ?? '').trim();
    return Profil(
      prenom: (ligne['first_name'] as String? ?? '').trim(),
      nom: (ligne['last_name'] as String? ?? '').trim(),
      email: (ligne['email'] as String? ?? '').trim(),
      telephone: numero.isEmpty ? null : numero,
      // `not null default true` : l'absence se lit « oui », qui est le défaut
      // du schéma. Jamais « non », qui couperait des rappels sans que personne
      // ne l'ait demandé.
      pushNonCritiques: ligne['push_enabled'] as bool? ?? true,
      langue: Langue.depuisSql(ligne['locale'] as String?),
    );
  }

  final String prenom;
  final String nom;

  /// L'adresse de connexion. **Jamais modifiable ici** : la changer veut dire
  /// changer d'identifiant chez le fournisseur d'authentification, ce qui est
  /// une autre affaire que corriger une faute de frappe dans un nom.
  final String email;

  /// `null` quand il n'y en a pas — jamais la chaîne vide, pour que « pas de
  /// téléphone » ait une seule écriture.
  final String? telephone;

  /// `profiles.push_enabled` : les notifications **non critiques** sont-elles
  /// acceptées ? Les propositions d'astreinte, elles, partent toujours
  /// (`docs/PRD.md § 6.5`).
  final bool pushNonCritiques;

  final Langue langue;

  /// Le nom composé comme partout ailleurs dans le produit
  /// (`MembreCaserne.libelle`). Vide tant que le profil n'est pas rempli.
  String get nomComplet =>
      <String>[prenom, nom].where((String part) => part.isNotEmpty).join(' ');

  Profil copyWith({
    String? prenom,
    String? nom,
    String? telephone,
    bool effacerTelephone = false,
    bool? pushNonCritiques,
  }) => Profil(
    prenom: prenom ?? this.prenom,
    nom: nom ?? this.nom,
    email: email,
    telephone: effacerTelephone ? null : (telephone ?? this.telephone),
    pushNonCritiques: pushNonCritiques ?? this.pushNonCritiques,
    langue: langue,
  );

  @override
  bool operator ==(Object other) =>
      other is Profil &&
      other.prenom == prenom &&
      other.nom == nom &&
      other.email == email &&
      other.telephone == telephone &&
      other.pushNonCritiques == pushNonCritiques &&
      other.langue == langue;

  @override
  int get hashCode =>
      Object.hash(prenom, nom, email, telephone, pushNonCritiques, langue);
}

/// `profiles.locale`.
///
/// **Une seule valeur au MVP**, et c'est pour cela que l'écran affiche la
/// langue sans la proposer au choix (`design/007-profil.md § 5.1`) : un
/// sélecteur à une entrée promet une traduction qui n'existe pas. L'énumération
/// existe pour que l'ajout d'une deuxième langue soit un cas de plus ici, et
/// rien d'autre à changer ailleurs.
enum Langue {
  francais('fr', AppStrings.profilLangueFrancais);

  const Langue(this.valeurSql, this.libelle);

  final String valeurSql;
  final String libelle;

  /// Une valeur inconnue retombe sur le français : l'application n'a de textes
  /// que dans cette langue, et prétendre le contraire ne servirait personne.
  static Langue depuisSql(String? valeur) => values.firstWhere(
    (Langue langue) => langue.valeurSql == valeur,
    orElse: () => Langue.francais,
  );
}

/// Ce qui peut faire échouer une suppression de compte
/// (`supabase/functions/README.md § delete-account`).
enum ErreurSuppression {
  /// Dernier administrateur actif d'une caserne. La sortie est écrite dans
  /// l'écran : nommer quelqu'un d'abord.
  dernierAdmin('last_admin'),

  /// Le profil est introuvable — session périmée, le plus souvent.
  profilIntrouvable('profile_missing'),

  /// Le compte d'authentification n'a pas pu être fermé. **Les données, elles,
  /// sont déjà effacées** : c'est ce que le message doit dire.
  accesNonFerme('auth_delete_failed'),

  /// Session expirée pendant le geste.
  nonAuthentifie('unauthenticated'),

  reseau('__reseau'),

  inconnue('__inconnue');

  const ErreurSuppression(this.code);

  final String code;

  static ErreurSuppression depuisCode(String? code) => values.firstWhere(
    (ErreurSuppression erreur) => erreur.code == code,
    orElse: () => ErreurSuppression.inconnue,
  );

  /// Le message affiché sous le bouton de la feuille. Il nomme le problème
  /// **et** la sortie (`DESIGN.md § Do's`).
  String message({String? caserne}) => switch (this) {
    ErreurSuppression.dernierAdmin =>
      caserne == null
          ? AppStrings.suppressionDernierAdmin
          : AppStrings.suppressionDernierAdminCaserne(caserne),
    ErreurSuppression.profilIntrouvable =>
      AppStrings.suppressionProfilIntrouvable,
    ErreurSuppression.accesNonFerme => AppStrings.suppressionAccesNonFerme,
    ErreurSuppression.nonAuthentifie => AppStrings.suppressionNonAuthentifie,
    ErreurSuppression.reseau => AppStrings.suppressionReseau,
    ErreurSuppression.inconnue => AppStrings.suppressionEchec,
  };
}

/// L'échec d'une suppression, avec le contexte que le serveur a bien voulu
/// donner.
@immutable
class EchecSuppression implements Exception {
  const EchecSuppression(this.erreur, {this.caserne});

  final ErreurSuppression erreur;

  /// Le nom de la caserne, quand le refus est `last_admin`.
  final String? caserne;

  String get message => erreur.message(caserne: caserne);

  @override
  String toString() => 'EchecSuppression(${erreur.code}, $caserne)';
}
