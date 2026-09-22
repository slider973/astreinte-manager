// Une caserne entière, en mémoire, qui rejoue les règles de la base.
//
// Pourquoi ce fichier existe
// --------------------------
// Les faux de `test/support/` sont **par écran** : chacun rend ce qu'un test
// lui a soufflé, et deux d'entre eux ne partagent rien. C'est ce qu'il faut
// pour éprouver un écran ; c'est exactement ce qu'il ne faut pas pour éprouver
// un **parcours**, où la saisie d'un pompier doit ressortir dans la matrice de
// son chef, où une publication doit faire apparaître des propositions, et où
// un refus doit rouvrir un créneau.
//
// [BackendMemoire] est donc une seule boîte : des tables, et les huit dépôts
// de l'application posés dessus. Les règles rejouées sont celles que la base
// impose, et **seulement** celles-là :
//
//   - `create_invitation` / `accept_invitation` (migration 0009) : une adresse
//     déjà membre est refusée par adresse, pas par lot ; l'acceptation crée
//     l'appartenance et marque l'invitation.
//   - `availabilities` (0003, 0012) : l'absence de ligne **est** le non-saisi,
//     et `set_by` est posé par la base — c'est lui qui fait relire une saisie
//     d'admin en minuscule dans la matrice (0017).
//   - `create_schedule` (0018) : deux créneaux par jour du mois, l'effectif
//     requis copié des réglages de la caserne à la création.
//   - `assignments_trace_disponibilite` (0018) : `was_available` est calculé
//     par la base, jamais envoyé par le client.
//   - `assignments_active_uniq` (0004) : deux attributions actives du même
//     membre sur le même créneau sont refusées.
//   - `publish_schedule` (0019) : `draft -> published`, `proposed_at` posé sur
//     toutes les attributions qui n'en avaient pas, et le compte rendu compte
//     des **personnes**.
//   - `schedule_complet` + `schedule_reevaluer` (0019) : un planning dont
//     chaque créneau atteint son effectif requis **en attributions acceptées**
//     passe en `validated` ; il en ressort dès qu'il cesse de l'être.
//   - `reassign_shift` (0020) : la nouvelle attribution couvre le plus ancien
//     trou non couvert et lui pose `replaced_by`.
//   - `v_schedule_progress` (0018) : les six nombres du suivi, comptés ici
//     comme la vue les compte.
//
// Ce qui n'est **pas** rejoué est dit une fois : la RLS. Elle est éprouvée là
// où elle vit, en SQL (`supabase/tests/`, `scripts/test_rls.sh`), et la
// prétendre ici en Dart donnerait une seconde vérité à tenir. Le parcours
// Dart répond à « les écrans s'enchaînent-ils ? » ; le parcours SQL
// (`supabase/tests/parcours_complet_test.sql`) répond à « la base tient-elle
// le même fil ? ».

import 'dart:async';

import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/data/dispos_repository.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/disponibilite_mois.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/domain/preferences_mois.dart';
import 'package:astreinte_sp/features/invitation/data/invitation_repository.dart';
import 'package:astreinte_sp/features/invitation/domain/acceptation.dart';
import 'package:astreinte_sp/features/invitation/domain/invitation_recue.dart';
import 'package:astreinte_sp/features/membres/data/membres_repository.dart';
import 'package:astreinte_sp/features/membres/domain/import_membres.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';
import 'package:astreinte_sp/features/planning/data/matrice_repository.dart';
import 'package:astreinte_sp/features/planning/data/planning_repository.dart';
import 'package:astreinte_sp/features/planning/data/suivi_repository.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:astreinte_sp/features/planning/domain/suivi_planning.dart';
import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';

/// L'identifiant d'un créneau : `c-<jour>-<j|n>`.
///
/// Nommé plutôt que tiré au hasard, pour qu'un test puisse désigner une case
/// de la ligne des créneaux sans la chercher. La base, elle, met un uuid : la
/// forme n'a aucune importance, seule l'unicité en a.
String identifiantCreneau(int jour, CreneauType creneau) =>
    'c-$jour-${creneau == CreneauType.jour ? 'j' : 'n'}';

/// Le jeton envoyé dans le lien d'invitation, dérivé de l'adresse pour qu'un
/// test puisse l'écrire. La base en tire un au hasard, et ne le rend jamais.
String jetonPour(String email) => 'jeton-${email.split('@').first}';

/// Une personne de la caserne : sa ligne `memberships` jointe à son `profiles`.
class MembreMemoire {
  MembreMemoire({
    required this.membershipId,
    required this.userId,
    required this.prenom,
    required this.nom,
    required this.email,
    this.role = RoleMembre.membre,
    this.statut = StatutMembre.actif,
    this.nomAffiche,
  });

  final String membershipId;
  final String userId;

  /// Mutables depuis le ticket 047 : `accept_invitation` amorce un profil vide
  /// avec le nom saisi par l'administrateur à l'import.
  String prenom;
  String nom;

  final String email;
  RoleMembre role;
  StatutMembre statut;
  String? nomAffiche;

  bool get actif => statut == StatutMembre.actif;

  /// Le nom d'usage de la caserne, avec le repli de `AttributionSuivi`.
  String get libelle {
    final affiche = nomAffiche?.trim() ?? '';
    if (affiche.isNotEmpty) return affiche;
    return <String>[prenom, nom].where((String p) => p.isNotEmpty).join(' ');
  }
}

/// Une ligne d'`invitations`. Le jeton n'est lisible que d'ici : côté écran,
/// il est hors du grant de select (migration 0008).
class InvitationMemoire {
  InvitationMemoire({
    required this.id,
    required this.email,
    required this.role,
    required this.jeton,
    required this.creeLe,
    required this.expireLe,
    this.prenom,
    this.nom,
  });

  final String id;
  final String email;
  final RoleMembre role;
  final String jeton;
  final DateTime creeLe;
  final DateTime expireLe;

  /// Le nom saisi par l'administrateur à l'import (ticket 047). Amorce le
  /// profil à l'acceptation, et seulement s'il est vide.
  String? prenom;
  String? nom;

  DateTime? accepteeLe;

  bool get enAttente => accepteeLe == null;
}

/// Une ligne d'`assignments`, avec toutes ses colonnes d'état.
class AttributionMemoire {
  AttributionMemoire({
    required this.id,
    required this.creneauId,
    required this.userId,
    required this.etaitDisponible,
    this.auteurId,
    this.etat = AttributionEtat.propose,
    this.proposeeLe,
    this.repondueLe,
    this.motifRefus,
    this.remplaceParId,
  });

  final String id;
  final String creneauId;
  final String userId;
  final bool etaitDisponible;
  final String? auteurId;

  AttributionEtat etat;
  DateTime? proposeeLe;
  DateTime? repondueLe;
  String? motifRefus;
  String? remplaceParId;
  int relances = 0;
  DateTime? derniereRelance;

  /// Les deux statuts qui occupent une place sur un créneau.
  bool get active =>
      etat == AttributionEtat.propose || etat == AttributionEtat.accepte;

  /// Les trois statuts qui laissent un trou à boucher.
  bool get close =>
      etat == AttributionEtat.refuse ||
      etat == AttributionEtat.remplace ||
      etat == AttributionEtat.annule;
}

/// Une notification partie depuis la base : ce que `notify` aurait inséré dans
/// `notification_outbox`. Le parcours s'en sert pour vérifier que les bons
/// téléphones sonnent au bon moment (`docs/WORKFLOWS.md § 8`).
class NotificationMemoire {
  const NotificationMemoire({required this.type, required this.destinataires});

  final String type;
  final List<String> destinataires;

  @override
  String toString() => '$type -> ${destinataires.join(', ')}';
}

/// La caserne en mémoire. Un seul mois : c'est celui du parcours.
class BackendMemoire {
  BackendMemoire({
    required this.stationId,
    required this.nomCaserne,
    required this.annee,
    required this.mois,
    required this.effectifRequis,
    DateTime? dateLimite,
    this.delaiRetardHeures = 72,
  }) : periode = PeriodeSaisie(
         id: 'periode-$annee-$mois',
         stationId: stationId,
         annee: annee,
         mois: mois,
         statut: PeriodeEtat.ouverte,
         dateLimite:
             dateLimite ?? DateTime.now().add(const Duration(days: 7)),
       );

  final String stationId;
  final String nomCaserne;
  final int annee;
  final int mois;

  /// L'effectif requis d'un créneau, tel que `station_required_count` le
  /// calcule depuis les réglages de la caserne (migration 0018) : il dépend
  /// du jour et du créneau, et **zéro est une valeur** — « pas d'astreinte ce
  /// jour-là » est une décision, pas un trou.
  final int Function(int jour, CreneauType creneau) effectifRequis;

  final int delaiRetardHeures;

  /// Le mois du parcours. Une seule période : ouvrir les douze mois d'une
  /// année ne dirait rien de plus et rallongerait chaque écran.
  final PeriodeSaisie periode;

  final List<MembreMemoire> membres = <MembreMemoire>[];
  final List<InvitationMemoire> invitations = <InvitationMemoire>[];

  /// `availabilities`, rangées par membre. L'absence de clé **est** le
  /// non-saisi : aucune valeur ne le représente.
  final Map<String, Map<CreneauCle, DisponibiliteEtat>> dispos =
      <String, Map<CreneauCle, DisponibiliteEtat>>{};

  /// Qui a écrit la case : c'est `availabilities.set_by`, et c'est lui qui
  /// fait relire une saisie par procuration en minuscule dans la matrice.
  final Map<String, Map<CreneauCle, String>> auteursDispos =
      <String, Map<CreneauCle, String>>{};

  /// `availability_preferences`, par membre.
  final Map<String, PreferencesMois> preferences = <String, PreferencesMois>{};

  /// La ligne `schedules` du mois, ou `null` tant que personne ne l'a créée.
  PlanningBrouillon? planning;

  final List<CreneauPlanning> creneaux = <CreneauPlanning>[];
  final List<AttributionMemoire> attributions = <AttributionMemoire>[];

  /// Ce que `notify` a inséré, dans l'ordre.
  final List<NotificationMemoire> notifications = <NotificationMemoire>[];

  /// Le nom que portera le profil de chaque adresse invitée.
  ///
  /// `invite-member` crée le **compte** à partir de la seule adresse ; le nom,
  /// lui, vient du profil que la recrue complète à son arrivée (ticket 006).
  /// Le parcours le connaît d'avance pour pouvoir nommer la personne dans ses
  /// assertions sans passer par l'écran de bienvenue.
  final Map<String, ({String prenom, String nom})> annuaire =
      <String, ({String prenom, String nom})>{};

  /// Le plafond horaire d'invitations de la caserne (ticket 038).
  int plafondInvitations = 60;

  /// Les instants des courriels d'invitation déjà partis, du plus ancien au
  /// plus récent. Un test qui veut jouer un plafond atteint le remplit.
  final List<DateTime> envoisInvitations = <DateTime>[];

  /// Appelé juste après une acceptation réussie.
  ///
  /// C'est la relecture de `memberships` que fait l'application au retour de
  /// l'Edge Function : sans elle, la session de la recrue ne connaîtrait pas
  /// encore la caserne qu'elle vient de rejoindre.
  void Function(MembreMemoire recrue)? apresAcceptation;

  /// L'horloge du parcours. Injectée pour que « il y a deux heures » ne
  /// dépende pas de l'heure à laquelle le test tourne.
  DateTime Function() horloge = DateTime.now;

  int _sequence = 0;

  String _id(String prefixe) => '$prefixe-${++_sequence}';

  // --- Lecture de l'état, pour les assertions du parcours -------------------

  MembreMemoire? membreParEmail(String email) {
    final cible = email.trim().toLowerCase();
    for (final membre in membres) {
      if (membre.email.toLowerCase() == cible) return membre;
    }
    return null;
  }

  MembreMemoire? membreParId(String userId) {
    for (final membre in membres) {
      if (membre.userId == userId) return membre;
    }
    return null;
  }

  /// L'appartenance telle que la session de ce membre la voit.
  Appartenance appartenanceDe(String userId) {
    final membre = membreParId(userId)!;
    return Appartenance(
      id: membre.membershipId,
      stationId: stationId,
      nomCaserne: nomCaserne,
      role: membre.role,
      statut: membre.statut,
      nomAffiche: membre.nomAffiche,
    );
  }

  CreneauPlanning? creneauDe(int jour, CreneauType type) {
    for (final creneau in creneaux) {
      if (creneau.jour == jour && creneau.creneau == type) return creneau;
    }
    return null;
  }

  List<AttributionMemoire> attributionsDe(String creneauId) => <AttributionMemoire>[
    for (final attribution in attributions)
      if (attribution.creneauId == creneauId) attribution,
  ];

  AttributionMemoire? attributionParId(String id) {
    for (final attribution in attributions) {
      if (attribution.id == id) return attribution;
    }
    return null;
  }

  PlanningEtat get etatPlanning => planning?.etat ?? PlanningEtat.brouillon;

  bool aNotifie(String type) =>
      notifications.any((NotificationMemoire n) => n.type == type);

  // --- Les règles de la base ----------------------------------------------

  void _notifier(String type, List<String> destinataires) {
    notifications.add(
      NotificationMemoire(type: type, destinataires: destinataires),
    );
  }

  List<String> get _membresActifs => <String>[
    for (final membre in membres)
      if (membre.actif) membre.userId,
  ];

  /// `assignments_trace_disponibilite` : la base regarde la case, le client ne
  /// lui dit rien.
  bool _etaitDisponible(String userId, CreneauPlanning creneau) {
    final cle = CreneauCle(
      DateTime(annee, mois, creneau.jour),
      creneau.creneau,
    );
    return dispos[userId]?[cle] == DisponibiliteEtat.disponible;
  }

  /// `schedule_complet` : chaque créneau atteint son effectif requis **en
  /// attributions acceptées**.
  bool get _complet {
    for (final creneau in creneaux) {
      final acceptees = attributionsDe(
        creneau.id,
      ).where((AttributionMemoire a) => a.etat == AttributionEtat.accepte).length;
      if (acceptees < creneau.effectifRequis) return false;
    }
    return true;
  }

  /// `schedule_reevaluer` : la transition que la complétude commande, dans les
  /// deux sens. Appelée après chaque réponse et chaque réattribution.
  void _reevaluer() {
    final entete = planning;
    if (entete == null) return;
    if (entete.etat != PlanningEtat.publie &&
        entete.etat != PlanningEtat.valide) {
      return;
    }

    if (!_complet) {
      if (entete.etat == PlanningEtat.valide) {
        planning = PlanningBrouillon(
          id: entete.id,
          etat: PlanningEtat.publie,
          publieLe: entete.publieLe,
        );
      }
      return;
    }

    if (entete.etat == PlanningEtat.valide) return;

    planning = PlanningBrouillon(
      id: entete.id,
      etat: PlanningEtat.valide,
      publieLe: entete.publieLe,
      valideLe: horloge(),
    );
    // Tous les membres actifs, administrateurs compris : ils n'ont pas
    // déclenché la transition, ils ont le droit de l'apprendre.
    _notifier('schedule_validated', _membresActifs);
  }

  // --- Les dépôts, posés sur les tables ------------------------------------

  MembresRepository get membresRepository => _MembresMemoire(this);

  InvitationRepository get invitationRepository => _InvitationMemoire(this);

  /// Le dépôt d'invitation **d'une session donnée**.
  ///
  /// `my_pending_invitations()` n'a pas de paramètre : l'adresse vient du
  /// jeton de la session, jamais d'un argument. Ici elle vient de la personne
  /// pour qui l'application est montée, ce qui revient au même.
  InvitationRepository invitationsDe(String email) =>
      _InvitationMemoire(this, email);

  DisposRepository get disposRepository => _DisposMemoire(this);

  /// Le dépôt de disponibilités **d'un membre donné** : c'est la session qui
  /// décide de l'utilisateur, jamais l'écran, et le parcours monte
  /// l'application une fois par personne.
  DisposRepository disposDe(String userId) => _DisposMemoire(this, userId);

  MatriceRepository get matriceRepository => _MatriceMemoire(this);

  PlanningRepository planningDe(String adminId) =>
      _PlanningMemoire(this, adminId);

  SuiviRepository suiviDe(String adminId) => _SuiviMemoire(this, adminId);

  PropositionsRepository get propositionsRepository =>
      _PropositionsMemoire(this);
}

// ===========================================================================
// Les dépôts
// ===========================================================================

class _MembresMemoire implements MembresRepository {
  _MembresMemoire(this._base);

  final BackendMemoire _base;

  @override
  Future<List<MembreCaserne>> membres(String stationId) async {
    final liste = <MembreCaserne>[
      for (final membre in _base.membres)
        if (membre.statut != StatutMembre.invite)
          MembreCaserne(
            id: membre.membershipId,
            userId: membre.userId,
            role: membre.role,
            statut: membre.statut,
            prenom: membre.prenom,
            nom: membre.nom,
            email: membre.email,
            nomAffiche: membre.nomAffiche,
          ),
    ]..sort((MembreCaserne a, MembreCaserne b) => a.cleDeTri.compareTo(b.cleDeTri));
    return List<MembreCaserne>.unmodifiable(liste);
  }

  @override
  Future<Map<String, DateTime>> dernieresSaisies(String stationId) async =>
      <String, DateTime>{
        for (final entree in _base.dispos.entries)
          if (entree.value.isNotEmpty) entree.key: _base.horloge(),
      };

  @override
  Future<List<Invitation>> invitationsEnAttente(String stationId) async {
    final liste = <Invitation>[
      for (final invitation in _base.invitations)
        if (invitation.enAttente)
          Invitation(
            id: invitation.id,
            email: invitation.email,
            role: invitation.role,
            expireLe: invitation.expireLe,
            creeLe: invitation.creeLe,
            prenom: invitation.prenom,
            nom: invitation.nom,
          ),
    ]..sort((Invitation a, Invitation b) => b.creeLe.compareTo(a.creeLe));
    return List<Invitation>.unmodifiable(liste);
  }

  @override
  Future<RapportInvitations> inviter({
    required String stationId,
    required List<String> emails,
    required RoleMembre role,
  }) => _inviter(<PersonneAInviter>[
    for (final email in emails)
      PersonneAInviter(email: email.trim().toLowerCase(), role: role),
  ]);

  @override
  Future<RapportInvitations> inviterPersonnes({
    required String stationId,
    required List<PersonneAInviter> personnes,
  }) => _inviter(personnes);

  @override
  Future<BudgetInvitations> budgetInvitations(String stationId) async =>
      BudgetInvitations(
        plafond: _base.plafondInvitations,
        envoisRecents: List<DateTime>.unmodifiable(_base.envoisInvitations),
      );

  Future<RapportInvitations> _inviter(List<PersonneAInviter> personnes) async {
    final maintenant = _base.horloge();
    final resultats = <ResultatInvitation>[];

    for (final personne in personnes) {
      final email = personne.email.trim().toLowerCase();
      final role = personne.role;

      // `create_invitation` refuse **par adresse** : le lot continue.
      if (_base.membreParEmail(email)?.actif ?? false) {
        resultats.add(
          ResultatInvitation(
            email: email,
            statut: StatutResultatInvitation.erreur,
            motif: MotifEchecInvitation.dejaMembre,
          ),
        );
        continue;
      }

      final existante = _base.invitations
          .where(
            (InvitationMemoire i) => i.enAttente && i.email == email,
          )
          .toList(growable: false);
      if (existante.isNotEmpty) {
        // Une invitation qui court encore est **renvoyée**, pas dupliquée.
        resultats.add(
          ResultatInvitation(
            email: email,
            statut: StatutResultatInvitation.relancee,
          ),
        );
        continue;
      }

      _base.invitations.add(
        InvitationMemoire(
          id: _base._id('inv'),
          email: email,
          role: role,
          jeton: jetonPour(email),
          creeLe: maintenant,
          expireLe: maintenant.add(const Duration(days: 14)),
          prenom: personne.prenom,
          nom: personne.nom,
        ),
      );
      _base.envoisInvitations.add(maintenant);

      // `invite-member` crée le compte chez le fournisseur d'authentification.
      // L'**appartenance**, elle, n'arrive qu'à l'acceptation : la personne
      // existe, elle n'est pas encore de la caserne.
      if (_base.membreParEmail(email) == null) {
        final identite =
            _base.annuaire[email] ?? (prenom: '', nom: '');
        _base.membres.add(
          MembreMemoire(
            membershipId: _base._id('m'),
            userId: _base._id('u'),
            prenom: identite.prenom,
            nom: identite.nom,
            email: email,
            role: role,
            statut: StatutMembre.invite,
          ),
        );
      }

      resultats.add(
        ResultatInvitation(
          email: email,
          statut: StatutResultatInvitation.invitee,
        ),
      );
    }

    return RapportInvitations(
      resultats: List<ResultatInvitation>.unmodifiable(resultats),
    );
  }

  @override
  Future<void> annuler(String invitationId) async =>
      _base.invitations.removeWhere(
        (InvitationMemoire i) => i.id == invitationId,
      );

  @override
  Future<void> changerRole({
    required String membershipId,
    required RoleMembre role,
  }) async => _membre(membershipId).role = role;

  @override
  Future<void> changerStatut({
    required String membershipId,
    required StatutMembre statut,
  }) async => _membre(membershipId).statut = statut;

  @override
  Future<void> renommer({
    required String membershipId,
    String? nomAffiche,
  }) async => _membre(membershipId).nomAffiche = nomAffiche;

  MembreMemoire _membre(String membershipId) => _base.membres.firstWhere(
    (MembreMemoire m) => m.membershipId == membershipId,
    orElse: () => throw const EchecAdministration(
      ErreurAdministration.refusee,
    ),
  );
}

/// L'acceptation d'un jeton. C'est le seul dépôt qui **crée** une appartenance.
class _InvitationMemoire implements InvitationRepository {
  _InvitationMemoire(this._base, [this.sessionEmail]);

  final BackendMemoire _base;

  /// L'adresse de la session. `accept_invitation` confronte l'invitation à
  /// l'adresse du compte, et une invitation acceptée par quelqu'un d'autre est
  /// un `email_mismatch` ; `my_pending_invitations()` ne rend que les siennes.
  final String? sessionEmail;

  @override
  Future<List<InvitationRecue>> mesInvitations() async {
    final adresse = (sessionEmail ?? '').toLowerCase();
    if (adresse.isEmpty) return const <InvitationRecue>[];

    // La forme exacte de la réponse de la fonction SQL : cinq champs, jamais
    // de jeton, et l'expiration **tranchée par le serveur**.
    return InvitationRecue.depuisListe(<Map<String, dynamic>>[
      for (final InvitationMemoire i in _base.invitations)
        if (i.enAttente && i.email.toLowerCase() == adresse)
          <String, dynamic>{
            'id': i.id,
            'station_name': _base.nomCaserne,
            'invited_by_name': 'Jean Dupont',
            'expires_at': i.expireLe.toIso8601String(),
            'status': i.expireLe.isBefore(_base.horloge())
                ? 'expired'
                : 'pending',
          },
    ]);
  }

  @override
  Future<AcceptationInvitation> accepter(EntreeInvitation entree) async {
    final cible = entree.valeurNettoyee;
    if (cible.isEmpty) {
      throw const EchecAcceptation(ErreurAcceptation.jetonManquant);
    }

    final parIdentifiant = entree.mode == ModeInvitation.identifiant;
    final trouvees = _base.invitations
        .where(
          (InvitationMemoire i) =>
              parIdentifiant ? i.id == cible : i.jeton == cible,
        )
        .toList(growable: false);

    // Par identifiant, un inconnu et celui de l'invitation de quelqu'un
    // d'autre rendent **la même chose**, sans caserne ni adresse masquée : les
    // distinguer ferait un oracle d'existence (`docs/SCHEMA.md § 3`).
    if (parIdentifiant &&
        (trouvees.isEmpty ||
            trouvees.single.email.toLowerCase() !=
                (sessionEmail ?? '').toLowerCase())) {
      throw EchecAcceptation(
        ErreurAcceptation.mauvaisCompte,
        adresseCourante: sessionEmail,
      );
    }
    if (trouvees.isEmpty) {
      throw const EchecAcceptation(ErreurAcceptation.introuvable);
    }
    final invitation = trouvees.single;

    final caserne = CaserneInvitation(nom: _base.nomCaserne);

    if (!invitation.enAttente) {
      // Le même lien rejoué par le même compte n'est pas une erreur.
      final deja = _base.membreParEmail(invitation.email);
      if (deja != null) {
        return AcceptationInvitation(
          dejaAcceptee: true,
          role: deja.role,
          caserne: caserne,
        );
      }
      throw EchecAcceptation(
        ErreurAcceptation.dejaAcceptee,
        caserne: caserne,
      );
    }

    if (invitation.expireLe.isBefore(_base.horloge())) {
      throw EchecAcceptation(ErreurAcceptation.expiree, caserne: caserne);
    }

    invitation.accepteeLe = _base.horloge();

    // `accept_invitation` crée l'appartenance : c'est elle, et elle seule, qui
    // fait entrer quelqu'un dans une caserne.
    final recrue = _base.membreParEmail(invitation.email)!
      ..role = invitation.role
      ..statut = StatutMembre.actif;

    // `accept_invitation` (migration 0034) recopie le nom de l'invitation dans
    // le profil **s'il est vide**. Le nom que la personne saisit sur elle-même
    // n'est jamais écrasé.
    if (recrue.prenom.isEmpty && (invitation.prenom ?? '').isNotEmpty) {
      recrue.prenom = invitation.prenom!;
    }
    if (recrue.nom.isEmpty && (invitation.nom ?? '').isNotEmpty) {
      recrue.nom = invitation.nom!;
    }
    _base.apresAcceptation?.call(recrue);

    return AcceptationInvitation(
      dejaAcceptee: false,
      role: invitation.role,
      caserne: caserne,
      inviteur: const InviteurInvitation(libelle: 'Jean Dupont'),
    );
  }
}

/// Les disponibilités d'**un** membre. `userId` vient de la session : l'écran
/// le passe, le dépôt ne l'invente pas.
class _DisposMemoire implements DisposRepository {
  _DisposMemoire(this._base, [this._auteur]);

  final BackendMemoire _base;

  /// L'auteur des écritures, quand il est connu. Sur cet écran c'est toujours
  /// le membre lui-même : la saisie par procuration passe par la matrice.
  final String? _auteur;

  @override
  Future<List<PeriodeSaisie>> periodes(String stationId) async =>
      <PeriodeSaisie>[_base.periode];

  @override
  Future<Map<CreneauCle, DisponibiliteEtat>> lireMois({
    required String stationId,
    required String userId,
    required int annee,
    required int mois,
  }) async {
    final carte = _base.dispos[userId] ?? const <CreneauCle, DisponibiliteEtat>{};
    return <CreneauCle, DisponibiliteEtat>{
      for (final entree in carte.entries)
        if (entree.key.date.year == annee && entree.key.date.month == mois)
          entree.key: entree.value,
    };
  }

  @override
  Future<int> enregistrerLot({
    required String stationId,
    required String userId,
    required List<LigneDisponibilite> lignes,
  }) async {
    if (lignes.isEmpty) return 0;
    if (_base.periode.statut != PeriodeEtat.ouverte) {
      throw const EchecDispos(ErreurDispos.verrouille);
    }

    final carte = _base.dispos.putIfAbsent(
      userId,
      () => <CreneauCle, DisponibiliteEtat>{},
    );
    final auteurs = _base.auteursDispos.putIfAbsent(
      userId,
      () => <CreneauCle, String>{},
    );
    for (final ligne in lignes) {
      carte[ligne.cle] = ligne.etat;
      auteurs[ligne.cle] = _auteur ?? userId;
    }
    return lignes.length;
  }

  @override
  Future<int> supprimerLot({
    required String stationId,
    required String userId,
    required List<CreneauCle> cles,
  }) async {
    if (cles.isEmpty) return 0;
    if (_base.periode.statut != PeriodeEtat.ouverte) {
      throw const EchecDispos(ErreurDispos.verrouille);
    }

    final carte = _base.dispos[userId];
    if (carte == null) return 0;
    var supprimees = 0;
    for (final cle in cles) {
      if (carte.remove(cle) != null) {
        _base.auteursDispos[userId]?.remove(cle);
        supprimees++;
      }
    }
    return supprimees;
  }

  @override
  Future<Map<String, PreferencesMois>> lirePreferences({
    required String stationId,
    required String userId,
    required List<String> periodIds,
  }) async {
    final valeur = _base.preferences[userId];
    if (valeur == null || !periodIds.contains(_base.periode.id)) {
      return <String, PreferencesMois>{};
    }
    return <String, PreferencesMois>{_base.periode.id: valeur};
  }

  @override
  Future<int> enregistrerPreferences({
    required String stationId,
    required String userId,
    required String periodId,
    required PreferencesMois preferences,
  }) async {
    _base.preferences[userId] = preferences;
    return 1;
  }
}

/// `availability_matrix` (migration 0017), calculée sur les mêmes tables.
class _MatriceMemoire implements MatriceRepository {
  _MatriceMemoire(this._base);

  final BackendMemoire _base;

  @override
  Future<List<LigneMatrice>> matrice({
    required String stationId,
    required String periodeId,
  }) async {
    final jours = _base.periode.nombreDeJours;
    final charges = _charges();

    final lignes = <LigneMatrice>[
      for (final membre in _base.membres)
        if (membre.actif)
          _ligne(membre, jours, charges[membre.userId]),
    ]..sort((LigneMatrice a, LigneMatrice b) => a.nomAffiche.compareTo(b.nomAffiche));
    return List<LigneMatrice>.unmodifiable(lignes);
  }

  LigneMatrice _ligne(
    MembreMemoire membre,
    int jours,
    ({int astreintes, int unitesWeekend})? charge,
  ) {
    final preferences = _base.preferences[membre.userId];
    final astreintes = charge?.astreintes ?? 0;
    final unites = charge?.unitesWeekend ?? 0;
    final max = preferences?.maxAstreintes;
    final maxWeekends = preferences?.maxWeekends;

    return LigneMatrice(
      userId: membre.userId,
      nomAffiche: membre.libelle,
      prenom: membre.prenom,
      nom: membre.nom,
      commentaire: preferences?.commentaire,
      maxAstreintes: max,
      maxWeekends: maxWeekends,
      astreintes: astreintes,
      unitesWeekend: unites,
      astreintesRestantes: max == null ? null : max - astreintes,
      weekendsRestants: maxWeekends == null ? null : maxWeekends - unites,
      jours: _chaine(membre.userId, jours, CreneauType.jour),
      nuits: _chaine(membre.userId, jours, CreneauType.nuit),
    );
  }

  /// L'alphabet de `availability_matrix` : `.`, `D`, `A`, et leurs minuscules
  /// quand un administrateur a saisi à la place du membre.
  String _chaine(String userId, int jours, CreneauType creneau) {
    final carte = _base.dispos[userId] ?? const <CreneauCle, DisponibiliteEtat>{};
    final auteurs = _base.auteursDispos[userId] ?? const <CreneauCle, String>{};
    final tampon = StringBuffer();

    for (var jour = 1; jour <= jours; jour++) {
      final cle = CreneauCle(
        DateTime(_base.annee, _base.mois, jour),
        creneau,
      );
      final etat = carte[cle];
      if (etat == null) {
        tampon.write('.');
        continue;
      }
      final parAdmin = auteurs[cle] != null && auteurs[cle] != userId;
      final cellule = parAdmin
          ? CelluleMatrice.parAdminPour(etat)
          : (etat == DisponibiliteEtat.disponible
                ? CelluleMatrice.disponible
                : CelluleMatrice.absent);
      tampon.write(cellule.code);
    }
    return tampon.toString();
  }

  /// `v_member_load` : astreintes actives du mois et unités de weekend.
  Map<String, ({int astreintes, int unitesWeekend})> _charges() {
    final astreintes = <String, int>{};
    final unites = <String, Set<DateTime>>{};

    for (final attribution in _base.attributions) {
      if (!attribution.active) continue;
      final creneau = _base.creneaux
          .where((CreneauPlanning c) => c.id == attribution.creneauId)
          .toList(growable: false);
      if (creneau.isEmpty) continue;

      astreintes[attribution.userId] =
          (astreintes[attribution.userId] ?? 0) + 1;
      final unite = uniteWeekend(
        DateTime(_base.annee, _base.mois, creneau.single.jour),
      );
      if (unite != null) {
        (unites[attribution.userId] ??= <DateTime>{}).add(unite);
      }
    }

    return <String, ({int astreintes, int unitesWeekend})>{
      for (final entree in astreintes.entries)
        entree.key: (
          astreintes: entree.value,
          unitesWeekend: unites[entree.key]?.length ?? 0,
        ),
    };
  }

  @override
  Future<bool> ecrire({
    required String stationId,
    required String userId,
    required DateTime jour,
    required CreneauType creneau,
    required DisponibiliteEtat etat,
  }) async {
    if (etat == DisponibiliteEtat.nonSaisi) return false;
    final cle = CreneauCle(jour, creneau);
    _base.dispos.putIfAbsent(userId, () => <CreneauCle, DisponibiliteEtat>{})[cle] =
        etat;
    // `availabilities_trace_auteur` : l'auteur est l'appelant, et ici c'est
    // toujours un administrateur — d'où la minuscule au relecture.
    _base.auteursDispos.putIfAbsent(userId, () => <CreneauCle, String>{})[cle] =
        'admin';
    return true;
  }

  @override
  Future<bool> effacer({
    required String stationId,
    required String userId,
    required DateTime jour,
    required CreneauType creneau,
  }) async {
    final cle = CreneauCle(jour, creneau);
    final retiree = _base.dispos[userId]?.remove(cle) != null;
    _base.auteursDispos[userId]?.remove(cle);
    return retiree;
  }
}

/// Le planning du mois : création, attribution, retrait, réattribution.
class _PlanningMemoire implements PlanningRepository {
  _PlanningMemoire(this._base, this._adminId);

  final BackendMemoire _base;
  final String _adminId;

  @override
  Future<PlanningMois> lire({
    required String stationId,
    required String periodeId,
  }) async => _mois();

  PlanningMois _mois() {
    final entete = _base.planning;
    if (entete == null) return PlanningMois.vide();
    return PlanningMois(
      planning: entete,
      creneaux: _base.creneaux,
      // La base ne rend que les attributions **actives** : les autres restent
      // pour l'historique et n'occupent aucune place.
      attributions: <Attribution>[
        for (final attribution in _base.attributions)
          if (attribution.active)
            Attribution(
              id: attribution.id,
              creneauId: attribution.creneauId,
              userId: attribution.userId,
              etaitDisponible: attribution.etaitDisponible,
              auteurId: attribution.auteurId,
            ),
      ],
    );
  }

  @override
  Future<PlanningMois> creer({
    required String stationId,
    required String periodeId,
  }) async {
    // `create_schedule` est idempotente : deux adjoints obtiennent le même
    // planning.
    if (_base.planning != null) return _mois();

    _base.planning = PlanningBrouillon(
      id: 'plan-${_base.annee}-${_base.mois}',
      etat: PlanningEtat.brouillon,
    );
    for (var jour = 1; jour <= _base.periode.nombreDeJours; jour++) {
      for (final type in CreneauType.values) {
        _base.creneaux.add(
          CreneauPlanning(
            id: identifiantCreneau(jour, type),
            jour: jour,
            creneau: type,
            effectifRequis: _base.effectifRequis(jour, type),
          ),
        );
      }
    }
    return _mois();
  }

  @override
  Future<Attribution> attribuer({
    required String stationId,
    required String creneauId,
    required String userId,
  }) async {
    // `assignments_active_uniq` : une seule attribution active par couple.
    final deja = _base
        .attributionsDe(creneauId)
        .any((AttributionMemoire a) => a.userId == userId && a.active);
    if (deja) {
      throw const EchecPlanning(ErreurPlanning.dejaAttribue);
    }

    final creneau = _base.creneaux.firstWhere(
      (CreneauPlanning c) => c.id == creneauId,
    );
    final ligne = AttributionMemoire(
      id: _base._id('att'),
      creneauId: creneauId,
      userId: userId,
      etaitDisponible: _base._etaitDisponible(userId, creneau),
      auteurId: _adminId,
      // Un planning publié attribué depuis cet écran n'existe pas : la
      // réattribution passe par `reattribuer`. On reste donc en brouillon.
      proposeeLe: _base.etatPlanning == PlanningEtat.brouillon
          ? null
          : _base.horloge(),
    );
    _base.attributions.add(ligne);

    return Attribution(
      id: ligne.id,
      creneauId: ligne.creneauId,
      userId: ligne.userId,
      etaitDisponible: ligne.etaitDisponible,
      auteurId: ligne.auteurId,
    );
  }

  @override
  Future<bool> retirer({required String attributionId}) async {
    // La politique `assignments_delete_admin` est bornée au brouillon : sur un
    // planning publié elle **filtre sans lever**.
    if (_base.etatPlanning != PlanningEtat.brouillon) return false;
    final avant = _base.attributions.length;
    _base.attributions.removeWhere(
      (AttributionMemoire a) => a.id == attributionId,
    );
    return _base.attributions.length != avant;
  }

  @override
  Future<bool> definirEffectif({
    required String creneauId,
    required int effectif,
  }) async {
    final index = _base.creneaux.indexWhere(
      (CreneauPlanning c) => c.id == creneauId,
    );
    if (index < 0) return false;
    _base.creneaux[index] = _base.creneaux[index].avecEffectif(effectif);
    _base._reevaluer();
    return true;
  }

  /// `apply_auto_proposal` : les limites, et rien d'autre. Le choix des
  /// pompiers a été fait par l'écran, avec le tri du ticket 017.
  @override
  Future<ResultatProposition> appliquerProposition({
    required String planningId,
    required List<Map<String, String>> picks,
  }) async {
    if (_base.etatPlanning != PlanningEtat.brouillon) {
      throw const EchecPlanning(ErreurPlanning.planningPublie);
    }

    var posees = 0;
    for (final ligne in picks) {
      final creneauId = ligne['shift_id']!;
      final userId = ligne['user_id']!;

      final index = _base.creneaux.indexWhere(
        (CreneauPlanning c) => c.id == creneauId,
      );
      if (index < 0) continue;
      final creneau = _base.creneaux[index];

      final membre = _base.membreParId(userId);
      if (membre == null || !membre.actif) continue;

      // Ni l'absent ni le non-saisi : la machine ne désigne que ceux qui ont
      // dit oui.
      if (!_base._etaitDisponible(userId, creneau)) continue;

      final lignes = _base.attributionsDe(creneauId);
      if (lignes.any((AttributionMemoire a) => a.userId == userId && a.active)) {
        continue;
      }
      if (lignes.where((AttributionMemoire a) => a.active).length >=
          creneau.effectifRequis) {
        continue;
      }

      _base.attributions.add(
        AttributionMemoire(
          id: _base._id('att'),
          creneauId: creneauId,
          userId: userId,
          etaitDisponible: true,
          auteurId: _adminId,
        ),
      );
      posees++;
    }

    final decouverts = _base.creneaux
        .where(
          (CreneauPlanning c) =>
              _base
                  .attributionsDe(c.id)
                  .where((AttributionMemoire a) => a.active)
                  .length <
              c.effectifRequis,
        )
        .length;

    return ResultatProposition(
      posees: posees,
      ecartees: picks.length - posees,
      decouverts: decouverts,
    );
  }

  @override
  Future<ResultatReattribution> reattribuer({
    required String creneauId,
    required String userId,
    String? ancienneId,
  }) async {
    if (_base.etatPlanning == PlanningEtat.brouillon) {
      throw const EchecPlanning(ErreurPlanning.brouillon);
    }
    final membre = _base.membreParId(userId);
    if (membre == null || !membre.actif) {
      throw const EchecPlanning(ErreurPlanning.membreInactif);
    }

    final creneau = _base.creneaux.firstWhere(
      (CreneauPlanning c) => c.id == creneauId,
    );
    final lignes = _base.attributionsDe(creneauId);

    if (lignes.where((AttributionMemoire a) => a.active).length >=
        creneau.effectifRequis) {
      throw const EchecPlanning(ErreurPlanning.creneauPourvu);
    }

    // `reassign_shift` : le plus ancien trou non couvert —
    // `order by responded_at nulls last, created_at`.
    final candidates =
        lignes
            .where(
              (AttributionMemoire a) =>
                  a.close &&
                  a.remplaceParId == null &&
                  (ancienneId == null || a.id == ancienneId),
            )
            .toList(growable: false)
          ..sort(_ordreDuPlusAncienTrou);
    final ancienne = candidates.isEmpty ? null : candidates.first;

    final nouvelle = AttributionMemoire(
      id: _base._id('att'),
      creneauId: creneauId,
      userId: userId,
      etaitDisponible: _base._etaitDisponible(userId, creneau),
      auteurId: _adminId,
      proposeeLe: _base.horloge(),
    );
    _base.attributions.add(nouvelle);
    ancienne?.remplaceParId = nouvelle.id;

    // Le téléphone du remplaçant sonne : c'est tout l'objet du geste.
    _base._notifier('assignment_proposed', <String>[userId]);
    final ancienPrevenu = ancienne?.etat == AttributionEtat.accepte;
    if (ancienPrevenu) {
      _base._notifier('assignment_cancelled', <String>[ancienne!.userId]);
    }

    _base._reevaluer();

    return ResultatReattribution(
      attribution: Attribution(
        id: nouvelle.id,
        creneauId: nouvelle.creneauId,
        userId: nouvelle.userId,
        etaitDisponible: nouvelle.etaitDisponible,
        auteurId: nouvelle.auteurId,
      ),
      ancienUserId: ancienne?.userId,
      ancienPrevenu: ancienPrevenu,
      planningPublie: _base.etatPlanning == PlanningEtat.publie,
    );
  }

  @override
  Future<bool> annuler({required String attributionId, String? motif}) async {
    final ligne = _base.attributionParId(attributionId);
    if (ligne == null || !ligne.active) {
      throw const EchecPlanning(ErreurPlanning.dejaRemplacee);
    }
    final prevenu = ligne.etat == AttributionEtat.accepte;
    ligne
      ..etat = AttributionEtat.annule
      ..motifRefus = motif
      ..repondueLe = _base.horloge();
    if (prevenu) {
      _base._notifier('assignment_cancelled', <String>[ligne.userId]);
    }
    _base._reevaluer();
    return prevenu;
  }

  @override
  Stream<EvenementPlanning> ecouter({required String stationId}) async* {
    // Le canal est branché et ne dit plus rien : dans ce parcours, personne
    // n'écrit depuis un second appareil. Un `StreamController` jamais fermé
    // serait un `close_sinks` de plus à taire pour la même absence d'écho.
    yield const EtatCanalPlanning(branche: true);
    await Completer<void>().future;
  }

  static int _ordreDuPlusAncienTrou(AttributionMemoire a, AttributionMemoire b) {
    final reponseA = a.repondueLe;
    final reponseB = b.repondueLe;
    if (reponseA != null && reponseB != null && reponseA != reponseB) {
      return reponseA.compareTo(reponseB);
    }
    if (reponseA == null && reponseB != null) return 1;
    if (reponseB == null && reponseA != null) return -1;
    return a.id.compareTo(b.id);
  }
}

/// Le suivi : la lecture du planning publié, la publication, les relances.
class _SuiviMemoire implements SuiviRepository {
  _SuiviMemoire(this._base, this._adminId);

  final BackendMemoire _base;
  final String _adminId;

  @override
  Future<SuiviPlanning> lire({
    required String stationId,
    required String periodeId,
    required int annee,
    required int mois,
  }) async {
    final entete = _base.planning;
    if (entete == null) return SuiviPlanning.vide(annee: annee, mois: mois);

    return SuiviPlanning(
      planning: entete,
      progression: _progression(),
      creneaux: _base.creneaux,
      attributions: <AttributionSuivi>[
        for (final attribution in _base.attributions)
          AttributionSuivi(
            id: attribution.id,
            creneauId: attribution.creneauId,
            userId: attribution.userId,
            nom: _base.membreParId(attribution.userId)?.libelle ?? '',
            etat: attribution.etat,
            proposeeLe: attribution.proposeeLe,
            repondueLe: attribution.repondueLe,
            motifRefus: attribution.motifRefus,
            relances: attribution.relances,
            derniereRelance: attribution.derniereRelance,
            remplaceParId: attribution.remplaceParId,
          ),
      ],
      annee: annee,
      mois: mois,
      delaiRetardHeures: _base.delaiRetardHeures,
    );
  }

  /// `v_schedule_progress`, comptée comme la vue la compte.
  ProgressionPlanning _progression() {
    var pourvus = 0;
    for (final creneau in _base.creneaux) {
      final actives = _base
          .attributionsDe(creneau.id)
          .where((AttributionMemoire a) => a.active)
          .length;
      if (actives >= creneau.effectifRequis) pourvus++;
    }

    final maintenant = _base.horloge();
    var enAttente = 0;
    var acceptees = 0;
    var refusees = 0;
    var enRetard = 0;
    for (final attribution in _base.attributions) {
      switch (attribution.etat) {
        case AttributionEtat.propose:
          enAttente++;
          final depuis = attribution.proposeeLe;
          if (depuis != null &&
              maintenant.difference(depuis).inHours >=
                  _base.delaiRetardHeures) {
            enRetard++;
          }
        case AttributionEtat.accepte:
          acceptees++;
        case AttributionEtat.refuse:
          refusees++;
        case AttributionEtat.remplace:
        case AttributionEtat.annule:
          break;
      }
    }

    return ProgressionPlanning(
      creneauxTotal: _base.creneaux.length,
      creneauxPourvus: pourvus,
      enAttente: enAttente,
      acceptees: acceptees,
      refusees: refusees,
      enRetard: enRetard,
    );
  }

  @override
  Future<ProgressionPlanning> lireProgression({
    required String planningId,
  }) async => _progression();

  @override
  Future<ResultatPublication> publier({required String planningId}) async {
    final entete = _base.planning;
    if (entete == null) {
      throw const EchecSuivi(ErreurSuivi.planningIntrouvable);
    }
    if (entete.etat != PlanningEtat.brouillon) {
      throw const EchecSuivi(ErreurSuivi.dejaPublie);
    }

    final maintenant = _base.horloge();
    _base.planning = PlanningBrouillon(
      id: entete.id,
      etat: PlanningEtat.publie,
      publieLe: maintenant,
    );

    // `proposed_at` posé sur toutes les attributions qui n'en avaient pas :
    // c'est **le** signal « c'est parti » (`docs/WORKFLOWS.md § 3`).
    final destinataires = <String>{};
    var attribuees = 0;
    for (final attribution in _base.attributions) {
      if (attribution.etat != AttributionEtat.propose) continue;
      if (attribution.proposeeLe != null) continue;
      attribution.proposeeLe = maintenant;
      destinataires.add(attribution.userId);
      attribuees++;
    }

    if (destinataires.isNotEmpty) {
      // `assignment_proposed`, regroupé par publication
      // (`docs/WORKFLOWS.md § 8`) : un pompier à sept créneaux fait une
      // entrée, pas sept.
      _base._notifier(
        'assignment_proposed',
        destinataires.toList(growable: false)..sort(),
      );
    }

    // Publier ne valide pas : personne n'a encore répondu. Le test de
    // complétude reste appelé, pour le cas d'un planning sans créneau.
    _base._reevaluer();

    return ResultatPublication(
      membres: destinataires.length,
      attributions: attribuees,
    );
  }

  @override
  Future<ResultatRelance> relancer({
    required String planningId,
    bool tout = false,
  }) async {
    final entete = _base.planning;
    if (entete == null || entete.etat == PlanningEtat.brouillon) {
      throw const EchecSuivi(ErreurSuivi.pasPublie);
    }

    final maintenant = _base.horloge();
    final destinataires = <String>{};
    for (final attribution in _base.attributions) {
      if (attribution.etat != AttributionEtat.propose) continue;
      final depuis = attribution.proposeeLe;
      if (depuis == null) continue;
      if (!tout &&
          maintenant.difference(depuis).inHours < _base.delaiRetardHeures) {
        continue;
      }
      attribution
        ..relances = attribution.relances + 1
        ..derniereRelance = maintenant;
      destinataires.add(attribution.userId);
    }

    if (destinataires.isNotEmpty) {
      _base._notifier(
        'assignment_reminder',
        destinataires.toList(growable: false)..sort(),
      );
    }
    return ResultatRelance(
      membres: destinataires.length,
      nouvelle: destinataires.isNotEmpty,
    );
  }

  @override
  Stream<EvenementSuivi> ecouter({required String stationId}) async* {
    yield const EtatCanalSuivi(branche: true);
    await Completer<void>().future;
  }

  /// L'administrateur qui agit. Conservé pour la symétrie avec la base, qui
  /// inscrit l'acteur sur chaque écriture.
  String get acteur => _adminId;
}

/// Les propositions d'un membre, et ses réponses.
class _PropositionsMemoire implements PropositionsRepository {
  _PropositionsMemoire(this._base);

  final BackendMemoire _base;

  @override
  Future<List<Proposition>> lister({
    required String userId,
    required String stationId,
  }) async {
    final liste = <Proposition>[
      for (final attribution in _base.attributions)
        if (attribution.userId == userId &&
            attribution.etat == AttributionEtat.propose &&
            attribution.proposeeLe != null)
          if (_creneau(attribution.creneauId) case final CreneauPlanning creneau)
            Proposition(
              id: attribution.id,
              creneauId: attribution.creneauId,
              planningId: _base.planning!.id,
              jour: DateTime(_base.annee, _base.mois, creneau.jour),
              creneau: creneau.creneau,
              planningEtat: _base.etatPlanning,
              proposeeLe: attribution.proposeeLe,
              relances: attribution.relances,
              derniereRelance: attribution.derniereRelance,
            ),
    ]..sort((Proposition a, Proposition b) => a.comparer(b));
    return List<Proposition>.unmodifiable(liste);
  }

  CreneauPlanning? _creneau(String id) {
    for (final creneau in _base.creneaux) {
      if (creneau.id == id) return creneau;
    }
    return null;
  }

  @override
  Future<ResultatReponse> repondre({
    required String attributionId,
    required bool accepte,
    String? motif,
  }) async {
    final ligne = _base.attributionParId(attributionId);
    // `assignments_member_transition` ne laisse répondre qu'à une ligne encore
    // `proposed` : tout le reste répond « 0 ligne touchée ».
    if (ligne == null || ligne.etat != AttributionEtat.propose) {
      return ResultatReponse.disparue;
    }

    ligne
      ..etat = accepte ? AttributionEtat.accepte : AttributionEtat.refuse
      ..repondueLe = _base.horloge()
      ..motifRefus = accepte ? null : motif?.trim();

    if (!accepte) {
      // L'administrateur apprend le refus : c'est lui qui devra réparer.
      _base._notifier('assignment_declined', <String>[
        for (final membre in _base.membres)
          if (membre.actif && membre.role == RoleMembre.admin) membre.userId,
      ]);
    }

    _base._reevaluer();
    return ResultatReponse.enregistree;
  }

  @override
  Future<PlanningEtat?> etatPlanning(String planningId) async =>
      _base.planning == null ? null : _base.etatPlanning;
}
