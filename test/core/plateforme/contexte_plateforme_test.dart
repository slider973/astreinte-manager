import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Agents utilisateurs réels, raccourcis à ce qui sert à décider.
const String _safariIphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const String _chromeIphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) CriOS/126.0.6478.54 Mobile/15E148 Safari/604.1';
const String _chromeAndroid =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
const String _samsungAndroid =
    'Mozilla/5.0 (Linux; Android 14; SM-S911B) AppleWebKit/537.36 (KHTML, like '
    'Gecko) SamsungBrowser/25.0 Chrome/121.0.0.0 Mobile Safari/537.36';
const String _chromeBureau =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, '
    'like Gecko) Chrome/126.0.0.0 Safari/537.36';

void main() {
  group('Détection du navigateur', () {
    test('Safari sur iPhone est reconnu', () {
      final contexte = ContextePlateforme.depuisAgent(userAgent: _safariIphone);

      expect(contexte.navigateur, NavigateurInstallation.safariIos);
      expect(contexte.aideUtile, isTrue);
    });

    test('Chrome sur Android est reconnu', () {
      final contexte = ContextePlateforme.depuisAgent(
        userAgent: _chromeAndroid,
      );

      expect(contexte.navigateur, NavigateurInstallation.chromeAndroid);
      expect(contexte.aideUtile, isTrue);
    });

    test('un navigateur tiers sur iOS ne reçoit pas les gestes de Safari', () {
      final contexte = ContextePlateforme.depuisAgent(userAgent: _chromeIphone);

      expect(contexte.navigateur, NavigateurInstallation.autre);
      expect(contexte.aideUtile, isFalse);
    });

    test('Samsung Internet n\'est pas Chrome', () {
      final contexte = ContextePlateforme.depuisAgent(
        userAgent: _samsungAndroid,
      );

      expect(contexte.navigateur, NavigateurInstallation.autre);
    });

    test('un navigateur de bureau n\'a rien à installer', () {
      final contexte = ContextePlateforme.depuisAgent(userAgent: _chromeBureau);

      expect(contexte.navigateur, NavigateurInstallation.autre);
      expect(contexte.aideUtile, isFalse);
    });
  });

  group('Mode autonome', () {
    test('display-mode: standalone coupe l\'aide à l\'installation', () {
      final contexte = ContextePlateforme.depuisAgent(
        userAgent: _chromeAndroid,
        affichageAutonome: true,
      );

      expect(contexte.autonome, isTrue);
      expect(contexte.aideUtile, isFalse);
    });

    test('navigator.standalone d\'iOS suffit, sans requête média', () {
      final contexte = ContextePlateforme.depuisAgent(
        userAgent: _safariIphone,
        autonomeIos: true,
      );

      expect(contexte.autonome, isTrue);
      expect(contexte.aideUtile, isFalse);
    });

    test('sans aucun signal, l\'application est dans un onglet', () {
      final contexte = ContextePlateforme.depuisAgent(userAgent: _safariIphone);

      expect(contexte.autonome, isFalse);
    });

    test('hors du web, il n\'y a rien à installer', () {
      expect(ContextePlateforme.natif.web, isFalse);
      expect(ContextePlateforme.natif.aideUtile, isFalse);
    });
  });
}
