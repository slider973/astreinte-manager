import 'package:astreinte_sp/core/caserne/etat_caserne.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/superadmin/data/superadmin_repository.dart';
import 'package:astreinte_sp/features/superadmin/domain/caserne_supervisee.dart';

/// Les deux casernes du seed, vues depuis l'écran de l'éditeur.
///
/// A a neuf membres, un administrateur et un planning publié ; B n'a **aucun
/// administrateur actif** — c'est le cas qui appelle une invitation, et le seul
/// défaut qu'une ligne peut porter.
final CaserneSupervisee caserneA = CaserneSupervisee(
  id: 'aaaaaaaa-0000-4000-8000-000000000001',
  nom: 'CIS Saint-Martin',
  slug: 'saint-martin',
  fuseau: 'Europe/Paris',
  creeLe: DateTime(2026, 3, 3),
  membresActifs: 9,
  adminsActifs: 1,
  invitationsEnAttente: 0,
  statut: StatutAbonnement.essai,
  ecriture: true,
  finEssai: DateTime(2026, 11, 20),
  dernierPlanningLe: DateTime(2026, 10, 18),
  dernierPlanningAnnee: 2026,
  dernierPlanningMois: 11,
);

final CaserneSupervisee caserneSansAdmin = CaserneSupervisee(
  id: 'bbbbbbbb-0000-4000-8000-000000000001',
  nom: 'CIS Val-de-Loue',
  slug: 'val-de-loue',
  fuseau: 'Europe/Paris',
  creeLe: DateTime(2026, 8, 12),
  membresActifs: 0,
  adminsActifs: 0,
  invitationsEnAttente: 0,
  statut: StatutAbonnement.essai,
  ecriture: true,
  finEssai: DateTime(2026, 11, 20),
);

/// Une caserne suspendue : la ligne propose « Réactiver », pas « Suspendre ».
final CaserneSupervisee caserneSuspendue = CaserneSupervisee(
  id: 'cccccccc-0000-4000-8000-000000000001',
  nom: 'CIS Bois-Clair',
  slug: 'bois-clair',
  fuseau: 'Europe/Paris',
  creeLe: DateTime(2025, 11, 2),
  membresActifs: 12,
  adminsActifs: 2,
  invitationsEnAttente: 0,
  statut: StatutAbonnement.suspendu,
  ecriture: false,
  suspendueLe: DateTime(2026, 9, 2),
  dernierPlanningLe: DateTime(2026, 7, 30),
  dernierPlanningAnnee: 2026,
  dernierPlanningMois: 8,
);

/// Ce que la consultation de support rend : de l'avancement, jamais un nom.
final PlanningSupervise planningSupport = PlanningSupervise(
  annee: 2026,
  mois: 11,
  etat: PlanningEtat.publie,
  periode: PeriodeEtat.verrouillee,
  creneaux: 60,
  attributions: const <AttributionEtat, int>{
    AttributionEtat.accepte: 48,
    AttributionEtat.propose: 12,
  },
  publieLe: DateTime(2026, 10, 18),
);

/// Un faux dépôt de l'éditeur, qui enregistre ce qu'on lui demande.
class FauxSuperAdminRepository implements SuperAdminRepository {
  FauxSuperAdminRepository({
    this.autorise = true,
    List<CaserneSupervisee>? casernes,
    this.plannings_ = const <PlanningSupervise>[],
    this.echecCreation,
    this.echecSuspension,
    this.echecSupport,
  }) : _casernes = casernes ?? <CaserneSupervisee>[caserneA, caserneSansAdmin];

  /// Le droit de l'éditeur, tel que `is_super_admin()` le rend.
  bool autorise;

  List<CaserneSupervisee> _casernes;

  final List<PlanningSupervise> plannings_;

  final ErreurSuperAdmin? echecCreation;
  final ErreurSuperAdmin? echecSuspension;
  final ErreurSuperAdmin? echecSupport;

  int lectures = 0;

  /// Les créations demandées, dans l'ordre.
  final List<({String nom, String fuseau})> creations =
      <({String nom, String fuseau})>[];

  /// Les suspensions demandées, avec leur raison : c'est elle qui part dans le
  /// journal d'audit, et le test vérifie qu'elle n'est jamais vide.
  final List<({String stationId, bool suspendue, String raison})> suspensions =
      <({String stationId, bool suspendue, String raison})>[];

  /// Les consultations de support demandées. **Le compte fait foi** : une
  /// lecture non demandée est une lecture non tracée.
  final List<({String stationId, String raison})> consultations =
      <({String stationId, String raison})>[];

  @override
  Future<bool> estSuperAdmin() async => autorise;

  @override
  Future<List<CaserneSupervisee>> casernes() async {
    lectures++;
    if (!autorise) return const <CaserneSupervisee>[];
    return List<CaserneSupervisee>.unmodifiable(_casernes);
  }

  @override
  Future<CaserneSupervisee> creerCaserne({
    required String nom,
    required String fuseau,
  }) async {
    creations.add((nom: nom, fuseau: fuseau));
    final echec = echecCreation;
    if (echec != null) throw EchecSuperAdmin(echec);

    final creee = CaserneSupervisee(
      id: 'dddddddd-0000-4000-8000-00000000000${creations.length}',
      nom: nom,
      slug: nom.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-'),
      fuseau: fuseau,
      creeLe: DateTime(2026, 9, 21),
      membresActifs: 0,
      adminsActifs: 0,
      invitationsEnAttente: 0,
      statut: StatutAbonnement.essai,
      ecriture: true,
    );
    _casernes = <CaserneSupervisee>[..._casernes, creee];
    return creee;
  }

  @override
  Future<void> definirSuspension({
    required String stationId,
    required bool suspendue,
    required String raison,
  }) async {
    suspensions.add((
      stationId: stationId,
      suspendue: suspendue,
      raison: raison,
    ));
    final echec = echecSuspension;
    if (echec != null) throw EchecSuperAdmin(echec);

    _casernes = <CaserneSupervisee>[
      for (final CaserneSupervisee c in _casernes)
        if (c.id != stationId)
          c
        else
          CaserneSupervisee(
            id: c.id,
            nom: c.nom,
            slug: c.slug,
            fuseau: c.fuseau,
            creeLe: c.creeLe,
            membresActifs: c.membresActifs,
            adminsActifs: c.adminsActifs,
            invitationsEnAttente: c.invitationsEnAttente,
            statut: suspendue
                ? StatutAbonnement.suspendu
                : StatutAbonnement.essai,
            ecriture: !suspendue,
            finEssai: c.finEssai,
            suspendueLe: suspendue ? DateTime(2026, 9, 21) : null,
            dernierPlanningLe: c.dernierPlanningLe,
            dernierPlanningAnnee: c.dernierPlanningAnnee,
            dernierPlanningMois: c.dernierPlanningMois,
          ),
    ];
  }

  @override
  Future<List<PlanningSupervise>> plannings({
    required String stationId,
    required String raison,
  }) async {
    consultations.add((stationId: stationId, raison: raison));
    final echec = echecSupport;
    if (echec != null) throw EchecSuperAdmin(echec);
    return plannings_;
  }
}
