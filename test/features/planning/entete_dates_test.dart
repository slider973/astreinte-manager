import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/entete_dates.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/geometrie_matrice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/widgets/helpers.dart';
import '../../support/polices.dart';

/// Le fond peint de la pastille d'une date : c'est lui qui dit « aujourd'hui ».
Color? _fond(WidgetTester tester, int jour) {
  final boite = tester.widget<DecoratedBox>(
    find
        .ancestor(
          of: find.text('$jour'),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (boite.decoration as BoxDecoration).color;
}

FontWeight? _graisse(WidgetTester tester, String abreviation) =>
    tester.widget<Text>(find.text(abreviation).first).style?.fontWeight;

Future<void> _monterLEnTete(
  WidgetTester tester,
  DateTime date, {
  double echelleTexte = 1,
}) async {
  // **Les vraies polices, sinon la mesure ne vaut rien** : l'en-tête est
  // borné à 60 points et ce fichier vérifie qu'il y tient.
  await chargerPolicesDuProduit();
  await monter(
    tester,
    Align(
      alignment: Alignment.topLeft,
      child: EnteteJour(date: date, aujourdhui: DateTime(2026, 10, 14)),
    ),
    echelleTexte: echelleTexte,
    taille: const Size(1440, 900),
  );
}

void main() {
  group('EnteteJour — la pastille de date', () {
    testWidgets('le jour courant porte la pastille indigo, les autres non', (
      tester,
    ) async {
      final scheme = AppTheme.clair.colorScheme;

      // Le 14 octobre 2026 est un mercredi : c'est le jour courant.
      await _monterLEnTete(tester, DateTime(2026, 10, 14));
      expect(_fond(tester, 14), scheme.primaryContainer);

      // Le 15, un jeudi ordinaire : rien du tout. Le fond `surface-dim` du
      // weekend, lui, est peint par `FondJour` sur la colonne entière.
      await _monterLEnTete(tester, DateTime(2026, 10, 15));
      expect(_fond(tester, 15), Colors.transparent);
    });

    testWidgets('l\'abréviation du jour accompagne son numéro, et le weekend '
        'se dit aussi par la graisse', (tester) async {
      // Le 17 octobre 2026 est un samedi.
      await _monterLEnTete(tester, DateTime(2026, 10, 17));
      expect(find.text(AppStrings.grilleJoursCourts[5]), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      expect(_graisse(tester, AppStrings.grilleJoursCourts[5]), FontWeight.w700);

      // Le 15, un jeudi : graisse ordinaire.
      await _monterLEnTete(tester, DateTime(2026, 10, 15));
      expect(_graisse(tester, AppStrings.grilleJoursCourts[3]), FontWeight.w400);
    });

    testWidgets('un jour férié garde son étoile et son nom annoncé', (
      tester,
    ) async {
      // 1er novembre 2026 : la Toussaint, un dimanche.
      await _monterLEnTete(tester, DateTime(2026, 11));

      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          <String>[
            dateAvecJourSemaine(DateTime(2026, 11)),
            AppStrings.jourFerieNomme('Toussaint'),
          ].join(', '),
        ),
        findsOneWidget,
      );
    });

    testWidgets('l\'en-tête ne se touche pas : il nomme, il ne commande pas', (
      tester,
    ) async {
      final poignee = tester.ensureSemantics();
      await _monterLEnTete(tester, DateTime(2026, 10, 14));

      // Aucun geste : la bande de semaine du 061b amenait une colonne au bord
      // gauche, ce que le 061c a retiré (l'en-tête est le repère, pas la
      // commande).
      expect(find.byType(InkWell), findsNothing);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            <String>[
              dateAvecJourSemaine(DateTime(2026, 10, 14)),
              AppStrings.jourAujourdhui,
            ].join(', '),
          ),
        ),
        isNot(containsSemantics(isButton: true)),
      );
      poignee.dispose();
    });

    testWidgets('les deux icônes de créneau restent sous la pastille', (
      tester,
    ) async {
      await _monterLEnTete(tester, DateTime(2026, 10, 14));

      expect(find.byIcon(Icons.light_mode), findsOneWidget);
      expect(find.byIcon(Icons.bedtime), findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(Icons.light_mode)).dy,
        greaterThan(tester.getCenter(find.text('14')).dy),
      );
    });
  });

  group('EnteteJour — la mesure', () {
    testWidgets('il tient dans ses 60 points, et 64 est le plafond', (
      tester,
    ) async {
      await _monterLEnTete(tester, DateTime(2026, 11));

      // Le plafond posé par le chantier : au-delà, la colonne figée et la
      // grille perdraient plus de hauteur que la bande n'en rendait.
      expect(GeoMatrice.hauteurEntete, lessThanOrEqualTo(64));
      expect(
        tester.getSize(find.byType(EnteteJour)).height,
        GeoMatrice.hauteurEntete,
      );
      // Composé avec les vraies polices, rien ne déborde.
      expect(tester.takeException(), isNull);
    });

    testWidgets('à grande échelle de texte, la date se resserre au lieu de '
        'déborder', (tester) async {
      await _monterLEnTete(tester, DateTime(2026, 10, 14), echelleTexte: 1.6);

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(EnteteJour)).height,
        GeoMatrice.hauteurEntete,
      );
    });
  });
}
