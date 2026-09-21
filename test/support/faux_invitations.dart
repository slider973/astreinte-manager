import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/invitation/data/invitation_repository.dart';
import 'package:astreinte_sp/features/invitation/domain/acceptation.dart';
import 'package:astreinte_sp/features/membres/data/membres_repository.dart';
import 'package:astreinte_sp/features/membres/domain/import_membres.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';

const String stationTest = 'aaaaaaaa-0000-4000-8000-000000000001';

const Appartenance appartenanceAdmin = Appartenance(
  id: 'm-admin',
  stationId: stationTest,
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
  nomAffiche: 'Jean D.',
);

const MembreCaserne membreMarie = MembreCaserne(
  id: 'm-1',
  userId: 'u-1',
  role: RoleMembre.membre,
  statut: StatutMembre.actif,
  prenom: 'Marie',
  nom: 'Lefebvre',
  email: 'membre1@caserne-a.test',
);

const MembreCaserne membreJean = MembreCaserne(
  id: 'm-admin',
  userId: 'u-0',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
  prenom: 'Jean',
  nom: 'Dupont',
  email: 'admin@caserne-a.test',
);

/// Une invitation qui court encore.
Invitation invitationEnAttente({
  String id = 'i-1',
  String email = 'recrue@exemple.fr',
  RoleMembre role = RoleMembre.membre,
  Duration restant = const Duration(days: 10),
}) => Invitation(
  id: id,
  email: email,
  role: role,
  expireLe: DateTime.now().add(restant),
  creeLe: DateTime.now().subtract(const Duration(days: 4)),
);

/// Un [MembresRepository] sans réseau, qui compte ce qu'on lui demande.
class FauxMembresRepository implements MembresRepository {
  FauxMembresRepository({
    this.membresActifs = const <MembreCaserne>[],
    List<Invitation>? invitations,
    this.erreurLecture = false,
    this.echecInvitation,
    this.rapport,
    this.echecAnnulation = false,
    Map<String, DateTime>? saisies,
    this.echecAdministration,
  }) : invitations = invitations ?? <Invitation>[],
       saisies = saisies ?? <String, DateTime>{};

  List<MembreCaserne> membresActifs;
  List<Invitation> invitations;

  /// Vrai pour faire échouer les deux lectures.
  bool erreurLecture;

  /// Refus de la requête entière d'invitation, ou `null`. C'est l'échec
  /// complet et non son code : un refus de débit porte en plus la phrase du
  /// serveur (ticket 038).
  EchecInvitation? echecInvitation;

  /// Rapport rendu par [inviter]. Par défaut : une adresse invitée.
  RapportInvitations? rapport;

  bool echecAnnulation;

  /// Dernières saisies de disponibilités, par identifiant d'utilisateur.
  Map<String, DateTime> saisies;

  /// Refus rendu par les trois écritures d'administration, ou `null`.
  ErreurAdministration? echecAdministration;

  int lectures = 0;

  /// Ce que l'écran a demandé d'écrire, dans l'ordre.
  final List<({String membershipId, RoleMembre role})> roles =
      <({String membershipId, RoleMembre role})>[];
  final List<({String membershipId, StatutMembre statut})> statuts =
      <({String membershipId, StatutMembre statut})>[];
  final List<({String membershipId, String? nomAffiche})> renommages =
      <({String membershipId, String? nomAffiche})>[];
  final List<List<String>> envois = <List<String>>[];
  final List<RoleMembre> rolesEnvoyes = <RoleMembre>[];

  /// Les lots de personnes nommées envoyés par l'import (ticket 047).
  final List<List<PersonneAInviter>> lotsImportes =
      <List<PersonneAInviter>>[];

  /// Rapports rendus par [inviterPersonnes], un par lot, dans l'ordre. Un lot
  /// sans rapport prévu reçoit le rapport « tout est passé ».
  List<RapportInvitations> rapportsParLot = <RapportInvitations>[];

  /// Refus de la requête entière au n-ième lot (compté depuis 0), ou `null`.
  /// C'est ainsi qu'un test joue un plafond atteint en cours d'import.
  int? lotQuiEchoue;

  /// Le budget rendu par [budgetInvitations]. `null` fait échouer la lecture,
  /// pour vérifier que l'écran se tait au lieu d'inventer une inquiétude.
  BudgetInvitations? budget = const BudgetInvitations(
    plafond: 60,
    envoisRecents: <DateTime>[],
  );

  /// La caserne visée par chaque envoi. L'écran de l'éditeur (ticket 031)
  /// invite dans une caserne dont il n'est pas membre : le test doit pouvoir
  /// vérifier laquelle.
  final List<String> casernesInvitees = <String>[];
  final List<String> annulations = <String>[];

  @override
  Future<List<MembreCaserne>> membres(String stationId) async {
    lectures++;
    if (erreurLecture) throw const FormatException('lecture refusée');
    return membresActifs;
  }

  @override
  Future<List<Invitation>> invitationsEnAttente(String stationId) async {
    if (erreurLecture) throw const FormatException('lecture refusée');
    return invitations;
  }

  @override
  Future<RapportInvitations> inviter({
    required String stationId,
    required List<String> emails,
    required RoleMembre role,
  }) async {
    envois.add(emails);
    rolesEnvoyes.add(role);
    casernesInvitees.add(stationId);

    final echec = echecInvitation;
    if (echec != null) throw echec;

    return rapport ??
        RapportInvitations(
          resultats: <ResultatInvitation>[
            for (final email in emails)
              ResultatInvitation(
                email: email,
                statut: StatutResultatInvitation.invitee,
              ),
          ],
        );
  }

  @override
  Future<RapportInvitations> inviterPersonnes({
    required String stationId,
    required List<PersonneAInviter> personnes,
  }) async {
    final rang = lotsImportes.length;
    lotsImportes.add(personnes);
    casernesInvitees.add(stationId);

    if (lotQuiEchoue == rang) {
      throw echecInvitation ??
          const EchecInvitation(ErreurInvitation.debitAtteint);
    }
    if (rang < rapportsParLot.length) return rapportsParLot[rang];

    return RapportInvitations(
      resultats: <ResultatInvitation>[
        for (final personne in personnes)
          ResultatInvitation(
            email: personne.email,
            statut: StatutResultatInvitation.invitee,
          ),
      ],
    );
  }

  @override
  Future<BudgetInvitations> budgetInvitations(String stationId) async {
    final lu = budget;
    if (lu == null) throw const FormatException('budget illisible');
    return lu;
  }

  @override
  Future<Map<String, DateTime>> dernieresSaisies(String stationId) async {
    if (erreurLecture) throw const FormatException('lecture refusée');
    return saisies;
  }

  @override
  Future<void> changerRole({
    required String membershipId,
    required RoleMembre role,
  }) async {
    _refuserSiDemande();
    roles.add((membershipId: membershipId, role: role));
    _remplacer(membershipId, role: role);
  }

  @override
  Future<void> changerStatut({
    required String membershipId,
    required StatutMembre statut,
  }) async {
    _refuserSiDemande();
    statuts.add((membershipId: membershipId, statut: statut));
    _remplacer(membershipId, statut: statut);
  }

  @override
  Future<void> renommer({
    required String membershipId,
    String? nomAffiche,
  }) async {
    _refuserSiDemande();
    renommages.add((membershipId: membershipId, nomAffiche: nomAffiche));
    _remplacer(membershipId, nomAffiche: nomAffiche, effaceNom: true);
  }

  void _refuserSiDemande() {
    final refus = echecAdministration;
    if (refus != null) throw EchecAdministration(refus);
  }

  /// La base rendrait la liste à jour à la relecture : le faux fait pareil.
  void _remplacer(
    String membershipId, {
    RoleMembre? role,
    StatutMembre? statut,
    String? nomAffiche,
    bool effaceNom = false,
  }) {
    membresActifs = <MembreCaserne>[
      for (final membre in membresActifs)
        if (membre.id != membershipId)
          membre
        else
          MembreCaserne(
            id: membre.id,
            userId: membre.userId,
            role: role ?? membre.role,
            statut: statut ?? membre.statut,
            prenom: membre.prenom,
            nom: membre.nom,
            email: membre.email,
            nomAffiche: effaceNom ? nomAffiche : membre.nomAffiche,
            derniereSaisie: membre.derniereSaisie,
          ),
    ];
  }

  @override
  Future<void> annuler(String invitationId) async {
    if (echecAnnulation) throw const FormatException('suppression refusée');
    annulations.add(invitationId);
    invitations = invitations
        .where((Invitation i) => i.id != invitationId)
        .toList();
  }
}

/// Un [InvitationRepository] sans réseau.
class FauxInvitationRepository implements InvitationRepository {
  FauxInvitationRepository({this.resultat, this.echec, this.auSucces});

  AcceptationInvitation? resultat;
  EchecAcceptation? echec;

  /// Joué juste avant de rendre la main : c'est là que le test fait
  /// apparaître la nouvelle appartenance, comme la base le ferait.
  void Function()? auSucces;

  final List<String> jetons = <String>[];

  @override
  Future<AcceptationInvitation> accepter(String jeton) async {
    jetons.add(jeton);
    final refus = echec;
    if (refus != null) throw refus;
    auSucces?.call();
    return resultat ??
        const AcceptationInvitation(
          dejaAcceptee: false,
          role: RoleMembre.membre,
          caserne: CaserneInvitation(nom: 'CIS Saint-Martin'),
          inviteur: InviteurInvitation(libelle: 'Jean Dupont'),
        );
  }
}
