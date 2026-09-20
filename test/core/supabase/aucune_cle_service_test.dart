import 'dart:io';

import 'package:astreinte_sp/core/env.dart';
import 'package:flutter_test/flutter_test.dart';

/// Motifs qui trahissent une clé de service côté application.
///
/// `docs/SCHEMA.md § 4` : toute la sécurité repose sur RLS, et `service_role`
/// a l'attribut `bypassrls`. Une telle clé dans un binaire distribué à des
/// casernes donnerait la base entière à qui ouvre les outils de développement.
const List<String> _motifsInterdits = <String>[
  'service_role',
  'SERVICE_ROLE',
  'serviceRole',
  'serviceKey',
  'SUPABASE_SECRET',
  'sb_secret',
];

Iterable<File> _fichiersDart(Directory racine) => racine
    .listSync(recursive: true)
    .whereType<File>()
    .where((fichier) => fichier.path.endsWith('.dart'));

void main() {
  group('Aucune clé de service dans l\'application', () {
    test('le code de lib/ ne mentionne aucune clé de service', () {
      final coupables = <String>[];

      for (final fichier in _fichiersDart(Directory('lib'))) {
        final contenu = fichier.readAsStringSync();
        for (final motif in _motifsInterdits) {
          // Le commentaire qui explique l'interdiction a le droit d'exister :
          // on cherche un usage, pas le mot dans une phrase de prose.
          final lignes = contenu
              .split('\n')
              .where((ligne) => ligne.contains(motif))
              .where((ligne) => !ligne.trimLeft().startsWith('//'))
              .where((ligne) => !ligne.trimLeft().startsWith('///'));
          for (final ligne in lignes) {
            coupables.add('${fichier.path} : ${ligne.trim()}');
          }
        }
      }

      expect(coupables, isEmpty, reason: coupables.join('\n'));
    });

    test('la configuration d\'environnement ne porte que la clé anon', () {
      const env = Env(
        supabaseUrl: 'https://exemple.supabase.co',
        supabaseAnonKey: 'anon',
        firebaseProjectId: '',
        appEnv: Env.devEnv,
      );

      // Le type lui-même ne peut pas transporter de secret : ses champs sont
      // connus et se lisent ici en entier.
      expect(env.toString(), isNot(contains('service')));
      expect(
        Env.supabaseAnonKeyKey,
        'SUPABASE_ANON_KEY',
        reason: 'La seule clé Supabase injectée à la compilation.',
      );
    });

    test('env/ ne contient aucune clé de service', () {
      for (final fichier in Directory(
        'env',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
        final contenu = fichier.readAsStringSync();
        for (final motif in _motifsInterdits) {
          expect(
            contenu,
            isNot(contains(motif)),
            reason: '${fichier.path} contient « $motif ».',
          );
        }
      }
    });
  });
}
