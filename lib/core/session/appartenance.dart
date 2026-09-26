import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';

/// `membership_role` (`docs/SCHEMA.md § 1`).
enum RoleMembre {
  membre('member', AppStrings.roleMembre),
  admin('admin', AppStrings.roleAdmin);

  const RoleMembre(this.valeurSql, this.libelle);

  final String valeurSql;
  final String libelle;

  /// Un rôle inconnu est traité comme un simple membre : on n'accorde jamais
  /// de privilège sur une valeur qu'on ne comprend pas.
  static RoleMembre depuisSql(String? valeur) => values.firstWhere(
    (role) => role.valeurSql == valeur,
    orElse: () => RoleMembre.membre,
  );
}

/// `membership_status` (`docs/SCHEMA.md § 1`).
enum StatutMembre {
  invite('invited'),
  actif('active'),
  desactive('disabled');

  const StatutMembre(this.valeurSql);

  final String valeurSql;

  static StatutMembre depuisSql(String? valeur) => values.firstWhere(
    (statut) => statut.valeurSql == valeur,
    orElse: () => StatutMembre.invite,
  );
}

/// Une ligne de `memberships`, jointe au nom de sa caserne.
@immutable
class Appartenance {
  const Appartenance({
    required this.id,
    required this.stationId,
    required this.nomCaserne,
    required this.role,
    required this.statut,
    this.nomAffiche,
    this.roleConfirme = true,
  });

  /// Construit depuis la réponse PostgREST.
  ///
  /// Colonnes de `docs/SCHEMA.md § 2.3`, jointes à `stations.name`
  /// (§ 2.1). Aucune colonne inventée.
  factory Appartenance.depuisJson(Map<String, dynamic> ligne) {
    final caserne = ligne['stations'];
    return Appartenance(
      id: ligne['id']! as String,
      stationId: ligne['station_id']! as String,
      nomCaserne: caserne is Map<String, dynamic>
          ? (caserne['name'] as String? ?? '')
          : '',
      role: RoleMembre.depuisSql(ligne['role'] as String?),
      statut: StatutMembre.depuisSql(ligne['status'] as String?),
      nomAffiche: ligne['display_name'] as String?,
    );
  }

  final String id;
  final String stationId;
  final String nomCaserne;
  final RoleMembre role;
  final StatutMembre statut;
  final String? nomAffiche;

  /// Vrai quand [role] vient d'une lecture de la base ; faux pour ce qui est
  /// restauré depuis l'appareil ([commeMembre]), dont le rôle n'est **pas
  /// connu** — « membre » y est une prudence, pas un fait.
  ///
  /// Un écran qui **affirme** quelque chose d'après le rôle doit le lire : le
  /// refus d'une proposition ne promet « ton chef de centre sera prévenu »
  /// que si l'on sait que le pompier n'est pas administrateur — un chef seul
  /// dans sa caserne, restauré en membre, lirait sinon une promesse que la
  /// base ne soutient pas (ticket 055).
  final bool roleConfirme;

  bool get estActive => statut == StatutMembre.actif;

  bool get estAdmin => role == RoleMembre.admin;

  /// La même appartenance, **sans privilège**.
  ///
  /// Sert à tout ce qui ne vient pas d'une lecture confirmée par la base —
  /// aujourd'hui l'instantané gardé sur l'appareil (ticket 027). Un rôle qu'on
  /// n'a pas pu revérifier n'accorde rien : c'est la règle déjà écrite dans
  /// [RoleMembre.depuisSql], appliquée à une valeur qu'on ne peut pas
  /// confirmer plutôt qu'à une valeur qu'on ne comprend pas.
  ///
  /// Le résultat porte `roleConfirme: false`, même quand le rôle était déjà
  /// « membre » : ce qui n'a pas été revérifié n'est pas confirmé.
  Appartenance get commeMembre => Appartenance(
    id: id,
    stationId: stationId,
    nomCaserne: nomCaserne,
    role: RoleMembre.membre,
    statut: statut,
    nomAffiche: nomAffiche,
    roleConfirme: false,
  );

  @override
  bool operator ==(Object other) =>
      other is Appartenance &&
      other.id == id &&
      other.stationId == stationId &&
      other.nomCaserne == nomCaserne &&
      other.role == role &&
      other.statut == statut &&
      other.nomAffiche == nomAffiche &&
      other.roleConfirme == roleConfirme;

  @override
  int get hashCode => Object.hash(
    id,
    stationId,
    nomCaserne,
    role,
    statut,
    nomAffiche,
    roleConfirme,
  );
}
