import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';
import '../../../core/session/email.dart';
import 'fichier_membres.dart';
import 'invitation.dart';
import 'liste_adresses.dart' show maxAdressesParEnvoi;
import 'membre_caserne.dart';

/// La fenêtre du plafond d'invitations (`invitation_rate_limit`, migration
/// `0032`). Une heure glissante, pas un compteur remis à zéro à l'heure ronde.
const Duration fenetrePlafond = Duration(hours: 1);

/// Le plafond horaire par défaut d'une caserne, quand `settings` ne le dit pas.
const int plafondInvitationsParDefaut = 60;

/// Ce qui va arriver à une ligne du fichier, décidé **avant** tout envoi.
///
/// Les quatre premiers motifs reprennent le vocabulaire du ticket 006 : une
/// ligne écartée ici porte le même nom qu'une adresse refusée par le serveur.
/// Les deux derniers n'existent que parce qu'il y a un fichier — un tableur
/// peut répéter une personne ou laisser une case vide, un champ de saisie non.
enum VerdictApercu {
  /// Elle partira. Rien à signaler.
  aInviter,

  /// Elle partira, sans nom. L'adresse fait entrer quelqu'un dans la caserne,
  /// pas le nom : refuser la ligne priverait le chef de centre d'une personne
  /// pour une colonne vide.
  aInviterSansNom,

  /// Déjà membre actif : rien à envoyer (`already_member` du 006).
  dejaMembre,

  /// Une invitation est déjà en attente pour cette adresse. Ignorée, et c'est
  /// ce qui rend l'import rejouable : redéposer le même fichier après un refus
  /// de débit n'envoie que ce qui manquait.
  dejaInvitee,

  /// La même adresse est déjà apparue plus haut dans le fichier.
  doublon,

  /// Ce qu'il y a dans la colonne n'est pas une adresse.
  adresseInvalide,

  /// La colonne d'adresse est vide sur cette ligne.
  adresseAbsente;

  /// Vrai si la ligne fait partie de l'envoi.
  bool get partira =>
      this == VerdictApercu.aInviter || this == VerdictApercu.aInviterSansNom;

  /// Vrai si c'est une faute du fichier plutôt qu'un fait de la caserne. Les
  /// faits restent gris, les fautes prennent l'encre d'erreur.
  bool get estUneFaute =>
      this == VerdictApercu.adresseInvalide ||
      this == VerdictApercu.adresseAbsente;
}

/// Une ligne du fichier, jugée.
@immutable
class LigneApercu {
  const LigneApercu({
    required this.ligne,
    required this.verdict,
    this.premiereApparition,
  });

  final LigneFichier ligne;
  final VerdictApercu verdict;

  /// Pour un doublon : le numéro de la ligne qui portait déjà cette adresse.
  final int? premiereApparition;

  bool get partira => verdict.partira;

  /// Le titre de la ligne : le nom, ou l'adresse quand le nom manque. Jamais
  /// une ligne muette.
  String get titre =>
      ligne.nomComplet.isNotEmpty ? ligne.nomComplet : _adresseOuNumero;

  /// Le sous-titre : l'adresse, sauf quand elle est déjà le titre.
  String? get sousTitre =>
      ligne.nomComplet.isNotEmpty ? _adresseOuNumero : null;

  String get _adresseOuNumero => ligne.email.isNotEmpty
      ? ligne.email
      : AppStrings.importLigneNumero(ligne.numero);

  /// La phrase sous la ligne, ou `null` quand il n'y a rien à dire.
  String? get detail => switch (verdict) {
    VerdictApercu.aInviter => null,
    VerdictApercu.aInviterSansNom => AppStrings.importSansNom,
    VerdictApercu.dejaMembre => AppStrings.inviteDejaMembre,
    VerdictApercu.dejaInvitee => AppStrings.importDejaInvitee,
    VerdictApercu.doublon => AppStrings.importDoublon(premiereApparition ?? 0),
    VerdictApercu.adresseInvalide => AppStrings.inviteAdresseInvalide,
    VerdictApercu.adresseAbsente => AppStrings.importAdresseAbsente,
  };

  @override
  bool operator ==(Object other) =>
      other is LigneApercu &&
      other.ligne == ligne &&
      other.verdict == verdict &&
      other.premiereApparition == premiereApparition;

  @override
  int get hashCode => Object.hash(ligne, verdict, premiereApparition);
}

/// Ce que la caserne a déjà consommé de son plafond horaire.
///
/// **Lu par le client, et c'est légitime** : `invitation_rate_events` est
/// ouverte en lecture aux administrateurs de la caserne (migration `0032` —
/// « il subit le refus, il doit pouvoir en voir la cause »), et
/// `stations.settings` porte le plafond. Compter les lignes de la dernière
/// heure donne exactement ce que `invitation_rate_limit()` calculerait.
///
/// **C'est une prévision, jamais une promesse.** Deux administrateurs qui
/// invitent en même temps la démentent. Le serveur reste l'autorité : le
/// rapport affiche toujours *sa* phrase dès qu'un refus arrive.
@immutable
class BudgetInvitations {
  const BudgetInvitations({required this.plafond, required this.envoisRecents});

  final int plafond;

  /// Les instants des envois de la dernière heure, **du plus ancien au plus
  /// récent**.
  final List<DateTime> envoisRecents;

  /// Combien de courriels peuvent encore partir tout de suite.
  int get restantes {
    final reste = plafond - envoisRecents.length;
    return reste < 0 ? 0 : reste;
  }

  /// Le moment où la place se rouvre une fois [restantes] consommées.
  ///
  /// Même calcul que `invitation_rate_limit()` : le plus ancien des [plafond]
  /// derniers envois sort de la fenêtre. Sur un compteur vierge, le budget
  /// entier part maintenant et la place suivante s'ouvre une heure plus tard.
  DateTime ouvertureApresEpuisement(DateTime maintenant) {
    final derniers = envoisRecents.length <= plafond
        ? envoisRecents
        : envoisRecents.sublist(envoisRecents.length - plafond);
    if (derniers.isEmpty) return maintenant.add(fenetrePlafond);
    return derniers.first.add(fenetrePlafond);
  }

  @override
  bool operator ==(Object other) =>
      other is BudgetInvitations &&
      other.plafond == plafond &&
      listEquals(other.envoisRecents, envoisRecents);

  @override
  int get hashCode => Object.hash(plafond, Object.hashAll(envoisRecents));
}

/// Le fichier relu ligne par ligne, avec ce qui va partir et ce qui suivra.
@immutable
class ApercuImport {
  const ApercuImport({
    required this.nomFichier,
    required this.lignes,
    this.budget,
  });

  final String nomFichier;
  final List<LigneApercu> lignes;

  /// `null` quand le budget n'a pas pu être lu : l'écran se tait alors.
  final BudgetInvitations? budget;

  /// Les lignes qui partiront, dans l'ordre du fichier.
  List<LigneApercu> get aInviter =>
      lignes.where((LigneApercu l) => l.partira).toList(growable: false);

  int get nombreAInviter => lignes.where((LigneApercu l) => l.partira).length;

  int get nombreEcartees => lignes.length - nombreAInviter;

  bool get envoyable => nombreAInviter > 0;

  /// Combien d'invitations peuvent partir tout de suite, au mieux.
  int partiraMaintenant(BudgetInvitations budget) {
    final place = budget.restantes;
    return place < nombreAInviter ? place : nombreAInviter;
  }

  /// Le compte des lignes écartées par motif, pour la phrase du rapport.
  Map<VerdictApercu, int> get ecarteesParMotif {
    final comptes = <VerdictApercu, int>{};
    for (final ligne in lignes) {
      if (ligne.partira) continue;
      comptes[ligne.verdict] = (comptes[ligne.verdict] ?? 0) + 1;
    }
    return comptes;
  }
}

/// Juge chaque ligne du fichier contre ce que la caserne contient déjà.
///
/// L'ordre des contrôles n'est pas indifférent : **le fichier d'abord, la
/// caserne ensuite.** Une ligne dont l'adresse est illisible n'a pas à être
/// comparée à quoi que ce soit, et un doublon interne se dit mieux par « déjà
/// présente ligne 12 » que par « déjà invitée », qui ferait chercher une
/// invitation qui n'existe pas encore.
ApercuImport preparerApercu({
  required LectureFichier lecture,
  required List<MembreCaserne> membres,
  required List<Invitation> invitations,
  BudgetInvitations? budget,
}) {
  final membresActifs = <String>{
    for (final membre in membres)
      if (membre.estActif) normaliserEmail(membre.email),
  };
  final dejaInvitees = <String>{
    for (final invitation in invitations) normaliserEmail(invitation.email),
  };

  final vues = <String, int>{};
  final lignes = <LigneApercu>[];

  for (final ligne in lecture.lignes) {
    final adresse = normaliserEmail(ligne.email);

    final VerdictApercu verdict;
    int? premiere;

    if (adresse.isEmpty) {
      verdict = VerdictApercu.adresseAbsente;
    } else if (!emailValide(adresse)) {
      verdict = VerdictApercu.adresseInvalide;
    } else if (vues.containsKey(adresse)) {
      verdict = VerdictApercu.doublon;
      premiere = vues[adresse];
    } else if (membresActifs.contains(adresse)) {
      verdict = VerdictApercu.dejaMembre;
      vues[adresse] = ligne.numero;
    } else if (dejaInvitees.contains(adresse)) {
      verdict = VerdictApercu.dejaInvitee;
      vues[adresse] = ligne.numero;
    } else {
      verdict = ligne.nomComplet.isEmpty
          ? VerdictApercu.aInviterSansNom
          : VerdictApercu.aInviter;
      vues[adresse] = ligne.numero;
    }

    lignes.add(
      LigneApercu(
        ligne: ligne,
        verdict: verdict,
        premiereApparition: premiere,
      ),
    );
  }

  return ApercuImport(
    nomFichier: lecture.nomFichier,
    lignes: List<LigneApercu>.unmodifiable(lignes),
    budget: budget,
  );
}

/// Une personne à inviter, telle qu'elle part dans le corps de la requête.
///
/// Le miroir exact de `people[]` de `invite-member` : l'adresse, les deux noms
/// et le rôle de la ligne. Rien d'autre du fichier ne quitte le navigateur.
@immutable
class PersonneAInviter {
  const PersonneAInviter({
    required this.email,
    required this.role,
    this.prenom,
    this.nom,
  });

  factory PersonneAInviter.depuisLigne(LigneFichier ligne) => PersonneAInviter(
    email: normaliserEmail(ligne.email),
    role: ligne.role,
    prenom: ligne.prenom.isEmpty ? null : ligne.prenom,
    nom: ligne.nom.isEmpty ? null : ligne.nom,
  );

  final String email;
  final RoleMembre role;
  final String? prenom;
  final String? nom;

  Map<String, dynamic> versJson() => <String, dynamic>{
    'email': email,
    'role': role.valeurSql,
    if (prenom != null) 'first_name': prenom,
    if (nom != null) 'last_name': nom,
  };

  @override
  bool operator ==(Object other) =>
      other is PersonneAInviter &&
      other.email == email &&
      other.role == role &&
      other.prenom == prenom &&
      other.nom == nom;

  @override
  int get hashCode => Object.hash(email, role, prenom, nom);
}

/// Découpe les personnes en lots de [maxAdressesParEnvoi].
///
/// Le plafond de vingt adresses par appel borne **une requête**, pas un import :
/// il tient le temps d'un aller-retour et la taille d'une réponse. Un import de
/// soixante personnes est donc trois appels, pas une demande d'assouplissement.
List<List<PersonneAInviter>> decouperEnLots(List<PersonneAInviter> personnes) {
  final lots = <List<PersonneAInviter>>[];
  for (var i = 0; i < personnes.length; i += maxAdressesParEnvoi) {
    final fin = i + maxAdressesParEnvoi;
    lots.add(
      List<PersonneAInviter>.unmodifiable(
        personnes.sublist(i, fin > personnes.length ? personnes.length : fin),
      ),
    );
  }
  return List<List<PersonneAInviter>>.unmodifiable(lots);
}
