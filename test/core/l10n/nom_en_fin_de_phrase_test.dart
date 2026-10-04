import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un nom d'usage finit souvent par une initiale abrégée (« Chloé C. ») :
/// la phrase qui le place en dernier ne doit pas doubler le point.
void main() {
  group('nomEnFinDePhrase', () {
    test('ajoute le point final à un nom sans point', () {
      expect(AppStrings.nomEnFinDePhrase('Marie'), 'Marie.');
    });

    test('ne double pas le point d\'une initiale abrégée', () {
      expect(AppStrings.nomEnFinDePhrase('Chloé C.'), 'Chloé C.');
    });
  });

  group('phrases finissant par un nom', () {
    const abrege = 'Chloé C.';
    const complet = 'Marc Dupont';

    final phrases = <String, String Function(String)>{
      'invitationParQui': AppStrings.invitationParQui,
      'planningModifieDistant': AppStrings.planningModifieDistant,
      'echangeInfoValidation': AppStrings.echangeInfoValidation,
      'echangeEnvoyeeA': AppStrings.echangeEnvoyeeA,
      'echangeDetailEnvoyeeAdmin': (nom) =>
          AppStrings.echangeDetailEnvoyeeAdmin('il y a 2 h', nom),
      'echangeDetailRefuseChef': AppStrings.echangeDetailRefuseChef,
      'echangeDetailAnnuleAdmin': AppStrings.echangeDetailAnnuleAdmin,
      'echangeRefusEnvoye': AppStrings.echangeRefusEnvoye,
    };

    for (final MapEntry(key: cle, value: phrase) in phrases.entries) {
      test('$cle : un seul point après une initiale abrégée', () {
        final texte = phrase(abrege);
        expect(texte, endsWith('Chloé C.'));
        expect(texte, isNot(contains('..')));
      });

      test('$cle : point final après un nom complet', () {
        expect(phrase(complet), endsWith('Marc Dupont.'));
      });
    }

    test('textes exacts', () {
      expect(AppStrings.echangeEnvoyeeA(abrege), 'Demande envoyée à Chloé C.');
      expect(
        AppStrings.invitationParQui(complet),
        'Invitation envoyée par Marc Dupont.',
      );
      expect(
        AppStrings.echangeInfoValidation(abrege),
        'Ton chef de centre devra valider après l\'accord de Chloé C.',
      );
    });
  });
}
