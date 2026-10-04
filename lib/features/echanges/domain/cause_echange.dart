import '../../../core/l10n/app_strings.dart';

/// La cause d'un échec ou d'un refus de règle, dite en français et **sans
/// code** (`design/073 § 5.3`).
///
/// Une phrase par motif de la liste fermée de `reason_code`
/// (`docs/SCHEMA.md § 2.19`) et des refus de `request_exchange`, et une
/// phrase de repli pour ce que cette version ne connaît pas.
///
/// **« Pris dans une autre caserne » ne se dit jamais à un pompier** : la base
/// le lui rend déjà `*_already_assigned`, « déjà pris sur ce créneau ». Seul
/// l'administrateur lit le détail `*_taken_elsewhere`, et seulement dans la
/// réponse de `decide_exchange` ([pourAdmin]).
String causeEchange(
  String? code, {
  String? qui,
  String nomDemandeur = '',
  String nomPair = '',
  bool pourAdmin = false,
  String? detail,
}) {
  if (pourAdmin && detail != null && detail.endsWith('taken_elsewhere')) {
    return AppStrings.echangeCauseAilleurs;
  }
  final demandeur = _nom(nomDemandeur);
  final pair = _nom(nomPair);

  switch (code) {
    case 'assignment_changed':
    case 'assignment_not_accepted':
    case 'return_assignment_not_accepted':
    case 'assignment_not_found':
    case 'return_assignment_not_found':
      return AppStrings.echangeCauseGardeChangee;
    case 'peer_already_assigned':
      return AppStrings.echangeCauseDejaPris(pair);
    case 'requester_already_assigned':
      return AppStrings.echangeCauseDejaPris(demandeur);
    case 'peer_shift_quota_reached':
      return AppStrings.echangeCausePlafondAstreintes(pair);
    case 'requester_shift_quota_reached':
      return AppStrings.echangeCausePlafondAstreintes(demandeur);
    case 'peer_weekend_quota_reached':
      return AppStrings.echangeCausePlafondWeekends(pair);
    case 'requester_weekend_quota_reached':
      return AppStrings.echangeCausePlafondWeekends(demandeur);
    case 'peer_not_active':
    case 'target_not_member':
      return AppStrings.echangeCauseInactif(pair);
    case 'requester_not_active':
      return AppStrings.echangeCauseInactif(demandeur);
    case 'station_suspended':
      return AppStrings.echangeCauseSuspendue;
    case 'schedule_not_published':
    case 'too_late':
    case 'exchange_expired':
    case 'deadline_reached':
      return AppStrings.echangeCauseCommence;
    case 'exchange_already_open':
      return AppStrings.echangeCauseDejaOuverte;
    // Les règles du remplaçant à la demande : `who` dit de qui il s'agit.
    // `target`, c'est le collègue désigné ; `requester`, c'est A lui-même,
    // pour le second mouvement d'un échange — la phrase lui parle alors.
    case 'already_assigned':
      return qui == 'requester'
          ? AppStrings.echangeCauseToiDejaPris
          : AppStrings.echangeCauseDejaPris(pair);
    case 'shift_quota_reached':
      return qui == 'requester'
          ? AppStrings.echangeCauseToiPlafondAstreintes
          : AppStrings.echangeCausePlafondAstreintes(pair);
    case 'weekend_quota_reached':
      return qui == 'requester'
          ? AppStrings.echangeCauseToiPlafondWeekends
          : AppStrings.echangeCausePlafondWeekends(pair);
    default:
      return AppStrings.echangeCauseAutre;
  }
}

String _nom(String nom) =>
    nom.trim().isEmpty ? AppStrings.echangeMembreInconnu : nom.trim();
