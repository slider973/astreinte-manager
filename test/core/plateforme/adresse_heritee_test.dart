import 'package:astreinte_sp/core/plateforme/adresse_heritee.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ce que devient une adresse partie avant la bascule du ticket 046.
///
/// La valeur renvoyée est réinjectée telle quelle dans la barre d'adresse par
/// `strategie_url_web.dart` : ce qui sort d'ici doit être une route de
/// l'application, et rien d'autre.
void main() {
  group('cheminHerite', () {
    test('rend la route cachée derrière le dièse', () {
      expect(cheminHerite('#/invite/8f3c-token'), '/invite/8f3c-token');
      expect(cheminHerite('#/proposals'), '/proposals');
      expect(cheminHerite('#/schedule/2026-10'), '/schedule/2026-10');
    });

    test('garde la requête, qui porte l\'état de l\'écran', () {
      expect(cheminHerite('#/?onglet=0&mois=2026-10'), '/?onglet=0&mois=2026-10');
    });

    test('ignore le dièse absent : c\'est la même adresse', () {
      expect(cheminHerite('/proposals'), '/proposals');
    });

    // Le cas qui a motivé le ticket : le fournisseur dépose ses jetons ici.
    // `supabase_flutter` les lit et nettoie l'adresse ; y toucher ferait
    // perdre la session à la première connexion par lien.
    test('laisse les jetons d\'authentification tranquilles', () {
      expect(
        cheminHerite(
          '#access_token=eyJh&expires_at=1&refresh_token=zz'
          '&token_type=bearer&type=magiclink',
        ),
        isNull,
      );
      expect(cheminHerite('#error=access_denied&error_code=otp_expired'), isNull);
      expect(cheminHerite('#code=abc'), isNull);
    });

    test('ne rend rien quand il n\'y a rien à rattraper', () {
      expect(cheminHerite(''), isNull);
      expect(cheminHerite('#'), isNull);
      // L'accueil nu : y « revenir » n'apprend rien.
      expect(cheminHerite('#/'), isNull);
      // Une ancre ordinaire n'est pas une route.
      expect(cheminHerite('#contenu'), isNull);
    });

    test('refuse tout ce qui sortirait de l\'application', () {
      expect(cheminHerite('#https://ailleurs.example/piege'), isNull);
      expect(cheminHerite('#javascript:alert(1)'), isNull);
      expect(cheminHerite('#//ailleurs.example/piege'), isNull);
      expect(cheminHerite(r'#/\ailleurs.example/piege'), isNull);
    });
  });
}
