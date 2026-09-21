import 'package:flutter/foundation.dart';

import '../../../core/caserne/etat_caserne.dart';
import '../../../core/l10n/app_strings.dart';

/// `StatutAbonnement` vit dans `core/caserne` depuis le ticket 030 : le bandeau
/// de lecture seule le lit sur tous les écrans qui écrivent, et aucun d'eux n'a
/// à dépendre de l'écran de paiement. Ré-exporté ici pour que les importations
/// de cet écran restent celles de son propre domaine.
export '../../../core/caserne/etat_caserne.dart' show StatutAbonnement;

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
    this.possedeAbonnement = false,
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
    possedeAbonnement:
        (json['has_subscription'] as bool?) ??
        (json['stripe_subscription_id'] as String?) != null,
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

  /// Vrai quand un **abonnement** existe chez le prestataire.
  ///
  /// Distinct de [possedeClient] : `create-checkout` crée le client avant même
  /// d'ouvrir la session de paiement, donc une caserne peut avoir un client
  /// sans avoir jamais rien souscrit.
  final bool possedeAbonnement;

  /// Vrai quand la caserne a un abonnement qui **vit encore** chez le
  /// prestataire, et qu'en souscrire un second la ferait payer deux fois.
  ///
  /// Le statut ne suffit pas, et c'est tout le piège : une caserne dont la
  /// carte a expiré n'est pas `active`, et elle a pourtant déjà tout ce qu'il
  /// faut. Une carte se change dans le portail ; ré-souscrire ne répare rien.
  /// Une résiliation, elle, se reprend — rien ne se dédouble.
  ///
  /// Même règle que `create-checkout/acces.ts`, et le serveur reste l'autorité :
  /// cette propriété ne fait que retirer de l'écran un bouton qu'il refuserait.
  bool get abonnementVivant =>
      possedeAbonnement && statut != StatutAbonnement.resilie;

  /// La date qui compte pour cet état : fin d'essai en essai, fin de période
  /// sinon. `null` quand elle manque — l'écran fait alors disparaître la ligne
  /// plutôt que d'écrire « Non définie ».
  DateTime? get dateCle =>
      statut == StatutAbonnement.essai ? finEssai : finPeriode;

  /// Le même abonnement, vu comme les autres écrans le voient.
  ///
  /// Une seule arithmétique de dates dans le produit : celle de `core`, que le
  /// bandeau d'essai du ticket 030 partage avec cet écran. Deux calculs de
  /// « jours restants » finiraient par se contredire d'un jour.
  EtatCaserne get caserne => EtatCaserne(
    statut: statut,
    ecriture: !statut.lectureSeule,
    finEssai: finEssai,
  );

  /// Vrai quand l'essai est terminé mais que la tâche de suspension n'a pas
  /// encore tourné : elle passe une fois par jour, et cette fenêtre existe.
  ///
  /// [maintenant] n'existe que pour les tests.
  bool essaiExpire({DateTime? maintenant}) =>
      caserne.essaiExpire(maintenant: maintenant);

  /// Jours restants d'essai, arrondis au jour supérieur, ou `null` hors essai.
  int? joursEssaiRestants({DateTime? maintenant}) =>
      caserne.joursEssaiRestants(maintenant: maintenant);

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
      other.possedeClient == possedeClient &&
      other.possedeAbonnement == possedeAbonnement;

  @override
  int get hashCode => Object.hash(
    statut,
    formule,
    finEssai,
    finPeriode,
    possedeClient,
    possedeAbonnement,
  );
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

  /// Vrai quand souscrire est possible : configuré, et sans abonnement vivant.
  bool get peutSouscrire => configure && !abonnement.abonnementVivant;

  /// Le bloc des formules disparaît dès qu'un abonnement vit : il n'y a plus
  /// rien à souscrire, et la carte comme la formule se changent dans le portail
  /// (`design/029 § 2`).
  ///
  /// **Le critère est l'abonnement, pas le statut.** Une caserne en retard de
  /// paiement n'est pas `active` ; lui montrer « S'abonner » l'enverrait vers
  /// un second prélèvement au lieu de la page où elle met sa carte à jour.
  bool get montreFormules => !abonnement.abonnementVivant;

  /// La raison affichée à côté d'un bouton inerte. `DESIGN.md § Buttons` : un
  /// bouton grisé sans explication est un défaut.
  String? get raisonSouscriptionImpossible {
    if (abonnement.abonnementVivant) return AppStrings.abonnementDejaAbonne;
    return configure ? null : AppStrings.abonnementBientotDisponible;
  }
}
