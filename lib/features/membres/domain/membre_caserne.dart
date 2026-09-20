import 'package:flutter/foundation.dart';

import '../../../core/session/appartenance.dart';

/// Un membre de la caserne, vu par l'écran d'administration.
///
/// Une ligne de `memberships` (`docs/SCHEMA.md § 2.3`) jointe aux colonnes
/// affichables de `profiles` (§ 2.2). Aucune colonne inventée.
@immutable
class MembreCaserne {
  const MembreCaserne({
    required this.id,
    required this.userId,
    required this.role,
    required this.statut,
    required this.prenom,
    required this.nom,
    required this.email,
    this.nomAffiche,
  });

  factory MembreCaserne.depuisJson(Map<String, dynamic> ligne) {
    final profil = ligne['profiles'];
    final champs = profil is Map<String, dynamic>
        ? profil
        : const <String, dynamic>{};

    return MembreCaserne(
      id: ligne['id']! as String,
      userId: ligne['user_id']! as String,
      role: RoleMembre.depuisSql(ligne['role'] as String?),
      statut: StatutMembre.depuisSql(ligne['status'] as String?),
      prenom: (champs['first_name'] as String? ?? '').trim(),
      nom: (champs['last_name'] as String? ?? '').trim(),
      email: (champs['email'] as String? ?? '').trim(),
      nomAffiche: ligne['display_name'] as String?,
    );
  }

  final String id;
  final String userId;
  final RoleMembre role;
  final StatutMembre statut;
  final String prenom;
  final String nom;
  final String email;
  final String? nomAffiche;

  /// Ce qu'on écrit en tête de ligne. Un profil vide ne laisse jamais un blanc :
  /// l'adresse e-mail fait foi tant que le nom n'est pas saisi.
  String get libelle {
    final complet = <String>[
      prenom,
      nom,
    ].where((String part) => part.isNotEmpty).join(' ');
    if (complet.isNotEmpty) return complet;

    final affiche = nomAffiche?.trim() ?? '';
    return affiche.isNotEmpty ? affiche : email;
  }

  /// Clé de tri : par nom, puis prénom, puis adresse. Stable d'un chargement
  /// à l'autre, insensible à la casse et aux accents du tri par défaut.
  String get cleDeTri => '${nom.toLowerCase()} ${prenom.toLowerCase()} $email';

  bool get estAdmin => role == RoleMembre.admin;

  @override
  bool operator ==(Object other) =>
      other is MembreCaserne &&
      other.id == id &&
      other.userId == userId &&
      other.role == role &&
      other.statut == statut &&
      other.prenom == prenom &&
      other.nom == nom &&
      other.email == email &&
      other.nomAffiche == nomAffiche;

  @override
  int get hashCode =>
      Object.hash(id, userId, role, statut, prenom, nom, email, nomAffiche);
}
