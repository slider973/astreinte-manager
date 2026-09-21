import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le produit ne parle à personne d'autre qu'à lui-même (ticket 037).
///
/// À l'ouverture, le chargeur Flutter web va chercher **deux** ressources chez
/// Google si on ne le lui interdit pas : le moteur de rendu CanvasKit sur
/// `www.gstatic.com` (1 620 Ko mesurés au ticket 032) et la police Roboto sur
/// `fonts.gstatic.com` (63 Ko). Une troisième part pendant la navigation : la
/// police Noto d'un glyphe absent du sous-ensemble embarqué, déclenchée par le
/// texte que saisissent les utilisateurs.
///
/// Rien de tout cela n'est visible depuis le code Dart : ça se règle dans
/// `web/flutter_bootstrap.js`, dans `pubspec.yaml` et dans `vercel.json`.
/// C'est-à-dire dans trois fichiers qu'aucun test de widget ne touche et qu'un
/// coup de `flutter create` peut réécrire. D'où ce fichier : le registre des
/// données personnelles du produit (`docs/PRD.md` § 8) tient à ces trois
/// réglages, pas à une intention.
void main() {
  final amorcage = File('web/flutter_bootstrap.js').readAsStringSync();
  final index = File('web/index.html').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final construction = File('scripts/build_web.sh').readAsStringSync();
  final vercel =
      jsonDecode(File('vercel.json').readAsStringSync())
          as Map<String, dynamic>;

  group('Chargeur web', () {
    test('le moteur de rendu est servi par l\'hébergement du produit', () {
      expect(amorcage, contains('canvasKitBaseUrl'));
      expect(amorcage, contains("canvasKitBaseUrl: 'canvaskit/'"));
      // La ceinture, en plus des bretelles : le drapeau pose la même chose
      // dans `buildConfig`, pour une construction lancée à la main.
      expect(construction, contains('--no-web-resources-cdn'));
    });

    test('les polices de repli sont cherchées chez nous, pas chez Google', () {
      expect(amorcage, contains("fontFallbackBaseUrl: 'polices-de-repli/'"));
      expect(
        Directory('web/polices-de-repli').existsSync(),
        isTrue,
        reason: 'le répertoire de repli doit exister, même vide',
      );
    });

    // La leçon du ticket 037, apprise en la cassant : `flutter build web`
    // remplace les jetons `{{…}}` **partout**, commentaires compris. Un jeton
    // cité de travers recopie tout `flutter.js` au milieu d'une phrase et
    // produit un fichier qui pèse le bon poids, s'installe, et laisse une page
    // blanche.
    test('ne contient que les trois jetons de substitution attendus', () {
      final jetons = RegExp(r'\{\{[a-z_]+\}\}')
          .allMatches(amorcage)
          .map((correspondance) => correspondance.group(0))
          .toList();
      expect(jetons, <String>[
        '{{flutter_js}}',
        '{{flutter_build_config}}',
        '{{flutter_service_worker_version}}',
      ]);
    });
  });

  group('Polices', () {
    // CanvasKit exige une police de dernier recours et l'a nommée `Roboto`.
    // Tant qu'aucune famille de ce nom n'est déclarée, il la télécharge chez
    // Google, sans condition et sans que le thème puisse s'y opposer.
    test('la famille Roboto est déclarée, donc jamais téléchargée', () {
      expect(pubspec, contains('- family: Roboto'));
      expect(
        pubspec,
        contains('asset: assets/fonts/AtkinsonHyperlegibleNext-Repli.ttf'),
      );
      expect(
        File('assets/fonts/AtkinsonHyperlegibleNext-Repli.ttf').existsSync(),
        isTrue,
      );
    });

    // `as="font"` attend une police demandée par une règle CSS ; CanvasKit,
    // lui, les récupère au `fetch()`. Les deux destinations ne se rencontrent
    // pas : avec `as="font"`, les trois fichiers préchargés partaient deux
    // fois, 52 Ko pour rien.
    test('les préchargements ont la destination que CanvasKit utilise', () {
      expect(index, contains('rel="preload" as="fetch"'));
      expect(
        index.contains('rel="preload" as="font"'),
        isFalse,
        reason: 'as="font" ne sera jamais réutilisé par le moteur',
      );
    });
  });

  group('Configuration de l\'hébergeur', () {
    final entetes = (vercel['headers'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    Map<String, String> valeurs(String source) => <String, String>{
      for (final entree in entetes.where((e) => e['source'] == source))
        for (final entete
            in (entree['headers'] as List<dynamic>)
                .cast<Map<String, dynamic>>())
          entete['key'] as String: entete['value'] as String,
    };

    // Servi sans cet en-tête, CanvasKit ne démarre pas du tout :
    // « WebAssembly.compileStreaming(): expected magic word ».
    test('le moteur est servi pré-compressé en brotli', () {
      final moteur = valeurs('/canvaskit/(.*)');
      expect(moteur['Content-Encoding'], 'br');
      expect(moteur['Vary'], 'Accept-Encoding');
    });

    // Auto-hébergé, `canvaskit/canvaskit.wasm` n'a plus la révision du moteur
    // dans son adresse : un cache d'un an y figerait la version d'aujourd'hui
    // et la prochaine mise à jour de Flutter servirait un moteur périmé à tous
    // les téléphones déjà venus. C'est le service worker qui gère les
    // versions, par empreinte de contenu.
    test('le moteur n\'est pas mis en cache pour l\'éternité', () {
      final cache = valeurs('/canvaskit/(.*)')['Cache-Control'];
      expect(cache, contains('max-age=0'));
      expect(cache, contains('must-revalidate'));
      expect(cache, isNot(contains('immutable')));
    });
  });
}
