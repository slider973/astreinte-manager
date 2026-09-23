import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/count_stat.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/domain/preferences_mois.dart';
import 'package:astreinte_sp/features/dispos/presentation/widgets/preferences_rangees.dart';
import 'package:astreinte_sp/features/dispos/presentation/widgets/section_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';

const String idOctobre = 'periode-2026-10';
const Duration apresLeDelai = Duration(milliseconds: 600);

CreneauCle jour(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.jour);
CreneauCle nuit(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.nuit);

/// Tous les samedis et dimanches d'octobre 2026, cochés jour et nuit : le cas
/// exact que ce ticket existe pour régler — « je coche tout pour laisser le
/// choix à mon chef ».
///
/// Octobre 2026 commence un jeudi : cinq samedis (3, 10, 17, 24, 31) et
/// quatre dimanches, donc **cinq unités de weekend** — le 31 en forme une à
/// lui seul, son dimanche appartenant à novembre (011 § 6.4).
Map<CreneauCle, DisponibiliteEtat> tousLesWeekends() {
  final valeurs = <CreneauCle, DisponibiliteEtat>{};
  for (var numero = 1; numero <= 31; numero++) {
    final date = DateTime(2026, 10, numero);
    if (date.weekday < DateTime.saturday) continue;
    valeurs[jour(numero)] = DisponibiliteEtat.disponible;
    valeurs[nuit(numero)] = DisponibiliteEtat.disponible;
  }
  return valeurs;
}

Future<void> ouvrir(
  WidgetTester tester, {
  required FauxDisposRepository depot,
  Size taille = const Size(390, 1100),
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    dispos: depot,
    reperes: ReperesLocauxMemoire(<RepereAccueil>{
      RepereAccueil.peintureDispos,
    }),
    taille: taille,
  ); // Le Calendrier a sa route depuis le ticket 064 : `/` porte le tableau de
  // bord.
  await ouvrirRoute(tester, AppRoutes.calendrier);
}

int compteur(WidgetTester tester, String libelle) =>
    tester.widget<CountStat>(find.widgetWithText(CountStat, libelle)).valeur;

/// La rangée de plafond, et non le compteur du même nom : « Weekends » est
/// écrit aux deux endroits, et c'est voulu — c'est le même chiffre.
Finder rangee(String libelle) => find.widgetWithText(RangeePlafond, libelle);

int? plafondDe(WidgetTester tester, String libelle) =>
    tester.widget<CountStat>(find.widgetWithText(CountStat, libelle)).plafond;

void main() {
  group('La section des maximums — quand elle se montre', () {
    testWidgets('absente tant que le mois est vierge', (tester) async {
      await ouvrir(tester, depot: FauxDisposRepository());

      expect(
        find.byType(SectionPreferences),
        findsNothing,
        reason:
            'rien de coché, rien à plafonner : le bloc d\'aide du 011 '
            'tient le haut de l\'écran',
      );
    });

    testWidgets('apparaît dès la première case cochée', (tester) async {
      await ouvrir(tester, depot: FauxDisposRepository());
      expect(find.byType(SectionPreferences), findsNothing);

      await tester.tap(find.byType(SlotChip).first);
      await tester.pump();

      expect(
        find.byType(SectionPreferences),
        findsOneWidget,
        reason:
            'la question « combien j\'en veux » naît avec la première '
            'réponse à « quand je peux »',
      );
      await tester.pump(apresLeDelai);
    });

    testWidgets('présente dès qu\'une case est cochée en base', (tester) async {
      await ouvrir(
        tester,
        depot: FauxDisposRepository(disponibilites: tousLesWeekends()),
      );

      expect(find.byType(SectionPreferences), findsOneWidget);
      expect(find.text(AppStrings.preferencesTitre), findsOneWidget);
      expect(
        find.text(AppStrings.preferencesSansLimite),
        findsOneWidget,
        reason: 'sans ligne enregistrée, le défaut est écrit en toutes lettres',
      );
      expect(
        find.text(AppStrings.preferencesLecon),
        findsOneWidget,
        reason: 'la leçon arrive quand elle a du sens',
      );
    });

    testWidgets('la leçon disparaît une fois le membre prononcé', (
      tester,
    ) async {
      await ouvrir(
        tester,
        depot: FauxDisposRepository(
          disponibilites: tousLesWeekends(),
          preferences: <String, PreferencesMois>{
            idOctobre: const PreferencesMois(maxWeekends: 1),
          },
        ),
      );

      expect(find.byType(SectionPreferences), findsOneWidget);
      expect(find.text(AppStrings.preferencesLecon), findsNothing);
      expect(find.text(AppStrings.preferencesValeurs(null, 1)), findsOneWidget);
    });
  });

  group('La section des maximums — l\'écart', () {
    testWidgets('quatre weekends cochés pour un voulu : la phrase y est', (
      tester,
    ) async {
      await ouvrir(
        tester,
        depot: FauxDisposRepository(
          disponibilites: tousLesWeekends(),
          preferences: <String, PreferencesMois>{
            idOctobre: const PreferencesMois(maxWeekends: 1),
          },
        ),
      );

      expect(compteur(tester, AppStrings.compteurWeekends), 5);
      expect(
        find.text(AppStrings.preferencesEcartWeekends(5, 1)),
        findsOneWidget,
        reason: 'l\'écart est expliqué, jamais reproché',
      );
    });

    testWidgets('aucun écart, aucune phrase', (tester) async {
      await ouvrir(
        tester,
        depot: FauxDisposRepository(
          disponibilites: tousLesWeekends(),
          preferences: <String, PreferencesMois>{
            idOctobre: const PreferencesMois(maxWeekends: 5),
          },
        ),
      );

      expect(
        find.text(AppStrings.preferencesEcartWeekends(5, 5)),
        findsNothing,
      );
    });
  });

  group('La section des maximums — le lien avec les compteurs', () {
    testWidgets('le compteur des weekends porte le plafond', (tester) async {
      await ouvrir(
        tester,
        depot: FauxDisposRepository(
          disponibilites: tousLesWeekends(),
          preferences: <String, PreferencesMois>{
            idOctobre: const PreferencesMois(maxAstreintes: 4, maxWeekends: 1),
          },
        ),
      );

      expect(plafondDe(tester, AppStrings.compteurWeekends), 1);
      expect(
        plafondDe(tester, AppStrings.compteurJours),
        isNull,
        reason: 'le maximum d\'astreintes porte sur la somme, pas sur un terme',
      );
      expect(plafondDe(tester, AppStrings.compteurNuits), isNull);
    });

    testWidgets('sans plafond, le compteur reste nu', (tester) async {
      await ouvrir(
        tester,
        depot: FauxDisposRepository(disponibilites: tousLesWeekends()),
      );

      expect(plafondDe(tester, AppStrings.compteurWeekends), isNull);
      expect(find.text(AppStrings.compteurIllimite), findsNothing);
    });

    testWidgets('la barre annonce les maximums en plus des totaux', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await ouvrir(
        tester,
        depot: FauxDisposRepository(
          disponibilites: tousLesWeekends(),
          preferences: <String, PreferencesMois>{
            idOctobre: const PreferencesMois(maxAstreintes: 4, maxWeekends: 1),
          },
        ),
      );

      expect(
        find.bySemanticsLabel(
          AppStrings.compteursResume(9, 9, 5) +
              AppStrings.compteursResumeMaximums(4, 1),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('La section des maximums — poser une valeur', () {
    testWidgets('la feuille pose un plafond, qui part tout seul', (
      tester,
    ) async {
      final depot = FauxDisposRepository(disponibilites: tousLesWeekends());
      await ouvrir(tester, depot: depot);

      // La forme compacte s'ouvre d'une touche sur toute sa largeur.
      await tester.tap(find.text(AppStrings.preferencesTitre));
      await tester.pumpAndSettle();
      expect(find.byType(RangeePlafond), findsNWidgets(2));

      await tester.tap(rangee(AppStrings.preferencesWeekends));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.preferencesFeuilleWeekends), findsOneWidget);

      await tester.tap(find.text('1 weekend au maximum'));
      await tester.pumpAndSettle();
      await tester.pump(apresLeDelai);

      expect(depot.basePreferences[idOctobre]!.maxWeekends, 1);
      expect(plafondDe(tester, AppStrings.compteurWeekends), 1);
    });

    testWidgets('la feuille sait revenir à « autant que nécessaire »', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        disponibilites: tousLesWeekends(),
        preferences: <String, PreferencesMois>{
          idOctobre: const PreferencesMois(maxWeekends: 1),
        },
      );
      await ouvrir(tester, depot: depot);

      await tester.tap(find.text(AppStrings.preferencesTitre));
      await tester.pumpAndSettle();
      await tester.tap(rangee(AppStrings.preferencesWeekends));
      await tester.pumpAndSettle();
      // `.last` : la feuille est la route du dessus, et « autant que
      // nécessaire » est écrit aussi dans la rangée des astreintes en
      // dessous.
      await tester.tap(find.text(AppStrings.preferencesSansLimite).last);
      await tester.pumpAndSettle();
      await tester.pump(apresLeDelai);

      expect(depot.basePreferences[idOctobre]!.maxWeekends, isNull);
      expect(
        depot.basePreferences.containsKey(idOctobre),
        isTrue,
        reason: 'la ligne reste : le membre s\'est prononcé',
      );
      expect(plafondDe(tester, AppStrings.compteurWeekends), isNull);
    });

    testWidgets('la feuille ne propose pas plus de weekends que le mois', (
      tester,
    ) async {
      // Octobre 2026 : cinq unités de weekend, aucun férié en semaine.
      await ouvrir(
        tester,
        depot: FauxDisposRepository(disponibilites: tousLesWeekends()),
      );

      await tester.tap(find.text(AppStrings.preferencesTitre));
      await tester.pumpAndSettle();
      await tester.tap(rangee(AppStrings.preferencesWeekends));
      await tester.pumpAndSettle();

      expect(find.text('5 weekends au maximum'), findsOneWidget);
      expect(find.text('6 weekends au maximum'), findsNothing);
      expect(find.text(AppStrings.preferencesZeroWeekends), findsOneWidget);
    });
  });

  group('La section des maximums — période verrouillée', () {
    testWidgets('lecture seule : les valeurs restent, la raison est dite', (
      tester,
    ) async {
      await ouvrir(
        tester,
        depot: FauxDisposRepository(
          periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
          disponibilites: tousLesWeekends(),
          preferences: <String, PreferencesMois>{
            idOctobre: const PreferencesMois(
              maxAstreintes: 4,
              maxWeekends: 1,
              commentaire: 'Garde des enfants.',
            ),
          },
        ),
      );

      expect(find.byType(SectionPreferences), findsOneWidget);
      expect(find.text(AppStrings.preferencesValeurs(4, 1)), findsOneWidget);
      expect(find.text('Garde des enfants.'), findsOneWidget);

      await tester.tap(find.text(AppStrings.preferencesTitre));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.preferencesVerrouille), findsOneWidget);
      for (final rangee in tester.widgetList<RangeePlafond>(
        find.byType(RangeePlafond),
      )) {
        expect(rangee.actionnable, isFalse);
      }
      expect(
        find.text(AppStrings.preferencesLecon),
        findsNothing,
        reason: 'plus rien à apprendre sur un mois qu\'on ne peut pas changer',
      );
    });

    testWidgets('mois verrouillé sans préférence : rien du tout', (
      tester,
    ) async {
      await ouvrir(
        tester,
        depot: FauxDisposRepository(
          periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
          disponibilites: tousLesWeekends(),
        ),
      );

      expect(
        find.byType(SectionPreferences),
        findsNothing,
        reason: 'poser une question sans réponse possible ne sert personne',
      );
    });
  });
}
