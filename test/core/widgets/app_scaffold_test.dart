import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/app_scaffold.dart';
import 'package:astreinte_sp/core/widgets/colonne_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Widget _ossature({
  bool admin = false,
  int nonLues = 0,
  AppBanner? banniere,
  ValueChanged<int>? onDestination,
  Widget? filActions,
  Widget? contenu,
}) {
  return AppScaffold(
    titre: 'Octobre 2026',
    destinations: AppDestination.pour(admin: admin, boiteNonLues: nonLues),
    indexSelectionne: 0,
    onDestination: onDestination ?? (_) {},
    banniere: banniere,
    filActions: filActions,
    child: contenu ?? const Center(child: Text('Contenu')),
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
          AppStrings.navAccueil,
          AppStrings.navCalendrier,
          AppStrings.navAstreintes,
          AppStrings.navBoite,
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

    testWidgets('expanded passe du rail à la colonne de navigation', (
      tester,
    ) async {
      await monterEcran(
        tester,
        _ossature(admin: true),
        taille: const Size(900, 900),
      );

      // Depuis le ticket 061b, le rail étendu **est** la colonne : libellés à
      // côté des icônes, pastille sur toute la largeur de l'élément. Le
      // détail de sa composition est couvert par `coquille_large_test.dart`.
      expect(find.byType(ColonneNavigation), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('les libellés sont toujours visibles', (tester) async {
      await monterEcran(tester, _ossature());

      final barre = tester.element(find.byType(NavigationBar));
      expect(
        NavigationBarTheme.of(barre).labelBehavior,
        NavigationDestinationLabelBehavior.alwaysShow,
      );
      expect(find.text(AppStrings.navAccueil), findsOneWidget);
      expect(find.text(AppStrings.navCalendrier), findsOneWidget);
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
      await monterEcran(tester, _ossature(nonLues: 3));

      expect(find.byType(Badge), findsWidgets);
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('le compte est plafonné à « 9+ » mais annoncé en entier', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monterEcran(tester, _ossature(nonLues: 12));

      expect(find.text('9+'), findsWidgets);
      // Le libellé complet est fusionné dans la destination : on le cherche
      // dans le nœud, pas en égalité stricte.
      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape(AppStrings.centreNonLuesBadge(12))),
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

    // **L'alignement de la barre d'actions** (chantier 064d). Le contenu
    // prend `classe.margePage` — 24 dès `medium` —, la barre d'actions
    // prenait 16 en dur : ses cartes sortaient de huit points par rapport à
    // tout ce qu'elles ferment. Mesuré contre les bords de la zone de
    // contenu, pas contre ceux de la fenêtre : en `medium`, le rail occupe
    // déjà la gauche.
    for (final cas in <(String, Size, double)>[
      ('compact, à 390', const Size(390, 844), 16),
      ('medium, à 768', const Size(768, 1024), 24),
    ]) {
      testWidgets('la barre d\'actions prend la marge de page — ${cas.$1}', (
        tester,
      ) async {
        await monterEcran(
          tester,
          _ossature(
            contenu: const SizedBox.expand(key: Key('corps')),
            filActions: const SizedBox(
              key: Key('actions'),
              height: 40,
              width: double.infinity,
            ),
          ),
          taille: cas.$2,
        );

        final corps = tester.getRect(find.byKey(const Key('corps')));
        final actions = tester.getRect(find.byKey(const Key('actions')));

        expect(actions.left - corps.left, cas.$3, reason: 'marge gauche');
        expect(corps.right - actions.right, cas.$3, reason: 'marge droite');
      });
    }

    testWidgets('sélectionner une destination remonte son index', (
      tester,
    ) async {
      var dernier = -1;
      await monterEcran(
        tester,
        _ossature(onDestination: (index) => dernier = index),
      );

      await tester.tap(find.text(AppStrings.navAstreintes));
      await tester.pumpAndSettle();
      expect(dernier, 2);
    });

    testWidgets('tient une échelle de texte de 2.0', (tester) async {
      await monterEcran(tester, _ossature(admin: true), echelleTexte: 2);

      expect(tester.takeException(), isNull);
    });
  });
}
