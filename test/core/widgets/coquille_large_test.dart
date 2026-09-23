import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/core/widgets/app_scaffold.dart';
import 'package:astreinte_sp/core/widgets/avatar_initiales.dart';
import 'package:astreinte_sp/core/widgets/colonne_navigation.dart';
import 'package:astreinte_sp/core/widgets/entete_travail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/polices.dart';
import 'helpers.dart';

/// Un poste d'administration : la composition de référence du ticket 061b.
const Size _poste = Size(1280, 900);

Widget _ossature({
  int selectionne = 4,
  String? caserne = 'CIS Saint-Martin',
  List<Widget> actions = const <Widget>[],
  List<Widget> actionsEnTete = const <Widget>[],
  ValueChanged<int>? onDestination,
}) => AppScaffold(
  titre: AppStrings.matriceTitre,
  caserne: caserne,
  destinations: AppDestination.pour(admin: true, boiteNonLues: 3),
  indexSelectionne: selectionne,
  onDestination: onDestination ?? (_) {},
  actions: actions,
  actionsEnTete: actionsEnTete,
  child: const Center(child: Text('Contenu')),
);

/// L'encre effective d'un libellé de la colonne : elle vient du
/// `DefaultTextStyle` que `NavigationDrawer` pose autour de lui.
Color? _encreDuLibelle(WidgetTester tester, String libelle) {
  final style = tester.widget<DefaultTextStyle>(
    find
        .ancestor(
          of: find.text(libelle),
          matching: find.byType(DefaultTextStyle),
        )
        .first,
  );
  return style.style.color;
}

void main() {
  group('Colonne de navigation — grand écran', () {
    testWidgets('remplace le rail dès 1280, avec ses cinq destinations', (
      tester,
    ) async {
      await chargerPolicesDuProduit();
      await monterEcran(tester, _ossature(), taille: _poste);

      expect(find.byType(ColonneNavigation), findsOneWidget);
      expect(find.byType(NavigationDrawer), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);

      // Cinq destinations, libellés visibles à côté des icônes.
      expect(find.byType(NavigationDrawerDestination), findsNWidgets(5));
      for (final libelle in <String>[
        AppStrings.navMonMois,
        AppStrings.navPropositions,
        AppStrings.navAstreintes,
        AppStrings.navProfil,
        AppStrings.navAdmin,
      ]) {
        expect(find.text(libelle), findsOneWidget);
      }

      // Le nom du produit en tête de colonne, et sa largeur inchangée.
      expect(find.text(AppStrings.appTitle), findsOneWidget);
      expect(
        tester.getSize(find.byType(ColonneNavigation)).width,
        ColonneNavigation.largeur,
      );
    });

    testWidgets('la destination courante porte la pastille indigo sur toute '
        'la largeur, icône et texte compris', (tester) async {
      await chargerPolicesDuProduit();
      await monterEcran(tester, _ossature(), taille: _poste);

      final scheme = AppTheme.clair.colorScheme;
      final pastilles = tester.widgetList<NavigationIndicator>(
        find.byType(NavigationIndicator),
      );
      expect(pastilles.length, 5);
      for (final pastille in pastilles) {
        expect(pastille.color, scheme.primaryContainer);
        expect(pastille.width, ColonneNavigation.largeur - 24);
      }

      expect(
        tester.widget<NavigationDrawer>(find.byType(NavigationDrawer))
            .selectedIndex,
        4,
      );
      // Le libellé choisi suit son icône sur l'encre de la pastille ; les
      // autres restent en encre secondaire.
      expect(
        _encreDuLibelle(tester, AppStrings.navAdmin),
        scheme.onPrimaryContainer,
      );
      expect(
        _encreDuLibelle(tester, AppStrings.navMonMois),
        scheme.onSurfaceVariant,
      );
    });

    testWidgets('la pastille des propositions reste chiffrée', (tester) async {
      await chargerPolicesDuProduit();
      await monterEcran(tester, _ossature(), taille: _poste);

      expect(find.byType(Badge), findsWidgets);
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('choisir une destination remonte son index', (tester) async {
      await chargerPolicesDuProduit();
      var dernier = -1;
      await monterEcran(
        tester,
        _ossature(onDestination: (int index) => dernier = index),
        taille: _poste,
      );

      await tester.tap(find.text(AppStrings.navAstreintes));
      await tester.pumpAndSettle();
      expect(dernier, 2);
    });

    testWidgets('aucun libellé ne déborde, même à 1.6 d\'échelle', (
      tester,
    ) async {
      await chargerPolicesDuProduit();
      await monterEcran(tester, _ossature(), taille: _poste, echelleTexte: 1.6);

      expect(tester.takeException(), isNull);
    });
  });

  group('En-tête de la zone de travail', () {
    testWidgets('porte le nom de la caserne, puis les actions', (tester) async {
      await chargerPolicesDuProduit();
      await monterEcran(
        tester,
        _ossature(
          actions: <Widget>[
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.refresh),
              tooltip: AppStrings.matriceRafraichir,
            ),
          ],
          actionsEnTete: const <Widget>[AvatarInitiales(nom: 'Jean D.')],
        ),
        taille: _poste,
      );

      expect(find.byType(EnTeteTravail), findsOneWidget);
      expect(find.text('CIS Saint-Martin'), findsOneWidget);
      // Plus de barre d'application pleine largeur au-dessus des deux zones.
      expect(find.byType(AppBar), findsNothing);

      // Les actions de l'écran précèdent la cloche et le compte, et toutes
      // sont à droite du titre.
      final titre = tester.getTopRight(find.text('CIS Saint-Martin')).dx;
      expect(tester.getTopLeft(find.byIcon(Icons.refresh)).dx, greaterThan(titre));
      expect(
        tester.getTopLeft(find.byType(AvatarInitiales)).dx,
        greaterThan(tester.getTopRight(find.byIcon(Icons.refresh)).dx),
      );
    });

    testWidgets('sans nom de caserne, le titre de l\'écran reste', (
      tester,
    ) async {
      await chargerPolicesDuProduit();
      await monterEcran(tester, _ossature(caserne: null), taille: _poste);

      expect(find.text(AppStrings.matriceTitre), findsOneWidget);
    });

    testWidgets('les actions d\'en-tête n\'existent pas sur téléphone', (
      tester,
    ) async {
      await chargerPolicesDuProduit();
      await monterEcran(
        tester,
        _ossature(
          actionsEnTete: const <Widget>[AvatarInitiales(nom: 'Jean D.')],
        ),
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(EnTeteTravail), findsNothing);
      expect(find.byType(AvatarInitiales), findsNothing);
    });
  });

  group('AvatarInitiales', () {
    test('deux initiales au plus, les composés comptent pour deux', () {
      expect(AvatarInitiales.initiales('Dubois Jean-Marc'), 'DJ');
      expect(AvatarInitiales.initiales('Marie L.'), 'ML');
      expect(AvatarInitiales.initiales('ana'), 'A');
      expect(AvatarInitiales.initiales('   '), '');
    });

    testWidgets('sans nom, un glyphe plutôt que deux lettres inventées', (
      tester,
    ) async {
      await monter(tester, const AvatarInitiales(nom: ''));
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });
  });
}
