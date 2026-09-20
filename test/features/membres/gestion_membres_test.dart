import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/membres/data/membres_repository.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';
import 'package:astreinte_sp/features/membres/presentation/widgets/marqueur_statut.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';

const String _cheminMembres = '/admin/membres';

/// L'admin connecté pendant ces tests : c'est **sa** ligne dans la liste.
///
/// `sessionMembre.userId` est l'utilisateur de la session montée par
/// [monterApp] : sans cette égalité, le garde-fou « soi-même » ne pourrait pas
/// être vérifié à l'écran.
const MembreCaserne moiAdmin = MembreCaserne(
  id: 'm-admin',
  userId: 'aaaaaaaa-0000-4000-8000-000000000101',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
  prenom: 'Jean',
  nom: 'Dupont',
  email: 'admin@caserne-a.test',
);

const MembreCaserne adjointAdmin = MembreCaserne(
  id: 'm-2',
  userId: 'u-2',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
  prenom: 'Camille',
  nom: 'Girard',
  email: 'membre3@caserne-a.test',
);

const MembreCaserne membreDesactive = MembreCaserne(
  id: 'm-3',
  userId: 'u-3',
  role: RoleMembre.membre,
  statut: StatutMembre.desactive,
  prenom: 'Lucas',
  nom: 'Bernard',
  email: 'membre4@caserne-a.test',
);

Future<void> _ouvrir(
  WidgetTester tester,
  FauxMembresRepository depot, {
  Appartenance appartenance = appartenanceAdmin,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    membres: depot,
  );
  await ouvrirRoute(tester, _cheminMembres);
}

/// Ouvre la feuille d'actions d'un membre par son bouton « ⋮ ».
Future<void> _ouvrirActions(WidgetTester tester, MembreCaserne membre) async {
  await tester.tap(find.byTooltip(AppStrings.membreActions(membre.libelle)));
  await tester.pumpAndSettle();
}

void main() {
  group('Informations par membre', () {
    testWidgets('la dernière saisie de disponibilités est datée', (
      tester,
    ) async {
      final saisie = DateTime(2026, 10, 4);
      await _ouvrir(
        tester,
        FauxMembresRepository(
          membresActifs: const <MembreCaserne>[moiAdmin, membreMarie],
          saisies: <String, DateTime>{membreMarie.userId: saisie},
        ),
      );

      expect(
        find.text(AppStrings.membreDerniereSaisie(formaterDateLongue(saisie))),
        findsOneWidget,
      );
      // Celui qui n'a jamais saisi le dit, il ne laisse pas un blanc. Son
      // rôle partage la même ligne, d'où la recherche par fragment.
      expect(
        find.textContaining(AppStrings.membreAucuneSaisie),
        findsOneWidget,
      );
    });

    testWidgets('un membre désactivé reste dans la liste, marqué', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        FauxMembresRepository(
          membresActifs: const <MembreCaserne>[moiAdmin, membreDesactive],
        ),
      );

      expect(find.text('Lucas Bernard'), findsOneWidget);
      expect(find.byType(MarqueurDesactive), findsOneWidget);
      expect(
        find.text(AppStrings.membresCompteAvecDesactives(1, 1)),
        findsOneWidget,
      );
    });
  });

  group('Recherche', () {
    testWidgets('filtre la liste et met le compte à jour', (tester) async {
      await _ouvrir(
        tester,
        FauxMembresRepository(
          membresActifs: const <MembreCaserne>[
            moiAdmin,
            membreMarie,
            adjointAdmin,
          ],
        ),
      );

      await tester.enterText(
        find.byType(TextField).first,
        'girard',
      );
      await tester.pumpAndSettle();

      expect(find.text('Camille Girard'), findsOneWidget);
      expect(find.text('Marie Lefebvre'), findsNothing);
      expect(find.text(AppStrings.membresCompteFiltre(1, 3)), findsOneWidget);
    });

    testWidgets('une recherche sans résultat nomme ce qui a été cherché', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        FauxMembresRepository(
          membresActifs: const <MembreCaserne>[moiAdmin, membreMarie],
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'durand');
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.membresRechercheVideTitre('durand')),
        findsOneWidget,
      );

      await tester.tap(find.text(AppStrings.membresRechercheEffacer));
      await tester.pumpAndSettle();

      expect(find.text('Marie Lefebvre'), findsOneWidget);
    });
  });

  group('Actions d\'administration', () {
    testWidgets('promouvoir un membre en administrateur', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[moiAdmin, membreMarie],
      );
      await _ouvrir(tester, depot);
      await _ouvrirActions(tester, membreMarie);

      expect(find.text(AppStrings.membreActionPromouvoir), findsOneWidget);
      await tester.tap(find.text(AppStrings.membreActionPromouvoir));
      await tester.pumpAndSettle();

      expect(depot.roles, <({String membershipId, RoleMembre role})>[
        (membershipId: 'm-1', role: RoleMembre.admin),
      ]);
      expect(
        find.text(AppStrings.membreVerdictPromu('Marie Lefebvre')),
        findsOneWidget,
      );
    });

    testWidgets('rétrograder un autre administrateur', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[moiAdmin, adjointAdmin],
      );
      await _ouvrir(tester, depot);
      await _ouvrirActions(tester, adjointAdmin);

      await tester.tap(find.text(AppStrings.membreActionRetrograder));
      await tester.pumpAndSettle();

      expect(depot.roles.single.role, RoleMembre.membre);
      expect(
        find.text(AppStrings.membreVerdictRetrograde('Camille Girard')),
        findsOneWidget,
      );
    });

    testWidgets('désactiver demande confirmation, puis coupe l\'accès', (
      tester,
    ) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[moiAdmin, membreMarie],
      );
      await _ouvrir(tester, depot);
      await _ouvrirActions(tester, membreMarie);

      await tester.tap(find.text(AppStrings.membreActionDesactiver));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.membreDesactiverTitre('Marie Lefebvre')),
        findsOneWidget,
      );

      // Renoncer n'écrit rien.
      await tester.tap(find.text(AppStrings.actionAnnuler));
      await tester.pumpAndSettle();
      expect(depot.statuts, isEmpty);

      await _ouvrirActions(tester, membreMarie);
      await tester.tap(find.text(AppStrings.membreActionDesactiver));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(InkWell, AppStrings.membreActionDesactiver).last,
      );
      await tester.pumpAndSettle();

      expect(depot.statuts.single.statut, StatutMembre.desactive);
      expect(
        find.text(AppStrings.membreVerdictDesactive('Marie Lefebvre')),
        findsOneWidget,
      );
      expect(find.byType(MarqueurDesactive), findsOneWidget);
    });

    testWidgets('réactiver un membre désactivé', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[moiAdmin, membreDesactive],
      );
      await _ouvrir(tester, depot);
      await _ouvrirActions(tester, membreDesactive);

      expect(find.text(AppStrings.membreActionDesactiver), findsNothing);
      await tester.tap(find.text(AppStrings.membreActionReactiver));
      await tester.pumpAndSettle();

      expect(depot.statuts.single.statut, StatutMembre.actif);
      expect(
        find.text(AppStrings.membreVerdictReactive('Lucas Bernard')),
        findsOneWidget,
      );
    });

    testWidgets('modifier le nom affiché', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[moiAdmin, membreMarie],
      );
      await _ouvrir(tester, depot);
      await _ouvrirActions(tester, membreMarie);

      await tester.tap(find.text(AppStrings.membreActionRenommer));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Marie L.');
      await tester.tap(find.text(AppStrings.membreRenommerEnregistrer));
      await tester.pumpAndSettle();

      expect(depot.renommages, <({String membershipId, String? nomAffiche})>[
        (membershipId: 'm-1', nomAffiche: 'Marie L.'),
      ]);
      expect(find.text(AppStrings.membreVerdictRenomme), findsOneWidget);
    });

    testWidgets('un champ vidé rend au membre le nom de son profil', (
      tester,
    ) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[moiAdmin, membreMarie],
      );
      await _ouvrir(tester, depot);
      await _ouvrirActions(tester, membreMarie);

      await tester.tap(find.text(AppStrings.membreActionRenommer));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.tap(find.text(AppStrings.membreRenommerEnregistrer));
      await tester.pumpAndSettle();

      expect(depot.renommages.single.nomAffiche, isNull);
    });
  });

  group('Garde-fous à l\'écran', () {
    testWidgets('le dernier admin ne peut pas se rétrograder, et on dit pourquoi', (
      tester,
    ) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[moiAdmin, membreMarie],
      );
      await _ouvrir(tester, depot);
      await _ouvrirActions(tester, moiAdmin);

      expect(find.text(AppStrings.membreRefusDernierAdmin), findsNWidgets(2));

      await tester.tap(find.text(AppStrings.membreActionRetrograder));
      await tester.pumpAndSettle();

      // La feuille est toujours là, et rien n'a été écrit.
      expect(find.text(AppStrings.membreActionRetrograder), findsOneWidget);
      expect(depot.roles, isEmpty);
      expect(depot.statuts, isEmpty);
    });

    testWidgets('à deux admins, on ne se retire pas soi-même', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[moiAdmin, adjointAdmin],
      );
      await _ouvrir(tester, depot);
      await _ouvrirActions(tester, moiAdmin);

      expect(find.text(AppStrings.membreRefusSoiMeme), findsNWidgets(2));

      await tester.tap(find.text(AppStrings.membreActionDesactiver));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.membreActionDesactiver), findsOneWidget);
      expect(depot.statuts, isEmpty);
    });

    testWidgets('un refus de la base est annoncé tel quel', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[moiAdmin, adjointAdmin],
        echecAdministration: ErreurAdministration.dernierAdmin,
      );
      await _ouvrir(tester, depot);
      await _ouvrirActions(tester, adjointAdmin);

      await tester.tap(find.text(AppStrings.membreActionRetrograder));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.membreRefusDernierAdmin), findsOneWidget);
      expect(find.text('Camille Girard'), findsOneWidget);
    });
  });

  group('Effet d\'une désactivation', () {
    testWidgets('à la connexion suivante, le membre désactivé n\'a plus de caserne', (
      tester,
    ) async {
      // Ce que la base rend après le passage de l'admin : la même
      // appartenance, mais désactivée.
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceDesactivee],
      );

      expect(find.text(AppStrings.caserneDesactiveeTitre), findsOneWidget);
      expect(
        find.text(AppStrings.caserneDesactiveeTexte('CIS Saint-Martin')),
        findsOneWidget,
      );

      // Sans le nom : la politique de `stations` n'ouvre la lecture qu'aux
      // membres actifs, un compte désactivé ne lit donc plus le nom de sa
      // caserne. Vérifié en vrai contre la base locale.
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[
          Appartenance(
            id: 'm-2',
            stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
            nomCaserne: '',
            role: RoleMembre.membre,
            statut: StatutMembre.desactive,
          ),
        ],
      );
      expect(
        find.text(AppStrings.caserneDesactiveeTexteSansNom),
        findsOneWidget,
      );

      // Et l'écran d'administration lui reste fermé, même en tapant l'adresse.
      await ouvrirRoute(tester, _cheminMembres);
      expect(find.text(AppStrings.membresTitre), findsNothing);
      expect(find.text(AppStrings.caserneDesactiveeTitre), findsOneWidget);
    });
  });
}
