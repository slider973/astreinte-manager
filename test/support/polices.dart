import 'dart:io';

import 'package:astreinte_sp/core/theme/app_typography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les trois graisses de texte embarquées, dans l'ordre de `pubspec.yaml`.
const List<String> _graisses = <String>['Regular', 'SemiBold', 'Bold'];

/// Les deux graisses de titre embarquées (Archivo, ticket 061).
const List<String> _graissesTitre = <String>['SemiBold', 'Bold'];

bool _chargees = false;

/// Charge la vraie police du produit avant une mesure de texte.
///
/// `flutter test` compose par défaut avec une police d'essai dont **chaque
/// glyphe est un carré** de la taille du corps. Elle est près de deux fois
/// plus large que l'Atkinson embarquée : une phrase qui tient à l'écran y
/// déborde, et une phrase qu'on aurait raccourcie pour elle serait mutilée
/// pour rien. Toute assertion sur un débordement, une coupure ou une largeur
/// de texte doit donc composer avec la police que le produit livre.
///
/// Les fichiers sont ceux déclarés dans `pubspec.yaml`, lus depuis la racine
/// du paquet — le répertoire courant d'un test. Le chargement est mondial à
/// l'isolat : il n'a lieu qu'une fois, même appelé par chaque test.
Future<void> chargerPolicesDuProduit() async {
  if (_chargees) return;

  Future<void> charger(String famille, List<String> graisses) async {
    final loader = FontLoader(famille);
    for (final graisse in graisses) {
      final octets = File(
        'assets/fonts/$famille-$graisse.ttf',
      ).readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(octets)));
    }
    await loader.load();
  }

  await charger(AppFonts.texte, _graisses);
  // Les titres ont leur propre famille depuis le ticket 061 : sans elle, une
  // mesure de titre composerait avec la police d'essai carrée, c'est-à-dire
  // avec autre chose que ce que le produit livre.
  await charger(AppFonts.titre, _graissesTitre);
  _chargees = true;
}
