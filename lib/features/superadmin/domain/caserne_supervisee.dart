import 'package:flutter/foundation.dart';

import '../../../core/caserne/etat_caserne.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';
import '../../planning/domain/suivi_planning.dart';

/// Une caserne vue depuis l'écran de l'éditeur du produit.
///
/// Reflet exact d'une ligne de `super_admin_stations()` (`docs/SCHEMA.md § 3`),
/// et **rien d'autre** : ni les réglages du centre, ni les identifiants du
/// prestataire de paiement, ni le moindre nom de personne. Les invitations en
/// attente sont un compte, pas une liste d'adresses.
@immutable
class CaserneSupervisee {
  const CaserneSupervisee({
    required this.id,
    required this.nom,
    required this.slug,
    required this.fuseau,
    required this.creeLe,
    required this.membresActifs,
    required this.adminsActifs,
    required this.invitationsEnAttente,
    required this.statut,
    required this.ecriture,
    this.finEssai,
    this.suspendueLe,
    this.dernierPlanningLe,
    this.dernierPlanningAnnee,
    this.dernierPlanningMois,
  });

  factory CaserneSupervisee.depuisJson(Map<String, dynamic> ligne) =>
      CaserneSupervisee(
        id: ligne['station_id']! as String,
        nom: (ligne['name'] as String? ?? '').trim(),
        slug: ligne['slug'] as String? ?? '',
        fuseau: ligne['timezone'] as String? ?? 'Europe/Paris',
        creeLe: DateTime.parse(ligne['created_at']! as String).toLocal(),
        membresActifs: (ligne['active_members'] as num?)?.toInt() ?? 0,
        adminsActifs: (ligne['active_admins'] as num?)?.toInt() ?? 0,
        invitationsEnAttente: (ligne['pending_invites'] as num?)?.toInt() ?? 0,
        statut: StatutAbonnement.depuisSql(ligne['status'] as String?),
        // `writable` fait autorité : il vient de `station_writable()`, la seule
        // définition du droit d'écrire (`design/030 § 1`). Absent, on relit le
        // statut plutôt que de supposer un refus.
        ecriture:
            (ligne['writable'] as bool?) ??
            !StatutAbonnement.depuisSql(
              ligne['status'] as String?,
            ).lectureSeule,
        finEssai: _instant(ligne['trial_ends_at']),
        suspendueLe: _instant(ligne['suspended_at']),
        dernierPlanningLe: _instant(ligne['last_published_at']),
        dernierPlanningAnnee: (ligne['last_published_year'] as num?)?.toInt(),
        dernierPlanningMois: (ligne['last_published_month'] as num?)?.toInt(),
      );

  static DateTime? _instant(Object? valeur) =>
      valeur is String && valeur.isNotEmpty
      ? DateTime.parse(valeur).toLocal()
      : null;

  final String id;
  final String nom;
  final String slug;
  final String fuseau;
  final DateTime creeLe;

  final int membresActifs;
  final int adminsActifs;
  final int invitationsEnAttente;

  final StatutAbonnement statut;

  /// Le verdict de `station_writable()`, tel quel.
  final bool ecriture;

  final DateTime? finEssai;
  final DateTime? suspendueLe;

  final DateTime? dernierPlanningLe;
  final int? dernierPlanningAnnee;
  final int? dernierPlanningMois;

  /// Vrai quand la caserne n'a personne pour l'administrer.
  ///
  /// C'est le seul défaut de la ligne qui appelle une action : une caserne sans
  /// administrateur actif est un cul-de-sac, et l'éditeur est le seul à pouvoir
  /// en sortir — par une invitation.
  bool get sansAdministrateur => adminsActifs == 0;

  /// Vrai quand l'éditeur a déjà invité quelqu'un et attend la réponse.
  bool get invitationEnRoute => sansAdministrateur && invitationsEnAttente > 0;

  bool get suspendue => statut == StatutAbonnement.suspendu;

  bool get aUnPlanningPublie => dernierPlanningAnnee != null;

  @override
  bool operator ==(Object other) =>
      other is CaserneSupervisee &&
      other.id == id &&
      other.nom == nom &&
      other.membresActifs == membresActifs &&
      other.adminsActifs == adminsActifs &&
      other.invitationsEnAttente == invitationsEnAttente &&
      other.statut == statut &&
      other.ecriture == ecriture &&
      other.dernierPlanningAnnee == dernierPlanningAnnee &&
      other.dernierPlanningMois == dernierPlanningMois;

  @override
  int get hashCode => Object.hash(
    id,
    nom,
    membresActifs,
    adminsActifs,
    invitationsEnAttente,
    statut,
    ecriture,
    dernierPlanningAnnee,
    dernierPlanningMois,
  );
}

/// Un mois de planning, tel que la consultation de support le rend.
///
/// `super_admin_support_schedules()` ne rend que des faits d'avancement :
/// aucun `user_id`, aucun nom. « Où en est le planning de novembre », jamais
/// « qui est de garde le 12 » (`design/031 § 2`).
@immutable
class PlanningSupervise {
  const PlanningSupervise({
    required this.annee,
    required this.mois,
    required this.etat,
    required this.periode,
    required this.creneaux,
    required this.attributions,
    this.publieLe,
    this.valideLe,
  });

  factory PlanningSupervise.depuisJson(Map<String, dynamic> ligne) {
    final comptes = ligne['assignments'];
    return PlanningSupervise(
      annee: (ligne['year'] as num).toInt(),
      mois: (ligne['month'] as num).toInt(),
      etat: PlanningSql.depuisSql(ligne['status'] as String?),
      periode: PeriodeSql.depuisSql(ligne['period_status'] as String?),
      creneaux: (ligne['shifts'] as num?)?.toInt() ?? 0,
      attributions: <AttributionEtat, int>{
        if (comptes is Map)
          for (final MapEntry<Object?, Object?> entree in comptes.entries)
            if (entree.value is num)
              AttributionSuivi.etatDepuisSql(entree.key as String?):
                  (entree.value! as num).toInt(),
      },
      publieLe: CaserneSupervisee._instant(ligne['published_at']),
      valideLe: CaserneSupervisee._instant(ligne['validated_at']),
    );
  }

  final int annee;
  final int mois;
  final PlanningEtat etat;
  final PeriodeEtat periode;
  final int creneaux;

  /// Le décompte des attributions par état.
  ///
  /// Traduit à la lecture par `AttributionSuivi.etatDepuisSql` — la **même**
  /// fonction que l'écran de suivi : deux tables de correspondance pour un seul
  /// enum Postgres finiraient par se contredire.
  final Map<AttributionEtat, int> attributions;

  final DateTime? publieLe;
  final DateTime? valideLe;

  int get total => attributions.values.fold(0, (int a, int b) => a + b);

  /// Les états présents, dans l'ordre stable de l'enum : deux mois voisins
  /// n'affichent pas leurs compteurs dans un ordre différent.
  List<AttributionEtat> get etatsPresents => AttributionEtat.values
      .where((AttributionEtat e) => (attributions[e] ?? 0) > 0)
      .toList(growable: false);

  int compte(AttributionEtat etat) => attributions[etat] ?? 0;
}
