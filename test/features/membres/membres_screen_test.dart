import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';
import 'package:astreinte_sp/features/membres/presentation/membres_screen.dart';
import 'package:astreinte_sp/features/membres/presentation/widgets/ligne_invitation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';

const String _cheminMembres = '/admin/membres';

/// Amène la première invitation sous les yeux.
///
/// Depuis le ticket 009, la section des membres porte un champ de recherche et
/// trois lignes de texte par membre : sur un téléphone, les invitations sont
/// sous le pli. C'est la liste virtualisée qui l'exige, pas le test — un
/// widget qui n'est pas construit n'est pas trouvable.
Future<void> _versInvitations(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byType(LigneInvitation),
    200,
    scrollable: find
        .descendant(
          of: find.byType(MembresScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<FauxMembresRepository> _ouvrirMembres(
  WidgetTester tester, {
  required FauxMembresRepository depot,
  Appartenance appartenance = appartenanceAdmin,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    membres: depot,
  );
  await ouvrirRoute(tester, _cheminMembres);
  return depot;
}

void main() {
  group('MembresScreen', () {
    testWidgets('liste les membres actifs et les invitations en attente', (
      tester,
    ) async {
      await _ouvrirMembres(
        tester,
        depot: FauxMembresRepository(
          membresActifs: const <MembreCaserne>[membreJean, membreMarie],
          invitations: <Invitation>[invitationEnAttente()],
        ),
      );

      expect(find.byType(MembresScreen), findsOneWidget);
      expect(find.text('Jean Dupont'), findsOneWidget);
      expect(find.text('Marie Lefebvre'), findsOneWidget);
      expect(find.text(AppStrings.membresCompte(2)), findsOneWidget);

      await _versInvitations(tester);
      expect(find.text('recrue@exemple.fr'), findsOneWidget);
      expect(find.text(AppStrings.invitationsCompte(1)), findsOneWidget);
      expect(find.text(AppStrings.invitationEnAttente), findsOneWidget);
    });

    testWidgets('une invitation périmée se dit expirée', (tester) async {
      await _ouvrirMembres(
        tester,
        depot: FauxMembresRepository(
          membresActifs: const <MembreCaserne>[membreJean],
          invitations: <Invitation>[
            invitationEnAttente(restant: const Duration(days: -1)),
          ],
        ),
      );

      await _versInvitations(tester);
      expect(find.text(AppStrings.invitationExpiree), findsOneWidget);
      expect(find.text(AppStrings.invitationEnAttente), findsNothing);
    });

    testWidgets('sans membre ni invitation, l\'écran explique et invite', (
      tester,
    ) async {
      await _ouvrirMembres(tester, depot: FauxMembresRepository());

      expect(find.text(AppStrings.membresVideTitre), findsOneWidget);
      expect(find.text(AppStrings.membresInviter), findsOneWidget);
    });

    testWidgets('une lecture en échec propose de réessayer', (tester) async {
      final depot = FauxMembresRepository(erreurLecture: true);
      await _ouvrirMembres(tester, depot: depot);

      expect(find.text(AppStrings.membresErreurTexte), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);

      depot
        ..erreurLecture = false
        ..membresActifs = const <MembreCaserne>[membreMarie];
      await tester.tap(find.text(AppStrings.actionReessayer));
      await tester.pumpAndSettle();

      expect(find.text('Marie Lefebvre'), findsOneWidget);
    });

    testWidgets('sans invitation en attente, la section le dit', (
      tester,
    ) async {
      await _ouvrirMembres(
        tester,
        depot: FauxMembresRepository(
          membresActifs: const <MembreCaserne>[membreMarie],
        ),
      );

      expect(find.text(AppStrings.membresInvitationsVide), findsOneWidget);
      expect(find.byType(LigneInvitation), findsNothing);
    });

    testWidgets('un membre simple n\'a rien à administrer ici', (tester) async {
      await _ouvrirMembres(
        tester,
        depot: FauxMembresRepository(),
        appartenance: appartenanceMembre,
      );

      expect(find.text(AppStrings.membresReserveAdmin), findsOneWidget);
      expect(find.text(AppStrings.membresInviter), findsNothing);
    });

    testWidgets('renvoyer une invitation la relance et le dit', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[membreJean],
        invitations: <Invitation>[invitationEnAttente()],
      );
      await _ouvrirMembres(tester, depot: depot);
      await _versInvitations(tester);

      await tester.tap(
        find.bySemanticsLabel(
          AppStrings.invitationRenvoyerSemantique('recrue@exemple.fr'),
        ),
      );
      await tester.pumpAndSettle();

      expect(depot.envois, <List<String>>[
        <String>['recrue@exemple.fr'],
      ]);
      expect(find.text(AppStrings.invitationRenvoyee), findsOneWidget);
    });

    testWidgets('un courriel qui ne part pas propose le renvoi, pas un échec', (
      tester,
    ) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[membreJean],
        invitations: <Invitation>[invitationEnAttente()],
        rapport: const RapportInvitations(
          resultats: <ResultatInvitation>[
            ResultatInvitation(
              email: 'recrue@exemple.fr',
              statut: StatutResultatInvitation.renvoyee,
              courrielEnvoye: false,
            ),
          ],
        ),
      );
      await _ouvrirMembres(tester, depot: depot);
      await _versInvitations(tester);

      await tester.tap(
        find.bySemanticsLabel(
          AppStrings.invitationRenvoyerSemantique('recrue@exemple.fr'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.resultatCourrielNonParti), findsOneWidget);
    });

    testWidgets('annuler une invitation la retire de la liste', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[membreJean],
        invitations: <Invitation>[invitationEnAttente()],
      );
      await _ouvrirMembres(tester, depot: depot);
      await _versInvitations(tester);

      await tester.tap(
        find.bySemanticsLabel(
          AppStrings.invitationAnnulerSemantique('recrue@exemple.fr'),
        ),
      );
      await tester.pumpAndSettle();

      expect(depot.annulations, <String>['i-1']);
      expect(find.text(AppStrings.invitationAnnulee), findsOneWidget);
      expect(find.text('recrue@exemple.fr'), findsNothing);
    });

    testWidgets('revenir sur l\'écran relit les deux listes', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[membreJean],
        invitations: <Invitation>[invitationEnAttente()],
      );
      await _ouvrirMembres(tester, depot: depot);
      expect(find.text('recrue@exemple.fr'), findsOneWidget);
      final lecturesInitiales = depot.lectures;

      // L'invité accepte pendant que l'admin est ailleurs : personne ne
      // prévient l'écran, seule la relecture le fera savoir.
      depot
        ..invitations = <Invitation>[]
        ..membresActifs = const <MembreCaserne>[membreJean, membreMarie];

      await ouvrirRoute(tester, '/');
      expect(find.byType(MembresScreen), findsNothing);

      await ouvrirRoute(tester, _cheminMembres);

      expect(depot.lectures, greaterThan(lecturesInitiales));
      expect(find.text('recrue@exemple.fr'), findsNothing);
      expect(find.text('Marie Lefebvre'), findsOneWidget);
    });

    testWidgets('le retour au premier plan relit les deux listes', (
      tester,
    ) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[membreJean],
        invitations: <Invitation>[invitationEnAttente()],
      );
      await _ouvrirMembres(tester, depot: depot);
      final lecturesInitiales = depot.lectures;

      depot
        ..invitations = <Invitation>[]
        ..membresActifs = const <MembreCaserne>[membreJean, membreMarie];

      // La suite complète d'un rangement puis d'un retour, telle que la
      // plateforme l'envoie : sauter une étape casse l'assertion du framework.
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

      expect(depot.lectures, greaterThan(lecturesInitiales));
      expect(find.text('recrue@exemple.fr'), findsNothing);
      expect(find.text('Marie Lefebvre'), findsOneWidget);
    });

    testWidgets('une annulation refusée ne ment pas', (tester) async {
      final depot = FauxMembresRepository(
        membresActifs: const <MembreCaserne>[membreJean],
        invitations: <Invitation>[invitationEnAttente()],
        echecAnnulation: true,
      );
      await _ouvrirMembres(tester, depot: depot);
      await _versInvitations(tester);

      await tester.tap(
        find.bySemanticsLabel(
          AppStrings.invitationAnnulerSemantique('recrue@exemple.fr'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.invitationAnnulationEchec), findsOneWidget);
      expect(find.text('recrue@exemple.fr'), findsOneWidget);
    });
  });
}
