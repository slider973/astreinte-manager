import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_status.dart';
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
///    et la reconstruire pendant qu'un envoi est en vol mélangerait l'état du
///    serveur et celui de la file. La relecture est alors **différée** au
///    retour au calme de la file, jamais perdue.
/// 3. **Aucune saisie perdue** : le tirer vide d'abord la file ; s'il n'y
///    parvient pas — hors ligne —, il ne relit pas, et la file reste gardée.
class RafraichissementPeriodes {
  RafraichissementPeriodes(this._ref);

  /// L'écart minimal entre deux relectures automatiques.
  static const Duration intervalleMinimal = Duration(seconds: 10);

  final Ref _ref;

  Future<void>? _enCours;

  /// Une relecture a été refusée parce qu'une écriture était en file : elle
  /// partira dès que la file sera vide.
  bool _differee = false;

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
      _differee = true;
      return Future<void>.value();
    }

    final periodes = _ref.read(periodesProvider.notifier);
    final derniere = periodes.derniereLecture;
    final maintenant = _ref.read(horlogeRafraichissementProvider)();
    if (derniere != null &&
        maintenant.difference(derniere) < intervalleMinimal) {
      return Future<void>.value();
    }

    return _lancer(() async {
      await periodes.relire();
    });
  }

  /// Tirer pour actualiser : relit les périodes **et** le mois affiché.
  Future<void> tirer() async {
    final enCours = _enCours;
    if (enCours != null) return enCours;

    final saisie = _ref.read(saisieControllerProvider.notifier);
    if (saisie.ecritureEnAttente) {
      final partie = await saisie.viderMaintenant();
      if (!partie || saisie.ecritureEnAttente) {
        _differee = true;
        return;
      }
    }

    return _lancer(() async {
      final change = await _ref.read(periodesProvider.notifier).relire();
      // Une liste nouvelle reconstruit déjà la saisie ; sinon, c'est le mois
      // lui-même qu'on vient chercher. La file, elle, survit au rechargement :
      // le contrôleur n'est pas recréé, seulement relu.
      if (!change) _ref.invalidate(saisieControllerProvider);
      try {
        await _ref.read(saisieControllerProvider.future);
      } on Object {
        // L'écran dit déjà l'échec de lecture ; l'indicateur doit se retirer.
      }
    });
  }

  /// La file est revenue au calme : la relecture refusée part maintenant.
  void _reprendre() {
    if (!_differee || _ecritureEnAttente) return;
    _differee = false;
    unawaited(auRetour());
  }

  bool get _ecritureEnAttente =>
      _ref.read(saisieControllerProvider.notifier).ecritureEnAttente;

  Future<void> _lancer(Future<void> Function() tache) {
    final futur = tache().whenComplete(() => _enCours = null);
    _enCours = futur;
    return futur;
  }
}

/// Le coordinateur des relectures, partagé par le Calendrier et l'accueil :
/// un seul délai minimal pour les deux écrans, et une seule relecture en vol.
final Provider<RafraichissementPeriodes> rafraichissementPeriodesProvider =
    Provider<RafraichissementPeriodes>((ref) {
      final rafraichissement = RafraichissementPeriodes(ref);
      ref.listen<SyncEtat?>(
        saisieControllerProvider.select(
          (AsyncValue<EtatSaisie?> valeur) => valeur.value?.sync,
        ),
        (SyncEtat? _, SyncEtat? sync) {
          if (sync == SyncEtat.repos || sync == SyncEtat.enregistre) {
            rafraichissement._reprendre();
          }
        },
      );
      return rafraichissement;
    });
