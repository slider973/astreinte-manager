import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';

/// `subscription_status` (`docs/SCHEMA.md § 1`).
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

  /// Vrai quand la caserne est en lecture seule. Le bandeau qui le dit est le
  /// ticket 030 ; ici, c'est l'écran d'abonnement qui l'annonce.
  bool get lectureSeule =>
      this == StatutAbonnement.suspendu || this == StatutAbonnement.resilie;
}

/// `subscriptions.plan` (`docs/SCHEMA.md § 2.13`) : `monthly` ou `yearly`.
enum FormuleAbonnement {
  mensuelle('monthly'),
  annuelle('yearly');

  const FormuleAbonnement(this.valeurSql);

  final String valeurSql;

  static FormuleAbonnement? depuisSql(String? valeur) {
    for (final formule in values) {
      if (formule.valeurSql == valeur) return formule;
    }
    return null;
  }
}

/// Les tarifs, tels que le serveur les annonce — en centimes.
///
/// Ils viennent de l'Edge Function et **jamais d'une constante Dart** : le jour
/// où le propriétaire règle un autre prix chez le prestataire, l'écran suit
/// sans recompilation de la PWA. Le serveur les rend même quand aucun compte
/// n'est configuré, avec les valeurs de `docs/PRD.md § 6.6` : un chef de centre
/// en essai a le droit de savoir ce que ça coûtera.
@immutable
class TarifsAbonnement {
  const TarifsAbonnement({
    required this.mensuelCentimes,
    required this.annuelCentimes,
    this.devise = 'eur',
  });

  /// Le repli de `docs/PRD.md § 6.6`, si le serveur ne répond pas.
  static const TarifsAbonnement parDefaut = TarifsAbonnement(
    mensuelCentimes: 1200,
    annuelCentimes: 12000,
  );

  factory TarifsAbonnement.depuisJson(Map<String, dynamic>? json) {
    if (json == null) return parDefaut;
    return TarifsAbonnement(
      mensuelCentimes:
          (json['monthly'] as num?)?.round() ?? parDefaut.mensuelCentimes,
      annuelCentimes:
          (json['yearly'] as num?)?.round() ?? parDefaut.annuelCentimes,
      devise: (json['currency'] as String?) ?? parDefaut.devise,
    );
  }

  final int mensuelCentimes;
  final int annuelCentimes;
  final String devise;

  /// Ce que la formule annuelle fait économiser sur douze mois, en centimes.
  /// Nul ou négatif, la mention disparaît : on n'annonce pas « 0 € offerts ».
  int get economieCentimes => mensuelCentimes * 12 - annuelCentimes;

  int centimes(FormuleAbonnement formule) =>
      formule == FormuleAbonnement.mensuelle ? mensuelCentimes : annuelCentimes;

  @override
  bool operator ==(Object other) =>
      other is TarifsAbonnement &&
      other.mensuelCentimes == mensuelCentimes &&
      other.annuelCentimes == annuelCentimes &&
      other.devise == devise;

  @override
  int get hashCode => Object.hash(mensuelCentimes, annuelCentimes, devise);
}

/// L'abonnement d'une caserne, tel que l'écran l'affiche.
///
/// Reflet exact de `subscriptions` (`docs/SCHEMA.md § 2.13`), moins les
/// identifiants du prestataire — l'application n'en a aucun usage et ils n'ont
/// rien à faire dans un état d'interface. Seul `possedeClient` en reste : c'est
/// lui qui décide si le bouton « Gérer » a une destination.
@immutable
class Abonnement {
  const Abonnement({
    required this.statut,
    this.formule,
    this.finEssai,
    this.finPeriode,
    this.possedeClient = false,
  });

  /// L'état d'une caserne dont la ligne d'abonnement n'existe pas encore.
  /// `station_writable()` la laisse écrire (migration `0007`) : elle est en
  /// essai, et l'écran le dit ainsi plutôt que d'afficher un vide.
  static const Abonnement sansLigne = Abonnement(
    statut: StatutAbonnement.essai,
  );

  factory Abonnement.depuisJson(Map<String, dynamic> json) => Abonnement(
    statut: StatutAbonnement.depuisSql(json['status'] as String?),
    formule: FormuleAbonnement.depuisSql(json['plan'] as String?),
    finEssai: _instant(json['trial_ends_at']),
    finPeriode: _instant(json['current_period_end']),
    possedeClient:
        (json['has_customer'] as bool?) ??
        (json['stripe_customer_id'] as String?) != null,
  );

  static DateTime? _instant(Object? valeur) =>
      valeur is String ? DateTime.tryParse(valeur)?.toLocal() : null;

  final StatutAbonnement statut;
  final FormuleAbonnement? formule;

  /// Fin de la période d'essai de 60 jours, posée par la base à la création de
  /// la caserne (migration `0023`).
  final DateTime? finEssai;

  /// Fin de la période payée. Aussi la date qui fait courir les quatorze jours
  /// d'un paiement en retard.
  final DateTime? finPeriode;

  /// Vrai quand un client existe chez le prestataire : le portail de gestion a
  /// alors une destination.
  final bool possedeClient;

  /// La date qui compte pour cet état : fin d'essai en essai, fin de période
  /// sinon. `null` quand elle manque — l'écran fait alors disparaître la ligne
  /// plutôt que d'écrire « Non définie ».
  DateTime? get dateCle =>
      statut == StatutAbonnement.essai ? finEssai : finPeriode;

  /// Vrai quand l'essai est terminé mais que la tâche de suspension n'a pas
  /// encore tourné : elle passe une fois par jour, et cette fenêtre existe.
  ///
  /// [maintenant] n'existe que pour les tests.
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

  /// La date à laquelle un impayé fera basculer la caserne en lecture seule :
  /// quatorze jours après la fin de la dernière période payée
  /// (`cron_suspend_subscriptions`, migration `0023`).
  DateTime? get bascule => statut == StatutAbonnement.retardPaiement
      ? finPeriode?.add(const Duration(days: 14))
      : null;

  @override
  bool operator ==(Object other) =>
      other is Abonnement &&
      other.statut == statut &&
      other.formule == formule &&
      other.finEssai == finEssai &&
      other.finPeriode == finPeriode &&
      other.possedeClient == possedeClient;

  @override
  int get hashCode =>
      Object.hash(statut, formule, finEssai, finPeriode, possedeClient);
}

/// Ce que l'Edge Function `create-checkout` rend à l'action `state` : l'état de
/// l'abonnement **et** celui de la configuration du prestataire.
///
/// Les deux voyagent ensemble parce que l'écran ne peut rien dire de juste avec
/// l'un sans l'autre : « Période d'essai » n'appelle pas la même page selon que
/// la souscription est ouverte ou non.
@immutable
class EtatAbonnement {
  const EtatAbonnement({
    required this.abonnement,
    required this.tarifs,
    required this.configure,
    required this.portailDisponible,
  });

  /// L'état d'un projet sans compte chez le prestataire — celui d'aujourd'hui.
  static const EtatAbonnement sansConfiguration = EtatAbonnement(
    abonnement: Abonnement.sansLigne,
    tarifs: TarifsAbonnement.parDefaut,
    configure: false,
    portailDisponible: false,
  );

  factory EtatAbonnement.depuisJson(Map<String, dynamic> json) {
    final ligne = json['subscription'];
    return EtatAbonnement(
      abonnement: ligne is Map<String, dynamic>
          ? Abonnement.depuisJson(ligne)
          : Abonnement.sansLigne,
      tarifs: TarifsAbonnement.depuisJson(
        json['prices'] as Map<String, dynamic>?,
      ),
      configure: (json['configured'] as bool?) ?? false,
      portailDisponible: (json['portal_available'] as bool?) ?? false,
    );
  }

  final Abonnement abonnement;
  final TarifsAbonnement tarifs;

  /// Vrai quand le prestataire de paiement est configuré sur ce projet. Faux :
  /// les formules restent affichées, leurs boutons sont inertes et le disent.
  final bool configure;

  /// Vrai quand « Gérer mon abonnement » a une destination.
  final bool portailDisponible;

  /// Vrai quand souscrire est possible : configuré, et pas déjà abonné.
  bool get peutSouscrire =>
      configure && abonnement.statut != StatutAbonnement.actif;

  /// Le bloc des formules disparaît une fois la caserne abonnée : il n'y a plus
  /// rien à souscrire, et le changement de formule se fait dans le portail
  /// (`design/029 § 2`).
  bool get montreFormules => abonnement.statut != StatutAbonnement.actif;

  /// La raison affichée à côté d'un bouton inerte. `DESIGN.md § Buttons` : un
  /// bouton grisé sans explication est un défaut.
  String? get raisonSouscriptionImpossible {
    if (abonnement.statut == StatutAbonnement.actif) {
      return AppStrings.abonnementDejaAbonne;
    }
    return configure ? null : AppStrings.abonnementBientotDisponible;
  }
}
