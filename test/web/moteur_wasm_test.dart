import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le moteur de rendu de la PWA, et les deux en-têtes dont il dépend
/// (ticket 065).
///
/// Ce que ces tests protègent tient en une phrase : **le gain de fluidité est
/// dans la configuration, pas dans le code Dart.** Le défilement de la matrice
/// passe de 37 % d'images perdues à 0 % parce que trois fichiers que Flutter
/// ne compile pas disent la même chose :
///
///   - `scripts/build_web.sh` construit avec `--wasm`, donc produit Skwasm et
///     son repli JavaScript ;
///   - `vercel.json` sert `Cross-Origin-Opener-Policy: same-origin` et
///     `Cross-Origin-Embedder-Policy: require-corp`, sans quoi la page n'a pas
///     `SharedArrayBuffer` et Skwasm rastérise sur un seul fil ;
///   - `vercel.json` sert `main.dart.wasm` pré-compressé, comme les moteurs.
///
/// Aucun de ces trois réglages ne casse quoi que ce soit en disparaissant :
/// l'application s'ouvre, marche, et **redevient lente**. C'est la panne qu'on
/// ne voit pas, donc celle qu'il faut tenir par un test.
void main() {
  final construction = File('scripts/build_web.sh').readAsStringSync();
  final vercel =
      jsonDecode(File('vercel.json').readAsStringSync())
          as Map<String, dynamic>;
  final entetes = (vercel['headers'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  Map<String, String> valeurs(String source) => <String, String>{
    for (final entree in entetes.where((e) => e['source'] == source))
      for (final entete
          in (entree['headers'] as List<dynamic>).cast<Map<String, dynamic>>())
        entete['key'] as String: entete['value'] as String,
  };

  group('Construction Wasm', () {
    test('la PWA est construite avec --wasm', () {
      expect(construction, contains('flutter build web --release --wasm'));
    });

    // Le repli est la moitié qu'on oublie : un navigateur sans WasmGC charge
    // `main.dart.js`, rendu par CanvasKit. Les deux moteurs sont déclarés dans
    // le même `flutter_bootstrap.js`, et le chargeur tranche à l'ouverture.
    test('les deux moteurs sont exigés de la construction', () {
      expect(construction, contains('"renderer":"skwasm"'));
      expect(construction, contains('"renderer":"canvaskit"'));
      for (final fichier in <String>[
        'main.dart.wasm',
        'main.dart.mjs',
        'main.dart.js',
      ]) {
        expect(construction, contains(fichier));
      }
    });

    // Jusqu'au ticket 065, `build_web.sh` **supprimait** `skwasm*` : une
    // construction `dart2js` + `canvaskit` ne pouvait pas les atteindre, ils
    // pesaient 14 Mo, et ils partaient. Les rétablir était la moitié du
    // ticket ; les re-élaguer par inadvertance rendrait la construction Wasm
    // inerte — elle se chargerait, sans rastériseur.
    test('skwasm n\'est plus élagué', () {
      expect(
        construction,
        isNot(contains("-name 'skwasm*'")),
        reason: 'skwasm est le rastériseur de la construction Wasm',
      );
      expect(construction, contains("-name '*.symbols'"));
    });
  });

  group('Isolation d\'origine', () {
    // La règle qui les porte est celle qui attrape tout : les deux en-têtes
    // doivent être sur **le document**, quelle que soit la route ouverte —
    // `/`, `/admin/planning`, un lien d'invitation. Une isolation posée sur la
    // racine seule laisserait toute route profonde sans `SharedArrayBuffer`.
    test('les deux en-têtes sont servis sur toutes les routes', () {
      final toutes = valeurs('/(.*)');
      expect(toutes['Cross-Origin-Opener-Policy'], 'same-origin');
      expect(toutes['Cross-Origin-Embedder-Policy'], 'require-corp');
    });

    // `credentialless` est la porte de secours, pas le réglage par défaut :
    // il laisse passer une ressource tierce sans CORP, au prix d'une requête
    // sans identifiants. Les deux origines que la PWA joint n'en ont pas
    // besoin (docs/DEPLOIEMENT.md § 11).
    test('l\'isolation n\'est pas relâchée en credentialless', () {
      expect(
        valeurs('/(.*)')['Cross-Origin-Embedder-Policy'],
        isNot('credentialless'),
      );
    });
  });

  group('main.dart.wasm', () {
    // 3,6 Mo → 1,0 Mo. Rien ne garantit qu'un CDN comprime `application/wasm`
    // à la volée comme il comprime le JavaScript : la compression est faite à
    // la construction, et l'en-tête l'annonce.
    test('est servi pré-compressé en brotli', () {
      final wasm = valeurs('/main.dart.wasm');
      expect(wasm['Content-Encoding'], 'br');
      expect(wasm['Vary'], 'Accept-Encoding');
    });

    // Même raison que pour `canvaskit/**` : le chemin ne porte pas
    // d'empreinte, c'est le service worker qui gère les versions.
    test('n\'est pas mis en cache pour l\'éternité', () {
      final cache = valeurs('/main.dart.wasm')['Cache-Control'];
      expect(cache, contains('max-age=0'));
      expect(cache, contains('must-revalidate'));
      expect(cache, isNot(contains('immutable')));
    });
  });
}
