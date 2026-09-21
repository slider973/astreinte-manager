import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ce que Flutter ne compile pas et que personne ne relit : `web/`.
///
/// `flutter build web` recopie ces fichiers tels quels. Une clé disparue du
/// manifeste ou un écouteur d'événement renommé ne casse ni l'analyse ni les
/// tests de widgets — ça se voit en production, sur le téléphone de quelqu'un,
/// sous la forme d'une application qui ne s'installe pas ou d'un squelette qui
/// ne s'efface jamais. D'où ces vérifications (ticket 032).
void main() {
  final manifeste =
      jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  final index = File('web/index.html').readAsStringSync();

  group('Manifeste PWA', () {
    // Les cinq conditions d'installabilité que le navigateur vérifie.
    test('porte de quoi être installable', () {
      expect(manifeste['name'], 'Astreinte SP');
      expect(manifeste['short_name'], 'Astreinte SP');
      expect(manifeste['display'], 'standalone');
      expect(manifeste['start_url'], isNotNull);
      expect(manifeste['lang'], 'fr');
      // Sans `id`, deux déploiements de la même application s'installent
      // comme deux applications différentes.
      expect(manifeste['id'], isNotNull);
      expect(manifeste['scope'], isNotNull);
    });

    test('les quatre icônes existent, aux deux tailles et aux deux usages', () {
      final icones = (manifeste['icons'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (final usage in <String>['any', 'maskable']) {
        for (final taille in <String>['192x192', '512x512']) {
          final trouvee = icones.where(
            (icone) => icone['purpose'] == usage && icone['sizes'] == taille,
          );
          expect(
            trouvee,
            hasLength(1),
            reason: 'icône $usage $taille absente du manifeste',
          );
          final fichier = File('web/${trouvee.single['src']}');
          expect(
            fichier.existsSync(),
            isTrue,
            reason: '${fichier.path} déclaré mais absent',
          );
        }
      }
    });

    // `DESIGN.md § Zones sûres et chrome PWA` : la couleur de chrome suit
    // `surface-container-low`. `background_color` est ce que le système peint
    // avant que le document existe : il doit valoir `surface` du thème clair,
    // et l'écran d'attente HTML doit commencer par la même valeur — sinon
    // l'ouverture produit un éclair blanc suivi d'un autre fond.
    test('les couleurs sont celles du système de design', () {
      expect(manifeste['theme_color'], '#F7F9FA');
      expect(manifeste['background_color'], '#FFFFFF');
      expect(index, contains('content="#F7F9FA"'));
      expect(index, contains('content="#141C22"'));
      expect(index, contains('--surface: #FFFFFF;'));
    });

    test('aucune icône par défaut de Flutter ne subsiste', () {
      // Les icônes livrées par `flutter create` pèsent 5 292 et 8 252 octets.
      // Ce n'est pas une empreinte : c'est un garde-fou contre le logo bleu
      // oublié en production.
      const tailles = <String, int>{
        'web/icons/Icon-192.png': 5292,
        'web/icons/Icon-512.png': 8252,
      };
      tailles.forEach((chemin, taille) {
        expect(
          File(chemin).lengthSync(),
          isNot(taille),
          reason: '$chemin est encore l\'icône par défaut de Flutter',
        );
      });
    });
  });

  group('Écran d\'attente HTML', () {
    test('se retire sur la première image de Flutter, pas sur une durée', () {
      expect(index, contains("addEventListener('flutter-first-frame'"));
    });

    test('a un garde-fou pour un réseau qui se tait', () {
      expect(index, contains('amorce-recharger'));
      expect(index, contains('Le chargement prend plus de temps que prévu'));
    });

    test('respecte Reduce Motion', () {
      expect(index, contains('prefers-reduced-motion: reduce'));
    });

    // Sans elle, un téléphone donne 980 px de large à l'écran d'attente et le
    // squelette arrive en miniature : le moteur Flutter ne pose la sienne
    // qu'une fois chargé, c'est-à-dire trop tard.
    test('porte sa propre balise viewport', () {
      expect(index, contains('name="viewport"'));
      expect(index, contains('width=device-width'));
    });

    // Une feuille de style, une police ou une image externes retarderaient
    // l'écran censé masquer l'attente.
    test('ne demande aucune ressource pour s\'afficher', () {
      expect(index, isNot(contains('<link rel="stylesheet"')));
      expect(
        RegExp(r'<img\s').hasMatch(index),
        isFalse,
        reason: 'la marque de l\'écran d\'attente est un SVG en ligne',
      );
    });
  });

  group('Configuration de l\'hébergeur', () {
    final vercel =
        jsonDecode(File('vercel.json').readAsStringSync())
            as Map<String, dynamic>;
    final entetes = (vercel['headers'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    List<Map<String, dynamic>> valeurs(String source) => entetes
        .where((entree) => entree['source'] == source)
        .expand(
          (entree) =>
              (entree['headers'] as List<dynamic>).cast<Map<String, dynamic>>(),
        )
        .toList();

    // Un service worker mis en cache par le CDN fige l'application sur une
    // version : plus aucune mise à jour n'atteint les téléphones installés.
    test('le service worker n\'est jamais mis en cache', () {
      final cache = valeurs('/flutter_service_worker.js')
          .where((entete) => entete['key'] == 'Cache-Control')
          .single;
      expect(cache['value'], contains('max-age=0'));
      expect(cache['value'], contains('must-revalidate'));
    });

    // `tickets/backlog/037` : TTF + brotli, 83 Ko au lieu de 184.
    // `assets/fonts/README.md` explique pourquoi ce n'est pas du WOFF2.
    test('les polices sont servies pré-compressées en brotli', () {
      final polices = valeurs('/assets/assets/fonts/(.*).ttf');
      expect(
        polices.any(
          (entete) =>
              entete['key'] == 'Content-Encoding' && entete['value'] == 'br',
        ),
        isTrue,
      );
    });

    // Depuis le ticket 046, les routes vivent dans le chemin de l'adresse :
    // sans cette réécriture, **tout** rechargement sur une route profonde —
    // `/install`, `/invite/xyz`, `/admin/planning` — rendrait une 404 de
    // l'hébergeur avant que l'application ait la moindre chance de s'ouvrir.
    test('toute adresse inconnue rend index.html : les routes sont côté client',
        () {
      final reecritures = (vercel['rewrites'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(reecritures.last['destination'], '/index.html');
      // La source doit tout attraper, y compris les chemins à plusieurs
      // segments : `/(.*)` et non `/([^/]*)`.
      final motif = RegExp(reecritures.last['source'] as String);
      for (final route in <String>[
        '/install',
        '/invite/8f3c-token',
        '/admin/planning',
        '/schedule/2026-10',
      ]) {
        expect(
          motif.stringMatch(route),
          route,
          reason: '$route ne retomberait pas sur index.html',
        );
      }
    });

    // Le ticket 032 redirigeait `/install` vers `/#/install`, faute de mieux.
    // Le dièse est parti (ticket 046) : `/install` est une route comme les
    // autres, et une redirection survivante renverrait sur une adresse que
    // plus personne ne sait lire.
    test('aucune redirection ne fabrique de dièse', () {
      final redirections = (vercel['redirects'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>();
      for (final regle in redirections) {
        expect(
          regle['destination'],
          isNot(contains('#')),
          reason: 'redirection vers ${regle['destination']}',
        );
      }
    });

    test('la sortie déployée est celle de flutter build web', () {
      expect(vercel['outputDirectory'], 'build/web');
    });
  });
}
