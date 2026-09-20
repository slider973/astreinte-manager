import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Widget _ossature({
  bool admin = false,
  int propositions = 0,
  AppBanner? banniere,
  ValueChanged<int>? onDestination,
}) {
  return AppScaffold(
    titre: 'Octobre 2026',
    destinations: AppDestination.pour(
      admin: admin,
      propositionsEnAttente: propositions,
    ),
    indexSelectionne: 0,
    onDestination: onDestination ?? (_) {},
    banniere: banniere,
    child: const Center(child: Text('Contenu')),
  );
}

void main() {
  group('AppDestination', () {
    test('un membre a quatre destinations, un admin cinq', () {
      expect(AppDestination.pour(admin: false).length, 4);
      expect(AppDestination.pour(admin: true).length, 5);
    });

    test('l\'ordre est celui de DESIGN.md', () {
      expect(
        AppDestination.pour(admin: true).map((d) => d.libelle).toList(),
        <String>[
          AppStrings.navMonMois,
          AppStrings.navPropositions,
          AppStrings.navPlanning,
          AppStrings.navProfil,
          AppStrings.navAdmin,
        ],
      );
    });

    test('chaque destination a deux icônes distinctes', () {
      for (final destination in AppDestination.pour(admin: true)) {
        expect(
          destination.icone,
          isNot(destination.iconeSelectionnee),
          reason: '${destination.libelle} : icônes identiques.',
        );
      }
    });
  });

  group('AppScaffold — composition', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} : compact utilise la barre basse', (
        tester,
      ) async {
        await monterEcran(tester, _ossature(), brightness: brightness);

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
        expect(find.text('Contenu'), findsOneWidget);
      });
    }

    testWidgets('medium utilise le rail', (tester) async {
      await monterEcran(tester, _ossature(), taille: const Size(700, 900));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('expanded étend le rail', (tester) async {
      await monterEcran(
        tester,
        _ossature(admin: true),
        taille: const Size(900, 900),
      );

      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue,
      );
    });

    testWidgets('les libellés sont toujours visibles', (tester) async {
      await monterEcran(tester, _ossature());

      final barre = tester.element(find.byType(NavigationBar));
      expect(
        NavigationBarTheme.of(barre).labelBehavior,
        NavigationDestinationLabelBehavior.alwaysShow,
      );
      expect(find.text(AppStrings.navMonMois), findsOneWidget);
      expect(find.text(AppStrings.navPropositions), findsOneWidget);
    });

    testWidgets('la bannière se place entre la barre et le contenu', (
      tester,
    ) async {
      await monterEcran(
        tester,
        _ossature(
          banniere: const AppBanner(
            variante: AppBannerVariante.information,
            texte: AppStrings.periodeOuverte,
          ),
        ),
      );

      expect(find.byType(AppBanner), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(AppBanner)).dy,
        lessThan(tester.getTopLeft(find.text('Contenu')).dy),
      );
    });

    testWidgets('plus de cinq destinations est une erreur de programmation', (
      tester,
    ) async {
      await monterEcran(
        tester,
        AppScaffold(
          titre: 'Trop',
          destinations: <AppDestination>[
            ...AppDestination.pour(admin: true),
            const AppDestination(
              libelle: 'En trop',
              icone: Icons.star_border,
              iconeSelectionnee: Icons.star,
              route: 'trop',
            ),
          ],
          indexSelectionne: 0,
          onDestination: (_) {},
          child: const SizedBox.shrink(),
        ),
      );

      expect(tester.takeException(), isAssertionError);
    });
  });

  group('AppScaffold — pastille de propositions', () {
    testWidgets('aucune pastille à zéro', (tester) async {
      await monterEcran(tester, _ossature());
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('une pastille chiffrée à trois', (tester) async {
      await monterEcran(tester, _ossature(propositions: 3));

      expect(find.byType(Badge), findsWidgets);
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('le compte est plafonné à « 9+ » mais annoncé en entier', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monterEcran(tester, _ossature(propositions: 12));

      expect(find.text('9+'), findsWidgets);
      // Le libellé complet est fusionné dans la destination : on le cherche
      // dans le nœud, pas en égalité stricte.
      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape(AppStrings.navPropositionsBadge(12))),
        ),
        findsWidgets,
      );

      handle.dispose();
    });
  });

  group('AppScaffold — zones sûres et navigation', () {
    testWidgets('la barre d\'accueil iOS s\'ajoute à la hauteur de la nav', (
      tester,
    ) async {
      await monterEcran(tester, _ossature());
      final sansZone = tester
          .getSize(find.byType(NavigationBar).hitTestable())
          .height;

      await monterEcran(
        tester,
        _ossature(),
        viewPadding: const EdgeInsets.only(bottom: 34),
      );
      final barre = find.byType(NavigationBar);
      final bas = tester.getBottomLeft(barre).dy;

      expect(sansZone, greaterThan(0));
      // Le contenu de la barre s'arrête 34 dp au-dessus du bas de l'écran.
      expect(bas, lessThanOrEqualTo(844 - 34));
    });

    testWidgets('sélectionner une destination remonte son index', (
      tester,
    ) async {
      var dernier = -1;
      await monterEcran(
        tester,
        _ossature(onDestination: (index) => dernier = index),
      );

      await tester.tap(find.text(AppStrings.navPlanning));
      await tester.pumpAndSettle();
      expect(dernier, 2);
    });

    testWidgets('tient une échelle de texte de 2.0', (tester) async {
      await monterEcran(tester, _ossature(admin: true), echelleTexte: 2);

      expect(tester.takeException(), isNull);
    });
  });
}
