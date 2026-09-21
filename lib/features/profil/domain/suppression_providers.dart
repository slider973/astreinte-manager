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
/// **Deux gestes, et la coupure entre les deux est le sujet.**
///
/// [supprimer] fait ce qui ne se voit pas : le serveur anonymise et ferme le
/// compte (Edge Function `delete-account`), puis l'appareil oublie tout ce
/// qu'il gardait de cette personne (`OubliLocal`). [fermerSession] fait ce qui
/// se voit : la session tombe et le routeur emmène vers la connexion.
///
/// Elles sont séparées **parce que la feuille de confirmation est une route
/// impérative** (`showModalBottomSheet`), et que `go_router` ne la connaît pas.
/// Fermer la session pendant qu'elle est ouverte remplace toutes les pages du
/// routeur en laissant la feuille seule au sommet de la pile : l'écran devient
/// **blanc** et le reste jusqu'au rechargement. Vu dans Chrome, PWA, après une
/// vraie suppression (`design/007-profil.md § 8`). La feuille se referme donc
/// d'abord, et l'appelant ferme la session ensuite.
///
/// Le ménage vient **après** le serveur, pas avant : un refus — le dernier
/// administrateur d'une caserne, par exemple — laisse la personne dans une
/// application qui marche encore. Effacer d'abord viderait ses caches pour rien
/// et la renverrait chercher son mois sans réseau.
///
/// Et ce ménage est le **même** qu'à la déconnexion, au même appel près : une
/// suppression doit laisser l'appareil au moins aussi propre qu'une sortie de
/// session (`core/session/oubli_local.dart`).
class SuppressionCompteController extends Notifier<EtatSuppression> {
  @override
  EtatSuppression build() => const EtatSuppression();

  /// Vrai si le compte a bien été supprimé et l'appareil nettoyé.
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
    // faire échouer la suite. `OubliLocal` avale déjà les pannes de stockage.
    //
    // **Avant la fermeture de session**, parce qu'après, ni l'identifiant du
    // membre ni ceux de ses casernes ne sont plus lisibles.
    await ref.read(oubliLocalProvider).tout();
    state = const EtatSuppression();
    return true;
  }

  /// Ferme la session, **une fois la feuille refermée**.
  ///
  /// Aucune erreur ne remonte : le jeton est de toute façon mort — le serveur
  /// ne connaît plus ce compte — et le routeur suivra dès que le SDK s'en
  /// apercevra.
  Future<void> fermerSession() async {
    try {
      await ref.read(authRepositoryProvider).seDeconnecter();
    } on Object {
      // Rien à dire à quelqu'un dont le compte n'existe plus.
    }
  }
}

final NotifierProvider<SuppressionCompteController, EtatSuppression>
suppressionCompteControllerProvider =
    NotifierProvider<SuppressionCompteController, EtatSuppression>(
      SuppressionCompteController.new,
      isAutoDispose: true,
    );
