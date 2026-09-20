import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/auth_erreur.dart';
import '../../../../core/session/session_providers.dart';
import '../../domain/email.dart';

/// L'état de l'écran de saisie de l'adresse e-mail.
@immutable
class EtatConnexion {
  const EtatConnexion({this.envoiEnCours = false, this.erreur});

  final bool envoiEnCours;

  /// `null` tant que rien n'a échoué.
  final AuthErreur? erreur;
}

/// Demande l'envoi d'un code à six chiffres.
///
/// La validation de forme se fait ici, avant tout appel réseau : une adresse
/// tronquée ne mérite pas un aller-retour, surtout en 4G rurale.
class ConnexionController extends Notifier<EtatConnexion> {
  @override
  EtatConnexion build() => const EtatConnexion();

  /// Vrai si le code est parti. Faux si l'adresse est invalide ou si l'envoi
  /// a échoué — l'erreur est alors dans `state.erreur`.
  Future<bool> envoyer(String emailSaisi) async {
    if (state.envoiEnCours) return false;

    final email = normaliserEmail(emailSaisi);
    if (!emailValide(email)) {
      state = const EtatConnexion(erreur: AuthErreur.emailInvalide);
      return false;
    }

    state = const EtatConnexion(envoiEnCours: true);
    try {
      await ref.read(authRepositoryProvider).envoyerCode(email);
      state = const EtatConnexion();
      return true;
    } on AuthEchec catch (echec) {
      state = EtatConnexion(erreur: echec.erreur);
      return false;
    } on Object catch (erreur) {
      state = EtatConnexion(
        erreur: traduireErreurAuth(erreur, etape: AuthEtape.envoi),
      );
      return false;
    }
  }

  /// Efface l'erreur dès que l'utilisateur corrige sa saisie.
  void effacerErreur() {
    if (state.erreur != null) {
      state = EtatConnexion(envoiEnCours: state.envoiEnCours);
    }
  }
}

final NotifierProvider<ConnexionController, EtatConnexion>
connexionControllerProvider =
    NotifierProvider<ConnexionController, EtatConnexion>(
      ConnexionController.new,
      isAutoDispose: true,
    );
