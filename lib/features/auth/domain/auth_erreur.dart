import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';

/// L'étape où l'erreur est survenue. Le même code HTTP ne dit pas la même
/// chose selon qu'on demandait un code ou qu'on le vérifiait.
enum AuthEtape { envoi, verification }

/// Les erreurs d'authentification que l'app sait nommer.
///
/// Chaque valeur porte une phrase qui dit **le problème et la sortie**
/// (`DESIGN.md § Inputs / Fields`).
enum AuthErreur {
  emailInvalide(AppStrings.authEmailInvalide),
  compteInconnu(AppStrings.authCompteInconnu),
  codeInvalide(AppStrings.authCodeInvalide),
  codeExpire(AppStrings.authCodeExpire),
  tropDeTentatives(AppStrings.authTropDeTentatives),
  reseau(AppStrings.erreurReseauTexte),
  inconnue(AppStrings.erreurTexteGenerique);

  const AuthErreur(this.message);

  /// Le message affiché à l'utilisateur, en français.
  final String message;

  /// Vrai si l'erreur porte sur le champ lui-même : elle s'affiche alors sous
  /// le champ, pas en bannière.
  bool get estErreurDeChamp =>
      this == emailInvalide ||
      this == compteInconnu ||
      this == codeInvalide ||
      this == codeExpire;
}

/// L'exception que lève la couche `data` : une [AuthErreur] nommée, déjà
/// traduite, que les contrôleurs n'ont plus qu'à afficher.
@immutable
class AuthEchec implements Exception {
  const AuthEchec(this.erreur);

  final AuthErreur erreur;

  /// La phrase à montrer, en français.
  String get message => erreur.message;

  @override
  String toString() => 'AuthEchec(${erreur.name})';
}

/// Traduit une erreur du SDK en erreur nommée par le produit.
///
/// Les codes d'erreur Supabase sont documentés sur
/// <https://supabase.com/docs/guides/auth/debugging/error-codes>.
AuthErreur traduireErreurAuth(Object erreur, {required AuthEtape etape}) {
  if (erreur is AuthEchec) return erreur.erreur;
  if (erreur is AuthErreur) return erreur;

  // `dart:io` n'existe pas sur le web : pas de `SocketException` ici. Le SDK
  // enveloppe déjà les pannes réseau dans `AuthRetryableFetchException`, et
  // `http.ClientException` couvre le reste (CORS, serveur injoignable).
  if (erreur is http.ClientException ||
      erreur is TimeoutException ||
      erreur is AuthRetryableFetchException) {
    return AuthErreur.reseau;
  }

  if (erreur is! AuthException) return AuthErreur.inconnue;

  switch (erreur.code) {
    case 'otp_expired':
      return AuthErreur.codeExpire;
    case 'otp_disabled':
    case 'signup_disabled':
    case 'email_provider_disabled':
      // `shouldCreateUser: false` : l'adresse n'a pas de compte.
      return AuthErreur.compteInconnu;
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return AuthErreur.tropDeTentatives;
    case 'validation_failed':
    case 'email_address_invalid':
      return AuthErreur.emailInvalide;
  }

  if (erreur.statusCode == '429') return AuthErreur.tropDeTentatives;

  final message = erreur.message.toLowerCase();
  if (message.contains('expired')) return AuthErreur.codeExpire;
  if (message.contains('signups not allowed') ||
      message.contains('user not found')) {
    return AuthErreur.compteInconnu;
  }

  return switch (erreur.statusCode) {
    '400' || '401' || '403' || '422' => etape == AuthEtape.verification
        ? AuthErreur.codeInvalide
        : AuthErreur.emailInvalide,
    _ => AuthErreur.inconnue,
  };
}
