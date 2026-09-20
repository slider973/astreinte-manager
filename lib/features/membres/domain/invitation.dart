import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';

/// Une invitation en attente (`docs/SCHEMA.md § 2.4`).
///
/// **Le jeton n'est pas là, et c'est voulu** : la colonne `token` est hors du
/// grant de select du rôle `authenticated` (migration `0008`). Un écran admin
/// ne voit jamais le lien qu'il a envoyé.
@immutable
class Invitation {
  const Invitation({
    required this.id,
    required this.email,
    required this.role,
    required this.expireLe,
    required this.creeLe,
  });

  factory Invitation.depuisJson(Map<String, dynamic> ligne) => Invitation(
    id: ligne['id']! as String,
    email: (ligne['email'] as String? ?? '').trim(),
    role: RoleMembre.depuisSql(ligne['role'] as String?),
    expireLe: DateTime.parse(ligne['expires_at']! as String).toLocal(),
    creeLe: DateTime.parse(ligne['created_at']! as String).toLocal(),
  );

  final String id;
  final String email;
  final RoleMembre role;
  final DateTime expireLe;
  final DateTime creeLe;

  bool expiree(DateTime maintenant) => expireLe.isBefore(maintenant);

  @override
  bool operator ==(Object other) =>
      other is Invitation &&
      other.id == id &&
      other.email == email &&
      other.role == role &&
      other.expireLe == expireLe &&
      other.creeLe == creeLe;

  @override
  int get hashCode => Object.hash(id, email, role, expireLe, creeLe);
}

/// Le sort d'une adresse dans un envoi de lot (`supabase/functions/README.md`).
enum StatutResultatInvitation {
  invitee(AppStrings.resultatInvitee),
  renvoyee(AppStrings.resultatRenvoyee),
  erreur(AppStrings.resultatEchec);

  const StatutResultatInvitation(this.libelle);

  final String libelle;

  /// Un statut inconnu est traité comme une erreur : on n'annonce jamais une
  /// réussite sur une valeur qu'on ne comprend pas.
  static StatutResultatInvitation depuisApi(String? valeur) => switch (valeur) {
    'invited' => invitee,
    'resent' => renvoyee,
    _ => erreur,
  };
}

/// Pourquoi une adresse n'a pas été invitée. Chaque motif porte sa phrase.
enum MotifEchecInvitation {
  dejaMembre(AppStrings.inviteDejaMembre),
  adresseInvalide(AppStrings.inviteAdresseInvalide),
  conflit(AppStrings.inviteConflit),
  compteImpossible(AppStrings.inviteCompteImpossible),
  erreurServeur(AppStrings.inviteErreurServeur);

  const MotifEchecInvitation(this.message);

  final String message;

  static MotifEchecInvitation depuisCode(String? code) => switch (code) {
    'already_member' => dejaMembre,
    'invalid_email' => adresseInvalide,
    'conflict' => conflit,
    'account_failed' => compteImpossible,
    _ => erreurServeur,
  };
}

/// Le sort d'une adresse, prêt à afficher.
@immutable
class ResultatInvitation {
  const ResultatInvitation({
    required this.email,
    required this.statut,
    this.motif,
    this.courrielEnvoye = true,
  });

  factory ResultatInvitation.depuisJson(Map<String, dynamic> ligne) {
    final statut = StatutResultatInvitation.depuisApi(
      ligne['status'] as String?,
    );
    return ResultatInvitation(
      email: (ligne['email'] as String? ?? '').trim(),
      statut: statut,
      motif: statut == StatutResultatInvitation.erreur
          ? MotifEchecInvitation.depuisCode(ligne['code'] as String?)
          : null,
      // Absent du corps : on ne prétend pas qu'un courriel est parti.
      courrielEnvoye: ligne['email_sent'] as bool? ?? false,
    );
  }

  final String email;
  final StatutResultatInvitation statut;

  /// Renseigné pour les seules erreurs.
  final MotifEchecInvitation? motif;

  /// Faux quand l'invitation existe mais que le courriel n'est pas parti. Ce
  /// n'est pas un échec de l'invitation : c'est un renvoi à proposer.
  final bool courrielEnvoye;

  bool get enEchec => statut == StatutResultatInvitation.erreur;

  /// La phrase à afficher sous l'adresse, ou `null` si tout s'est bien passé.
  String? get detail {
    if (motif != null) return motif!.message;
    if (!courrielEnvoye) return AppStrings.resultatCourrielNonParti;
    return null;
  }
}

/// Le résultat complet d'un envoi de lot.
@immutable
class RapportInvitations {
  const RapportInvitations({required this.resultats});

  factory RapportInvitations.depuisJson(Map<String, dynamic> corps) {
    final brut = corps['results'];
    final lignes = brut is List ? brut : const <dynamic>[];
    return RapportInvitations(
      resultats: List<ResultatInvitation>.unmodifiable(
        lignes.whereType<Map<String, dynamic>>().map(
          ResultatInvitation.depuisJson,
        ),
      ),
    );
  }

  final List<ResultatInvitation> resultats;

  int get envoyees =>
      resultats.where((ResultatInvitation r) => !r.enEchec).length;

  int get echecs => resultats.where((ResultatInvitation r) => r.enEchec).length;

  /// Les adresses en échec, pour proposer de les réessayer seules.
  List<String> get adressesEnEchec => resultats
      .where((ResultatInvitation r) => r.enEchec)
      .map((ResultatInvitation r) => r.email)
      .toList(growable: false);

  bool get toutEstPasse => echecs == 0;
}

/// Les refus qui portent sur la requête entière, pas sur une adresse.
enum ErreurInvitation {
  requeteInvalide(AppStrings.inviteRequeteInvalide),
  nonAdmin(AppStrings.inviteNonAdmin),
  caserneSuspendue(AppStrings.inviteCaserneSuspendue),
  caserneInconnue(AppStrings.inviteCaserneInconnue),
  reseau(AppStrings.erreurReseauTexte),
  inconnue(AppStrings.erreurTexteGenerique);

  const ErreurInvitation(this.message);

  final String message;

  static ErreurInvitation depuisCode(String? code) => switch (code) {
    'invalid_body' => requeteInvalide,
    'not_admin' || 'unauthenticated' => nonAdmin,
    'station_suspended' => caserneSuspendue,
    'station_not_found' => caserneInconnue,
    _ => inconnue,
  };
}

/// Erreur nommée, levée par le dépôt et affichée telle quelle.
class EchecInvitation implements Exception {
  const EchecInvitation(this.erreur);

  final ErreurInvitation erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecInvitation(${erreur.name})';
}
