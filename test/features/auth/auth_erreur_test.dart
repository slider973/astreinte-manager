import 'dart:async';

import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/features/auth/domain/email.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('traduireErreurAuth', () {
    test('un code faux et un code périmé partagent le même message', () {
      // GoTrue répond la même chose aux deux : prétendre les distinguer
      // reviendrait à deviner devant l'utilisateur.
      expect(
        traduireErreurAuth(
          const AuthException(
            'Token has expired or is invalid',
            statusCode: '403',
            code: 'otp_expired',
          ),
          etape: AuthEtape.verification,
        ),
        AuthErreur.codeInvalide,
      );
      expect(
        AuthErreur.codeInvalide.message,
        allOf(contains('incorrect'), contains('expiré')),
      );
    });

    test('un serveur qui ne dirait que « périmé » est entendu', () {
      expect(
        traduireErreurAuth(
          const AuthException('Token has expired', statusCode: '403'),
          etape: AuthEtape.verification,
        ),
        AuthErreur.codeExpire,
      );
    });

    test('une adresse sans compte renvoie vers l\'invitation', () {
      expect(
        traduireErreurAuth(
          const AuthException('Signups not allowed', code: 'otp_disabled'),
          etape: AuthEtape.envoi,
        ),
        AuthErreur.compteInconnu,
      );
    });

    test('la limite d\'envoi est distinguée d\'une panne', () {
      expect(
        traduireErreurAuth(
          const AuthException(
            'For security purposes...',
            code: 'over_email_send_rate_limit',
          ),
          etape: AuthEtape.envoi,
        ),
        AuthErreur.tropDeTentatives,
      );
      expect(
        traduireErreurAuth(
          const AuthException('Too many requests', statusCode: '429'),
          etape: AuthEtape.verification,
        ),
        AuthErreur.tropDeTentatives,
      );
    });

    test('un code faux en vérification n\'est pas une adresse invalide', () {
      expect(
        traduireErreurAuth(
          const AuthException('Invalid token', statusCode: '403'),
          etape: AuthEtape.verification,
        ),
        AuthErreur.codeInvalide,
      );
      expect(
        traduireErreurAuth(
          const AuthException('Bad request', statusCode: '400'),
          etape: AuthEtape.envoi,
        ),
        AuthErreur.emailInvalide,
      );
    });

    test('une panne réseau est reconnue sous ses différentes formes', () {
      expect(
        traduireErreurAuth(
          AuthRetryableFetchException(),
          etape: AuthEtape.envoi,
        ),
        AuthErreur.reseau,
      );
      expect(
        traduireErreurAuth(
          http.ClientException('Failed to fetch'),
          etape: AuthEtape.envoi,
        ),
        AuthErreur.reseau,
      );
      expect(
        traduireErreurAuth(TimeoutException('lent'), etape: AuthEtape.envoi),
        AuthErreur.reseau,
      );
    });

    test('une erreur déjà traduite traverse sans se dégrader', () {
      expect(
        traduireErreurAuth(
          const AuthEchec(AuthErreur.codeExpire),
          etape: AuthEtape.envoi,
        ),
        AuthErreur.codeExpire,
      );
    });

    test('tout message porte une sortie, jamais un code technique', () {
      for (final erreur in AuthErreur.values) {
        expect(erreur.message, isNotEmpty);
        expect(erreur.message, isNot(contains('_')));
        expect(erreur.message.trim(), endsWith('.'));
      }
    });
  });

  group('emailValide', () {
    test('accepte les adresses des casernes de test', () {
      expect(emailValide('membre1@caserne-a.test'), isTrue);
      expect(emailValide('prenom.nom+garde@sdis25.fr'), isTrue);
    });

    test('refuse ce qui n\'a pas de domaine complet', () {
      expect(emailValide('membre1'), isFalse);
      expect(emailValide('membre1@caserne'), isFalse);
      expect(emailValide('membre1 @caserne.fr'), isFalse);
      expect(emailValide(''), isFalse);
    });

    test('normalise la casse et les espaces du clavier de téléphone', () {
      expect(
        normaliserEmail('  Membre1@Caserne-A.test '),
        'membre1@caserne-a.test',
      );
    });
  });
}
