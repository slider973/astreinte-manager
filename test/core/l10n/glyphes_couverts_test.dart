/// Le garde-fou qu'un carré vide a produit (ticket 064a).
///
/// La flèche `→` (U+2192) était dans la chaîne des heures d'un créneau. Elle
/// n'existe dans **aucune** des quatre coupes Atkinson embarquées dans
/// `assets/fonts/` — seulement dans Archivo, qui ne porte que les trois styles
/// de titre. Les heures étant composées en Atkinson Mono, elles s'affichaient
/// « 19:00 ▯ 07:00 » : vu à l'écran sur la carte indigo de l'accueil.
///
/// Rien ne l'avait attrapé, parce qu'un glyphe absent ne lève pas : Flutter
/// dessine le `.notdef` de la police et continue. D'où ces deux tests, qui
/// lisent la **source** de `AppStrings` — le seul endroit où vit un texte
/// visible (`DESIGN.md § Do's`).
library;

import 'dart:io';

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les caractères non ASCII que les six coupes embarquées portent **toutes**,
/// vérifiés en lisant la table `cmap` de chaque fichier TTF.
///
/// Ajouter une entrée ici veut dire : j'ai ouvert les polices et je l'y ai
/// trouvée. Ce n'est pas une liste de ce qu'on aime écrire, c'est une liste de
/// ce que le produit sait dessiner.
const Set<String> _glyphesCouverts = <String>{
  // Diacritiques français.
  'é', 'è', 'ê', 'ë', 'à', 'â', 'î', 'ï', 'ô', 'ö', 'ù', 'û', 'ü', 'ç', 'œ',
  'É', 'È', 'Ê', 'À', 'Â', 'Î', 'Ô', 'Ù', 'Û', 'Ç', 'Œ',
  // Ponctuation du produit.
  '«', '»', '…', '—', '–', '·', '×', '€', '’',
  // Espace insécable : elle sépare un nombre de son unité. Écrite en code
  // d'échappement, parce qu'une espace invisible dans une liste de glyphes
  // ne se relit pas.
  '\u00A0',
};

/// Ce qu'une chaîne d'heures a le droit de contenir : des chiffres, le
/// deux-points, l'espace, et le tiret demi-cadratin qui sépare les deux bornes.
final RegExp _heuresPermises = RegExp('^[0-9: \u2013]+\$');

/// Les littéraux de chaîne d'un fichier Dart, commentaires exclus.
///
/// Tous les textes du produit sont des littéraux à apostrophes simples dans
/// `AppStrings` ; les concaténations implicites sur plusieurs lignes en font
/// plusieurs, ce qui convient : on regarde les caractères, pas les phrases.
List<String> _litteraux(String source) {
  final sansCommentaires = source
      .split('\n')
      .where((String ligne) => !ligne.trimLeft().startsWith('//'))
      .join('\n');
  return RegExp(r"'((?:[^'\\\n]|\\.)*)'")
      .allMatches(sansCommentaires)
      .map((RegExpMatch m) => m.group(1) ?? '')
      .toList(growable: false);
}

void main() {
  group('Les heures d\'un créneau', () {
    test('ne contiennent que des chiffres, deux-points, espaces et tiret', () {
      for (final paire in <(String, String)>[
        ('07:00', '19:00'),
        ('19:00', '07:00'),
        ('06:30', '18:45'),
      ]) {
        final heures = AppStrings.astreintesIntervalle(paire.$1, paire.$2);
        expect(
          _heuresPermises.hasMatch(heures),
          isTrue,
          reason: '« $heures » porte un caractère que les polices du produit '
              'ne dessinent peut-être pas.',
        );
        expect(
          heures,
          isNot(contains('\u2192')),
          reason: 'la flèche du carré vide ne doit jamais revenir',
        );
      }
    });

    test('la phrase dite, elle, n\'a pas de tiret du tout', () {
      // Un lecteur d'écran ne prononce pas un tiret : la phrase annoncée dit
      // « de 19:00 à 07:00 ».
      expect(
        AppStrings.astreintesIntervalleDit('19:00', '07:00'),
        'de 19:00 à 07:00',
      );
    });
  });

  group('Tous les textes du produit', () {
    test('n\'emploient que des glyphes que les polices embarquées portent', () {
      final source = File('lib/core/l10n/app_strings.dart').readAsStringSync();
      final inconnus = <String, int>{};

      for (final litteral in _litteraux(source)) {
        // Les points de code, et non les unités UTF-16 : un caractère hors du
        // plan de base compterait pour deux moitiés qu'aucune police ne
        // dessine.
        for (final point in litteral.runes) {
          if (point < 0x20 || point > 0x7E) {
            final caractere = String.fromCharCode(point);
            if (!_glyphesCouverts.contains(caractere)) {
              inconnus.update(
                caractere,
                (int n) => n + 1,
                ifAbsent: () => 1,
              );
            }
          }
        }
      }

      expect(
        inconnus,
        isEmpty,
        reason:
            'Caractères hors de la liste vérifiée : '
            '${inconnus.keys.map((String c) => '« $c » '
                '(U+${c.runes.first.toRadixString(16).toUpperCase().padLeft(4, '0')})').join(', ')}. '
            'Ouvre les six fichiers d\'`assets/fonts/`, vérifie qu\'ils le '
            'portent, puis ajoute-le à `_glyphesCouverts`. Un glyphe absent '
            'ne lève pas : il se dessine en carré vide.',
      );
    });
  });
}
