import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('AppBanner — rendu', () {
    for (final brightness in Brightness.values) {
      for (final variante in AppBannerVariante.values) {
        testWidgets('${brightness.name} / ${variante.name} affiche son texte', (
          tester,
        ) async {
          await monter(
            tester,
            AppBanner(variante: variante, texte: 'Un fait à comprendre.'),
            brightness: brightness,
          );

          expect(find.text('Un fait à comprendre.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('chaque variante porte une icône distincte', (tester) async {
      await monter(
        tester,
        const Column(
          children: <Widget>[
            AppBanner(
              variante: AppBannerVariante.erreur,
              texte: 'Impossible d\'enregistrer.',
            ),
            AppBanner(
              variante: AppBannerVariante.horsLigne,
              texte: AppStrings.horsLigneDetail,
            ),
            AppBanner(
              variante: AppBannerVariante.lectureSeule,
              texte: AppStrings.lectureSeuleDetail,
            ),
            AppBanner(
              variante: AppBannerVariante.verrouille,
              texte: AppStrings.periodeVerrouillee,
            ),
            AppBanner(
              variante: AppBannerVariante.attention,
              texte: 'Plus que 2 jours.',
            ),
            AppBanner(
              variante: AppBannerVariante.information,
              texte: AppStrings.periodeOuverte,
            ),
          ],
        ),
      );

      for (final icone in <IconData>[
        Icons.error_outline,
        Icons.cloud_off,
        Icons.visibility,
        Icons.lock,
        Icons.schedule,
        Icons.info_outline,
      ]) {
        expect(find.byIcon(icone), findsOneWidget);
      }
    });

    testWidgets('l\'action est rendue et appelable', (tester) async {
      var appels = 0;
      await monter(
        tester,
        AppBanner(
          variante: AppBannerVariante.erreur,
          texte: 'Impossible d\'enregistrer.',
          libelleAction: AppStrings.actionReessayer,
          onAction: () => appels++,
        ),
      );

      await tester.tap(find.text(AppStrings.actionReessayer));
      expect(appels, 1);
    });
  });

  group('AppBanner — priorité', () {
    test('erreur gagne sur tout le reste', () {
      expect(
        AppBannerVariante.prioritaire(<AppBannerVariante>[
          AppBannerVariante.information,
          AppBannerVariante.erreur,
          AppBannerVariante.verrouille,
        ]),
        AppBannerVariante.erreur,
      );
    });

    test('l\'ordre complet est celui de DESIGN.md', () {
      expect(AppBannerVariante.values, <AppBannerVariante>[
        AppBannerVariante.erreur,
        AppBannerVariante.horsLigne,
        AppBannerVariante.lectureSeule,
        AppBannerVariante.verrouille,
        AppBannerVariante.attention,
        AppBannerVariante.information,
      ]);
    });

    test('une liste vide ne donne aucune bannière', () {
      expect(
        AppBannerVariante.prioritaire(const <AppBannerVariante>[]),
        isNull,
      );
    });

    test('seule « information » est fermable', () {
      for (final variante in AppBannerVariante.values) {
        expect(
          variante.persistante,
          variante != AppBannerVariante.information,
          reason: '${variante.name} : mauvaise persistance.',
        );
      }
    });
  });

  group('AppBanner — accessibilité', () {
    testWidgets('l\'erreur est annoncée sans déplacer le focus', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        AppBanner(
          variante: AppBannerVariante.erreur,
          texte: 'Impossible d\'enregistrer.',
          libelleAction: AppStrings.actionReessayer,
          onAction: () {},
        ),
      );

      expect(
        tester
            .getSemantics(find.byType(AppBanner))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );

      handle.dispose();
    });

    testWidgets('tient une échelle de texte de 2.0', (tester) async {
      await monter(
        tester,
        AppBanner(
          variante: AppBannerVariante.verrouille,
          texte: AppStrings.periodeVerrouilleeDetail('15 septembre'),
        ),
        echelleTexte: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
