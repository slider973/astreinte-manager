import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/profil/data/calendrier_repository.dart';
import 'package:astreinte_sp/features/profil/presentation/widgets/bloc_calendrier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_calendrier.dart';

/// Le bloc « Ajouter à mon calendrier » de l'écran de profil (ticket 028).
///
/// **Le point dur est la révocation.** L'adresse est publique et elle voyage :
/// l'écran doit pouvoir la couper, dire qu'il l'a coupée, et ne jamais laisser
/// croire qu'il l'a fait quand ce n'est pas arrivé.
void main() {
  /// L'adresse composée à partir du jeton du faux dépôt et de `SUPABASE_URL`
  /// de l'environnement de test.
  String adresseAttendue(String jeton) =>
      '${envDeTest.supabaseUrl}/functions/v1/ics-feed/$jeton.ics';

  Future<({FauxCalendrierRepository depot, FauxPressePapiers presse})> ouvrir(
    WidgetTester tester, {
    FauxCalendrierRepository? calendrier,
    FauxPressePapiers? pressePapiers,
  }) async {
    final depot = calendrier ?? FauxCalendrierRepository();
    final presse = pressePapiers ?? FauxPressePapiers();

    await monterApp(
      tester,
      session: sessionMembre,
      appartenances: const <Appartenance>[appartenanceMembre],
      calendrier: depot,
      pressePapiers: presse,
    );
    await tester.tap(find.text(AppStrings.navProfil));
    await tester.pumpAndSettle();
    await defilerJusqua(tester, find.byType(BlocCalendrier));
    return (depot: depot, presse: presse);
  }

  group('Le bloc d\'abonnement calendrier', () {
    testWidgets('montre l\'adresse en entier, et l\'avertissement', (
      WidgetTester tester,
    ) async {
      await ouvrir(tester);

      expect(find.text(AppStrings.calendrierTitre), findsOneWidget);
      expect(
        find.text(adresseAttendue(FauxCalendrierRepository.jetonInitial)),
        findsOneWidget,
      );
      // Un lien qui vaut mot de passe se dit **avant** qu'on le distribue.
      expect(find.text(AppStrings.calendrierAvertissement), findsOneWidget);
    });

    /// Trois modes d'emploi dépliés feraient un mur au milieu d'un écran de
    /// réglages, et deux personnes sur trois n'en liront qu'un
    /// (`design/028-export-ics.md § 5`).
    testWidgets('le mode d\'emploi est replié, et s\'ouvre', (
      WidgetTester tester,
    ) async {
      await ouvrir(tester);

      expect(find.text(AppStrings.calendrierModeEmploi), findsOneWidget);
      expect(find.text(AppStrings.calendrierGoogle), findsNothing);

      await tester.tap(find.text(AppStrings.calendrierModeEmploi));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.calendrierGoogleTitre), findsOneWidget);
      expect(find.text(AppStrings.calendrierAppleTitre), findsOneWidget);
      expect(find.text(AppStrings.calendrierOutlookTitre), findsOneWidget);
      // Le délai de rafraîchissement n'est pas à nous : le dire évite la
      // question « pourquoi ma garde d'hier n'est pas là ».
      expect(find.text(AppStrings.calendrierDelai), findsOneWidget);
    });

    testWidgets('copie l\'adresse, et le dit sur place', (
      WidgetTester tester,
    ) async {
      final faux = await ouvrir(tester);

      await tester.tap(find.text(AppStrings.calendrierCopier));
      await tester.pumpAndSettle();

      expect(
        faux.presse.dernier,
        adresseAttendue(FauxCalendrierRepository.jetonInitial),
      );
      expect(find.text(AppStrings.calendrierCopie), findsOneWidget);
    });

    /// Le presse-papiers du navigateur refuse hors contexte sécurisé. Annoncer
    /// une réussite là où rien n'a été copié laisse coller une adresse vide.
    testWidgets('un presse-papiers qui refuse dit de copier à la main', (
      WidgetTester tester,
    ) async {
      await ouvrir(tester, pressePapiers: FauxPressePapiers(accepte: false));

      await tester.tap(find.text(AppStrings.calendrierCopier));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.calendrierCopie), findsNothing);
      // L'adresse reste à l'écran, sélectionnable : c'est le repli.
      expect(
        find.text(adresseAttendue(FauxCalendrierRepository.jetonInitial)),
        findsOneWidget,
      );
    });
  });

  group('La régénération', () {
    /// Elle casse quelque chose qui marchait : elle se confirme, et la
    /// confirmation dit ce qu'elle casse.
    testWidgets('demande confirmation, et ne fait rien si on annule', (
      WidgetTester tester,
    ) async {
      final faux = await ouvrir(tester);

      await tester.tap(find.text(AppStrings.calendrierRegenerer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.calendrierRegenereTitre), findsOneWidget);
      expect(find.text(AppStrings.calendrierRegenereCorps), findsOneWidget);

      await tester.tap(find.text(AppStrings.calendrierRegenereAnnuler));
      await tester.pumpAndSettle();

      expect(faux.depot.regenerations, 0);
      expect(
        find.text(adresseAttendue(FauxCalendrierRepository.jetonInitial)),
        findsOneWidget,
      );
    });

    testWidgets('remplace l\'adresse affichée, et le dit', (
      WidgetTester tester,
    ) async {
      final faux = await ouvrir(tester);
      final ancienne = adresseAttendue(FauxCalendrierRepository.jetonInitial);

      await tester.tap(find.text(AppStrings.calendrierRegenerer));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.calendrierRegenereConfirmer));
      await tester.pumpAndSettle();

      expect(faux.depot.regenerations, 1);
      expect(find.text(ancienne), findsNothing);
      expect(
        find.text(adresseAttendue(FauxCalendrierRepository.jetonRegenere)),
        findsOneWidget,
      );
      // Dans une PWA installée, rien d'autre ne signale qu'une adresse vient
      // de mourir.
      expect(find.text(AppStrings.calendrierRegenereFait), findsOneWidget);
    });

    /// **Si l'appel n'est pas parti, l'ancienne adresse marche encore.** La
    /// faire disparaître de l'écran ferait croire à une coupure qui n'a pas eu
    /// lieu — le pire des deux mondes.
    testWidgets('une régénération en échec ne fait pas disparaître le lien', (
      WidgetTester tester,
    ) async {
      final depot = FauxCalendrierRepository()
        ..echecRegeneration = const EchecAbonnement(ErreurAbonnement.reseau);
      await ouvrir(tester, calendrier: depot);

      await tester.tap(find.text(AppStrings.calendrierRegenerer));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.calendrierRegenereConfirmer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.calendrierReseau), findsOneWidget);
      expect(
        find.text(adresseAttendue(FauxCalendrierRepository.jetonInitial)),
        findsOneWidget,
      );
      expect(find.text(AppStrings.calendrierRegenereFait), findsNothing);
    });
  });

  group('Quand la lecture échoue', () {
    testWidgets('le bloc dit pourquoi et propose de relire', (
      WidgetTester tester,
    ) async {
      final depot = FauxCalendrierRepository()
        ..echecLecture = const EchecAbonnement(ErreurAbonnement.nonAuthentifie);
      await ouvrir(tester, calendrier: depot);

      expect(find.text(AppStrings.calendrierNonAuthentifie), findsOneWidget);
      // Pas « Réessayer » : la bannière de l'écran en porte déjà un, et deux
      // boutons au même libellé ne se distinguent pas à l'oreille.
      expect(find.text(AppStrings.calendrierRelire), findsOneWidget);
      expect(find.text(AppStrings.calendrierCopier), findsNothing);

      depot.echecLecture = null;
      await tester.tap(find.text(AppStrings.calendrierRelire));
      await tester.pumpAndSettle();

      expect(
        find.text(adresseAttendue(FauxCalendrierRepository.jetonInitial)),
        findsOneWidget,
      );
      expect(find.text(AppStrings.calendrierNonAuthentifie), findsNothing);
    });

    /// Le reste de l'écran de profil ne tombe pas avec ce bloc : on vient
    /// peut-être y corriger son nom, ou s'en aller.
    testWidgets('le reste du profil reste entier', (WidgetTester tester) async {
      final depot = FauxCalendrierRepository()
        ..echecLecture = const EchecAbonnement(ErreurAbonnement.reseau);
      await ouvrir(tester, calendrier: depot);

      expect(find.text(AppStrings.profilIdentiteTitre), findsOneWidget);
      expect(find.text(AppStrings.profilCompteTitre), findsOneWidget);
    });
  });
}
