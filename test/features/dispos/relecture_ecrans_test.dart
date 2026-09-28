import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/dispos/domain/dispos_providers.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/presentation/mois_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';

/// Une horloge qu'on avance à la main : c'est elle qui décide du délai
/// minimal entre deux relectures automatiques.
class Horloge {
  DateTime maintenant = DateTime(2026, 9, 28, 10, 12);

  void avancer(Duration duree) => maintenant = maintenant.add(duree);
}

const Duration apresLIntervalle = Duration(seconds: 11);

/// Septembre et octobre verrouillés : l'état de la caserne du propriétaire
/// avant que l'admin n'ouvre novembre, le 28 septembre 2026 à 10:12.
FauxDisposRepository depotDeProduction() => FauxDisposRepository(
  periodes: <PeriodeSaisie>[
    periodeVerrouillee(annee: 2026, mois: 9),
    periodeVerrouillee(annee: 2026, mois: 10),
  ],
);

PeriodeSaisie novembre() => periodeOuverte(
  annee: 2026,
  mois: 11,
  dateLimite: DateTime(2026, 10, 15, 23, 59, 59),
);

/// Un rangement de la PWA puis son retour, dans l'ordre exact où la
/// plateforme l'envoie. Sur le web, c'est `visibilitychange`.
Future<void> rangerPuisRevenir(WidgetTester tester) async {
  for (final etat in <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(etat);
  }
  await tester.pumpAndSettle();
}

Future<void> monter(
  WidgetTester tester, {
  required FauxDisposRepository depot,
  required Horloge horloge,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    dispos: depot,
    horloge: () => DateTime(2026, 9, 28, 10, 12),
    horlogeRafraichissement: () => horloge.maintenant,
  );
}

/// Vérifie qu'un élément de l'accueil n'existe pas **du tout** : la liste ne
/// construit que ce qui est à l'écran, un simple `findsNothing` ne prouverait
/// rien. On descend jusqu'en bas, on vérifie, et on remonte.
Future<void> verifierAbsent(WidgetTester tester, Finder cible) async {
  await tester.drag(find.byType(ListView), const Offset(0, -4000));
  await tester.pumpAndSettle();
  expect(cible, findsNothing);
  await tester.drag(find.byType(ListView), const Offset(0, 4000));
  await tester.pumpAndSettle();
}

final Finder boutonNovembre = find.text(AppStrings.moisNomEtAnnee(11, 2026));

void main() {
  group('Le Calendrier', () {
    testWidgets('un mois ouvert pendant que l\'app tourne apparaît au retour '
        'au premier plan', (tester) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      await monter(tester, depot: depot, horloge: horloge);
      await ouvrirRoute(tester, AppRoutes.calendrier);
      expect(find.byType(MoisScreen), findsOneWidget);
      expect(boutonNovembre, findsNothing);

      depot.ajouterPeriode(novembre());
      horloge.avancer(apresLIntervalle);
      await rangerPuisRevenir(tester);

      expect(boutonNovembre, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un mois ouvert pendant que l\'app tourne apparaît après un '
        'tirer pour actualiser', (tester) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      await monter(tester, depot: depot, horloge: horloge);
      await ouvrirRoute(tester, AppRoutes.calendrier);
      final lecturesMois = depot.lectures;

      depot.ajouterPeriode(novembre());
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(boutonNovembre, findsOneWidget);
      expect(depot.lectures, greaterThan(lecturesMois));
      expect(tester.takeException(), isNull);
    });

    testWidgets('un ?mois= explicite ne bouge pas quand un nouveau mois '
        's\'ouvre', (tester) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      await monter(tester, depot: depot, horloge: horloge);
      await ouvrirRoute(
        tester,
        '${AppRoutes.calendrier}?${AppRoutes.parametreMois}=2026-09',
      );
      final conteneur = ProviderScope.containerOf(
        tester.element(find.byType(MoisScreen)),
      );
      expect(conteneur.read(periodeCouranteProvider)!.cle, '2026-09');

      depot.ajouterPeriode(novembre());
      horloge.avancer(apresLIntervalle);
      await rangerPuisRevenir(tester);

      expect(boutonNovembre, findsOneWidget);
      expect(conteneur.read(periodeCouranteProvider)!.cle, '2026-09');
      expect(tester.takeException(), isNull);
    });

    testWidgets('l\'ouverture relit la liste si elle a vieilli', (
      tester,
    ) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      await monter(tester, depot: depot, horloge: horloge);

      depot.ajouterPeriode(novembre());
      horloge.avancer(apresLIntervalle);
      await ouvrirRoute(tester, AppRoutes.calendrier);

      expect(boutonNovembre, findsOneWidget);
    });

    testWidgets('trois retours d\'affilée ne font qu\'une lecture', (
      tester,
    ) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      await monter(tester, depot: depot, horloge: horloge);
      await ouvrirRoute(tester, AppRoutes.calendrier);
      final avant = depot.lecturesPeriodes;

      horloge.avancer(apresLIntervalle);
      await rangerPuisRevenir(tester);
      await rangerPuisRevenir(tester);
      await rangerPuisRevenir(tester);

      expect(depot.lecturesPeriodes, avant + 1);
    });

    testWidgets('sans période, l\'écran vide se tire aussi', (tester) async {
      final horloge = Horloge();
      final depot = FauxDisposRepository(periodes: const <PeriodeSaisie>[]);
      await monter(tester, depot: depot, horloge: horloge);
      await ouvrirRoute(tester, AppRoutes.calendrier);
      expect(find.text(AppStrings.moisAucunePeriodeTitre), findsOneWidget);

      depot.ajouterPeriode(novembre());
      await tester.fling(
        find.text(AppStrings.moisAucunePeriodeTitre),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.moisAucunePeriodeTitre), findsNothing);
      expect(boutonNovembre, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('L\'accueil', () {
    final appelNovembre = find.text(
      AppStrings.accueilSaisirMois(AppStrings.moisLongs[10]),
    );

    testWidgets('« Saisir mes disponibilités de novembre » apparaît au retour '
        'au premier plan', (tester) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      await monter(tester, depot: depot, horloge: horloge);
      expect(find.byType(AccueilScreen), findsOneWidget);
      await verifierAbsent(tester, appelNovembre);

      depot.ajouterPeriode(novembre());
      horloge.avancer(apresLIntervalle);
      await rangerPuisRevenir(tester);

      await tester.scrollUntilVisible(appelNovembre, 200);
      expect(appelNovembre, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Saisir mes disponibilités de novembre » apparaît après un '
        'tirer pour actualiser', (tester) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      await monter(tester, depot: depot, horloge: horloge);
      await verifierAbsent(tester, appelNovembre);

      depot.ajouterPeriode(novembre());
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(appelNovembre, 200);
      expect(appelNovembre, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
