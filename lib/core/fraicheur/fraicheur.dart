import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../features/astreintes/domain/astreintes_providers.dart';
import '../../features/astreintes/domain/planning_caserne_providers.dart';
import '../../features/dispos/domain/dispos_providers.dart';
import '../../features/dispos/presentation/controllers/rafraichissement_periodes.dart';
import '../../features/dispos/presentation/controllers/saisie_controller.dart';
import '../../features/invitation/domain/invitation_providers.dart';
import '../../features/notifications/domain/centre_providers.dart';
import '../../features/planning/domain/matrice_providers.dart';
import '../../features/planning/domain/planning_providers.dart';
import '../../features/planning/domain/suivi_providers.dart';
import '../../features/propositions/domain/propositions_providers.dart';
import '../caserne/caserne_providers.dart';
import '../reseau/connectivite.dart';
import '../session/session_providers.dart';
import '../theme/app_status.dart';

/// Ce qu'un écran affiche, et que le coordinateur sait relire.
enum Donnee {
  /// `memberships` : la caserne courante et le rôle.
  appartenances,

  /// `station_access` : suspension, lecture seule, fin d'essai.
  caserne,

  /// Mes astreintes acceptées (`AstreintesController`).
  astreintes,

  /// Le planning de toute la caserne (`PlanningCaserneController`).
  planningCaserne,

  /// Mes propositions en attente (`PropositionsController`).
  propositions,

  /// Le centre de notifications.
  centre,

  /// La liste des mois de saisie — déléguée au coordinateur du ticket 068.
  periodes,

  /// La matrice des disponibilités de l'admin.
  matrice,

  /// Le planning du mois, côté admin.
  planningAdmin,

  /// Le suivi du planning publié, côté admin.
  suivi,

  /// Les invitations en attente d'un membre déjà rattaché (ticket 072) : la
  /// carte de l'accueil. Rien n'en est gardé sur l'appareil.
  invitations,
}

/// **Un seul endroit décide des relectures** (ticket 070).
///
/// Les onglets de la PWA sont des routes voisines et leurs contrôleurs ne sont
/// pas auto-disposés : un contrôleur ne relit que si quelqu'un le lui demande.
/// Avant ce ticket, chaque écran demandait pour lui-même, et l'accueil ne
/// demandait rien — une astreinte acceptée dans la Boîte n'y apparaissait
/// qu'après un passage par l'onglet Astreintes.
///
/// Le coordinateur reprend la discipline de `RafraichissementPeriodes`
/// (ticket 068), étendue à toutes les données partagées :
///
/// 1. **Quand.** À l'**ouverture** d'un écran ([afficher]), au **retour au
///    premier plan** ([auPremierPlan], branché une fois pour toute
///    l'application par `CoucheFraicheur`), au **retour du réseau**, et sur un
///    **événement** qui annonce une nouveauté ([maintenant] : push reçu,
///    réponse à une proposition, publication).
/// 2. **Pas de rafale.** Une relecture automatique ne part pas si la dernière
///    lecture aboutie de cette donnée a moins de [intervalleMinimal]. Un
///    événement passe outre ce délai, pas le reste.
/// 3. **Jamais deux fois en même temps**, par donnée.
/// 4. **Rien sous une écriture ni sous un geste.** Une relecture qui
///    reconstruirait un écran pendant qu'une écriture est en vol, ou sous un
///    doigt qui peint, est **retenue** ; elle repart dès que l'écriture est
///    retombée, jamais perdue. La condition est vérifiée après la lecture
///    réseau, juste avant de publier — un geste a pu commencer pendant
///    l'attente.
/// 5. **Jamais en vidant l'écran.** Chaque relecture garde la valeur à l'écran
///    et ne la remplace qu'en cas de succès. Une lecture qui échoue garde ce
///    qui est lisible.
///
/// Il ne garde rien sur l'appareil : ses horodatages vivent en mémoire vive,
/// avec la page. La règle des caches de `deconnexion.dart` n'a rien à y
/// oublier.
class Fraicheur {
  Fraicheur(this._ref);

  /// Le même délai que les périodes : un seul rythme pour toute l'application.
  static const Duration intervalleMinimal =
      RafraichissementPeriodes.intervalleMinimal;

  /// Ce que le retour au premier plan relit **quel que soit l'écran** : la
  /// caserne et le rôle décident de tous les autres.
  static const Set<Donnee> globales = <Donnee>{
    Donnee.appartenances,
    Donnee.caserne,
  };

  final Ref _ref;

  final Map<Donnee, DateTime> _dernieres = <Donnee, DateTime>{};
  final Map<Donnee, Future<void>> _enCours = <Donnee, Future<void>>{};

  /// Les relectures retenues sous une écriture, et l'abonnement qui les
  /// relancera.
  final Map<Donnee, List<ProviderSubscription<Object?>>> _retenues =
      <Donnee, List<ProviderSubscription<Object?>>>{};

  /// Les écrans montés, et ce que chacun affiche.
  final Map<Object, Set<Donnee>> _ecrans = <Object, Set<Donnee>>{};

  /// Vrai si une relecture de [donnee] attend la fin d'une écriture. Exposé
  /// aux tests.
  @visibleForTesting
  bool retenue(Donnee donnee) => _retenues.containsKey(donnee);

  /// Les données affichées par les écrans montés. Exposé aux tests.
  @visibleForTesting
  Set<Donnee> get affichees => <Donnee>{
    for (final donnees in _ecrans.values) ...donnees,
  };

  // -------------------------------------------------------------------
  // Les moments
  // -------------------------------------------------------------------

  /// Un écran s'ouvre, ou change ce qu'il affiche : ses données sont relues
  /// si elles ont vieilli, puis à chaque retour au premier plan tant qu'il
  /// reste monté.
  Future<void> afficher(Object ecran, Set<Donnee> donnees) {
    _ecrans[ecran] = donnees;
    return auRetour(donnees);
  }

  /// L'écran est démonté : ses données ne sont plus relues pour lui.
  void retirer(Object ecran) => _ecrans.remove(ecran);

  /// Retour au premier plan : la caserne, le rôle, et ce qu'affichent les
  /// écrans montés.
  Future<void> auPremierPlan() => auRetour(<Donnee>{...globales, ...affichees});

  /// Relit ce qui a vieilli parmi [donnees].
  Future<void> auRetour(Set<Donnee> donnees) => _tout(donnees, forcer: false);

  /// Relit [donnees] **tout de suite**, délai minimal ou pas : un événement
  /// vient d'annoncer une nouveauté.
  Future<void> maintenant(Set<Donnee> donnees) => _tout(donnees, forcer: true);

  Future<void> _tout(Set<Donnee> donnees, {required bool forcer}) async {
    await Future.wait(<Future<void>>[
      for (final donnee in donnees) _relire(donnee, forcer: forcer),
    ]);
  }

  // -------------------------------------------------------------------
  // Une donnée
  // -------------------------------------------------------------------

  Future<void> _relire(Donnee donnee, {required bool forcer}) {
    // Les périodes ont leur coordinateur depuis le ticket 068, et ses tests :
    // on lui délègue, il applique la même discipline.
    if (donnee == Donnee.periodes) {
      return _ref
          .read(rafraichissementPeriodesProvider)
          .auRetour(forcer: forcer);
    }

    final enCours = _enCours[donnee];
    if (enCours != null) return enCours;
    if (!forcer && _recente(donnee)) return Future<void>.value();

    // Surtout pas `() => _enCours.remove(donnee)` : `remove` rend le futur
    // retiré, et `whenComplete` attendrait alors ce futur — lui-même. Le
    // premier test unitaire du coordinateur s'y est bloqué.
    final futur = _lire(donnee).whenComplete(
      () => _enCours.removeWhere((Donnee cle, _) => cle == donnee),
    );
    _enCours[donnee] = futur;
    return futur;
  }

  bool _recente(Donnee donnee) {
    final candidates = <DateTime?>[_dernieres[donnee], _lectureDe(donnee)];
    DateTime? derniere;
    for (final instant in candidates) {
      if (instant != null && (derniere == null || instant.isAfter(derniere))) {
        derniere = instant;
      }
    }
    if (derniere == null) return false;
    return _maintenant().difference(derniere) < intervalleMinimal;
  }

  /// La dernière lecture réseau que le contrôleur a faite **de lui-même** —
  /// sa première lecture, surtout : un contrôleur qui vient de naître vient
  /// de lire, et le coordinateur n'a pas à redemander.
  DateTime? _lectureDe(Donnee donnee) => switch (donnee) {
    Donnee.astreintes when _ref.exists(astreintesControllerProvider) =>
      _ref.read(astreintesControllerProvider.notifier).derniereLecture,
    Donnee.propositions when _ref.exists(propositionsControllerProvider) =>
      _ref.read(propositionsControllerProvider.notifier).derniereLecture,
    Donnee.matrice when _ref.exists(matriceControllerProvider) =>
      _ref.read(matriceControllerProvider.notifier).derniereLecture,
    Donnee.planningAdmin when _ref.exists(planningControllerProvider) =>
      _ref.read(planningControllerProvider.notifier).derniereLecture,
    Donnee.suivi when _ref.exists(suiviControllerProvider) =>
      _ref.read(suiviControllerProvider.notifier).derniereLecture,
    _ => null,
  };

  DateTime _maintenant() => _ref.read(horlogeRafraichissementProvider)();

  Future<void> _lire(Donnee donnee) async {
    final Relecture issue;
    try {
      issue = await _source(donnee);
    } on Object {
      // Une relecture n'a pas le droit de faire tomber l'application : l'écran
      // garde ce qu'il sait, et le prochain moment réessaiera.
      return;
    }
    switch (issue) {
      case Relecture.publiee:
      case Relecture.inchangee:
        _dernieres[donnee] = _maintenant();
      case Relecture.retenue:
        _retenir(donnee);
      case Relecture.echouee:
        // Pas d'horodatage : le prochain retour réessaie sans attendre.
        break;
    }
  }

  /// Lit une donnée et dit ce qu'il en est advenu.
  Future<Relecture> _source(Donnee donnee) async {
    switch (donnee) {
      case Donnee.appartenances:
        return relireAppartenances(_ref, publierSi: _auRepos);

      case Donnee.caserne:
        return _ref
            .read(etatCaserneProvider.notifier)
            .relire(publierSi: _auRepos);

      case Donnee.astreintes:
        final premiere = await _premiereLecture(astreintesControllerProvider);
        if (premiere == null) return Relecture.echouee;
        // La première lecture vient d'aboutir **au réseau** : la relire serait
        // une seconde requête pour rien. Mais si elle vient du cache — c'est
        // tout l'objet de `build` —, c'est maintenant qu'on va chercher mieux.
        if (premiere &&
            !(_ref.read(astreintesControllerProvider).value?.depuisCache ??
                true)) {
          return Relecture.inchangee;
        }
        await _ref.read(astreintesControllerProvider.notifier).rafraichir();
        final apres = _ref.read(astreintesControllerProvider);
        // Un échec sur un écran déjà lisible garde l'écran et pose un
        // bandeau : ce n'est pas une lecture aboutie.
        if (apres.value?.echec != null) return Relecture.echouee;
        return _issue(apres);

      case Donnee.planningCaserne:
        // Son `build` ne lit **que** le cache (`design/027 § 3`) : la première
        // lecture réseau, c'est celle-ci.
        if (await _premiereLecture(planningCaserneControllerProvider) == null) {
          return Relecture.echouee;
        }
        await _ref
            .read(planningCaserneControllerProvider.notifier)
            .rafraichir();
        return _issue(_ref.read(planningCaserneControllerProvider));

      case Donnee.propositions:
        switch (await _premiereLecture(propositionsControllerProvider)) {
          case null:
            return Relecture.echouee;
          case true:
            return Relecture.inchangee;
          case false:
            break;
        }
        return _ref
            .read(propositionsControllerProvider.notifier)
            .rafraichir(publierSi: () => !_propositionsOccupees);

      case Donnee.centre:
        switch (await _premiereLecture(centreNotificationsProvider)) {
          case null:
            return Relecture.echouee;
          case true:
            return Relecture.inchangee;
          case false:
            break;
        }
        await _ref.read(centreNotificationsProvider.notifier).rafraichir();
        return _issue(_ref.read(centreNotificationsProvider));

      case Donnee.matrice:
        // Auto-disposée : sans écran pour la regarder, elle n'existe pas, et
        // la lire ici la ferait naître pour rien.
        if (!_ref.exists(matriceControllerProvider)) return Relecture.inchangee;
        if (_ref.read(matriceControllerProvider).isLoading) {
          return Relecture.inchangee;
        }
        if (_matriceOccupee) return Relecture.retenue;
        return _ref.read(matriceControllerProvider.notifier).rafraichir();

      case Donnee.planningAdmin:
        if (!_ref.exists(planningControllerProvider)) {
          return Relecture.inchangee;
        }
        final etat = _ref.read(planningControllerProvider);
        if (etat.isLoading) return Relecture.inchangee;
        if (etat.value?.sync == SyncEtat.enregistrement) {
          return Relecture.retenue;
        }
        await _ref.read(planningControllerProvider.notifier).rafraichir();
        return _issue(_ref.read(planningControllerProvider));

      case Donnee.suivi:
        if (!_ref.exists(suiviControllerProvider)) return Relecture.inchangee;
        final etat = _ref.read(suiviControllerProvider);
        if (etat.isLoading) return Relecture.inchangee;
        if (etat.value?.sync == SyncEtat.enregistrement) {
          return Relecture.retenue;
        }
        await _ref.read(suiviControllerProvider.notifier).rafraichir();
        return _issue(_ref.read(suiviControllerProvider));

      case Donnee.periodes:
        // Délégué plus haut, dans `_relire`.
        return Relecture.inchangee;

      case Donnee.invitations:
        // Auto-disposée, et source secondaire : sans écran qui la montre, on
        // ne la fait pas naître ; en vie, on la relit sans vider la carte.
        if (!_ref.exists(invitationsRecuesProvider)) {
          return Relecture.inchangee;
        }
        _ref.invalidate(invitationsRecuesProvider);
        return Relecture.publiee;
    }
  }

  /// Le plus longtemps qu'on attend une première lecture encore en vol.
  ///
  /// Sans borne, une première lecture qui ne répond jamais — le trou noir du
  /// réseau rural — garderait la relecture de cette donnée « en cours » pour
  /// toujours : tous les moments suivants recevraient ce même futur, et la
  /// donnée ne serait plus jamais relue.
  static const Duration attenteMaximalePremiereLecture = Duration(seconds: 15);

  /// L'attente effective, raccourcie par les tests qui éprouvent la borne.
  @visibleForTesting
  Duration attentePremiereLecture = attenteMaximalePremiereLecture;

  /// Les premières lectures qui n'ont pas répondu à temps : le moment
  /// suivant ne les attend plus, il relit par-dessus.
  final Set<Object> _premieresAbandonnees = <Object>{};

  /// Si la première lecture de [provider] est encore en vol, l'attend et rend
  /// vrai : elle vient de lire, il n'y a rien à redemander. Faux si elle
  /// était déjà finie. `null` si elle n'a pas répondu dans
  /// [attenteMaximalePremiereLecture] : la relecture n'a pas abouti, et le
  /// prochain moment réessaiera.
  Future<bool?> _premiereLecture(
    ProviderListenable<AsyncValue<Object?>> provider,
  ) async {
    // Une première lecture **en échec** a répondu, même si Riverpod la
    // retente en tâche de fond (l'état reste alors « en chargement » avec son
    // erreur) : c'est la relecture qui va réessayer, tout de suite.
    bool enVol(AsyncValue<Object?> etat) =>
        etat.isLoading && !etat.hasValue && !etat.hasError;
    if (!enVol(_ref.read(provider))) return false;
    // Déjà attendue en vain une fois : on ne l'attend plus, on relit.
    if (_premieresAbandonnees.contains(provider)) return false;
    final attente = Completer<bool>();
    final abonnement = _ref.listen<AsyncValue<Object?>>(provider, (_, suivant) {
      if (!enVol(suivant) && !attente.isCompleted) attente.complete(true);
    });
    try {
      if (!enVol(_ref.read(provider))) return true;
      final repondu = await attente.future.timeout(
        attentePremiereLecture,
        onTimeout: () => false,
      );
      if (repondu) return true;
      _premieresAbandonnees.add(provider);
      return null;
    } finally {
      abonnement.close();
    }
  }

  /// Une relecture qui a laissé une erreur sans valeur, ou un message
  /// d'échec, n'a pas abouti.
  static Relecture _issue(AsyncValue<Object?> etat) =>
      etat.hasError && !etat.hasValue ? Relecture.echouee : Relecture.publiee;

  // -------------------------------------------------------------------
  // Les écritures en attente
  // -------------------------------------------------------------------

  /// Vrai quand rien ne s'écrit et qu'aucun doigt ne peint : c'est la
  /// condition pour publier ce qui reconstruit **tout** — la caserne et le
  /// rôle sont lus par la saisie, la matrice, les propositions et le suivi.
  bool _auRepos() =>
      !_saisieOccupee && !_matriceOccupee && !_propositionsOccupees;

  bool get _saisieOccupee =>
      _ref.exists(saisieControllerProvider) &&
      _ref.read(saisieControllerProvider.notifier).ecritureEnAttente;

  bool get _matriceOccupee =>
      _ref.exists(matriceControllerProvider) &&
      _ref.read(matriceControllerProvider).value?.sync ==
          SyncEtat.enregistrement;

  bool get _propositionsOccupees =>
      _ref.exists(propositionsControllerProvider) &&
      _ref.read(propositionsControllerProvider.notifier).ecritureEnAttente;

  /// Ce qu'il faut écouter pour savoir quand [donnee] peut repartir.
  ///
  /// La caserne et le rôle attendent le repos de **tout** ce qui écrit — la
  /// saisie, la matrice, les réponses aux propositions —, et seulement de ce
  /// qui existe : écouter la saisie d'un admin qui n'a jamais ouvert son mois
  /// la ferait naître, avec ses lectures, pour rien. Ce qui n'existe pas
  /// n'écrit pas.
  List<ProviderListenable<Object?>> _repos(Donnee donnee) => switch (donnee) {
    Donnee.propositions => <ProviderListenable<Object?>>[
      propositionsControllerProvider,
    ],
    Donnee.matrice => <ProviderListenable<Object?>>[matriceControllerProvider],
    Donnee.planningAdmin => <ProviderListenable<Object?>>[
      planningControllerProvider,
    ],
    Donnee.suivi => <ProviderListenable<Object?>>[suiviControllerProvider],
    _ => <ProviderListenable<Object?>>[
      if (_ref.exists(saisieControllerProvider)) saisieControllerProvider,
      if (_ref.exists(matriceControllerProvider)) matriceControllerProvider,
      if (_ref.exists(propositionsControllerProvider))
        propositionsControllerProvider,
    ],
  };

  bool _occupee(Donnee donnee) => switch (donnee) {
    Donnee.propositions => _propositionsOccupees,
    Donnee.matrice => _matriceOccupee,
    Donnee.planningAdmin =>
      _ref.exists(planningControllerProvider) &&
          _ref.read(planningControllerProvider).value?.sync ==
              SyncEtat.enregistrement,
    Donnee.suivi =>
      _ref.exists(suiviControllerProvider) &&
          _ref.read(suiviControllerProvider).value?.sync ==
              SyncEtat.enregistrement,
    _ => !_auRepos(),
  };

  /// Retient une relecture jusqu'au retour au repos de ce qui l'a bloquée.
  void _retenir(Donnee donnee) {
    if (_retenues.containsKey(donnee)) return;
    _retenues[donnee] = <ProviderSubscription<Object?>>[
      for (final source in _repos(donnee))
        _ref.listen<Object?>(source, (_, _) => _reprendre()),
    ];
    // Rien n'a peut-être changé entre-temps, et l'écriture est déjà
    // retombée : on ne l'attend pas une seconde fois.
    scheduleMicrotask(_reprendre);
  }

  /// Relance les relectures retenues dont l'écriture est retombée, **sans
  /// délai minimal** : elles étaient déjà dues.
  void _reprendre() {
    for (final donnee in _retenues.keys.toList()) {
      if (_occupee(donnee) || _enCours.containsKey(donnee)) continue;
      for (final abonnement
          in _retenues.remove(donnee) ??
              const <ProviderSubscription<Object?>>[]) {
        abonnement.close();
      }
      unawaited(_relire(donnee, forcer: true));
    }
  }
}

/// Le coordinateur des relectures, un pour toute l'application.
final Provider<Fraicheur> fraicheurProvider = Provider<Fraicheur>((ref) {
  final fraicheur = Fraicheur(ref);

  // **Le retour du réseau** est un retour au premier plan pour la caserne et
  // le rôle : un démarrage hors ligne a laissé un chef de centre en simple
  // membre, et c'est le moment de le lui rendre.
  ref.listen<AsyncValue<bool>>(enLigneProvider, (avant, apres) {
    if (avant?.value == false && apres.value == true) {
      unawaited(fraicheur.maintenant(Fraicheur.globales));
    }
  });

  // **Une réponse à une proposition change mes astreintes** : l'accueil ne
  // compte que les acceptées, et le jour accepté y restait « libre »
  // (ticket 070). Le planning de la caserne aussi, s'il vient de se valider.
  ref.listen<NouvellePropositions?>(
    propositionsControllerProvider.select(
      (AsyncValue<EtatPropositions> etat) => etat.value?.nouvelle,
    ),
    (_, nouvelle) {
      if (nouvelle is ReponseEnvoyee || nouvelle is PlanningValide) {
        unawaited(
          fraicheur.maintenant(<Donnee>{
            Donnee.astreintes,
            if (nouvelle is PlanningValide) Donnee.planningCaserne,
          }),
        );
      }
      // La réponse vient de retomber : une relecture retenue peut repartir.
      fraicheur._reprendre();
    },
  );

  ref.onDispose(() {
    for (final abonnements in fraicheur._retenues.values) {
      for (final abonnement in abonnements) {
        abonnement.close();
      }
    }
    fraicheur._retenues.clear();
  });
  return fraicheur;
});
