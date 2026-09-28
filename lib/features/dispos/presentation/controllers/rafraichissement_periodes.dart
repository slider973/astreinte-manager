import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/dispos_providers.dart';
import 'saisie_controller.dart';

/// **Quand relire les périodes de la caserne** (ticket 068).
///
/// Un mois ouvert par l'admin pendant que la PWA tournait n'apparaissait
/// qu'après l'avoir fermée et rouverte : la liste des périodes était lue une
/// fois, au démarrage, et plus jamais. Trois moments la relisent désormais,
/// sur le Calendrier comme sur l'accueil :
///
/// - le **retour au premier plan** — sur le web, Flutter remonte
///   `visibilitychange` vers `visible` et le retour du focus en
///   `AppLifecycleState.resumed` ;
/// - l'**ouverture de l'écran** ;
/// - le **tirer pour actualiser**.
///
/// Trois règles, parce que ces moments arrivent en grappe — sur un
/// ordinateur, chaque clic qui rend le focus à la fenêtre est un `resumed` :
///
/// 1. **Pas de rafale** : les deux premiers moments ne relisent pas si la
///    dernière lecture aboutie date de moins de [intervalleMinimal]. Le tirer,
///    lui, est un geste délibéré : il relit toujours, mais jamais deux fois en
///    même temps.
/// 2. **Rien sous une écriture** : une nouvelle liste reconstruit la saisie,
///    et la reconstruire pendant qu'un envoi est en vol, ou sous un doigt qui
///    peint, mélangerait l'état du serveur et celui de la file, ou remettrait
///    le pinceau à zéro au milieu du trait. La condition est vérifiée **deux
///    fois** : avant de partir, et après la lecture réseau, juste avant de
///    publier — un geste a pu commencer pendant l'attente. Dans les deux cas
///    la relecture est **différée** au retour au repos de la saisie (file
///    vide, aucun envoi en vol, aucun doigt posé), jamais perdue.
/// 3. **Aucune saisie perdue** : le tirer vide d'abord la file ; s'il n'y
///    parvient pas — hors ligne —, il ne relit pas, et la file reste gardée.
class RafraichissementPeriodes {
  RafraichissementPeriodes(this._ref);

  /// L'écart minimal entre deux relectures automatiques.
  static const Duration intervalleMinimal = Duration(seconds: 10);

  final Ref _ref;

  Future<void>? _enCours;

  /// Une relecture a été refusée ou retenue parce qu'une écriture était en
  /// attente : elle partira dès que la saisie reviendra au repos.
  bool _differee = false;

  /// La relecture différée venait d'un tirer : elle relira aussi le mois
  /// affiché.
  bool _differeeAvecMois = false;

  /// Vrai si une relecture attend la fin d'une écriture. Exposé aux tests.
  bool get differee => _differee;

  /// Retour au premier plan, ouverture d'un écran : relit si la liste a
  /// vieilli, sinon ne fait rien.
  Future<void> auRetour() {
    final enCours = _enCours;
    if (enCours != null) return enCours;

    // La première lecture est déjà partie : rien à ajouter.
    if (_ref.read(periodesProvider).isLoading) return Future<void>.value();

    if (_ecritureEnAttente) {
      _differer(avecMois: false);
      return Future<void>.value();
    }

    final derniere = _ref.read(periodesProvider.notifier).derniereLecture;
    final maintenant = _ref.read(horlogeRafraichissementProvider)();
    if (derniere != null &&
        maintenant.difference(derniere) < intervalleMinimal) {
      return Future<void>.value();
    }

    return _lancer(_relirePeriodes);
  }

  /// Tirer pour actualiser : relit les périodes **et** le mois affiché.
  Future<void> tirer() async {
    final enCours = _enCours;
    if (enCours != null) return enCours;

    final saisie = _ref.read(saisieControllerProvider.notifier);
    if (saisie.ecritureEnAttente) {
      final partie = await saisie.viderMaintenant();
      if (!partie || saisie.ecritureEnAttente) {
        _differer(avecMois: true);
        return;
      }
    }

    return _lancer(_relireTout);
  }

  /// Relit la liste des périodes, et ne la publie que si la saisie est au
  /// repos **au retour du réseau**.
  Future<void> _relirePeriodes() async {
    final issue = await _ref
        .read(periodesProvider.notifier)
        .relire(publierSi: () => !_ecritureEnAttente);
    if (issue == Relecture.retenue) _differer(avecMois: false);
  }

  /// Relit la liste des périodes puis le mois affiché, sans jamais
  /// reconstruire la saisie sous une écriture apparue pendant la lecture.
  Future<void> _relireTout() async {
    final issue = await _ref
        .read(periodesProvider.notifier)
        .relire(publierSi: () => !_ecritureEnAttente);
    switch (issue) {
      case Relecture.retenue:
        _differer(avecMois: true);
        return;
      case Relecture.inchangee:
        // Une liste inchangée ne reconstruit rien ; c'est le mois lui-même
        // qu'on vient chercher. Mais pas sous un geste ni une écriture
        // commencés pendant la lecture : ce rechargement-là est différé.
        if (_ecritureEnAttente) {
          _differer(avecMois: true);
          return;
        }
        // La file survit au rechargement : le contrôleur n'est pas recréé,
        // seulement relu.
        _ref.invalidate(saisieControllerProvider);
      case Relecture.publiee:
        // Une liste nouvelle reconstruit déjà la saisie.
        break;
    }
    try {
      await _ref.read(saisieControllerProvider.future);
    } on Object {
      // L'écran dit déjà l'échec de lecture ; l'indicateur doit se retirer.
    }
  }

  void _differer({required bool avecMois}) {
    _differee = true;
    _differeeAvecMois = _differeeAvecMois || avecMois;
  }

  /// La saisie a changé d'état : si elle est revenue au repos, la relecture
  /// différée part maintenant, sans délai minimal — elle était déjà due.
  void _reprendre() {
    if (!_differee || _enCours != null || _ecritureEnAttente) return;
    final avecMois = _differeeAvecMois;
    _differee = false;
    _differeeAvecMois = false;
    unawaited(_lancer(avecMois ? _relireTout : _relirePeriodes));
  }

  bool get _ecritureEnAttente =>
      _ref.read(saisieControllerProvider.notifier).ecritureEnAttente;

  Future<void> _lancer(Future<void> Function() tache) {
    final futur = tache().whenComplete(() {
      _enCours = null;
      // Une relecture différée pendant celle-ci — la saisie étant revenue au
      // repos entre-temps — ne doit pas attendre le prochain changement.
      _reprendre();
    });
    _enCours = futur;
    return futur;
  }
}

/// Le coordinateur des relectures, partagé par le Calendrier et l'accueil :
/// un seul délai minimal pour les deux écrans, et une seule relecture en vol.
final Provider<RafraichissementPeriodes> rafraichissementPeriodesProvider =
    Provider<RafraichissementPeriodes>((ref) {
      final rafraichissement = RafraichissementPeriodes(ref);
      // **Tout** changement d'état de la saisie est une occasion de reprendre,
      // pas seulement celui de la synchronisation : un geste levé sans avoir
      // peint une seule case ne change pas `sync`, et la relecture différée
      // resterait bloquée. `_reprendre` ne fait rien tant que la saisie n'est
      // pas au repos.
      ref.listen<AsyncValue<EtatSaisie?>>(
        saisieControllerProvider,
        (_, _) => rafraichissement._reprendre(),
      );
      return rafraichissement;
    });
