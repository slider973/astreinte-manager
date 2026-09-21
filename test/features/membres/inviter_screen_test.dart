import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/presentation/inviter_screen.dart';
import 'package:astreinte_sp/features/membres/presentation/membres_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/promesse_envoi.dart';

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
        find.text(
          AppStrings.invitationsResume(creees: 2, parties: 2, echecs: 1),
        ),
        findsOneWidget,
      );
      expect(find.text(AppStrings.resultatInvitee), findsOneWidget);
      expect(find.text(AppStrings.resultatRenvoyee), findsOneWidget);
      expect(find.text(AppStrings.resultatEchec), findsOneWidget);
      expect(find.text(AppStrings.inviteDejaMembre), findsOneWidget);
    });

    // Les quatre situations du compte rendu (ticket 048) : une adresse ou un
    // lot, tous les courriels partis ou non. Le résumé compte et porte le
    // verbe — « envoyées » seulement si les envois couvrent les créations —,
    // la ligne dit laquelle n'a prévenu personne, et aucun des deux ne redit
    // ce que l'autre a déjà dit. Chaque cas où un courriel manque est gardé
    // par [aucunEnvoiPromis] : c'est la phrase **en trop** qui ment, et ce
    // n'est jamais celle qu'on vérifie.
    group('le résumé ne promet que les envois qui ont eu lieu', () {
      testWidgets('une adresse, courriel parti : « envoyée »', (tester) async {
        final depot = FauxMembresRepository(
          rapport: const RapportInvitations(
            resultats: <ResultatInvitation>[
              ResultatInvitation(
                email: 'recrue@exemple.fr',
                statut: StatutResultatInvitation.invitee,
              ),
            ],
          ),
        );
        await _ouvrirFormulaire(tester, depot);

        await tester.enterText(find.byType(TextField), 'recrue@exemple.fr');
        await tester.tap(find.text(AppStrings.inviterEnvoyer));
        await tester.pumpAndSettle();

        expect(
          find.text(
            AppStrings.invitationsResume(creees: 1, parties: 1, echecs: 0),
          ),
          findsOneWidget,
        );
        // Rien à ajouter sous l'adresse : le courriel est parti.
        expect(find.text(AppStrings.resultatCourrielNonParti), findsNothing);
      });

      testWidgets('une adresse, courriel non parti : « créée », et la ligne '
          'dit ce qui manque', (tester) async {
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

        // Le défaut de la revue : « 1 invitation envoyée, 0 échec. » juste
        // au-dessus de « le courriel n'est pas parti ».
        expect(
          find.text(
            AppStrings.invitationsResume(creees: 1, parties: 0, echecs: 0),
          ),
          findsOneWidget,
        );
        expect(find.text(AppStrings.resultatCourrielNonParti), findsOneWidget);
        // Ce n'est pas un échec : rien à réessayer.
        expect(find.text(AppStrings.inviterReessayerEchecs), findsNothing);
        aucunEnvoiPromis(tester);
      });

      testWidgets('un lot dont tous les courriels partent : « envoyées »', (
        tester,
      ) async {
        final depot = FauxMembresRepository(
          rapport: const RapportInvitations(
            resultats: <ResultatInvitation>[
              ResultatInvitation(
                email: 'une@exemple.fr',
                statut: StatutResultatInvitation.invitee,
              ),
              ResultatInvitation(
                email: 'deux@exemple.fr',
                statut: StatutResultatInvitation.invitee,
              ),
            ],
          ),
        );
        await _ouvrirFormulaire(tester, depot);

        await tester.enterText(
          find.byType(TextField),
          'une@exemple.fr\ndeux@exemple.fr',
        );
        await tester.tap(find.text(AppStrings.inviterEnvoyer));
        await tester.pumpAndSettle();

        expect(
          find.text(
            AppStrings.invitationsResume(creees: 2, parties: 2, echecs: 0),
          ),
          findsOneWidget,
        );
        expect(find.text(AppStrings.resultatCourrielNonParti), findsNothing);
      });

      testWidgets('un lot dont un seul courriel part : « créées », et deux '
          'lignes le disent', (tester) async {
        final depot = FauxMembresRepository(
          rapport: const RapportInvitations(
            resultats: <ResultatInvitation>[
              ResultatInvitation(
                email: 'une@exemple.fr',
                statut: StatutResultatInvitation.invitee,
              ),
              ResultatInvitation(
                email: 'deux@exemple.fr',
                statut: StatutResultatInvitation.invitee,
                courrielEnvoye: false,
              ),
              ResultatInvitation(
                email: 'trois@exemple.fr',
                statut: StatutResultatInvitation.invitee,
                courrielEnvoye: false,
              ),
            ],
          ),
        );
        await _ouvrirFormulaire(tester, depot);

        await tester.enterText(
          find.byType(TextField),
          'une@exemple.fr\ndeux@exemple.fr\ntrois@exemple.fr',
        );
        await tester.tap(find.text(AppStrings.inviterEnvoyer));
        await tester.pumpAndSettle();

        expect(
          find.text(
            AppStrings.invitationsResume(creees: 3, parties: 1, echecs: 0),
          ),
          findsOneWidget,
        );
        // Le résumé ne compte pas les courriels restés à quai : ici, vingt
        // lignes au plus, et chacune porte déjà son sort. C'est l'import,
        // qui n'énumère rien, qui a besoin d'une phrase de plus.
        expect(
          find.text(AppStrings.resultatCourrielNonParti),
          findsNWidgets(2),
        );
        aucunEnvoiPromis(tester);
      });
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
