import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';

/// Par où l'on entre dans une invitation.
///
/// Deux chemins, une seule Edge Function (`accept-invitation`), **exactement
/// l'un des deux** dans le corps de la requête : les deux ensemble ne sont pas
/// une requête plus riche, c'est une requête ambiguë, et le serveur la refuse
/// (`supabase/functions/_shared/invitation_entree.ts`).
enum ModeInvitation {
  /// Le jeton du lien reçu par courriel (ticket 006). Un porteur de droits,
  /// transférable : il ne vit que dans l'URL.
  jeton,

  /// L'identifiant rendu par `my_pending_invitations()` (ticket 051), depuis
  /// l'écran « Aucune caserne ». Il ne désigne rien pour qui n'est pas la
  /// personne invitée : le serveur confronte l'adresse avant tout le reste.
  identifiant,
}

/// Ce qu'on présente au serveur pour entrer dans une caserne.
///
/// Le type porte la règle : une entrée est un jeton **ou** un identifiant,
/// donc le corps envoyé ne peut pas contenir les deux.
@immutable
class EntreeInvitation {
  const EntreeInvitation.jeton(this.valeur) : mode = ModeInvitation.jeton;

  const EntreeInvitation.identifiant(this.valeur)
    : mode = ModeInvitation.identifiant;

  final ModeInvitation mode;
  final String valeur;

  String get valeurNettoyee => valeur.trim();
  bool get vide => valeurNettoyee.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is EntreeInvitation && other.mode == mode && other.valeur == valeur;

  @override
  int get hashCode => Object.hash(mode, valeur);

  @override
  String toString() => 'EntreeInvitation(${mode.name})';
}

/// La caserne qui invite, telle que la renvoie `accept-invitation`.
@immutable
class CaserneInvitation {
  const CaserneInvitation({required this.nom});

  static CaserneInvitation? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final nom = brut['name'];
    if (nom is! String || nom.trim().isEmpty) return null;
    return CaserneInvitation(nom: nom.trim());
  }

  final String nom;
}

/// Qui a envoyé l'invitation. Sert à dire « invitation envoyée par … » et à
/// nommer la personne à qui écrire quand le lien ne marche plus.
@immutable
class InviteurInvitation {
  const InviteurInvitation({required this.libelle});

  static InviteurInvitation? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final nom = <String>[
      (brut['first_name'] as String? ?? '').trim(),
      (brut['last_name'] as String? ?? '').trim(),
    ].where((String part) => part.isNotEmpty).join(' ');
    final email = (brut['email'] as String? ?? '').trim();
    final libelle = nom.isNotEmpty ? nom : email;
    return libelle.isEmpty ? null : InviteurInvitation(libelle: libelle);
  }

  final String libelle;
}

/// Ce que l'acceptation a rapporté.
@immutable
class AcceptationInvitation {
  const AcceptationInvitation({
    required this.dejaAcceptee,
    required this.role,
    this.caserne,
    this.inviteur,
  });

  factory AcceptationInvitation.depuisJson(Map<String, dynamic> corps) {
    final membership = corps['membership'];
    return AcceptationInvitation(
      dejaAcceptee: corps['already_accepted'] as bool? ?? false,
      role: RoleMembre.depuisSql(
        membership is Map ? membership['role'] as String? : null,
      ),
      caserne: CaserneInvitation.depuisJson(corps['station']),
      inviteur: InviteurInvitation.depuisJson(corps['inviter']),
    );
  }

  /// Vrai quand le même lien est rejoué : ce n'est pas une erreur, l'invité
  /// est déjà dans la caserne.
  final bool dejaAcceptee;

  final RoleMembre role;
  final CaserneInvitation? caserne;
  final InviteurInvitation? inviteur;
}

/// Les fins de parcours possibles d'un lien d'invitation.
///
/// Chacune porte son titre et sa phrase : un cul-de-sac sans explication est
/// un défaut (`DESIGN.md § Don't`).
enum ErreurAcceptation {
  jetonManquant(
    AppStrings.invitationIntrouvableTitre,
    AppStrings.invitationJetonManquant,
  ),
  introuvable(
    AppStrings.invitationIntrouvableTitre,
    AppStrings.invitationIntrouvableTexte,
  ),
  expiree(AppStrings.invitationExpireeTitre, AppStrings.invitationExpireeTexte),
  dejaAcceptee(
    AppStrings.invitationDejaAccepteeTitre,
    AppStrings.invitationDejaAccepteeTexte,
  ),
  mauvaisCompte(AppStrings.invitationMauvaisCompteTitre, ''),
  caserneSuspendue(
    AppStrings.invitationCaserneSuspendueTitre,
    AppStrings.invitationCaserneSuspendueTexte,
  ),
  profilManquant(
    AppStrings.erreurTitre,
    AppStrings.invitationProfilManquantTexte,
  ),
  reseau(AppStrings.erreurReseauTitre, AppStrings.erreurReseauTexte),
  inconnue(AppStrings.erreurTitre, AppStrings.invitationEchecTexte);

  const ErreurAcceptation(this.titre, this.texte);

  final String titre;

  /// Vide pour [mauvaisCompte], dont la phrase nomme les deux adresses et se
  /// compose donc dans [EchecAcceptation.message].
  final String texte;

  /// Vrai quand réessayer a un sens : le lien est bon, c'est le réseau ou le
  /// serveur qui a lâché.
  bool get reessayable => this == reseau || this == inconnue;

  static ErreurAcceptation depuisCode(String? code) => switch (code) {
    'invitation_not_found' => introuvable,
    'invitation_expired' => expiree,
    'invitation_already_accepted' => dejaAcceptee,
    'email_mismatch' => mauvaisCompte,
    'station_suspended' => caserneSuspendue,
    'profile_missing' => profilManquant,
    'invalid_body' => jetonManquant,
    _ => inconnue,
  };
}

/// Un lien qui ne mène pas dans la caserne, avec tout ce qu'il faut pour
/// proposer une sortie.
class EchecAcceptation implements Exception {
  const EchecAcceptation(
    this.erreur, {
    this.caserne,
    this.inviteur,
    this.adresseInviteeMasquee,
    this.adresseCourante,
  });

  final ErreurAcceptation erreur;
  final CaserneInvitation? caserne;
  final InviteurInvitation? inviteur;

  /// L'adresse invitée, masquée par le serveur (`m***e@exemple.fr`) : elle
  /// guide sans révéler l'adresse de quelqu'un d'autre.
  final String? adresseInviteeMasquee;

  /// L'adresse de la session en cours.
  final String? adresseCourante;

  String get titre => erreur.titre;

  String get message {
    if (erreur != ErreurAcceptation.mauvaisCompte) return erreur.texte;

    // **Entrée par identifiant** (ticket 051) : le serveur ne rend alors ni la
    // caserne ni l'adresse masquée, et c'est volontaire — les rendre ferait
    // un oracle d'existence, et l'adresse masquée n'a pas lieu d'être ici
    // (`docs/SCHEMA.md § 3`). Elle existe sur le chemin du jeton parce qu'un
    // lien se transfère et que son porteur doit reconnaître de quelle boîte il
    // s'agit ; un identifiant n'a été donné qu'à la session qu'il concerne.
    final masquee = adresseInviteeMasquee;
    if (masquee == null) {
      return AppStrings.invitationMauvaisCompteTexteSansAdresse(
        adresseCourante ?? AppStrings.valueUndefined,
      );
    }

    return AppStrings.invitationMauvaisCompteTexte(
      adresseInvitee: masquee,
      adresseCourante: adresseCourante ?? AppStrings.valueUndefined,
    );
  }

  /// La sortie de secours, quand on sait à qui écrire.
  String? get sortie {
    if (erreur != ErreurAcceptation.expiree) return null;
    final nom = caserne?.nom;
    return nom == null ? null : AppStrings.invitationContacterAdmin(nom);
  }

  @override
  String toString() => 'EchecAcceptation(${erreur.name})';
}
