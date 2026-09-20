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
    this.derniereSaisie,
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

  /// Date de la ligne de `availabilities` la plus récemment écrite par ce
  /// membre pour cette caserne (`v_member_last_availability`). `null` quand il
  /// n'a jamais saisi une seule disponibilité.
  final DateTime? derniereSaisie;

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

  bool get estActif => statut == StatutMembre.actif;

  bool get estDesactive => statut == StatutMembre.desactive;

  /// Un admin qui compte dans le quorum de la caserne : le déclencheur
  /// `memberships_guard_admin` (migration `0010`) ne compte que ceux-là.
  bool get estAdminActif => estAdmin && estActif;

  /// La même ligne, avec sa date de dernière saisie. Les deux lectures sont
  /// faites séparément (deux tables, deux politiques) et recollées ici.
  MembreCaserne avecDerniereSaisie(DateTime? date) => MembreCaserne(
    id: id,
    userId: userId,
    role: role,
    statut: statut,
    prenom: prenom,
    nom: nom,
    email: email,
    nomAffiche: nomAffiche,
    derniereSaisie: date,
  );

  /// Vrai si ce membre répond à une recherche déjà normalisée
  /// ([normaliserRecherche]). Le nom, le nom affiché et l'adresse sont
  /// cherchés ensemble : le chef de centre tape ce qu'il a sous les yeux.
  bool correspondA(String requeteNormalisee) {
    if (requeteNormalisee.isEmpty) return true;
    final champs = normaliserRecherche(
      <String>[prenom, nom, nomAffiche ?? '', email].join(' '),
    );
    return champs.contains(requeteNormalisee);
  }

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
      other.nomAffiche == nomAffiche &&
      other.derniereSaisie == derniereSaisie;

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    role,
    statut,
    prenom,
    nom,
    email,
    nomAffiche,
    derniereSaisie,
  );
}

/// Met une saisie de recherche à plat : minuscules, sans accent, espaces
/// réduits.
///
/// « Émilie ROUX » et « emilie roux » doivent se trouver l'un l'autre : une
/// recherche sensible aux accents est une recherche qui ne trouve pas, et
/// personne ne tape « é » sur un clavier de téléphone tenu d'une main.
String normaliserRecherche(String texte) {
  final bas = texte.toLowerCase().trim();
  final tampon = StringBuffer();
  for (final unite in bas.runes) {
    tampon.write(_sansAccent[unite] ?? String.fromCharCode(unite));
  }
  return tampon.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Les lettres accentuées du français, ramenées à leur lettre de base.
/// `intl` n'est pas embarqué (`core/l10n/format_date.dart`) : la table tient
/// en dix lignes et couvre la langue de l'application.
const Map<int, String> _sansAccent = <int, String>{
  0xE0: 'a', 0xE1: 'a', 0xE2: 'a', 0xE3: 'a', 0xE4: 'a', 0xE5: 'a',
  0xE6: 'ae',
  0xE7: 'c',
  0xE8: 'e', 0xE9: 'e', 0xEA: 'e', 0xEB: 'e',
  0xEC: 'i', 0xED: 'i', 0xEE: 'i', 0xEF: 'i',
  0xF1: 'n',
  0xF2: 'o', 0xF3: 'o', 0xF4: 'o', 0xF5: 'o', 0xF6: 'o',
  0xF9: 'u', 0xFA: 'u', 0xFB: 'u', 0xFC: 'u',
  0xFD: 'y', 0xFF: 'y',
  0x153: 'oe',
};
