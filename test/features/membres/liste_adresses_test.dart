import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/features/membres/domain/liste_adresses.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ListeAdresses', () {
    test('découpe les retours à la ligne, les virgules et les espaces', () {
      final liste = ListeAdresses.depuisSaisie(
        'a@exemple.fr\nb@exemple.fr, c@exemple.fr; d@exemple.fr',
      );

      expect(liste.adresses, <String>[
        'a@exemple.fr',
        'b@exemple.fr',
        'c@exemple.fr',
        'd@exemple.fr',
      ]);
      expect(liste.envoyable, isTrue);
    });

    test('normalise la casse et dédoublonne en gardant l\'ordre', () {
      final liste = ListeAdresses.depuisSaisie(
        'Recrue@Exemple.FR\nrecrue@exemple.fr\nautre@exemple.fr',
      );

      expect(liste.adresses, <String>['recrue@exemple.fr', 'autre@exemple.fr']);
    });

    test('nomme la première adresse incomplète', () {
      final liste = ListeAdresses.depuisSaisie(
        'bon@exemple.fr\npas-une-adresse',
      );

      expect(liste.envoyable, isFalse);
      expect(liste.invalides, <String>['pas-une-adresse']);
      expect(liste.erreur, contains('pas-une-adresse'));
    });

    test('une saisie vide dit quoi faire', () {
      final liste = ListeAdresses.depuisSaisie('   \n  ');

      expect(liste.envoyable, isFalse);
      expect(liste.erreur, AppStrings.inviterAucuneAdresse);
    });

    test('au-delà de vingt adresses, l\'envoi est refusé avant le réseau', () {
      final saisie = List<String>.generate(
        maxAdressesParEnvoi + 1,
        (int index) => 'pompier$index@exemple.fr',
      ).join('\n');

      final liste = ListeAdresses.depuisSaisie(saisie);

      expect(liste.envoyable, isFalse);
      expect(liste.erreur, contains('${maxAdressesParEnvoi + 1}'));
    });

    test('vingt adresses passent', () {
      final saisie = List<String>.generate(
        maxAdressesParEnvoi,
        (int index) => 'pompier$index@exemple.fr',
      ).join(', ');

      expect(ListeAdresses.depuisSaisie(saisie).envoyable, isTrue);
    });
  });
}
