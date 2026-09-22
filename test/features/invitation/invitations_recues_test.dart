import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/barre_actions_basse.dart';
import 'package:astreinte_sp/core/widgets/ecran_simple.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/auth/presentation/aucune_caserne_screen.dart';
import 'package:astreinte_sp/features/invitation/domain/invitation_recue.dart';
import 'package:astreinte_sp/features/invitation/presentation/invitation_screen.dart';
import 'package:astreinte_sp/features/invitation/presentation/widgets/ligne_invitation_recue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/polices.dart';

/// Le 21 septembre 2026 en production : quelqu'un se connecte avec l'adresse
/// qui vient d'être invitée, sans passer par le lien du courriel, et « Aucune
/// caserne » lui répond d'aller demander ce qu'il a déjà.
void main() {
  group('Aucune caserne, quand une invitation attend', () {
    testWidgets('pendant la recherche : le titre neutre, un squelette, et '
        'surtout pas le conseil', (tester) async {
      final invitations = FauxInvitationRepository(lectureSuspendue: true);

      await monterApp(
        tester,
        session: sessionMembre,
        invitations: invitations,
        stabiliser: false,
      );
      // `pumpAndSettle` ne rend jamais la main devant un squelette : son
      // balayage tourne en boucle. On avance donc à la main, le temps que le
      // routeur pose l'écran.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byType(AucuneCaserneScreen), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneTitreNeutre), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneVerification), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AucuneCaserneScreen),
          matching: find.byType(LoadingSkeleton),
        ),
        findsOneWidget,
      );
      // Jamais de roue au milieu de l'écran (`DESIGN.md § Don't`).
      expect(
        find.descendant(
          of: find.byType(AucuneCaserneScreen),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );

      // Le défaut réparé par ce ticket : la phrase ne doit pas s'afficher
      // pendant l'attente non plus. Lue une fois, elle a déjà fait partir.
      expect(find.text(AppStrings.aucuneCaserneTexte), findsNothing);
      expect(find.text(AppStrings.aucuneCaserneTitre), findsNothing);

      // La sortie reste, dans toutes les formes : se tromper d'adresse est
      // exactement l'erreur que cet écran reçoit.
      expect(find.text(AppStrings.seDeconnecter), findsOneWidget);
    });

    testWidgets('une invitation en attente s\'affiche, et se rejoint sans '
        'relire son courriel', (tester) async {
      final invitations = FauxInvitationRepository(
        recues: <InvitationRecue>[invitationRecue()],
      );
      final montee = await monterApp(
        tester,
        session: sessionMembre,
        invitations: invitations,
      );

      expect(find.text(AppStrings.invitationsRecuesTitre(1)), findsOneWidget);
      expect(
        find.text(AppStrings.invitationsRecuesIntro(sessionMembre.email, 1)),
        findsOneWidget,
      );
      expect(find.text('CS Maurepas'), findsOneWidget);
      expect(
        find.text(AppStrings.invitationParQui('Marc Dubois')),
        findsOneWidget,
      );
      expect(find.text(AppStrings.invitationEnAttente), findsOneWidget);
      expect(
        find.text(
          AppStrings.invitationExpireLe(
            formaterDateLongue(DateTime(2026, 10, 5)),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(AppStrings.aucuneCaserneTexte), findsNothing);

      // La caserne n'existe pour cet invité qu'une fois l'invitation acceptée.
      invitations.auSucces = () => montee.memberships.appartenances =
          const <Appartenance>[appartenanceMembre];

      await tester.tap(
        find.text(AppStrings.invitationRejoindre('CS Maurepas')),
      );
      await tester.pumpAndSettle();

      // L'identifiant, et **seulement** lui : cet écran n'a jamais vu de jeton.
      expect(invitations.identifiants, <String>['inv-1']);
      expect(invitations.jetons, isEmpty);

      // Et l'arrivée est celle du lien du courriel : « Bienvenue », la caserne
      // nommée, puis le profil.
      expect(find.byType(InvitationScreen), findsOneWidget);
      expect(find.text(AppStrings.invitationAccepteeTitre), findsOneWidget);
      expect(
        find.text(AppStrings.invitationRejointe('CIS Saint-Martin')),
        findsOneWidget,
      );
    });

    testWidgets('plusieurs invitations : aucune n\'est « la » bonne', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(
          recues: <InvitationRecue>[
            invitationRecue(),
            invitationRecue(
              id: 'inv-2',
              caserne: 'CS Trappes',
              inviteur: null,
              echeance: DateTime(2026, 10, 12),
            ),
          ],
        ),
      );

      expect(find.text(AppStrings.invitationsRecuesTitre(2)), findsOneWidget);
      expect(
        find.text(AppStrings.invitationsRecuesIntro(sessionMembre.email, 2)),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.invitationRejoindre('CS Maurepas')),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.invitationRejoindre('CS Trappes')),
        findsOneWidget,
      );

      // Sans nom d'invitant, la ligne est **omise**, jamais remplie par une
      // adresse.
      expect(find.textContaining('Invitation envoyée par'), findsOneWidget);

      for (final bouton in tester.widgetList<PrimaryButton>(
        find.byType(PrimaryButton),
      )) {
        if (bouton.libelle.startsWith('Rejoindre')) {
          expect(bouton.variante, PrimaryButtonVariante.secondaire);
        }
      }
    });

    testWidgets('une invitation expirée n\'est pas une invitation absente', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(
          recues: <InvitationRecue>[invitationRecue(expiree: true)],
        ),
      );

      expect(find.text(AppStrings.invitationsExpireesTitre(1)), findsOneWidget);
      expect(find.text(AppStrings.invitationExpiree), findsOneWidget);
      expect(
        find.text(
          AppStrings.invitationExpireeDepuis(
            formaterDateLongue(DateTime(2026, 10, 5)),
          ),
        ),
        findsOneWidget,
      );

      // Elle nomme à qui redemander, et n'offre pas un bouton dont on sait
      // qu'il échouerait.
      expect(
        find.text(AppStrings.invitationExpireeDemander('Marc Dubois')),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.invitationRejoindre('CS Maurepas')),
        findsNothing,
      );
      expect(find.text(AppStrings.aucuneCaserneTexte), findsNothing);
    });

    testWidgets('une expirée sous une valide garde sa ligne et sa phrase', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(
          // Lues comme la réponse du serveur, pour que l'ordre d'affichage
          // soit celui de la vraie chaîne et non celui du test.
          recues: InvitationRecue.depuisListe(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'inv-2',
              'station_name': 'CS Trappes',
              'invited_by_name': null,
              'expires_at': '2026-08-01T12:00:00+02:00',
              'status': 'expired',
            },
            <String, dynamic>{
              'id': 'inv-1',
              'station_name': 'CS Maurepas',
              'invited_by_name': 'Marc Dubois',
              'expires_at': '2026-10-05T12:00:00+02:00',
              'status': 'pending',
            },
          ]),
        ),
      );

      // Le titre compte les invitations qu'on peut rejoindre, pas les autres.
      expect(find.text(AppStrings.invitationsRecuesTitre(1)), findsOneWidget);
      expect(
        find.text(AppStrings.invitationRejoindre('CS Maurepas')),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.invitationExpireeDemanderSansNom),
        findsOneWidget,
      );

      // La valide d'abord, l'expirée en dernier.
      expect(
        tester.getTopLeft(find.text('CS Maurepas')).dy,
        lessThan(tester.getTopLeft(find.text('CS Trappes')).dy),
      );
    });

    testWidgets('aucune invitation : le texte du ticket 006, inchangé', (
      tester,
    ) async {
      final invitations = FauxInvitationRepository();

      await monterApp(tester, session: sessionMembre, invitations: invitations);

      expect(invitations.lectures, 1);
      expect(find.text(AppStrings.aucuneCaserneTitre), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneTexte), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneTitreNeutre), findsNothing);
    });

    testWidgets('la recherche en échec dit le fait, et abandonne le conseil', (
      tester,
    ) async {
      final invitations = FauxInvitationRepository(
        echecLecture: const FormatException('réponse illisible'),
      );

      await monterApp(tester, session: sessionMembre, invitations: invitations);

      expect(find.text(AppStrings.aucuneCaserneTitreNeutre), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneFait), findsOneWidget);
      expect(find.text(AppStrings.invitationsRecuesEchec), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneTexte), findsNothing);

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.erreur);

      // « Réessayer » repose la question.
      await tester.tap(find.text(AppStrings.actionReessayer));
      await tester.pumpAndSettle();
      expect(invitations.lectures, 2);
    });

    testWidgets('hors ligne, l\'écran accuse le réseau et pas le compte', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        reseau: ConnectiviteMemoire(enLigne: false),
        invitations: FauxInvitationRepository(
          echecLecture: const FormatException('pas de réseau'),
        ),
      );

      expect(find.text(AppStrings.invitationsRecuesHorsLigne), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneFait), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneTexte), findsNothing);

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.horsLigne);
    });

    testWidgets('un accès désactivé garde son écran quand rien n\'attend', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceDesactivee],
        invitations: FauxInvitationRepository(),
      );

      expect(find.text(AppStrings.caserneDesactiveeTitre), findsOneWidget);
      expect(
        find.text(AppStrings.caserneDesactiveeTexte('CIS Saint-Martin')),
        findsOneWidget,
      );
    });

    testWidgets('un accès désactivé + une invitation : l\'invitation gagne le '
        'centre, le fait reste en bannière', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceDesactivee],
        invitations: FauxInvitationRepository(
          recues: <InvitationRecue>[invitationRecue()],
        ),
      );

      expect(find.text(AppStrings.invitationsRecuesTitre(1)), findsOneWidget);
      expect(
        find.text(AppStrings.invitationRejoindre('CS Maurepas')),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.caserneDesactiveeRappel('CIS Saint-Martin')),
        findsOneWidget,
      );
      expect(find.text(AppStrings.caserneDesactiveeTitre), findsNothing);

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.information);
    });
  });

  /// Ce que le superviseur a vu sur la vitrine de la branche, et que les
  /// assertions par `find.text` ne voyaient pas : un texte coupé porte le même
  /// nom que le texte entier, et un bouton trop large trouve son libellé.
  group('Le fini, mesuré à l\'écran', () {
    /// Aucun texte de bannière n'est coupé.
    ///
    /// `AppBanner` plafonne à deux lignes et met des points de suspension :
    /// c'est une règle de `DESIGN.md`, pas un accident, donc c'est à la phrase
    /// de tenir. Un message d'erreur tronqué ne dit plus ce qui se passe — et
    /// ici la moitié perdue était la seule qui disait « une invitation
    /// t'attend peut-être ».
    void attendreAucuneCoupure(WidgetTester tester) {
      final textes = find.descendant(
        of: find.byType(AppBanner),
        matching: find.byType(RichText),
      );
      expect(textes, findsWidgets);
      for (final element in textes.evaluate()) {
        final paragraphe = element.renderObject! as RenderParagraph;
        expect(
          paragraphe.didExceedMaxLines,
          isFalse,
          reason:
              'coupé à ${paragraphe.size.width} points : '
              '« ${paragraphe.text.toPlainText()} »',
        );
      }
    }

    testWidgets('390 points : l\'échec se lit en entier, action comprise', (
      tester,
    ) async {
      await chargerPolicesDuProduit();
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(
          echecLecture: const FormatException('réponse illisible'),
        ),
      );

      expect(find.text(AppStrings.invitationsRecuesEchec), findsOneWidget);
      attendreAucuneCoupure(tester);
    });

    testWidgets('390 points : le hors-ligne se lit en entier', (tester) async {
      await chargerPolicesDuProduit();
      await monterApp(
        tester,
        session: sessionMembre,
        reseau: ConnectiviteMemoire(enLigne: false),
        invitations: FauxInvitationRepository(
          echecLecture: const FormatException('pas de réseau'),
        ),
      );

      expect(find.text(AppStrings.invitationsRecuesHorsLigne), findsOneWidget);
      attendreAucuneCoupure(tester);
    });

    /// Le défaut du ticket 048, d'un cran plus petit : une barre d'actions
    /// pleine fenêtre sous une colonne bornée.
    testWidgets('1280 points : « Se déconnecter » a la largeur de la colonne, '
        'centré', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(
          recues: <InvitationRecue>[invitationRecue()],
        ),
        taille: const Size(1280, 900),
      );

      expect(find.byType(BarreActionsBasse), findsOneWidget);
      final bouton = tester.getRect(
        find.widgetWithText(PrimaryButton, AppStrings.seDeconnecter),
      );
      expect(bouton.width, EcranSimple.colonneLecture);
      expect(bouton.center.dx, 1280 / 2);

      // Et le corps qu'elle termine est bien cette colonne-là : le pied ne
      // déborde pas de son écran, l'écran ne déborde pas de son pied.
      expect(
        tester.getRect(find.byType(LigneInvitationRecue)).width,
        lessThanOrEqualTo(EcranSimple.colonneLecture),
      );
      expect(
        tester.getRect(find.byType(LigneInvitationRecue)).center.dx,
        1280 / 2,
      );
    });

    testWidgets('1280 points : l\'état vide garde son centrage sous la barre', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(),
        taille: const Size(1280, 900),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(tester.getRect(find.byType(EmptyState)).center.dx, 1280 / 2);

      final bouton = tester.getRect(
        find.widgetWithText(PrimaryButton, AppStrings.seDeconnecter),
      );
      expect(bouton.width, EcranSimple.colonneLecture);
      expect(bouton.center.dx, 1280 / 2);

      // La barre reste au-dessous du corps, jamais par-dessus.
      expect(
        tester.getRect(find.byType(EmptyState)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(BarreActionsBasse)).top),
      );
    });

    testWidgets('pendant la recherche aussi, la sortie garde sa colonne', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        invitations: FauxInvitationRepository(lectureSuspendue: true),
        taille: const Size(1280, 900),
        stabiliser: false,
      );
      // Assez de trames pour que la transition de route soit finie : mesurer
      // un écran qui glisse encore mesure la transition, pas la mise en page.
      // `pumpAndSettle` ne rend jamais la main devant un squelette.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byType(LoadingSkeleton), findsWidgets);
      expect(find.text(AppStrings.seDeconnecter), findsOneWidget);
      final bouton = tester.getRect(
        find.widgetWithText(PrimaryButton, AppStrings.seDeconnecter),
      );
      expect(bouton.width, EcranSimple.colonneLecture);
      expect(bouton.center.dx, 1280 / 2);
    });
  });

  group('La route /rejoindre', () {
    testWidgets('s\'ouvre sur un compte sans caserne, sans être renvoyée', (
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

      await ouvrirRoute(tester, '/rejoindre/inv-1');

      expect(find.byType(AucuneCaserneScreen), findsNothing);
      expect(find.byType(InvitationScreen), findsOneWidget);
      expect(invitations.identifiants, <String>['inv-1']);
      expect(invitations.jetons, isEmpty);

      // Et l'appartenance qui apparaît ne l'arrache pas vers l'accueil : la
      // chaîne « Bienvenue → profil → guide » doit pouvoir se dérouler.
      expect(find.text(AppStrings.invitationAccepteeTitre), findsOneWidget);
    });
  });
}
