import 'package:flutter/foundation.dart';

import '../../../core/l10n/format_date.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';

/// Le statut d'une demande d'échange (`shift_exchanges.status`,
/// `docs/WORKFLOWS.md § 3 bis`).
enum StatutEchange {
  ouvert('open'),
  accepteParPair('accepted_by_peer'),
  valide('approved'),
  refuse('rejected'),
  annule('cancelled'),
  expire('expired'),
  echoue('failed');

  const StatutEchange(this.valeurSql);

  final String valeurSql;

  /// Vrai tant que la demande peut encore bouger : ni validée, ni close.
  bool get enCours => this == ouvert || this == accepteParPair;

  bool get terminal => !enCours;

  /// Un statut inconnu — la base a gagné un état avant que la PWA ne soit
  /// redéployée — se lit comme un échec neutre : la demande n'est plus en
  /// cours, et aucun bouton ne s'offre sur elle.
  static StatutEchange depuisSql(String? valeur) {
    for (final statut in values) {
      if (statut.valeurSql == valeur) return statut;
    }
    return echoue;
  }
}

/// La forme d'une demande : cession (`give`) ou échange (`swap`).
enum FormeEchange {
  cession('give'),
  echange('swap');

  const FormeEchange(this.valeurSql);

  final String valeurSql;

  static FormeEchange depuisSql(String? valeur) =>
      valeur == echange.valeurSql ? echange : cession;
}

/// Une garde engagée dans une demande : un créneau, et l'attribution qui le
/// tient.
@immutable
class GardeEchange {
  const GardeEchange({
    required this.jour,
    required this.creneau,
    this.attributionId,
    this.creneauId,
  });

  /// Le jour du créneau, local à minuit.
  final DateTime jour;
  final CreneauType creneau;

  /// `assignment_id` (garde cédée) ou `return_assignment_id` (garde rendue).
  final String? attributionId;

  /// `shift_id` ou `return_shift_id`.
  final String? creneauId;

  /// La clé du mois : `2026-10`.
  String get cleMois => '${jour.year}-${jour.month.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is GardeEchange &&
      other.jour == jour &&
      other.creneau == creneau &&
      other.attributionId == attributionId &&
      other.creneauId == creneauId;

  @override
  int get hashCode => Object.hash(jour, creneau, attributionId, creneauId);
}

/// Qui regarde la demande : c'est ce qui choisit les phrases et les boutons.
enum LecteurEchange {
  /// A, celui qui a demandé.
  demandeur,

  /// B : le collègue désigné, ou celui qui a repris une demande à la caserne.
  pair,

  /// Un disponible à qui une demande « à la caserne » est montrée.
  disponible,

  /// Un administrateur qui n'est ni A ni B.
  admin,
}

/// Une ligne de `shift_exchanges` (`docs/SCHEMA.md § 2.19`), avec les noms
/// déjà résolus.
///
/// **Pas de `toJson()`** : aucune écriture cliente n'existe sur cette table
/// (RLS en lecture seule). Tout passe par les quatre fonctions du § 3, dont
/// les arguments sont construits à la main dans le dépôt.
@immutable
class Echange {
  const Echange({
    required this.id,
    required this.stationId,
    required this.forme,
    required this.statut,
    required this.demandeurId,
    required this.garde,
    required this.expireLe,
    required this.creeLe,
    this.demandeurNom = '',
    this.cibleId,
    this.cibleNom,
    this.gardeRendue,
    this.repreneurId,
    this.repreneurNom,
    this.autoValide = false,
    this.decideurId,
    this.decideurNom,
    this.codeMotif,
    this.motif,
    this.accepteLe,
    this.decideLe,
    this.closLe,
  });

  /// Les colonnes lues. Les deux créneaux sont joints par leur clé
  /// étrangère, nommée pour lever l'ambiguïté (`shift_id`, `return_shift_id`).
  static const String colonnes =
      'id, station_id, kind, status, requester_id, assignment_id, shift_id, '
      'target_id, return_assignment_id, return_shift_id, taker_id, '
      'auto_approved, decided_by, reason_code, reason, expires_at, '
      'accepted_at, decided_at, closed_at, created_at, '
      'garde:shifts!shift_id(date, slot), '
      'rendue:shifts!return_shift_id(date, slot)';

  /// Construit depuis PostgREST. [noms] traduit un identifiant en nom
  /// d'usage de la caserne.
  ///
  /// Rend `null` quand le créneau cédé n'est pas lisible : une demande dont on
  /// ne sait pas dire la date ne peut ni s'afficher ni se répondre.
  static Echange? depuisJson(
    Map<String, dynamic> ligne, {
    Map<String, String> noms = const <String, String>{},
  }) {
    final garde = _garde(
      ligne['garde'],
      attributionId: ligne['assignment_id'] as String?,
      creneauId: ligne['shift_id'] as String?,
    );
    if (garde == null) return null;
    final expire = _instant(ligne['expires_at']);
    final cree = _instant(ligne['created_at']);
    if (expire == null || cree == null) return null;

    String? nom(Object? id) => id is String ? noms[id] : null;

    return Echange(
      id: ligne['id']! as String,
      stationId: ligne['station_id'] as String? ?? '',
      forme: FormeEchange.depuisSql(ligne['kind'] as String?),
      statut: StatutEchange.depuisSql(ligne['status'] as String?),
      demandeurId: ligne['requester_id'] as String? ?? '',
      demandeurNom: nom(ligne['requester_id']) ?? '',
      garde: garde,
      cibleId: ligne['target_id'] as String?,
      cibleNom: nom(ligne['target_id']),
      gardeRendue: _garde(
        ligne['rendue'],
        attributionId: ligne['return_assignment_id'] as String?,
        creneauId: ligne['return_shift_id'] as String?,
      ),
      repreneurId: ligne['taker_id'] as String?,
      repreneurNom: nom(ligne['taker_id']),
      autoValide: ligne['auto_approved'] == true,
      decideurId: ligne['decided_by'] as String?,
      decideurNom: nom(ligne['decided_by']),
      codeMotif: ligne['reason_code'] as String?,
      motif: (ligne['reason'] as String?)?.trim(),
      expireLe: expire,
      creeLe: cree,
      accepteLe: _instant(ligne['accepted_at']),
      decideLe: _instant(ligne['decided_at']),
      closLe: _instant(ligne['closed_at']),
    );
  }

  final String id;
  final String stationId;
  final FormeEchange forme;
  final StatutEchange statut;

  final String demandeurId;
  final String demandeurNom;

  /// La garde cédée par A.
  final GardeEchange garde;

  /// B désigné ; `null` pour une demande « à la caserne ».
  final String? cibleId;
  final String? cibleNom;

  /// La garde de B rendue à A, pour un échange.
  final GardeEchange? gardeRendue;

  /// Celui qui a dit oui.
  final String? repreneurId;
  final String? repreneurNom;

  final bool autoValide;

  /// Qui a tranché : l'administrateur, ou B pour un refus (`peer_declined`).
  final String? decideurId;
  final String? decideurNom;

  /// `reason_code`, liste fermée par statut (`docs/SCHEMA.md § 2.19`).
  final String? codeMotif;

  /// Le motif d'un refus de l'administrateur.
  final String? motif;

  final DateTime expireLe;
  final DateTime creeLe;
  final DateTime? accepteLe;
  final DateTime? decideLe;
  final DateTime? closLe;

  bool get aLaCaserne => cibleId == null;

  bool get estEchange => forme == FormeEchange.echange;

  /// B : le repreneur s'il y en a un, sinon le collègue désigné.
  String? get pairId => repreneurId ?? cibleId;

  String get pairNom => repreneurNom ?? cibleNom ?? '';

  bool get refuseParPair => codeMotif == 'peer_declined';

  /// L'instant qui classe la demande parmi les terminées.
  DateTime get finLe => closLe ?? decideLe ?? accepteLe ?? creeLe;

  /// Ce que [moi] est pour cette demande.
  LecteurEchange lecteur(String moi) {
    if (moi == demandeurId) return LecteurEchange.demandeur;
    if (moi == repreneurId || moi == cibleId) return LecteurEchange.pair;
    if (aLaCaserne && statut == StatutEchange.ouvert) {
      return LecteurEchange.disponible;
    }
    return LecteurEchange.admin;
  }

  /// Vrai quand [moi] doit y répondre : une demande ouverte qui m'est
  /// adressée, ou une demande à la caserne que la base me montre.
  bool aRepondre(String moi) =>
      statut == StatutEchange.ouvert &&
      moi != demandeurId &&
      (cibleId == moi || aLaCaserne);

  /// Vrai quand [moi] suit la demande : je l'ai faite, ou je l'ai acceptée.
  bool suivie(String moi) => moi == demandeurId || moi == repreneurId ||
      (moi == cibleId && statut != StatutEchange.ouvert);

  /// Vrai si le créneau cédé est encore à venir à [aujourdhui]. Une demande
  /// terminée reste dans le suivi tant que sa garde est à venir.
  bool aVenir(DateTime aujourdhui) {
    final minuit = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
    return !garde.jour.isBefore(minuit);
  }

  static GardeEchange? _garde(
    Object? creneau, {
    String? attributionId,
    String? creneauId,
  }) {
    if (creneau is! Map<String, dynamic>) return null;
    final date = creneau['date'];
    final slot = creneau['slot'];
    if (date is! String || slot is! String) return null;
    return GardeEchange(
      jour: depuisIsoJour(date),
      creneau: CreneauSql.depuisSql(slot),
      attributionId: attributionId,
      creneauId: creneauId,
    );
  }

  static DateTime? _instant(Object? valeur) =>
      valeur is String ? DateTime.tryParse(valeur)?.toLocal() : null;

  @override
  bool operator ==(Object other) =>
      other is Echange &&
      other.id == id &&
      other.statut == statut &&
      other.repreneurId == repreneurId &&
      other.decideurId == decideurId &&
      other.codeMotif == codeMotif &&
      other.motif == motif &&
      other.accepteLe == accepteLe &&
      other.decideLe == decideLe &&
      other.closLe == closLe &&
      other.demandeurNom == demandeurNom &&
      other.pairNom == pairNom &&
      other.garde == garde &&
      other.gardeRendue == gardeRendue;

  @override
  int get hashCode => Object.hash(
    id,
    statut,
    repreneurId,
    decideurId,
    codeMotif,
    motif,
    accepteLe,
    decideLe,
    closLe,
    garde,
    gardeRendue,
  );
}

/// Une garde de B que A peut demander en retour (`exchangeable_shifts_of`).
@immutable
class GardeProposable {
  const GardeProposable({
    required this.attributionId,
    required this.creneauId,
    required this.stationId,
    required this.jour,
    required this.creneau,
    this.expireLe,
  });

  static GardeProposable? depuisJson(Map<String, dynamic> ligne) {
    final id = ligne['assignment_id'];
    final creneauId = ligne['shift_id'];
    final date = ligne['date'];
    final slot = ligne['slot'];
    if (id is! String || creneauId is! String) return null;
    if (date is! String || slot is! String) return null;
    final expire = ligne['expires_at'];
    return GardeProposable(
      attributionId: id,
      creneauId: creneauId,
      stationId: ligne['station_id'] as String? ?? '',
      jour: depuisIsoJour(date),
      creneau: CreneauSql.depuisSql(slot),
      expireLe: expire is String ? DateTime.tryParse(expire)?.toLocal() : null,
    );
  }

  final String attributionId;
  final String creneauId;
  final String stationId;
  final DateTime jour;
  final CreneauType creneau;
  final DateTime? expireLe;

  GardeEchange get garde => GardeEchange(
    jour: jour,
    creneau: creneau,
    attributionId: attributionId,
    creneauId: creneauId,
  );

  int comparer(GardeProposable autre) {
    final parJour = jour.compareTo(autre.jour);
    if (parJour != 0) return parJour;
    return creneau.index.compareTo(autre.creneau.index);
  }
}

/// Un membre actif de la caserne, tel que l'étape « À qui ? » le propose.
@immutable
class Collegue {
  const Collegue({required this.userId, required this.nom});

  final String userId;
  final String nom;

  @override
  bool operator ==(Object other) =>
      other is Collegue && other.userId == userId && other.nom == nom;

  @override
  int get hashCode => Object.hash(userId, nom);
}

/// Les réglages d'échange de la caserne, lus dans `stations.settings`
/// (`exchange_auto_approve`, `exchange_deadline_hours`), avec les heures
/// d'affichage qui donnent le début d'un créneau.
@immutable
class ReglagesEchange {
  const ReglagesEchange({
    this.validationAuto = false,
    this.echeanceHeures = 24,
    this.debutJour = '07:00',
    this.finJour = '19:00',
  });

  static const ReglagesEchange defaut = ReglagesEchange();

  final bool validationAuto;
  final int echeanceHeures;
  final String debutJour;
  final String finJour;

  /// Le début d'une garde : `day_start` pour le jour, `day_end` pour la nuit,
  /// en heure locale. C'est la borne de `exchange_shift_start` côté base ;
  /// l'écran ne s'en sert que pour **annoncer** une échéance, jamais pour
  /// décider — la base pose `expires_at` et refuse ce qui est échu.
  DateTime debut(GardeEchange garde) {
    final heure = garde.creneau == CreneauType.jour ? debutJour : finJour;
    final morceaux = heure.split(':');
    final h = int.tryParse(morceaux.first) ?? 0;
    final m = morceaux.length > 1 ? int.tryParse(morceaux[1]) ?? 0 : 0;
    return DateTime(garde.jour.year, garde.jour.month, garde.jour.day, h, m);
  }

  /// L'échéance annoncée d'une demande sur [gardes] : la plus proche.
  DateTime echeance(Iterable<GardeEchange> gardes) {
    DateTime? plusProche;
    for (final garde in gardes) {
      final fin = debut(garde).subtract(Duration(hours: echeanceHeures));
      if (plusProche == null || fin.isBefore(plusProche)) plusProche = fin;
    }
    return plusProche ?? DateTime.now();
  }
}

/// « 07:00 » : l'heure d'une échéance, comme les heures d'un créneau.
String heureMinute(DateTime instant) {
  final locale = instant.toLocal();
  return '${locale.hour.toString().padLeft(2, '0')}:'
      '${locale.minute.toString().padLeft(2, '0')}';
}
