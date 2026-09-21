import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/presentation/inviter_screen.dart';
import 'package:astreinte_sp/features/membres/presentation/membres_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';

Future<void> _ouvrirFormulaire(
  WidgetTester tester,
  FauxMembresRepository depot,
) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceAdmin],
    membres: depot,
  );
  await ouvrirRoute(tester, '/admin/membres/inviter');
  expect(find.byType(InviterScreen), findsOneWidget);
}

void main() {
  group('InviterScreen', () {
    testWidgets('refuse une adresse incomplète avant tout appel', (
      tester,
    ) async {
      final depot = FauxMembresRepository();
      await _ouvrirFormulaire(tester, depot);

      await tester.enterText(find.byType(TextField), 'pas-une-adresse');
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      expect(find.textContaining('pas-une-adresse'), findsWidgets);
      expect(depot.envois, isEmpty);
    });

    testWidgets('envoie le lot et rend compte adresse par adresse', (
      tester,
    ) async {
      final depot = FauxMembresRepository(
        rapport: const RapportInvitations(
          resultats: <ResultatInvitation>[
            ResultatInvitation(
              email: 'recrue@exemple.fr',
              statut: StatutResultatInvitation.invitee,
            ),
            ResultatInvitation(
              email: 'ancien@exemple.fr',
              statut: StatutResultatInvitation.renvoyee,
            ),
            ResultatInvitation(
              email: 'deja@exemple.fr',
              statut: StatutResultatInvitation.erreur,
              motif: MotifEchecInvitation.dejaMembre,
            ),
          ],
        ),
      );
      await _ouvrirFormulaire(tester, depot);

      await tester.enterText(
        find.byType(TextField),
        'recrue@exemple.fr\nancien@exemple.fr\ndeja@exemple.fr',
      );
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      expect(depot.envois.single, <String>[
        'recrue@exemple.fr',
        'ancien@exemple.fr',
        'deja@exemple.fr',
      ]);
      expect(
        find.text(AppStrings.inviterResume(envoyees: 2, echecs: 1)),
        findsOneWidget,
      );
      expect(find.text(AppStrings.resultatInvitee), findsOneWidget);
      expect(find.text(AppStrings.resultatRenvoyee), findsOneWidget);
      expect(find.text(AppStrings.resultatEchec), findsOneWidget);
      expect(find.text(AppStrings.inviteDejaMembre), findsOneWidget);
    });

    testWidgets('un courriel non parti est dit sans crier à l\'échec', (
      tester,
    ) async {
      final depot = FauxMembresRepository(
        rapport: const RapportInvitations(
          resultats: <ResultatInvitation>[
            ResultatInvitation(
              email: 'recrue@exemple.fr',
              statut: StatutResultatInvitation.invitee,
              courrielEnvoye: false,
            ),
          ],
        ),
      );
      await _ouvrirFormulaire(tester, depot);

      await tester.enterText(find.byType(TextField), 'recrue@exemple.fr');
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.inviterResume(envoyees: 1, echecs: 0)),
        findsOneWidget,
      );
      expect(find.text(AppStrings.resultatCourrielNonParti), findsOneWidget);
      expect(find.text(AppStrings.inviterReessayerEchecs), findsNothing);
    });

    testWidgets('le rôle choisi part avec le lot', (tester) async {
      final depot = FauxMembresRepository();
      await _ouvrirFormulaire(tester, depot);

      await tester.enterText(find.byType(TextField), 'chef@exemple.fr');
      await tester.tap(find.text(AppStrings.roleAdmin));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      expect(depot.rolesEnvoyes, <RoleMembre>[RoleMembre.admin]);
    });

    testWidgets('un refus de la requête entière s\'affiche en bannière', (
      tester,
    ) async {
      final depot = FauxMembresRepository(
        echecInvitation: const EchecInvitation(ErreurInvitation.caserneSuspendue),
      );
      await _ouvrirFormulaire(tester, depot);

      await tester.enterText(find.byType(TextField), 'recrue@exemple.fr');
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.inviteCaserneSuspendue), findsOneWidget);
      expect(find.text(AppStrings.inviterResultatsTitre), findsNothing);
    });

    // Ticket 038 : le plafond horaire. La phrase porte le délai avant de
    // pouvoir réessayer — elle vient du serveur et s'affiche telle quelle,
    // sinon l'écran annoncerait une panne à la place d'une limite.
    testWidgets('un refus de débit affiche la phrase du serveur', (
      tester,
    ) async {
      const phrase =
          'Limite d\'invitations atteinte (60 par heure pour cette caserne). '
          'Réessaie dans 13 minutes.';
      final depot = FauxMembresRepository(
        echecInvitation: const EchecInvitation(
          ErreurInvitation.debitAtteint,
          messageServeur: phrase,
          plafond: PlafondInvitations(
            portee: PorteePlafond.caserne,
            plafond: 60,
            delaiAvantNouvelEssai: Duration(seconds: 730),
          ),
        ),
      );
      await _ouvrirFormulaire(tester, depot);

      await tester.enterText(find.byType(TextField), 'recrue@exemple.fr');
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      expect(find.text(phrase), findsOneWidget);
      expect(find.text(AppStrings.erreurTexteGenerique), findsNothing);
    });

    testWidgets('un lot à moitié refusé nomme la limite sous l\'adresse', (
      tester,
    ) async {
      const phrase =
          'Limite d\'invitations atteinte (60 par heure pour cette caserne). '
          'Réessaie dans 2 minutes.';
      final depot = FauxMembresRepository(
        rapport: const RapportInvitations(
          resultats: <ResultatInvitation>[
            ResultatInvitation(
              email: 'bon@exemple.fr',
              statut: StatutResultatInvitation.invitee,
            ),
            ResultatInvitation(
              email: 'trop@exemple.fr',
              statut: StatutResultatInvitation.erreur,
              motif: MotifEchecInvitation.debitAtteint,
              messageServeur: phrase,
            ),
          ],
        ),
      );
      await _ouvrirFormulaire(tester, depot);

      await tester.enterText(
        find.byType(TextField),
        'bon@exemple.fr, trop@exemple.fr',
      );
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      expect(find.text(phrase), findsOneWidget);
      expect(find.text(AppStrings.inviteErreurServeur), findsNothing);
      // Le lot garde sa liste : les adresses passées ne se réessaient pas.
      expect(find.text(AppStrings.inviterReessayerEchecs), findsOneWidget);
    });

    testWidgets('les adresses en échec se réessaient seules', (tester) async {
      final depot = FauxMembresRepository(
        rapport: const RapportInvitations(
          resultats: <ResultatInvitation>[
            ResultatInvitation(
              email: 'bon@exemple.fr',
              statut: StatutResultatInvitation.invitee,
            ),
            ResultatInvitation(
              email: 'rate@exemple.fr',
              statut: StatutResultatInvitation.erreur,
              motif: MotifEchecInvitation.erreurServeur,
            ),
          ],
        ),
      );
      await _ouvrirFormulaire(tester, depot);

      await tester.enterText(
        find.byType(TextField),
        'bon@exemple.fr, rate@exemple.fr',
      );
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.inviterReessayerEchecs));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      expect(depot.envois.last, <String>['rate@exemple.fr']);
    });

    testWidgets('« Revenir aux membres » ramène à la liste', (tester) async {
      final depot = FauxMembresRepository();
      await _ouvrirFormulaire(tester, depot);

      await tester.enterText(find.byType(TextField), 'recrue@exemple.fr');
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.inviterTerminer));
      await tester.pumpAndSettle();

      expect(find.byType(MembresScreen), findsOneWidget);
      expect(find.byType(InviterScreen), findsNothing);
    });
  });
}
