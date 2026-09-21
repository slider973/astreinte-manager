import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/telechargement.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/presentation/widgets/bouton_ajout_calendrier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_export.dart';

/// « Ajouter cette astreinte » depuis son détail (ticket 028).
///
/// Ce qui se vérifie ici n'est pas le format du fichier —
/// `ics_astreinte_test.dart` s'en charge — mais **le geste** : un bouton par
/// créneau, un fichier remis par le mécanisme du ticket 034, et ce que l'écran
/// dit ensuite. Dans une PWA installée il n'y a pas de barre de téléchargement :
/// si l'écran ne nomme pas le fichier, rien ne le fait.
void main() {
  final aujourdhui = DateTime(2026, 10, 15, 9);
  const lien = '/schedule/2026-10';

  /// Le 17 octobre, de nuit **et** de jour : la feuille d'une journée à deux
  /// créneaux, celle qui montre que les boutons ne se confondent pas.
  List<Astreinte> deuxCreneaux() => <Astreinte>[
    astreinte(id: 'a-nuit', creneauId: 'c-nuit', jour: DateTime(2026, 10, 17)),
    astreinte(
      id: 'a-jour',
      creneauId: 'c-jour',
      jour: DateTime(2026, 10, 17),
      creneau: CreneauType.jour,
    ),
  ];

  Future<FauxTelechargement> ouvrirDetail(
    WidgetTester tester, {
    FauxTelechargement? telechargement,
    List<Astreinte>? astreintes,
  }) async {
    final fichiers = telechargement ?? FauxTelechargement();
    await monterApp(
      tester,
      session: sessionMembre,
      appartenances: const <Appartenance>[appartenanceMembre],
      astreintes: FauxAstreintesRepository(
        astreintes: astreintes ?? deuxCreneaux(),
      ),
      cacheAstreintes: CacheAstreintesMemoire(),
      telechargement: fichiers,
      horloge: () => aujourdhui,
    );
    await ouvrirRoute(tester, lien);
    // **Par le calendrier**, et pas par la liste : une case porte la journée
    // entière, donc les deux créneaux du 17. C'est la configuration où les deux
    // boutons se côtoient, celle qu'il faut éprouver.
    await tester.tap(find.text(AppStrings.astreintesVueCalendrier));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsLabel('samedi 17 octobre, jour et nuit. Voir le détail.'),
    );
    await tester.pumpAndSettle();
    return fichiers;
  }

  group('Ajouter une astreinte à son agenda', () {
    testWidgets('un bouton par créneau, pas un par feuille', (
      WidgetTester tester,
    ) async {
      await ouvrirDetail(tester);

      // La journée porte deux créneaux : un bouton unique ne saurait pas lequel
      // enregistrer (`design/028-export-ics.md § 6`).
      expect(find.byType(BoutonAjoutCalendrier), findsNWidgets(2));
      expect(find.text(AppStrings.calendrierAjouterUne), findsNWidgets(2));

      // Et ils ne se confondent pas à l'oreille : l'annoncé porte la date et le
      // créneau, le libellé visible reste court.
      expect(
        find.bySemanticsLabel('Ajouter samedi 17 octobre, jour, à mon agenda'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Ajouter samedi 17 octobre, nuit, à mon agenda'),
        findsOneWidget,
      );
    });

    testWidgets('remet un fichier calendrier, et le nomme', (
      WidgetTester tester,
    ) async {
      final fichiers = await ouvrirDetail(tester);

      await tester.tap(
        find.bySemanticsLabel('Ajouter samedi 17 octobre, nuit, à mon agenda'),
      );
      await tester.pumpAndSettle();

      expect(fichiers.fichiers, hasLength(1));
      final remis = fichiers.dernier!;
      expect(remis.nom, 'astreinte-2026-10-17-nuit.ics');
      // Le type MIME compte : c'est lui qui fait proposer l'agenda dans la
      // feuille de partage d'un iPhone.
      expect(remis.typeMime, 'text/calendar');
      expect(remis.contenu, contains('BEGIN:VCALENDAR'));
      expect(remis.contenu, contains('UID:a-nuit@astreinte-sp'));
      expect(
        remis.contenu,
        contains('SUMMARY:Astreinte nuit — CIS Saint-Martin'),
      );

      // L'écran nomme le fichier : sans lui, personne ne sait où le retrouver.
      expect(
        find.text(
          AppStrings.calendrierAjoutEnregistre('astreinte-2026-10-17-nuit.ics'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('seul le bouton touché parle', (WidgetTester tester) async {
      await ouvrirDetail(tester);

      await tester.tap(
        find.bySemanticsLabel('Ajouter samedi 17 octobre, jour, à mon agenda'),
      );
      await tester.pumpAndSettle();

      // Une seule confirmation, sous le créneau touché — pas deux.
      expect(
        find.text(
          AppStrings.calendrierAjoutEnregistre('astreinte-2026-10-17-jour.ics'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('astreinte-2026-10-17-nuit.ics'),
        findsNothing,
      );
    });

    testWidgets('le partage système est une réussite, dite autrement', (
      WidgetTester tester,
    ) async {
      await ouvrirDetail(
        tester,
        telechargement: FauxTelechargement(
          resultat: ResultatTelechargement.partage,
        ),
      );

      await tester.tap(find.text(AppStrings.calendrierAjouterUne).first);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.calendrierAjoutPartage), findsOneWidget);
    });

    /// Un partage refermé sans rien faire n'est **pas** une panne : c'est un
    /// choix, et annoncer une erreur à qui vient d'annuler lui apprend à ne
    /// plus lire les messages (`design/034-rgpd-export.md § 4`).
    testWidgets('un partage annulé ne dit rien', (WidgetTester tester) async {
      await ouvrirDetail(
        tester,
        telechargement: FauxTelechargement(
          resultat: ResultatTelechargement.annule,
        ),
      );

      await tester.tap(find.text(AppStrings.calendrierAjouterUne).first);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.calendrierAjoutImpossible), findsNothing);
      expect(find.textContaining('Fichier enregistré'), findsNothing);
    });

    testWidgets('un enregistrement impossible le dit, et dit quoi faire', (
      WidgetTester tester,
    ) async {
      await ouvrirDetail(
        tester,
        telechargement: FauxTelechargement(
          resultat: ResultatTelechargement.impossible,
        ),
      );

      await tester.tap(find.text(AppStrings.calendrierAjouterUne).first);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.calendrierAjoutImpossible), findsOneWidget);
    });

    /// La feuille de détail **ne charge rien** (ticket 027) : ce bouton non
    /// plus. Le fichier est composé sur l'appareil, donc il marche hors ligne.
    testWidgets('n\'appelle pas le serveur', (WidgetTester tester) async {
      final astreintes = FauxAstreintesRepository(astreintes: deuxCreneaux());
      final fichiers = FauxTelechargement();

      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        astreintes: astreintes,
        cacheAstreintes: CacheAstreintesMemoire(),
        telechargement: fichiers,
        horloge: () => aujourdhui,
      );
      await ouvrirRoute(tester, lien);
      await tester.tap(find.text(AppStrings.astreintesVueCalendrier));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel(
          'samedi 17 octobre, jour et nuit. Voir le détail.',
        ),
      );
      await tester.pumpAndSettle();

      final avant = astreintes.lectures;
      await tester.tap(find.text(AppStrings.calendrierAjouterUne).first);
      await tester.pumpAndSettle();

      expect(astreintes.lectures, avant);
      expect(fichiers.fichiers, hasLength(1));
    });
  });
}
