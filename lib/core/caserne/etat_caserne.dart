import 'package:flutter/foundation.dart';

/// `subscription_status` (`docs/SCHEMA.md § 1`).
///
/// Vit dans `core` et non dans la fonctionnalité « Abonnement » depuis le
/// ticket 030 : **tous** les écrans qui écrivent en dépendent, et un écran de
/// saisie de disponibilités n'a pas à importer l'écran de paiement pour savoir
/// s'il a le droit d'enregistrer. `features/abonnement` la ré-exporte.
enum StatutAbonnement {
  essai('trialing'),
  actif('active'),
  retardPaiement('past_due'),
  suspendu('suspended'),
  resilie('cancelled');

  const StatutAbonnement(this.valeurSql);

  final String valeurSql;

  /// Un statut inconnu est lu comme un **essai**, jamais comme une suspension :
  /// une valeur qu'on ne comprend pas ne doit pas mettre une caserne en
  /// lecture seule à l'écran. La base, elle, a déjà tranché de son côté
  /// (`station_writable`, migration `0007`).
  static StatutAbonnement depuisSql(String? valeur) => values.firstWhere(
    (statut) => statut.valeurSql == valeur,
    orElse: () => StatutAbonnement.essai,
  );

  /// Vrai quand la caserne est en lecture seule.
  bool get lectureSeule =>
      this == StatutAbonnement.suspendu || this == StatutAbonnement.resilie;
}

/// Ce que `station_access(uuid)` rend à **tout membre actif** de la caserne
/// (migration `0024`) : le droit d'écrire, et les deux dates qui l'expliquent.
///
/// Rien du prestataire de paiement n'en sort — ni client, ni formule, ni
/// montant. Ce n'est pas l'écran d'abonnement (ticket 029), c'est le drapeau
/// qui pilote les autres écrans.
@immutable
class EtatCaserne {
  const EtatCaserne({
    required this.statut,
    required this.ecriture,
    this.finEssai,
    this.suspendueLe,
  });

  /// **L'état supposé quand on ne sait pas.**
  ///
  /// Réseau coupé, fonction absente, réponse illisible : la caserne est réputée
  /// ouverte. Un faux bandeau de lecture seule bloquerait une caserne qui paie ;
  /// un bandeau manquant ne coûte qu'un refus serveur — celui d'avant ce
  /// ticket. L'asymétrie décide, comme pour [StatutAbonnement.depuisSql].
  static const EtatCaserne inconnue = EtatCaserne(
    statut: StatutAbonnement.essai,
    ecriture: true,
  );

  factory EtatCaserne.depuisJson(Map<String, dynamic> json) => EtatCaserne(
    statut: StatutAbonnement.depuisSql(json['status'] as String?),
    // `writable` fait autorité : il vient de `station_writable()`, la seule
    // définition du droit d'écrire. Absent, on relit le statut plutôt que de
    // supposer un refus.
    ecriture:
        (json['writable'] as bool?) ??
        !StatutAbonnement.depuisSql(json['status'] as String?).lectureSeule,
    finEssai: _instant(json['trial_ends_at']),
    suspendueLe: _instant(json['suspended_at']),
  );

  static DateTime? _instant(Object? valeur) =>
      valeur is String ? DateTime.tryParse(valeur)?.toLocal() : null;

  final StatutAbonnement statut;

  /// Le verdict de `station_writable()`, tel quel.
  final bool ecriture;

  /// Fin de la période d'essai de 60 jours (migration `0023`).
  final DateTime? finEssai;

  /// Date du passage en lecture seule. Effacée par un retour en `active`.
  final DateTime? suspendueLe;

  /// Vrai quand la caserne ne peut plus rien écrire.
  bool get lectureSeule => !ecriture;

  /// Vrai quand l'essai est terminé mais que la tâche de suspension n'a pas
  /// encore tourné : elle passe une fois par jour, et cette fenêtre existe.
  bool essaiExpire({DateTime? maintenant}) {
    final fin = finEssai;
    if (statut != StatutAbonnement.essai || fin == null) return false;
    return fin.isBefore(maintenant ?? DateTime.now());
  }

  /// Jours restants d'essai, arrondis au jour supérieur, ou `null` hors essai.
  int? joursEssaiRestants({DateTime? maintenant}) {
    final fin = finEssai;
    if (statut != StatutAbonnement.essai || fin == null) return null;
    final reste = fin.difference(maintenant ?? DateTime.now());
    return reste.isNegative
        ? 0
        : reste.inHours ~/ 24 + (reste.inHours % 24 > 0 ? 1 : 0);
  }

  @override
  bool operator ==(Object other) =>
      other is EtatCaserne &&
      other.statut == statut &&
      other.ecriture == ecriture &&
      other.finEssai == finEssai &&
      other.suspendueLe == suspendueLe;

  @override
  int get hashCode => Object.hash(statut, ecriture, finEssai, suspendueLe);

  @override
  String toString() =>
      'EtatCaserne(${statut.name}, écriture: $ecriture, essai: $finEssai)';
}
