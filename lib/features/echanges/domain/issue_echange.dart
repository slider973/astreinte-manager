import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/theme/app_status.dart';
import '../data/echanges_repository.dart';
import 'cause_echange.dart';
import 'echange.dart';

/// Le ton d'une issue : il choisit la surface — message passager pour un
/// succès, bannière d'information pour une course perdue (jamais de rouge),
/// bannière d'erreur pour une règle qui refuse.
enum TonIssue { succes, information, erreur }

/// Ce qu'un geste d'échange a produit, déjà en français.
///
/// Les fonctions de ce fichier sont **pures** : c'est elles que les tests
/// éprouvent, motif par motif.
@immutable
class IssueEchange {
  const IssueEchange({
    required this.ok,
    required this.ton,
    required this.message,
    this.detail,
    this.valideMaintenant = false,
    this.retiree = false,
  });

  /// Le geste n'a pas atteint la base, ou n'en est pas revenu.
  factory IssueEchange.panne(String message) =>
      IssueEchange(ok: false, ton: TonIssue.erreur, message: message);

  /// La base a fait ce qui était demandé.
  final bool ok;
  final TonIssue ton;
  final String message;
  final String? detail;

  /// La garde vient de changer de main (validation, automatique ou non).
  final bool valideMaintenant;

  /// La demande n'est plus là où on la lisait : sa carte quitte la liste.
  final bool retiree;
}

/// « nuit du samedi 12 octobre ».
String creneauPhrase(GardeEchange garde) => AppStrings.echangeCreneauPhrase(
  nuit: garde.creneau == CreneauType.nuit,
  jourEtDate: dateAvecJourSemaine(garde.jour),
);

/// La réponse de `request_exchange`.
IssueEchange issueDemande(ResultatEchange r, {Collegue? cible}) {
  if (r.ok) {
    if (r.notifies == 0) {
      return const IssueEchange(
        ok: true,
        ton: TonIssue.information,
        message: AppStrings.echangeEnvoyeePersonne,
      );
    }
    return IssueEchange(
      ok: true,
      ton: TonIssue.succes,
      message: cible == null
          ? AppStrings.echangeEnvoyeeCaserne
          : AppStrings.echangeEnvoyeeA(cible.nom),
    );
  }

  if (r.code == 'station_suspended') {
    return const IssueEchange(
      ok: false,
      ton: TonIssue.erreur,
      message: AppStrings.echangeLectureSeuleRaison,
    );
  }
  final expire = r.expireLe;
  if (r.code == 'too_late' && expire != null) {
    return IssueEchange(
      ok: false,
      ton: TonIssue.erreur,
      message: AppStrings.echangeTropTard(
        formaterDateCourte(expire),
        heureMinute(expire),
      ),
    );
  }
  return IssueEchange(
    ok: false,
    ton: TonIssue.erreur,
    message: AppStrings.echangeEnvoiRefuse(
      causeEchange(r.code, qui: r.qui, nomPair: cible?.nom ?? ''),
    ),
    detail: AppStrings.echangeEnvoiRefuseAide,
  );
}

/// La réponse de `respond_exchange`, lue par B.
IssueEchange issueReponse(
  ResultatEchange r,
  Echange echange, {
  required bool accepte,
}) {
  if (r.ok) {
    return switch (r.statut) {
      StatutEchange.valide => IssueEchange(
        ok: true,
        ton: TonIssue.succes,
        message: AppStrings.echangeAccordValide(creneauPhrase(echange.garde)),
        valideMaintenant: true,
        retiree: true,
      ),
      StatutEchange.refuse => IssueEchange(
        ok: true,
        ton: TonIssue.succes,
        message: AppStrings.echangeRefusEnvoye(_nom(echange.demandeurNom)),
        retiree: true,
      ),
      _ => const IssueEchange(
        ok: true,
        ton: TonIssue.succes,
        message: AppStrings.echangeAccordEnvoye,
        retiree: true,
      ),
    };
  }

  // **Les courses** : la demande n'est plus ouverte. Une nouvelle, jamais une
  // faute — bannière d'information, la carte quitte la liste.
  IssueEchange disparue(String message) => IssueEchange(
    ok: false,
    ton: TonIssue.information,
    message: message,
    retiree: true,
  );

  IssueEchange regle(String message) =>
      IssueEchange(ok: false, ton: TonIssue.erreur, message: message);

  switch (r.code) {
    case 'exchange_not_open':
      return switch (r.statut) {
        StatutEchange.annule => disparue(
          AppStrings.echangeAnnuleeParA(_nom(echange.demandeurNom)),
        ),
        StatutEchange.expire => disparue(AppStrings.echangeExpiree),
        StatutEchange.accepteParPair || StatutEchange.valide
            when echange.aLaCaserne =>
          disparue(AppStrings.echangeDejaReprise),
        _ => disparue(AppStrings.echangePlusOuverte),
      };
    case 'exchange_expired':
      return disparue(AppStrings.echangeExpiree);
    case 'exchange_not_found':
    case 'not_target':
      return disparue(AppStrings.echangePlusOuverte);
    case 'already_assigned':
      return regle(AppStrings.echangeTuEsDejaPris);
    case 'shift_quota_reached':
      return regle(AppStrings.echangeTonPlafondAstreintes);
    case 'weekend_quota_reached':
      return regle(AppStrings.echangeTonPlafondWeekends);
    case 'not_available':
      return regle(AppStrings.echangePasDisponible);
    case 'station_suspended':
      return regle(AppStrings.echangeReponseLectureSeule);
    case 'exchange_failed':
      // B lit l'échec à la deuxième personne quand il le concerne.
      final message = switch (r.codeMotif) {
        'peer_already_assigned' => AppStrings.echangeTuEsDejaPris,
        'peer_shift_quota_reached' => AppStrings.echangeTonPlafondAstreintes,
        'peer_weekend_quota_reached' => AppStrings.echangeTonPlafondWeekends,
        final code => AppStrings.echangeDetailEchec(
          causeEchange(code, nomDemandeur: echange.demandeurNom),
        ),
      };
      return IssueEchange(
        ok: false,
        ton: TonIssue.erreur,
        message: message,
        retiree: true,
      );
    default:
      return regle(AppStrings.echangeReponseEchec);
  }
}

/// La réponse de `cancel_exchange`.
IssueEchange issueAnnulation(ResultatEchange r) {
  if (r.ok) {
    return const IssueEchange(
      ok: true,
      ton: TonIssue.succes,
      message: AppStrings.echangeAnnulee,
    );
  }
  if (r.code == 'exchange_not_open' && r.statut == StatutEchange.valide) {
    return const IssueEchange(
      ok: false,
      ton: TonIssue.erreur,
      message: AppStrings.echangeAnnulerTropTard,
    );
  }
  return const IssueEchange(
    ok: false,
    ton: TonIssue.information,
    message: AppStrings.echangePlusOuverte,
  );
}

/// La réponse de `decide_exchange`, lue par l'administrateur.
IssueEchange issueDecision(
  ResultatEchange r,
  Echange echange, {
  required bool valide,
}) {
  final a = _nom(echange.demandeurNom);
  final b = _nom(echange.pairNom);
  if (r.ok) {
    return r.statut == StatutEchange.valide
        ? IssueEchange(
            ok: true,
            ton: TonIssue.succes,
            message: AppStrings.echangesValide(a, b),
            valideMaintenant: true,
          )
        : IssueEchange(
            ok: true,
            ton: TonIssue.succes,
            message: AppStrings.echangesRefuse(a, b),
          );
  }
  return switch (r.code) {
    'cannot_decide_own_exchange' => const IssueEchange(
      ok: false,
      ton: TonIssue.erreur,
      message: AppStrings.echangesPasSaDecision,
    ),
    'exchange_not_pending' || 'exchange_not_found' => const IssueEchange(
      ok: false,
      ton: TonIssue.information,
      message: AppStrings.echangesPlusEnAttente,
    ),
    'exchange_expired' => const IssueEchange(
      ok: false,
      ton: TonIssue.information,
      message: AppStrings.echangeExpiree,
    ),
    'exchange_failed' => IssueEchange(
      ok: false,
      ton: TonIssue.erreur,
      message: AppStrings.echangesEchec(
        causeEchange(
          r.codeMotif,
          nomDemandeur: a,
          nomPair: b,
          pourAdmin: true,
          detail: r.detail,
        ),
      ),
    ),
    'not_admin' => const IssueEchange(
      ok: false,
      ton: TonIssue.erreur,
      message: AppStrings.echangesReserveAdmin,
    ),
    _ => const IssueEchange(
      ok: false,
      ton: TonIssue.erreur,
      message: AppStrings.echangesDecisionEchec,
    ),
  };
}

String _nom(String nom) =>
    nom.trim().isEmpty ? AppStrings.echangeMembreInconnu : nom.trim();
