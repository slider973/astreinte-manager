import 'package:astreinte_sp/features/abonnement/data/abonnement_repository.dart';
import 'package:astreinte_sp/features/abonnement/domain/abonnement.dart';

/// L'état d'un projet **sans compte chez le prestataire de paiement** : celui
/// du projet aujourd'hui, et le cas par défaut de tous les tests.
final EtatAbonnement etatSansStripe = EtatAbonnement(
  abonnement: Abonnement(
    statut: StatutAbonnement.essai,
    finEssai: finEssaiSeed,
  ),
  tarifs: TarifsAbonnement.parDefaut,
  configure: false,
  portailDisponible: false,
);

/// Le seed pose un essai de 60 jours. La date est figée pour que
/// « il reste 12 jours » ne dépende pas du jour où le test tourne.
final DateTime maintenantTest = DateTime(2026, 9, 21, 10);
final DateTime finEssaiSeed = DateTime(2026, 11, 20);

/// Un projet configuré, caserne encore en essai.
final EtatAbonnement etatEssaiConfigure = EtatAbonnement(
  abonnement: Abonnement(
    statut: StatutAbonnement.essai,
    finEssai: finEssaiSeed,
  ),
  tarifs: TarifsAbonnement.parDefaut,
  configure: true,
  portailDisponible: false,
);

/// Une caserne abonnée.
final EtatAbonnement etatActif = EtatAbonnement(
  abonnement: Abonnement(
    statut: StatutAbonnement.actif,
    formule: FormuleAbonnement.mensuelle,
    finEssai: finEssaiSeed,
    finPeriode: DateTime(2026, 12, 20),
    possedeClient: true,
  ),
  tarifs: TarifsAbonnement.parDefaut,
  configure: true,
  portailDisponible: true,
);

/// Un paiement en retard : le seul état rouge de l'écran.
final EtatAbonnement etatRetard = EtatAbonnement(
  abonnement: Abonnement(
    statut: StatutAbonnement.retardPaiement,
    formule: FormuleAbonnement.mensuelle,
    finPeriode: DateTime(2026, 11, 20),
    possedeClient: true,
  ),
  tarifs: TarifsAbonnement.parDefaut,
  configure: true,
  portailDisponible: true,
);

/// Une caserne suspendue : gris, jamais rouge, et rien de supprimé.
final EtatAbonnement etatSuspendu = EtatAbonnement(
  abonnement: Abonnement(
    statut: StatutAbonnement.suspendu,
    finPeriode: DateTime(2026, 8, 20),
    possedeClient: true,
  ),
  tarifs: TarifsAbonnement.parDefaut,
  configure: true,
  portailDisponible: true,
);

/// Un essai déjà passé, que la tâche quotidienne n'a pas encore suspendu.
final EtatAbonnement etatEssaiExpire = EtatAbonnement(
  abonnement: Abonnement(
    statut: StatutAbonnement.essai,
    finEssai: DateTime(2026, 9, 15),
  ),
  tarifs: TarifsAbonnement.parDefaut,
  configure: true,
  portailDisponible: false,
);

/// Un [AbonnementRepository] sans réseau : il rend ce qu'on lui a donné et
/// garde la trace de ce qu'on lui a demandé.
class FauxAbonnementRepository implements AbonnementRepository {
  FauxAbonnementRepository({
    EtatAbonnement? etat,
    this.erreurLecture,
    this.erreurAction,
    this.adresse = 'https://checkout.example/session',
  }) : etat = etat ?? etatSansStripe;

  EtatAbonnement etat;

  ErreurAbonnement? erreurLecture;
  ErreurAbonnement? erreurAction;

  /// L'adresse rendue par une ouverture réussie.
  String adresse;

  int lectures = 0;
  final List<FormuleAbonnement> souscriptions = <FormuleAbonnement>[];
  int portails = 0;

  @override
  Future<EtatAbonnement> lire(String stationId) async {
    lectures++;
    final echec = erreurLecture;
    if (echec != null) throw EchecAbonnement(echec);
    return etat;
  }

  @override
  Future<String> ouvrirPaiement({
    required String stationId,
    required FormuleAbonnement formule,
  }) async {
    souscriptions.add(formule);
    final echec = erreurAction;
    if (echec != null) throw EchecAbonnement(echec);
    return adresse;
  }

  @override
  Future<String> ouvrirPortail(String stationId) async {
    portails++;
    final echec = erreurAction;
    if (echec != null) throw EchecAbonnement(echec);
    return adresse;
  }
}

/// Un ouvreur d'onglet qui n'ouvre rien : aucun test ne quitte l'application.
class FauxOuvertureExterne {
  FauxOuvertureExterne({this.autorise = true});

  /// Faux : le navigateur a bloqué la fenêtre.
  bool autorise;

  final List<String> adresses = <String>[];

  bool call(String adresse) {
    adresses.add(adresse);
    return autorise;
  }
}
