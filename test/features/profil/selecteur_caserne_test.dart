import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/caserne_choisie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_profil.dart';

/// La seconde caserne d'un regroupement de centres (`docs/PRD.md § 6.1`). Son
/// nom vient **après** celui de la première dans l'ordre alphabétique : c'est
/// ce qui permet de distinguer « le choix a été suivi » de « on est tombé sur
/// la première par défaut ».
const Appartenance _secondeCaserne = Appartenance(
  id: 'm-9',
  stationId: 'bbbbbbbb-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Val-de-Loue',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
);

const Appartenance _secondeDesactivee = Appartenance(
  id: 'm-9',
  stationId: 'bbbbbbbb-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Val-de-Loue',
  role: RoleMembre.membre,
  statut: StatutMembre.desactive,
);

Future<void> _ouvrirProfil(
  WidgetTester tester, {
  required List<Appartenance> appartenances,
  CaserneChoisieLocale? caserneChoisie,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: appartenances,
    profils: FauxProfilRepository(),
    caserneChoisie: caserneChoisie,
  );
  await tester.tap(find.text(AppStrings.navProfil));
  await tester.pumpAndSettle();
  await defilerJusqua(tester, find.text(AppStrings.profilCaserneTitre));
}

void main() {
  group('Sélecteur de caserne', () {
    testWidgets('une seule caserne : aucun sélecteur', (tester) async {
      await _ouvrirProfil(
        tester,
        appartenances: const <Appartenance>[appartenanceMembre],
      );

      expect(find.text('CIS Saint-Martin'), findsOneWidget);
      expect(find.text(AppStrings.roleMembre), findsOneWidget);

      // Un contrôle à un seul choix est un contrôle de trop.
      expect(find.text(AppStrings.profilCaserneChoixTitre), findsNothing);
      expect(find.byType(RadioListTile<String>), findsNothing);
    });

    testWidgets(
      'une seule caserne active parmi deux appartenances : aucun sélecteur',
      (tester) async {
        // Une appartenance désactivée n'est pas un choix : la RLS ne laisse
        // rien lire de cette caserne-là.
        await _ouvrirProfil(
          tester,
          appartenances: const <Appartenance>[
            appartenanceMembre,
            _secondeDesactivee,
          ],
        );

        expect(find.text(AppStrings.profilCaserneChoixTitre), findsNothing);
        expect(find.text('CIS Val-de-Loue'), findsNothing);
      },
    );

    testWidgets('deux casernes : le sélecteur apparaît et suit le choix', (
      tester,
    ) async {
      await _ouvrirProfil(
        tester,
        appartenances: const <Appartenance>[
          appartenanceMembre,
          _secondeCaserne,
        ],
      );

      expect(find.text(AppStrings.profilCaserneChoixTitre), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNWidgets(2));

      // Sans choix gardé, c'est la première dans l'ordre alphabétique.
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        appartenanceMembre.stationId,
      );

      await tester.tap(find.text('CIS Val-de-Loue'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        _secondeCaserne.stationId,
      );
    });

    testWidgets('changer de caserne change tout ce qui en dépend', (
      tester,
    ) async {
      await _ouvrirProfil(
        tester,
        appartenances: const <Appartenance>[
          appartenanceMembre,
          _secondeCaserne,
        ],
      );

      // Membre dans la première, administrateur dans la seconde : la
      // destination « Admin » est le signe le plus visible que **tout** suit le
      // choix, puisque le routeur lui-même lit `appartenanceCouranteProvider`.
      expect(find.text(AppStrings.navAdmin), findsNothing);

      await tester.tap(find.text('CIS Val-de-Loue'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.navAdmin), findsWidgets);
    });

    testWidgets('le choix est gardé sur l\'appareil, par utilisateur', (
      tester,
    ) async {
      final local = CaserneChoisieLocaleMemoire();
      await _ouvrirProfil(
        tester,
        appartenances: const <Appartenance>[
          appartenanceMembre,
          _secondeCaserne,
        ],
        caserneChoisie: local,
      );

      await tester.tap(find.text('CIS Val-de-Loue'));
      await tester.pumpAndSettle();

      expect(
        await local.lire(sessionMembre.userId),
        _secondeCaserne.stationId,
      );
      // Rangé par utilisateur : sur un téléphone partagé, la caserne de l'un
      // n'est pas celle de l'autre.
      expect(await local.lire('aaaaaaaa-0000-4000-8000-000000000199'), isNull);
    });

    testWidgets('un choix gardé est repris à l\'ouverture suivante', (
      tester,
    ) async {
      await _ouvrirProfil(
        tester,
        appartenances: const <Appartenance>[
          appartenanceMembre,
          _secondeCaserne,
        ],
        caserneChoisie: CaserneChoisieLocaleMemoire(<String, String>{
          sessionMembre.userId: _secondeCaserne.stationId,
        }),
      );

      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        _secondeCaserne.stationId,
      );
    });

    testWidgets(
      'un choix devenu invalide retombe sur la caserne qui reste',
      (tester) async {
        // Retiré de la caserne B entre deux ouvertures : l'application ne se
        // bloque pas sur un souvenir.
        await _ouvrirProfil(
          tester,
          appartenances: const <Appartenance>[appartenanceMembre],
          caserneChoisie: CaserneChoisieLocaleMemoire(<String, String>{
            sessionMembre.userId: _secondeCaserne.stationId,
          }),
        );

        expect(find.text('CIS Saint-Martin'), findsOneWidget);
        expect(find.text(AppStrings.aucuneCaserneTitre), findsNothing);
      },
    );

    test('le stockage réel range par utilisateur et s\'efface', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const local = CaserneChoisieLocalePartagee();
      const autre = 'aaaaaaaa-0000-4000-8000-000000000199';

      await local.ecrire(sessionMembre.userId, _secondeCaserne.stationId);
      await local.ecrire(autre, appartenanceMembre.stationId);

      expect(
        await local.lire(sessionMembre.userId),
        _secondeCaserne.stationId,
      );
      expect(await local.lire(autre), appartenanceMembre.stationId);

      await local.effacer(sessionMembre.userId);
      expect(await local.lire(sessionMembre.userId), isNull);
      expect(await local.lire(autre), appartenanceMembre.stationId);
    });
  });
}
