import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/domain/raccourci.dart';
import 'package:astreinte_sp/features/dispos/presentation/widgets/barre_raccourcis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';

CreneauCle jour(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.jour);
CreneauCle nuit(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.nuit);

const Duration apresLeDelai = Duration(milliseconds: 600);

Future<void> ouvrirMois(
  WidgetTester tester, {
  FauxDisposRepository? depot,
  Size taille = const Size(390, 844),
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    dispos: depot ?? FauxDisposRepository(),
    reperes: ReperesLocauxMemoire(<RepereAccueil>{
      RepereAccueil.peintureDispos,
    }),
    taille: taille,
  );
  // Le Calendrier a sa route depuis le ticket 064 : `/` porte le tableau de
  // bord.
  await ouvrirRoute(tester, AppRoutes.calendrier);
}

/// Amène un bouton de portée sous le doigt — la bande défile — puis l'ouvre.
Future<void> ouvrirPortee(WidgetTester tester, PorteeRaccourci portee) async {
  final bouton = find.text(portee.libelle);
  await tester.ensureVisible(bouton);
  await tester.pumpAndSettle();
  await tester.tap(bouton);
  await tester.pumpAndSettle();
}

/// Un texte **dans la feuille** : « Jour » et « Nuit » vivent aussi dans
/// l'en-tête de colonnes de la grille, qui reste à l'écran derrière elle.
Finder dansLaFeuille(String texte) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(texte));

/// Choisit un créneau dans la feuille ouverte.
Future<void> choisirCible(WidgetTester tester, CibleCreneau cible) async {
  await tester.tap(dansLaFeuille(cible.libelle));
  await tester.pumpAndSettle();
}

Map<CreneauCle, DisponibiliteEtat> moisComplet() {
  final valeurs = <CreneauCle, DisponibiliteEtat>{};
  for (var numero = 1; numero <= 31; numero++) {
    valeurs[jour(numero)] = DisponibiliteEtat.disponible;
    valeurs[nuit(numero)] = DisponibiliteEtat.disponible;
  }
  return valeurs;
}

void main() {
  group('La bande de raccourcis', () {
    testWidgets('affiche les cinq portées au-dessus de la grille', (
      tester,
    ) async {
      await ouvrirMois(tester);

      expect(find.byType(BarreRaccourcis), findsOneWidget);
      for (final portee in PorteeRaccourci.values) {
        expect(find.text(portee.libelle), findsOneWidget);
      }
    });

    testWidgets('la feuille propose jour, nuit et les deux avec leur coût', (
      tester,
    ) async {
      await ouvrirMois(tester);
      await ouvrirPortee(tester, PorteeRaccourci.weekends);

      expect(find.text(AppStrings.raccourciWeekendsDetail), findsOneWidget);
      expect(dansLaFeuille(AppStrings.raccourciCibleJour), findsOneWidget);
      expect(dansLaFeuille(AppStrings.raccourciCibleNuit), findsOneWidget);
      expect(dansLaFeuille(AppStrings.raccourciCibleLesDeux), findsOneWidget);
      // 9 cases pour un créneau, 18 pour les deux.
      expect(
        dansLaFeuille(AppStrings.raccourciCasesConcernees(9)),
        findsNWidgets(2),
      );
      expect(
        dansLaFeuille(AppStrings.raccourciCasesConcernees(18)),
        findsOneWidget,
      );
    });

    testWidgets('« la semaine » + « nuit » coche les 22 nuits de semaine', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      await ouvrirMois(tester, depot: depot);

      await ouvrirPortee(tester, PorteeRaccourci.semaine);
      await choisirCible(tester, CibleCreneau.nuit);
      await tester.pump(apresLeDelai);

      expect(depot.base.length, 22);
      expect(depot.requetes, 1, reason: 'une requête, pas vingt-deux');
      expect(find.text(AppStrings.raccourciResultat(22)), findsNothing);
      expect(
        find.textContaining(AppStrings.raccourciResultat(22)),
        findsOneWidget,
        reason: 'la ligne de résultat annonce le compte',
      );
    });
  });

  group('La confirmation', () {
    testWidgets(
      '« tout effacer » demande confirmation quand le mois est saisi',
      (tester) async {
        final depot = FauxDisposRepository(disponibilites: moisComplet());
        await ouvrirMois(tester, depot: depot);

        await ouvrirPortee(tester, PorteeRaccourci.effacer);
        await choisirCible(tester, CibleCreneau.lesDeux);

        expect(
          find.text(AppStrings.raccourciConfirmerEffacerTitre(62)),
          findsOneWidget,
        );

        await tester.tap(find.text(AppStrings.actionAnnuler));
        await tester.pumpAndSettle();
        await tester.pump(apresLeDelai);

        expect(depot.base.length, 62, reason: 'refuser ne change rien');
        expect(depot.requetes, 0);
      },
    );

    testWidgets('confirmée, elle efface le mois en une requête', (
      tester,
    ) async {
      final depot = FauxDisposRepository(disponibilites: moisComplet());
      await ouvrirMois(tester, depot: depot);

      await ouvrirPortee(tester, PorteeRaccourci.effacer);
      await choisirCible(tester, CibleCreneau.lesDeux);
      await tester.tap(find.text(AppStrings.raccourciConfirmerEffacerAction));
      await tester.pumpAndSettle();
      await tester.pump(apresLeDelai);

      expect(depot.base, isEmpty);
      expect(depot.requetes, 1);
    });

    testWidgets('un mois vierge s\'efface sans confirmation', (tester) async {
      final depot = FauxDisposRepository();
      await ouvrirMois(tester, depot: depot);

      await ouvrirPortee(tester, PorteeRaccourci.effacer);
      await choisirCible(tester, CibleCreneau.lesDeux);

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'rien à protéger : pas de modale',
      );
      expect(find.text(AppStrings.raccourciAucunChangement), findsOneWidget);
    });

    testWidgets('« copier le mois précédent » demande confirmation', (
      tester,
    ) async {
      final depot = FauxDisposRepository(disponibilites: moisComplet());
      await ouvrirMois(tester, depot: depot);

      await ouvrirPortee(tester, PorteeRaccourci.copieMoisPrecedent);
      await choisirCible(tester, CibleCreneau.jour);

      expect(
        find.text(AppStrings.raccourciConfirmerCopieTitre(31)),
        findsOneWidget,
      );
      expect(
        depot.lectures,
        1,
        reason: 'le mois source n\'est lu qu\'après la confirmation',
      );

      await tester.tap(find.text(AppStrings.raccourciConfirmerCopieAction));
      await tester.pumpAndSettle();
      await tester.pump(apresLeDelai);

      expect(depot.lectures, 2, reason: 'une lecture du mois précédent');
      expect(
        depot.base.length,
        31,
        reason: 'les nuits sont intactes, les jours effacés par la copie',
      );
    });
  });

  group('L\'annulation', () {
    testWidgets('la ligne de résultat propose « Annuler » et le fait', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      await ouvrirMois(tester, depot: depot);

      await ouvrirPortee(tester, PorteeRaccourci.weekends);
      await choisirCible(tester, CibleCreneau.nuit);
      await tester.pump(apresLeDelai);
      expect(depot.base.length, 9);

      final annuler = find.text(AppStrings.raccourciAnnulerLabel);
      expect(annuler, findsOneWidget);
      await tester.tap(annuler);
      await tester.pumpAndSettle();
      await tester.pump(apresLeDelai);

      expect(depot.base, isEmpty);
      expect(
        find.text(AppStrings.raccourciAnnulerLabel),
        findsNothing,
        reason: 'un cran, pas un historique',
      );
    });

    testWidgets('elle disparaît dès qu\'une case est touchée à la main', (
      tester,
    ) async {
      await ouvrirMois(tester);

      await ouvrirPortee(tester, PorteeRaccourci.weekends);
      await choisirCible(tester, CibleCreneau.nuit);
      await tester.pump();
      expect(find.text(AppStrings.raccourciAnnulerLabel), findsOneWidget);

      // La case « jour » du 1er octobre : le premier `SlotChip` du registre.
      await tester.tap(find.byType(SlotChip).first);
      await tester.pump();

      expect(
        find.text(AppStrings.raccourciAnnulerLabel),
        findsNothing,
        reason: 'annuler emporterait la retouche : l\'offre tombe',
      );
      await tester.pump(apresLeDelai);
    });
  });

  group('Période verrouillée', () {
    testWidgets('les raccourcis sont inertes et disent pourquoi', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
        disponibilites: moisComplet(),
      );
      await ouvrirMois(tester, depot: depot);

      // La bande reste à sa place : l'écran ne change pas de forme.
      expect(find.byType(BarreRaccourcis), findsOneWidget);
      expect(find.text(AppStrings.raccourcisVerrouilles), findsOneWidget);

      // Le bouton ne répond pas : aucune feuille ne s'ouvre.
      await ouvrirPortee(tester, PorteeRaccourci.effacer);
      expect(find.text(AppStrings.raccourciCibleLesDeux), findsNothing);
      await tester.pump(apresLeDelai);
      expect(depot.requetes, 0);
      expect(depot.base.length, 62);
    });

    testWidgets('leur sémantique les déclare désactivés', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
      );
      await ouvrirMois(tester, depot: depot);

      final semantique = tester.getSemantics(
        find.text(AppStrings.raccourciEffacer),
      );
      expect(semantique, containsSemantics(isButton: true, isEnabled: false));
    });
  });
}
