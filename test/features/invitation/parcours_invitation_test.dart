import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/auth/presentation/code_screen.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/invitation/domain/acceptation.dart';
import 'package:astreinte_sp/features/invitation/presentation/invitation_screen.dart';
import 'package:astreinte_sp/features/onboarding/presentation/profil_accueil_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';

const String _jeton = 'a1b2c3d4e5f6';
const String _lien = '/invite/$_jeton';

void main() {
  group('Parcours de l\'invité', () {
    testWidgets('le lien, la connexion par code, puis l\'acceptation', (
      tester,
    ) async {
      final invitations = FauxInvitationRepository();
      final montee = await monterApp(tester, invitations: invitations);

      // 1. Le lien s'ouvre sans être connecté, et ne révèle rien.
      await ouvrirRoute(tester, _lien);
      expect(find.byType(InvitationScreen), findsOneWidget);
      expect(find.text(AppStrings.invitationSeConnecter), findsOneWidget);

      // 2. La connexion par code, celle du ticket 005.
      await tester.tap(find.text(AppStrings.invitationSeConnecter));
      await tester.pumpAndSettle();
      expect(find.byType(ConnexionScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'recrue@exemple.fr');
      await tester.tap(find.text(AppStrings.connexionEnvoyer));
      await tester.pumpAndSettle();
      expect(find.byType(CodeScreen), findsOneWidget);

      // La caserne n'existe pour cet invité qu'une fois l'invitation acceptée.
      invitations.auSucces = () => montee.memberships.appartenances =
          const <Appartenance>[appartenanceMembre];

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();

      // 3. Le routeur ramène sur l'invitation, qui s'accepte toute seule.
      expect(invitations.jetons, <String>[_jeton]);
      expect(find.byType(InvitationScreen), findsOneWidget);
      expect(
        find.text(AppStrings.invitationRejointe('CIS Saint-Martin')),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.invitationParQui('Jean Dupont')),
        findsOneWidget,
      );

      // 4. Le complément de profil suit.
      await tester.tap(find.text(AppStrings.actionContinuer));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilAccueilScreen), findsOneWidget);
    });

    testWidgets('déjà connecté, le lien s\'accepte sans rien demander', (
      tester,
    ) async {
      final invitations = FauxInvitationRepository();
      final montee = await monterApp(
        tester,
        session: sessionMembre,
        invitations: invitations,
      );
      invitations.auSucces = () => montee.memberships.appartenances =
          const <Appartenance>[appartenanceMembre];

      await ouvrirRoute(tester, _lien);

      expect(invitations.jetons, <String>[_jeton]);
      expect(
        find.text(AppStrings.invitationRejointe('CIS Saint-Martin')),
        findsOneWidget,
      );
    });

    testWidgets('une invitation expirée dit à qui écrire', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(
          echec: const EchecAcceptation(
            ErreurAcceptation.expiree,
            caserne: CaserneInvitation(nom: 'CIS Saint-Martin'),
          ),
        ),
      );

      await ouvrirRoute(tester, _lien);

      expect(find.text(AppStrings.invitationExpireeTitre), findsOneWidget);
      expect(find.text(AppStrings.invitationExpireeTexte), findsOneWidget);
      expect(
        find.text(AppStrings.invitationContacterAdmin('CIS Saint-Martin')),
        findsOneWidget,
      );
    });

    testWidgets('une adresse qui ne correspond pas nomme les deux', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(
          echec: const EchecAcceptation(
            ErreurAcceptation.mauvaisCompte,
            adresseInviteeMasquee: 'r****e@exemple.fr',
            adresseCourante: 'membre1@caserne-a.test',
          ),
        ),
      );

      await ouvrirRoute(tester, _lien);

      expect(
        find.text(AppStrings.invitationMauvaisCompteTitre),
        findsOneWidget,
      );
      expect(find.textContaining('r****e@exemple.fr'), findsOneWidget);
      expect(find.textContaining('membre1@caserne-a.test'), findsOneWidget);
      expect(find.text(AppStrings.seDeconnecter), findsOneWidget);
    });

    testWidgets('une invitation déjà utilisée n\'est pas un cul-de-sac', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(
          echec: const EchecAcceptation(
            ErreurAcceptation.dejaAcceptee,
            caserne: CaserneInvitation(nom: 'CIS Saint-Martin'),
          ),
        ),
      );

      await ouvrirRoute(tester, _lien);

      expect(find.text(AppStrings.invitationDejaAccepteeTitre), findsOneWidget);
      expect(find.text(AppStrings.actionContinuer), findsOneWidget);
    });

    testWidgets('une caserne suspendue se refuse en le disant', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(
          echec: const EchecAcceptation(ErreurAcceptation.caserneSuspendue),
        ),
      );

      await ouvrirRoute(tester, _lien);

      expect(
        find.text(AppStrings.invitationCaserneSuspendueTitre),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.invitationCaserneSuspendueTexte),
        findsOneWidget,
      );
    });

    testWidgets('un incident réseau se réessaie', (tester) async {
      final invitations = FauxInvitationRepository(
        echec: const EchecAcceptation(ErreurAcceptation.reseau),
      );
      final montee = await monterApp(
        tester,
        session: sessionMembre,
        invitations: invitations,
      );

      await ouvrirRoute(tester, _lien);
      expect(find.text(AppStrings.erreurReseauTexte), findsOneWidget);

      invitations.echec = null;
      invitations.auSucces = () => montee.memberships.appartenances =
          const <Appartenance>[appartenanceMembre];

      await tester.tap(find.text(AppStrings.actionReessayer));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.invitationRejointe('CIS Saint-Martin')),
        findsOneWidget,
      );
    });
  });
}
