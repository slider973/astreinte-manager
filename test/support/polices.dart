import 'dart:io';

import 'package:astreinte_sp/core/theme/app_typography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les trois graisses embarquées, dans l'ordre de `pubspec.yaml`.
const List<String> _graisses = <String>['Regular', 'SemiBold', 'Bold'];

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

  final loader = FontLoader(AppFonts.texte);
  for (final graisse in _graisses) {
    final octets = File(
      'assets/fonts/${AppFonts.texte}-$graisse.ttf',
    ).readAsBytesSync();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(octets)));
  }
  await loader.load();
  _chargees = true;
}
