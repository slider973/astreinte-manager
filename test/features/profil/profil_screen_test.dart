import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_spacing.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/profil/domain/profil.dart';
import 'package:astreinte_sp/features/profil/presentation/profil_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_profil.dart';

Future<FauxProfilRepository> _ouvrirProfil(
  WidgetTester tester, {
  FauxProfilRepository? profils,
  List<Appartenance> appartenances = const <Appartenance>[appartenanceMembre],
}) async {
  final depot = profils ?? FauxProfilRepository();
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: appartenances,
    profils: depot,
  );
  await tester.tap(find.text(AppStrings.navProfil));
  await tester.pumpAndSettle();
  return depot;
}

/// Le bouton d'enregistrement est sous la ligne de flottaison d'un téléphone :
/// trois champs et une adresse le poussent hors de l'écran.
Future<void> _enregistrer(WidgetTester tester) async {
  await defilerJusqua(tester, find.text(AppStrings.profilEnregistrerIdentite));
  await tester.tap(find.text(AppStrings.profilEnregistrerIdentite));
  await tester.pumpAndSettle();
}

void main() {
  group('ProfilScreen', () {
    testWidgets('montre le profil lu, et l\'adresse de connexion en lecture', (
      tester,
    ) async {
      await _ouvrirProfil(tester);

      expect(find.byType(ProfilScreen), findsOneWidget);
      expect(find.text(AppStrings.profilIdentiteTitre), findsOneWidget);

      // Les trois champs sont pré-remplis avec ce que la base a rendu.
      expect(find.widgetWithText(TextField, 'Marie'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Lefebvre'), findsOneWidget);
      expect(find.widgetWithText(TextField, '+33600000101'), findsOneWidget);

      // L'adresse est un fait, pas un champ — et la raison est écrite à côté.
      expect(find.text('membre1@caserne-a.test'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'membre1@caserne-a.test'),
        findsNothing,
      );
      expect(find.text(AppStrings.profilEmailRaison), findsOneWidget);
    });

    testWidgets('la langue s\'affiche sans se régler', (tester) async {
      await _ouvrirProfil(tester);
      await defilerJusqua(tester, find.text(AppStrings.profilLangueRaison));

      expect(find.text(AppStrings.profilLangueFrancais), findsOneWidget);
      expect(find.text(AppStrings.profilLangueRaison), findsOneWidget);
      // Aucun contrôle de choix : un sélecteur à une entrée promettrait une
      // traduction qui n'existe pas.
      expect(find.byType(DropdownButton<Langue>), findsNothing);
      expect(find.byType(DropdownMenu<Langue>), findsNothing);
    });

    testWidgets('enregistre prénom, nom et téléphone, et le dit', (
      tester,
    ) async {
      final depot = await _ouvrirProfil(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Lefebvre'),
        'Lefèvre',
      );
      await tester.pumpAndSettle();
      await _enregistrer(tester);

      expect(depot.ecritures, hasLength(1));
      expect(depot.ecritures.single.prenom, 'Marie');
      expect(depot.ecritures.single.nom, 'Lefèvre');
      expect(depot.ecritures.single.telephone, '+33600000101');

      // Le résultat est écrit, pas seulement deviné à la disparition d'un
      // indicateur.
      expect(find.text(AppStrings.profilEnregistre), findsOneWidget);

      // Et l'écran relit la base : c'est ce qu'elle a accepté qui s'affiche.
      expect(depot.lectures, greaterThan(1));
      expect(depot.profil.nom, 'Lefèvre');
    });

    testWidgets('un téléphone vidé remet null, jamais la chaîne vide', (
      tester,
    ) async {
      final depot = await _ouvrirProfil(tester);

      await tester.enterText(
        find.widgetWithText(TextField, '+33600000101'),
        '',
      );
      await tester.pumpAndSettle();
      await _enregistrer(tester);

      expect(depot.profil.telephone, isNull);
    });

    testWidgets('un nom vide est refusé avant l\'envoi, et le champ le dit', (
      tester,
    ) async {
      final depot = await _ouvrirProfil(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Lefebvre'), '  ');
      await tester.pumpAndSettle();
      await _enregistrer(tester);

      expect(find.text(AppStrings.profilNomManquant), findsOneWidget);
      expect(depot.ecritures, isEmpty);
      expect(find.text(AppStrings.profilEnregistre), findsNothing);
    });

    testWidgets('une écriture refusée le dit, et rien n\'est perdu', (
      tester,
    ) async {
      final depot = await _ouvrirProfil(tester);
      depot.echoue = true;

      await tester.enterText(
        find.widgetWithText(TextField, 'Marie'),
        'Marie-Claire',
      );
      await tester.pumpAndSettle();
      await _enregistrer(tester);

      expect(find.text(AppStrings.profilEchec), findsOneWidget);
      // La saisie reste à l'écran : on ne refait pas taper ce qui vient
      // d'échouer à cause du réseau.
      expect(find.widgetWithText(TextField, 'Marie-Claire'), findsOneWidget);
    });

    testWidgets(
      'une lecture en échec propose de réessayer sans vider l\'écran',
      (tester) async {
        final depot = FauxProfilRepository()..lectureEchoue = true;
        await _ouvrirProfil(tester, profils: depot);

        expect(find.text(AppStrings.profilLectureEchec), findsOneWidget);

        // Le reste de l'écran fonctionne : la caserne et les deux sorties ne
        // dépendent pas de `profiles`, et c'est peut-être pour se déconnecter
        // qu'on est venu.
        expect(find.text(AppStrings.profilCaserneTitre), findsOneWidget);
        await defilerJusqua(tester, find.text(AppStrings.seDeconnecter));
        expect(find.text(AppStrings.seDeconnecter), findsOneWidget);

        // Et « Réessayer » relit vraiment.
        final avant = depot.lectures;
        depot.lectureEchoue = false;
        await tester.tap(find.text(AppStrings.actionReessayer));
        await tester.pumpAndSettle();
        expect(depot.lectures, greaterThan(avant));
        expect(find.text(AppStrings.profilLectureEchec), findsNothing);
      },
    );

    testWidgets('le réglage des notifications a bien déménagé ici', (
      tester,
    ) async {
      await _ouvrirProfil(tester);
      await defilerJusqua(tester, find.text(AppStrings.notifReglageToujours));

      expect(find.text(AppStrings.notifReglageTitre), findsOneWidget);
      expect(find.text(AppStrings.notifReglageToujours), findsOneWidget);
    });

    testWidgets('chaque cible fait au moins 44 pt', (tester) async {
      await _ouvrirProfil(tester);

      // Les champs du système font 56 dp ; le bouton d'enregistrement 52.
      for (final champ in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(champ.style?.fontSize ?? 16, greaterThanOrEqualTo(16));
      }
      await defilerJusqua(
        tester,
        find.text(AppStrings.profilEnregistrerIdentite),
      );
      final bouton = tester.getSize(
        find
            .ancestor(
              of: find.text(AppStrings.profilEnregistrerIdentite),
              matching: find.byType(PrimaryButton),
            )
            .first,
      );
      expect(bouton.height, greaterThanOrEqualTo(AppTouch.plancher));
    });
  });
}
