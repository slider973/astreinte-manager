import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/auth_erreur.dart';
import '../../../../core/session/session_providers.dart';
import '../../domain/email.dart';

/// Longueur du code envoyé par Supabase (`supabase/config.toml`,
/// `auth.email.otp_length`).
const int longueurCode = 6;

/// Délai avant de pouvoir redemander un code.
///
/// Assez long pour que le courriel arrive (et que la limite d'envoi du
/// serveur ne soit pas frôlée), assez court pour ne pas bloquer quelqu'un
/// dont le message est tombé dans les indésirables.
const int delaiRenvoiSecondes = 60;

/// L'état de l'écran de saisie du code.
@immutable
class EtatCode {
  const EtatCode({
    this.verificationEnCours = false,
    this.renvoiEnCours = false,
    this.erreur,
    this.secondesAvantRenvoi = delaiRenvoiSecondes,
    this.renvoye = false,
  });

  final bool verificationEnCours;
  final bool renvoiEnCours;
  final AuthErreur? erreur;

  /// Secondes restantes avant que « Renvoyer un code » redevienne actif.
  final int secondesAvantRenvoi;

  /// Vrai juste après un renvoi réussi : l'écran le confirme.
  final bool renvoye;

  bool get renvoiPossible => secondesAvantRenvoi <= 0 && !renvoiEnCours;

  /// Attention : [erreur] n'est **jamais** conservée implicitement. Chaque
  /// action repart d'un écran sans erreur ; pour la garder, la repasser.
  EtatCode copyWith({
    bool? verificationEnCours,
    bool? renvoiEnCours,
    AuthErreur? erreur,
    int? secondesAvantRenvoi,
    bool? renvoye,
  }) => EtatCode(
    verificationEnCours: verificationEnCours ?? this.verificationEnCours,
    renvoiEnCours: renvoiEnCours ?? this.renvoiEnCours,
    erreur: erreur,
    secondesAvantRenvoi: secondesAvantRenvoi ?? this.secondesAvantRenvoi,
    renvoye: renvoye ?? this.renvoye,
  );
}

/// Vérifie le code et gère le compte à rebours du renvoi.
///
/// Arriver sur l'écran signifie qu'un code vient de partir : le compte à
/// rebours démarre donc avec le contrôleur.
class CodeController extends Notifier<EtatCode> {
  Timer? _minuterie;

  @override
  EtatCode build() {
    ref.onDispose(_arreterMinuterie);
    _demarrerMinuterie();
    return const EtatCode();
  }

  /// Vrai si la session est ouverte. Le routeur fait le reste : la redirection
  /// suit l'état d'authentification, l'écran n'a personne à pousser.
  Future<bool> verifier({required String email, required String code}) async {
    if (state.verificationEnCours) return false;

    if (code.length != longueurCode) {
      state = state.copyWith(erreur: AuthErreur.codeInvalide, renvoye: false);
      return false;
    }

    state = state.copyWith(verificationEnCours: true, renvoye: false);
    try {
      await ref
          .read(authRepositoryProvider)
          .verifierCode(email: normaliserEmail(email), code: code);
      state = state.copyWith(verificationEnCours: false);
      return true;
    } on Object catch (erreur) {
      state = state.copyWith(
        verificationEnCours: false,
        erreur: traduireErreurAuth(erreur, etape: AuthEtape.verification),
      );
      return false;
    }
  }

  /// Redemande un code et relance le compte à rebours.
  Future<void> renvoyer(String email) async {
    if (!state.renvoiPossible) return;

    state = state.copyWith(renvoiEnCours: true, renvoye: false);
    try {
      await ref
          .read(authRepositoryProvider)
          .envoyerCode(normaliserEmail(email));
      state = const EtatCode(renvoye: true);
      _demarrerMinuterie();
    } on Object catch (erreur) {
      state = state.copyWith(
        renvoiEnCours: false,
        secondesAvantRenvoi: 0,
        erreur: traduireErreurAuth(erreur, etape: AuthEtape.envoi),
      );
    }
  }

  /// Efface l'erreur dès que l'utilisateur retouche le code.
  void effacerErreur() {
    if (state.erreur != null || state.renvoye) {
      state = state.copyWith(renvoye: false);
    }
  }

  void _demarrerMinuterie() {
    _arreterMinuterie();
    _minuterie = Timer.periodic(const Duration(seconds: 1), (minuterie) {
      final restant = state.secondesAvantRenvoi - 1;
      if (restant <= 0) {
        minuterie.cancel();
        _minuterie = null;
      }
      state = state.copyWith(
        secondesAvantRenvoi: restant < 0 ? 0 : restant,
        erreur: state.erreur,
      );
    });
  }

  void _arreterMinuterie() {
    _minuterie?.cancel();
    _minuterie = null;
  }
}

final NotifierProvider<CodeController, EtatCode> codeControllerProvider =
    NotifierProvider<CodeController, EtatCode>(
      CodeController.new,
      isAutoDispose: true,
    );
