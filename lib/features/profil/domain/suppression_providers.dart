import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/oubli_local.dart';
import '../../../core/session/session_providers.dart';
import 'profil.dart';
import 'profil_providers.dart';

/// Où en est la suppression de compte.
@immutable
class EtatSuppression {
  const EtatSuppression({this.enCours = false, this.echec});

  final bool enCours;

  /// `null` tant que rien n'a échoué.
  final EchecSuppression? echec;

  String? get message => echec?.message;
}

/// Supprime le compte, puis fait le ménage sur l'appareil.
///
/// **Trois temps, et l'ordre est le sujet** :
///
///   1. le serveur anonymise et ferme le compte (Edge Function
///      `delete-account`) ;
///   2. l'appareil oublie tout ce qu'il gardait de cette personne
///      (`OubliLocal`), **avant** la fermeture de session — après, les clés ne
///      sont plus composables ;
///   3. la session se ferme, et le routeur emmène vers la connexion.
///
/// Le ménage vient **après** le serveur, pas avant : un refus — le dernier
/// administrateur d'une caserne, par exemple — laisse la personne dans une
/// application qui marche encore. Effacer d'abord viderait ses caches pour rien
/// et la renverrait chercher son mois sans réseau.
///
/// Et le ménage est le **même** qu'à la déconnexion, au même appel près : une
/// suppression doit laisser l'appareil au moins aussi propre qu'une sortie de
/// session (`core/session/oubli_local.dart`).
class SuppressionCompteController extends Notifier<EtatSuppression> {
  @override
  EtatSuppression build() => const EtatSuppression();

  /// Vrai si le compte a bien été supprimé.
  Future<bool> supprimer() async {
    if (state.enCours) return false;
    state = const EtatSuppression(enCours: true);

    try {
      await ref.read(profilRepositoryProvider).supprimerCompte();
    } on EchecSuppression catch (echec) {
      state = EtatSuppression(echec: echec);
      return false;
    } on Object {
      state = const EtatSuppression(
        echec: EchecSuppression(ErreurSuppression.inconnue),
      );
      return false;
    }

    // À partir d'ici le compte n'existe plus côté serveur : plus rien ne doit
    // faire échouer la suite. `OubliLocal` avale déjà les pannes de stockage,
    // et une fermeture de session qui trébuche ne rendrait pas le compte.
    await ref.read(oubliLocalProvider).tout();
    try {
      await ref.read(authRepositoryProvider).seDeconnecter();
    } on Object {
      // Le jeton est de toute façon mort : le serveur ne connaît plus ce
      // compte. Le routeur suivra dès que le SDK s'en apercevra.
    }
    return true;
  }
}

final NotifierProvider<SuppressionCompteController, EtatSuppression>
suppressionCompteControllerProvider =
    NotifierProvider<SuppressionCompteController, EtatSuppression>(
      SuppressionCompteController.new,
      isAutoDispose: true,
    );
