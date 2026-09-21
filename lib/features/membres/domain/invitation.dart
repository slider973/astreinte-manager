import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';

/// Ce que la caserne sait de l'envoi du courriel d'une invitation.
///
/// Trois états, lus dans les deux colonnes `email_sent_at` / `email_error`
/// de la migration `0035` (`docs/SCHEMA.md § 2.4`). Le troisième n'est pas un
/// quatrième nom pour [nonParti] : une invitation créée avant la migration ne
/// porte aucune trace, et la déclarer en échec serait inventer un fait.
enum EnvoiCourriel {
  /// Un motif d'échec, et aucune date : personne n'a été prévenu.
  nonParti,

  /// Une date : le courriel est parti, à cette date.
  parti,

  /// Les deux colonnes vides. **On ne sait pas**, et surtout pas « non
  /// envoyé ».
  inconnu,
}

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
    this.prenom,
    this.nom,
    this.courrielEnvoyeLe,
    this.courrielEnEchec = false,
  });

  factory Invitation.depuisJson(Map<String, dynamic> ligne) => Invitation(
    id: ligne['id']! as String,
    email: (ligne['email'] as String? ?? '').trim(),
    role: RoleMembre.depuisSql(ligne['role'] as String?),
    expireLe: DateTime.parse(ligne['expires_at']! as String).toLocal(),
    creeLe: DateTime.parse(ligne['created_at']! as String).toLocal(),
    prenom: _texte(ligne['first_name']),
    nom: _texte(ligne['last_name']),
    courrielEnvoyeLe: _date(ligne['email_sent_at']),
    // Le motif lui-même ne monte pas : « aucun fournisseur de courriel
    // configuré » se diagnostique dans les journaux, il ne se lit pas dans un
    // écran d'administration de caserne. Seul le fait qu'il existe compte.
    courrielEnEchec: _texte(ligne['email_error']) != null,
  );

  static String? _texte(Object? valeur) =>
      valeur is String && valeur.trim().isNotEmpty ? valeur.trim() : null;

  static DateTime? _date(Object? valeur) =>
      valeur is String ? DateTime.tryParse(valeur)?.toLocal() : null;

  final String id;
  final String email;
  final RoleMembre role;
  final DateTime expireLe;
  final DateTime creeLe;

  /// Le nom saisi par l'administrateur à l'import (ticket 047). Absent des
  /// invitations créées à la main : le formulaire ne demande que des adresses.
  final String? prenom;
  final String? nom;

  /// L'horodatage du dernier envoi **réussi** du courriel, s'il y en a eu un.
  final DateTime? courrielEnvoyeLe;

  /// Vrai quand le dernier envoi a échoué. Le motif reste côté base : il est
  /// technique, et le chef de centre n'en fait rien.
  final bool courrielEnEchec;

  /// Ce qu'on peut affirmer de l'envoi, et rien de plus.
  ///
  /// L'ordre de lecture est celui de `docs/SCHEMA.md § 2.4` : un motif sans
  /// date dit que personne n'a été prévenu ; une date dit que c'est parti,
  /// même si un renvoi a échoué depuis ; deux colonnes vides ne disent rien.
  EnvoiCourriel get envoiCourriel {
    if (courrielEnEchec && courrielEnvoyeLe == null) {
      return EnvoiCourriel.nonParti;
    }
    if (courrielEnvoyeLe != null) return EnvoiCourriel.parti;
    return EnvoiCourriel.inconnu;
  }

  /// « Marie Lefèbvre », ou `null` quand l'invitation n'a pas de nom.
  ///
  /// Sert de titre à la ligne d'invitation en attente. Sans lui, un chef de
  /// centre qui vient d'importer sa caserne passerait deux semaines devant une
  /// liste d'adresses.
  String? get nomComplet {
    final morceaux = <String>[?prenom, ?nom];
    return morceaux.isEmpty ? null : morceaux.join(' ');
  }

  bool expiree(DateTime maintenant) => expireLe.isBefore(maintenant);

  @override
  bool operator ==(Object other) =>
      other is Invitation &&
      other.id == id &&
      other.email == email &&
      other.role == role &&
      other.expireLe == expireLe &&
      other.creeLe == creeLe &&
      other.prenom == prenom &&
      other.nom == nom &&
      other.courrielEnvoyeLe == courrielEnvoyeLe &&
      other.courrielEnEchec == courrielEnEchec;

  @override
  int get hashCode => Object.hash(
    id,
    email,
    role,
    expireLe,
    creeLe,
    prenom,
    nom,
    courrielEnvoyeLe,
    courrielEnEchec,
  );
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
///
/// Deux codes de refus global — caserne suspendue, appelant qui n'est plus
/// admin — redescendent ici quand l'état change entre le contrôle préalable
/// et la création : le serveur les rend alors **par adresse**. Les ranger en
/// « incident serveur » enverrait réessayer quelque chose qui ne passera pas.
enum MotifEchecInvitation {
  dejaMembre(AppStrings.inviteDejaMembre),
  adresseInvalide(AppStrings.inviteAdresseInvalide),
  conflit(AppStrings.inviteConflit),
  compteImpossible(AppStrings.inviteCompteImpossible),
  caserneSuspendue(AppStrings.inviteCaserneSuspendue),
  nonAdmin(AppStrings.inviteNonAdmin),

  /// Le plafond horaire d'invitations (ticket 038). Sa phrase **ne peut pas
  /// être une constante** : elle porte le délai avant de pouvoir réessayer,
  /// qui change à chaque seconde. Elle vient donc du serveur, et
  /// [MotifEchecInvitation.message] n'est ici qu'un secours.
  debitAtteint(AppStrings.inviteDebitAtteint, messageDuServeur: true),

  erreurServeur(AppStrings.inviteErreurServeur);

  const MotifEchecInvitation(this.message, {this.messageDuServeur = false});

  /// La phrase de secours. Affichée telle quelle sauf si [messageDuServeur].
  final String message;

  /// Vrai quand la phrase affichable est composée par le serveur : la
  /// constante d'à côté ne saurait pas dire *quand* réessayer. Les autres
  /// motifs gardent la phrase de l'application, mieux tournée pour l'écran
  /// que celle de l'API.
  final bool messageDuServeur;

  static MotifEchecInvitation depuisCode(String? code) => switch (code) {
    'already_member' => dejaMembre,
    'invalid_email' => adresseInvalide,
    'conflict' => conflit,
    'account_failed' => compteImpossible,
    'station_suspended' => caserneSuspendue,
    'not_admin' => nonAdmin,
    'rate_limited' => debitAtteint,
    _ => erreurServeur,
  };
}

/// La portée du plafond de débit : la caserne, ou le compte qui invite.
///
/// Un super-administrateur est compté par acteur, toutes casernes confondues
/// (`supabase/functions/README.md § Le plafond de débit`).
enum PorteePlafond {
  caserne,
  acteur;

  static PorteePlafond depuisApi(String? valeur) =>
      valeur == 'actor' ? acteur : caserne;
}

/// Les faits d'un refus de débit, à côté de la phrase déjà composée.
///
/// Ils ne sont pas là pour reconstruire le message — le serveur l'a fait —
/// mais pour que l'écran puisse composer autre chose, et pour tenir la
/// promesse « dis quand réessayer » même si la phrase venait à manquer.
@immutable
class PlafondInvitations {
  const PlafondInvitations({
    required this.portee,
    this.plafond,
    this.utilisees,
    this.restantes,
    this.fenetreMinutes,
    this.reessayerLe,
    this.delaiAvantNouvelEssai,
  });

  /// Les faits tels que l'API les rend : sous `rate_limit` pour un résultat
  /// par adresse, à plat dans `error` pour le refus global.
  static PlafondInvitations? depuisJson(Object? valeur) {
    if (valeur is! Map) return null;

    final secondes = _entier(valeur['retry_after_seconds']);
    final quand = valeur['retry_at'];
    return PlafondInvitations(
      portee: PorteePlafond.depuisApi(valeur['scope'] as String?),
      plafond: _entier(valeur['limit']),
      utilisees: _entier(valeur['used']),
      restantes: _entier(valeur['remaining']),
      fenetreMinutes: _entier(valeur['window_minutes']),
      reessayerLe: quand is String ? DateTime.tryParse(quand)?.toLocal() : null,
      delaiAvantNouvelEssai: secondes == null
          ? null
          : Duration(seconds: secondes < 0 ? 0 : secondes),
    );
  }

  final PorteePlafond portee;
  final int? plafond;
  final int? utilisees;
  final int? restantes;
  final int? fenetreMinutes;

  /// Le moment exact où le budget se relâche, déjà en heure locale.
  final DateTime? reessayerLe;

  final Duration? delaiAvantNouvelEssai;

  /// Ce qu'on affiche si le serveur n'a pas envoyé sa phrase. Arrondi à la
  /// minute **supérieure** : annoncer moins que le délai réel ferait réessayer
  /// pour rien.
  String get messageDeSecours {
    final delai = delaiAvantNouvelEssai;
    if (delai == null) return AppStrings.inviteDebitAtteint;
    return AppStrings.inviteDebitAtteintDans((delai.inSeconds / 60).ceil());
  }

  static int? _entier(Object? valeur) {
    if (valeur is int) return valeur;
    if (valeur is num) return valeur.round();
    if (valeur is String) return int.tryParse(valeur);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PlafondInvitations &&
      other.portee == portee &&
      other.plafond == plafond &&
      other.utilisees == utilisees &&
      other.restantes == restantes &&
      other.fenetreMinutes == fenetreMinutes &&
      other.reessayerLe == reessayerLe &&
      other.delaiAvantNouvelEssai == delaiAvantNouvelEssai;

  @override
  int get hashCode => Object.hash(
    portee,
    plafond,
    utilisees,
    restantes,
    fenetreMinutes,
    reessayerLe,
    delaiAvantNouvelEssai,
  );
}

/// Le sort d'une adresse, prêt à afficher.
@immutable
class ResultatInvitation {
  const ResultatInvitation({
    required this.email,
    required this.statut,
    this.motif,
    this.messageServeur,
    this.plafond,
    this.courrielEnvoye = true,
  });

  factory ResultatInvitation.depuisJson(Map<String, dynamic> ligne) {
    final statut = StatutResultatInvitation.depuisApi(
      ligne['status'] as String?,
    );
    final motif = statut == StatutResultatInvitation.erreur
        ? MotifEchecInvitation.depuisCode(ligne['code'] as String?)
        : null;
    final message = ligne['message'];

    return ResultatInvitation(
      email: (ligne['email'] as String? ?? '').trim(),
      statut: statut,
      motif: motif,
      // La phrase du serveur n'est retenue que pour les motifs qui la
      // réclament : ailleurs, la copie de l'écran est mieux tournée.
      messageServeur: motif != null && motif.messageDuServeur
          ? _phrase(message)
          : null,
      plafond: PlafondInvitations.depuisJson(ligne['rate_limit']),
      // Absent du corps : on ne prétend pas qu'un courriel est parti.
      courrielEnvoye: ligne['email_sent'] as bool? ?? false,
    );
  }

  static String? _phrase(Object? valeur) =>
      valeur is String && valeur.trim().isNotEmpty ? valeur.trim() : null;

  final String email;
  final StatutResultatInvitation statut;

  /// Renseigné pour les seules erreurs.
  final MotifEchecInvitation? motif;

  /// La phrase composée par le serveur, quand le motif la réclame.
  final String? messageServeur;

  /// Les faits du refus de débit, s'il y en a un.
  final PlafondInvitations? plafond;

  /// Faux quand l'invitation existe mais que le courriel n'est pas parti. Ce
  /// n'est pas un échec de l'invitation : c'est un renvoi à proposer.
  final bool courrielEnvoye;

  bool get enEchec => statut == StatutResultatInvitation.erreur;

  /// La phrase à afficher sous l'adresse, ou `null` si tout s'est bien passé.
  ///
  /// Un refus de débit affiche le message du serveur : lui seul sait de
  /// combien de temps il parle. Sans lui, les faits le disent encore ; sans
  /// eux, la constante reste vraie, en moins précis.
  String? get detail {
    final motif = this.motif;
    if (motif != null) {
      if (!motif.messageDuServeur) return motif.message;
      return messageServeur ?? plafond?.messageDeSecours ?? motif.message;
    }
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

  /// Les invitations que le serveur a acceptées, courriel parti ou non.
  ///
  /// **Ce n'est pas un compte d'envois**, et le nom le dit maintenant : une
  /// invitation peut exister en base sans que le moindre courriel soit sorti
  /// (`email_sent` faux). Compter les deux ensemble a fait afficher « 3
  /// invitations envoyées » au-dessus de « aucun courriel n'est parti »
  /// (ticket 048). Pour les envois, voir [courrielsPartis].
  int get creees =>
      resultats.where((ResultatInvitation r) => !r.enEchec).length;

  /// Les invitations créées **dont le courriel est réellement sorti**.
  ///
  /// Le seul compte qui autorise le verbe « envoyée », à l'écran comme dans
  /// le compteur d'avancement.
  int get courrielsPartis => resultats
      .where((ResultatInvitation r) => !r.enEchec && r.courrielEnvoye)
      .length;

  int get echecs => resultats.where((ResultatInvitation r) => r.enEchec).length;

  /// Les refus, dans l'ordre où le serveur les a rendus.
  ///
  /// Ce sont les seules lignes qu'un compte rendu a besoin de **nommer** :
  /// une réussite se compte, un refus se lit.
  List<ResultatInvitation> get refus => resultats
      .where((ResultatInvitation r) => r.enEchec)
      .toList(growable: false);

  /// Les invitations créées dont le courriel n'est jamais parti.
  ///
  /// Ce n'est pas un échec d'invitation — la ligne existe, le renvoi la
  /// relance —, et c'est un **nombre** plutôt qu'une liste : quand aucun
  /// fournisseur de courriel n'est configuré, tout l'envoi est dans ce cas.
  int get courrielsNonPartis => resultats
      .where((ResultatInvitation r) => !r.enEchec && !r.courrielEnvoye)
      .length;

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

  /// Le plafond horaire, quand **aucune** adresse du lot n'est passée : le
  /// serveur rend alors un 429 plutôt qu'une liste. Même règle que pour
  /// [MotifEchecInvitation.debitAtteint] : la phrase vient du serveur.
  debitAtteint(AppStrings.inviteDebitAtteint, messageDuServeur: true),

  /// Une réponse est arrivée, mais elle ne se lit pas : fonction absente,
  /// passerelle qui refuse, corps vide. **Ce n'est pas le réseau** — quelque
  /// chose a répondu —, et réessayer dans la minute ne changera rien tant que
  /// le serveur n'est pas réparé.
  serveurIndisponible(AppStrings.inviteServeurIndisponible),

  /// Rien n'est revenu, et le navigateur ne se dit pas hors ligne. On ne sait
  /// donc pas ce qui s'est passé, et surtout pas si la demande est arrivée :
  /// la phrase ne promet aucune cause.
  sansReponse(AppStrings.inviteSansReponse),

  /// La seule erreur qui a le droit de parler de connexion : le navigateur
  /// affirme être hors ligne, et un « non » de sa part est sûr
  /// (`lib/core/reseau/connectivite.dart`).
  reseau(AppStrings.erreurReseauTexte),

  inconnue(AppStrings.erreurTexteGenerique);

  const ErreurInvitation(this.message, {this.messageDuServeur = false});

  /// La phrase de secours. Affichée telle quelle sauf si [messageDuServeur].
  final String message;

  /// Voir [MotifEchecInvitation.messageDuServeur].
  final bool messageDuServeur;

  static ErreurInvitation depuisCode(String? code) => switch (code) {
    'invalid_body' => requeteInvalide,
    'not_admin' || 'unauthenticated' => nonAdmin,
    'station_suspended' => caserneSuspendue,
    'station_not_found' => caserneInconnue,
    'rate_limited' => debitAtteint,
    _ => inconnue,
  };
}

/// Erreur nommée, levée par le dépôt et affichée telle quelle.
class EchecInvitation implements Exception {
  const EchecInvitation(this.erreur, {this.messageServeur, this.plafond});

  /// Lit `error` : `{"code", "message", …faits du plafond}` — pour un refus
  /// de débit, les faits sont à plat à côté du code
  /// (`supabase/functions/README.md § Le plafond de débit`).
  factory EchecInvitation.depuisCorps(Map<Object?, Object?> erreur) {
    final code = ErreurInvitation.depuisCode(erreur['code'] as String?);
    if (!code.messageDuServeur) return EchecInvitation(code);

    final message = erreur['message'];
    return EchecInvitation(
      code,
      messageServeur: message is String && message.trim().isNotEmpty
          ? message.trim()
          : null,
      plafond: PlafondInvitations.depuisJson(erreur),
    );
  }

  final ErreurInvitation erreur;

  /// La phrase composée par le serveur, quand le code la réclame.
  final String? messageServeur;

  /// Les faits du refus de débit, s'il y en a un.
  final PlafondInvitations? plafond;

  String get message {
    if (!erreur.messageDuServeur) return erreur.message;
    return messageServeur ?? plafond?.messageDeSecours ?? erreur.message;
  }

  @override
  String toString() => 'EchecInvitation(${erreur.name})';
}
