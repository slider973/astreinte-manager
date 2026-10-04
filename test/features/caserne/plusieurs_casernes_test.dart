import 'dart:async';

import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/bascule_caserne.dart';
import 'package:astreinte_sp/core/session/caserne_choisie.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/bouton_caserne.dart';
import 'package:astreinte_sp/features/invitation/domain/acceptation.dart';
import 'package:astreinte_sp/features/invitation/domain/invitation_recue.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:astreinte_sp/features/notifications/domain/message_push.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:astreinte_sp/features/notifications/presentation/couche_notifications.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_notifications.dart';
import '../../support/faux_propositions.dart';
import '../../support/faux_push.dart';
import '../../support/polices.dart';

/// Ticket 072 : un pompier dans plusieurs casernes, côté PWA.
///
/// Deux casernes : **Nord** (`appartenanceMembre`, « CIS Saint-Martin »,
/// membre), ouverte par défaut parce qu'elle vient la première dans l'ordre
/// alphabétique, et **Sud** (« CIS Val-de-Loue », administrateur).
const Appartenance _nord = appartenanceMembre;

const Appartenance _sud = Appartenance(
  id: 'm-sud',
  stationId: 'bbbbbbbb-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Val-de-Loue',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
);

const Appartenance _sudDesactivee = Appartenance(
  id: 'm-sud',
  stationId: 'bbbbbbbb-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Val-de-Loue',
  role: RoleMembre.admin,
  statut: StatutMembre.desactive,
);

const List<Appartenance> _deux = <Appartenance>[_nord, _sud];

final ContextePlateforme _androidInstalle = ContextePlateforme.depuisAgent(
  userAgent:
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, '
      'like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
  affichageAutonome: true,
);

ProviderContainer _conteneur(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(AstreinteApp)));

Appartenance? _ouverte(WidgetTester tester) =>
    _conteneur(tester).read(appartenanceCouranteProvider);

final DateTime _jourNord = DateTime(2026, 12, 5);
final DateTime _jourSud = DateTime(2026, 12, 19);

Future<AppMontee> _monterAvecPush(
  WidgetTester tester, {
  List<Appartenance> appartenances = _deux,
}) => monterApp(
  tester,
  session: sessionMembre,
  appartenances: appartenances,
  firebase: FirebaseDemarrage.pret,
  plateforme: _androidInstalle,
  messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
);

Future<void> _recevoir(
  WidgetTester tester,
  AppMontee faux,
  MessagePush message,
) async {
  faux.push.messages.add(message);
  await tester.pump();
  await tester.pump();
}

void main() {
  // -------------------------------------------------------------------
  // Le sélecteur
  // -------------------------------------------------------------------

  group('Le sélecteur de caserne', () {
    testWidgets('une seule caserne : ni sélecteur ni passerelle', (
      tester,
    ) async {
      final semantique = tester.ensureSemantics();
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[_nord],
        notifications: FauxNotificationsRepository(
          notifications: <NotificationInterne>[
            notification(id: 'n-1', stationId: _sud.stationId),
          ],
        ),
      );

      expect(find.bySemanticsLabel(RegExp('^Caserne ouverte')), findsNothing);

      await ouvrirRoute(tester, '/boite');
      expect(find.text(AppStrings.boitePasserelleAction), findsNothing);
      semantique.dispose();
    });

    testWidgets('à 390 : la puce sous la salutation, la feuille, deux '
        'touches', (tester) async {
      final semantique = tester.ensureSemantics();
      await monterApp(tester, session: sessionMembre, appartenances: _deux);

      expect(find.byType(BoutonCaserne), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            RegExp.escape(
              AppStrings.caserneSelecteurSemantique(_nord.nomCaserne),
            ),
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(_nord.nomCaserne));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.caserneChoixTitre), findsOneWidget);
      expect(find.text(AppStrings.caserneChoixOuverte), findsOneWidget);

      await tester.tap(find.text(_sud.nomCaserne));
      await tester.pumpAndSettle();

      // La feuille s'est fermée, la caserne a changé, et **pas de bandeau** :
      // la personne vient de le faire.
      expect(find.text(AppStrings.caserneChoixTitre), findsNothing);
      expect(_ouverte(tester)?.stationId, _sud.stationId);
      expect(find.text(_sud.nomCaserne), findsOneWidget);
      expect(
        find.text(AppStrings.bandeauCaserneOuverte(_sud.nomCaserne)),
        findsNothing,
      );
      tester.takeException();
      semantique.dispose();
    });

    testWidgets('à 1280 : le titre de l\'en-tête de travail ouvre un menu', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: _deux,
        taille: const Size(1280, 900),
      );

      // Une seule forme : la puce ne se double pas sous la salutation.
      expect(find.byType(BoutonCaserne), findsOneWidget);
      await tester.tap(find.text(_nord.nomCaserne));
      await tester.pumpAndSettle();

      // Un menu ancré, pas une feuille : pas de titre de feuille.
      expect(find.text(AppStrings.caserneChoixOuverte), findsOneWidget);
      expect(find.text(AppStrings.caserneChoixTitre), findsNothing);

      await tester.tap(find.text(_sud.nomCaserne));
      await tester.pumpAndSettle();
      expect(_ouverte(tester)?.stationId, _sud.stationId);
      expect(find.text(AppStrings.caserneChoixOuverte), findsNothing);
      tester.takeException();
    });

    testWidgets('un nom de 47 caractères à ×1,6 ne déborde pas, vraies '
        'polices', (tester) async {
      await chargerPolicesDuProduit();
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const longue = Appartenance(
        id: 'm-long',
        stationId: 'dddddddd-0000-4000-8000-000000000001',
        nomCaserne: 'Centre de secours de Saint-Rémy-lès-Chevreuse',
        role: RoleMembre.membre,
        statut: StatutMembre.actif,
      );
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[longue, _nord],
      );

      expect(find.byType(BoutonCaserne), findsOneWidget);
      expect(tester.takeException(), isNull);

      // La feuille aussi : le nom entier, sur deux lignes au plus.
      await tester.tap(find.byType(BoutonCaserne));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.caserneChoixTitre), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------
  // Aucune donnée de l'ancienne caserne
  // -------------------------------------------------------------------

  group('Après une bascule', () {
    testWidgets('aucune proposition de l\'ancienne caserne n\'est peinte '
        'avant la première réponse de la nouvelle', (tester) async {
      final propositions = FauxPropositionsRepository();
      // Deux à Nord, une à Sud : le compte de la section suffit à dire de
      // quelle caserne viennent les lignes.
      propositions.parCaserne[_nord.stationId] = <Proposition>[
        proposition(id: 'p-nord', jour: _jourNord),
        proposition(id: 'p-nord-2', jour: _jourNord, creneau: CreneauType.jour),
      ];
      propositions.parCaserne[_sud.stationId] = <Proposition>[
        proposition(id: 'p-sud', jour: _jourSud),
      ];
      final retenue = Completer<void>();
      propositions.retenues[_sud.stationId] = retenue;

      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: _deux,
        propositions: propositions,
      );
      String section(int n) => AppStrings.accueilSectionCompte(
        AppStrings.accueilPropositionsSection,
        n,
      );
      expect(find.text(section(2)), findsOneWidget);

      unawaited(
        _conteneur(
          tester,
        ).read(basculeCaserneProvider.notifier).choisir(_sud.stationId),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Le sélecteur dit déjà Sud ; les propositions de Nord ont disparu,
      // celles de Sud ne sont pas encore là.
      expect(find.text(_sud.nomCaserne), findsOneWidget);
      expect(find.text(section(2)), findsNothing);
      expect(find.text(section(1)), findsNothing);

      retenue.complete();
      await tester.pumpAndSettle();

      expect(find.text(section(1)), findsOneWidget);
      expect(find.text(section(2)), findsNothing);
      expect(propositions.casernesLues, contains(_sud.stationId));
      tester.takeException();
    });
  });

  // -------------------------------------------------------------------
  // Push et liens d'une autre caserne
  // -------------------------------------------------------------------

  group('Un push d\'une autre caserne', () {
    testWidgets('le bandeau du message nomme la caserne, « Voir » bascule et '
        'le bandeau de bascule le dit', (tester) async {
      final faux = await _monterAvecPush(tester);

      await _recevoir(
        tester,
        faux,
        MessagePush(
          titre: 'Astreinte proposée',
          route: '/proposals',
          stationId: _sud.stationId,
        ),
      );
      expect(
        find.text(
          AppStrings.pushTitreAutreCaserne(
            _sud.nomCaserne,
            'Astreinte proposée',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(AppStrings.notifBanniereVoir));
      await tester.pumpAndSettle();

      expect(_ouverte(tester)?.stationId, _sud.stationId);
      expect(emplacementCourant(tester), '/boite?onglet=propositions');
      expect(
        find.text(AppStrings.bandeauCaserneOuverte(_sud.nomCaserne)),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.bandeauRaisonNotification(_nord.nomCaserne)),
        findsOneWidget,
      );
      // Une seule bannière à la fois : celle du push s'est effacée.
      expect(find.text(AppStrings.notifBanniereVoir), findsNothing);

      // Huit secondes, puis plus rien — le nom reste dans le sélecteur.
      await tester.pump(CoucheNotifications.duree);
      await tester.pump();
      expect(
        find.text(AppStrings.bandeauCaserneOuverte(_sud.nomCaserne)),
        findsNothing,
      );
      tester.takeException();
    });

    testWidgets('« Revenir » rouvre l\'ancienne caserne, sur l\'accueil, sans '
        'nouveau bandeau', (tester) async {
      final faux = await _monterAvecPush(tester);
      await _recevoir(
        tester,
        faux,
        MessagePush(
          titre: 'Astreinte proposée',
          route: '/proposals',
          stationId: _sud.stationId,
        ),
      );
      await tester.tap(find.text(AppStrings.notifBanniereVoir));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.bandeauRevenir(_nord.nomCaserne)));
      await tester.pumpAndSettle();

      expect(_ouverte(tester)?.stationId, _nord.stationId);
      expect(emplacementCourant(tester), '/');
      expect(find.textContaining(' est ouverte.'), findsNothing);
      tester.takeException();
    });

    testWidgets('sous lecteur d\'écran, le bandeau attend « Fermer »', (
      tester,
    ) async {
      final semantique = tester.ensureSemantics();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final faux = await _monterAvecPush(tester);
      await _recevoir(
        tester,
        faux,
        MessagePush(
          titre: 'Astreinte proposée',
          route: '/proposals',
          stationId: _sud.stationId,
        ),
      );
      await tester.tap(find.text(AppStrings.notifBanniereVoir));
      await tester.pumpAndSettle();

      await tester.pump(CoucheNotifications.duree * 2);
      final texte = AppStrings.bandeauCaserneOuverte(_sud.nomCaserne);
      expect(find.text(texte), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(AppStrings.bandeauFermer));
      await tester.pumpAndSettle();
      expect(find.text(texte), findsNothing);
      tester.takeException();
      semantique.dispose();
    });

    testWidgets('une caserne où l\'accès n\'est pas actif : l\'accueil, sans '
        'bascule ni message', (tester) async {
      final faux = await _monterAvecPush(
        tester,
        appartenances: const <Appartenance>[_nord, _sudDesactivee],
      );
      await _recevoir(
        tester,
        faux,
        MessagePush(
          titre: 'Astreinte proposée',
          route: '/proposals',
          stationId: _sud.stationId,
        ),
      );
      // Pas de préfixe : ce n'est pas une caserne du compte.
      expect(find.text('Astreinte proposée'), findsOneWidget);
      await tester.tap(find.text(AppStrings.notifBanniereVoir));
      await tester.pumpAndSettle();

      expect(_ouverte(tester)?.stationId, _nord.stationId);
      expect(emplacementCourant(tester), '/');
      expect(find.textContaining(' est ouverte.'), findsNothing);
    });

    testWidgets('un push de la caserne ouverte ne change rien', (tester) async {
      final faux = await _monterAvecPush(tester);
      await _recevoir(
        tester,
        faux,
        MessagePush(
          titre: 'Astreinte proposée',
          route: '/proposals',
          stationId: _nord.stationId,
        ),
      );
      expect(find.text('Astreinte proposée'), findsOneWidget);
      await tester.tap(find.text(AppStrings.notifBanniereVoir));
      await tester.pumpAndSettle();

      expect(_ouverte(tester)?.stationId, _nord.stationId);
      expect(emplacementCourant(tester), '/boite?onglet=propositions');
      expect(find.textContaining(' est ouverte.'), findsNothing);
    });
  });

  group('Un lien d\'une autre caserne', () {
    testWidgets('?station= bascule, ouvre le chemin, puis disparaît de '
        'l\'adresse', (tester) async {
      await monterApp(tester, session: sessionMembre, appartenances: _deux);

      await ouvrirRoute(tester, '/proposals?station=${_sud.stationId}');

      expect(_ouverte(tester)?.stationId, _sud.stationId);
      expect(emplacementCourant(tester), '/boite?onglet=propositions');
      expect(
        find.text(AppStrings.bandeauRaisonLien(_nord.nomCaserne)),
        findsOneWidget,
      );
      tester.takeException();
    });

    testWidgets('le rôle de la caserne du lien ouvre l\'administration', (
      tester,
    ) async {
      // Membre à Nord, administrateur à Sud : sans la bascule avant la garde,
      // le lien du suivi retomberait sur l'accueil.
      await monterApp(tester, session: sessionMembre, appartenances: _deux);

      await ouvrirRoute(
        tester,
        '/admin/schedule/2026-11?station=${_sud.stationId}',
      );

      expect(_ouverte(tester)?.stationId, _sud.stationId);
      expect(emplacementCourant(tester), '/admin/suivi?mois=2026-11');
      tester.takeException();
    });

    testWidgets('une caserne inconnue : l\'accueil, sans bascule', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[_nord],
      );

      await ouvrirRoute(tester, '/proposals?station=${_sud.stationId}');

      expect(_ouverte(tester)?.stationId, _nord.stationId);
      expect(emplacementCourant(tester), '/');
      expect(find.textContaining(' est ouverte.'), findsNothing);
    });
  });

  // -------------------------------------------------------------------
  // L'accès retiré
  // -------------------------------------------------------------------

  testWidgets('l\'accès retiré à la caserne ouverte bascule vers l\'autre, '
      'sans « Revenir »', (tester) async {
    final faux = await monterApp(
      tester,
      session: sessionMembre,
      appartenances: _deux,
      caserneChoisie: CaserneChoisieLocaleMemoire(<String, String>{
        sessionMembre.userId: _sud.stationId,
      }),
    );
    expect(_ouverte(tester)?.stationId, _sud.stationId);

    faux.memberships.appartenances = const <Appartenance>[
      _nord,
      _sudDesactivee,
    ];
    _conteneur(tester).invalidate(appartenancesProvider);
    await tester.pumpAndSettle();

    expect(_ouverte(tester)?.stationId, _nord.stationId);
    expect(
      find.text(AppStrings.bandeauRaisonDesactivee(_sud.nomCaserne)),
      findsOneWidget,
    );
    expect(find.textContaining('Revenir à'), findsNothing);
    await tester.pump(CoucheNotifications.duree);
    tester.takeException();
  });

  // -------------------------------------------------------------------
  // Les invitations d'un membre déjà rattaché
  // -------------------------------------------------------------------

  group('Les invitations d\'un membre déjà rattaché', () {
    InvitationRecue invitation({
      required String id,
      required String caserne,
      bool expiree = false,
    }) => InvitationRecue(
      id: id,
      caserne: caserne,
      echeance: DateTime(2026, 10, 18, 12),
      expiree: expiree,
      inviteur: 'Jean Martin',
    );

    testWidgets('la carte en tête de l\'accueil, rien pour l\'expirée', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[_nord],
        invitations: FauxInvitationRepository(
          recues: <InvitationRecue>[
            invitation(id: 'inv-1', caserne: 'CS Ury'),
            invitation(id: 'inv-2', caserne: 'CS Vieille', expiree: true),
          ],
        ),
      );

      expect(
        find.text(AppStrings.accueilInvitationTitre('CS Ury')),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.accueilInvitationTitre('CS Vieille')),
        findsNothing,
      );

      await tester.tap(find.text(AppStrings.accueilInvitationAction));
      await tester.pumpAndSettle();
      expect(emplacementCourant(tester), startsWith('/rejoindre/inv-1'));
      tester.takeException();
    });

    testWidgets('une lecture en échec ne met pas l\'accueil en erreur', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[_nord],
        invitations: FauxInvitationRepository(
          echecLecture: Exception('réseau'),
        ),
      );

      expect(find.text(AppStrings.accueilErreurTexte), findsNothing);
      expect(find.text(AppStrings.accueilInvitationAction), findsNothing);
    });

    testWidgets('accepter l\'invitation d\'une seconde caserne l\'ouvre', (
      tester,
    ) async {
      late AppMontee faux;
      final invitations = FauxInvitationRepository(
        resultat: AcceptationInvitation(
          dejaAcceptee: false,
          role: RoleMembre.admin,
          caserne: CaserneInvitation(nom: _sud.nomCaserne),
          stationId: _sud.stationId,
        ),
        auSucces: () => faux.memberships.appartenances = _deux,
      );
      faux = await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[_nord],
        invitations: invitations,
      );
      expect(_ouverte(tester)?.stationId, _nord.stationId);

      await ouvrirRoute(tester, '/rejoindre/inv-sud');
      await tester.pumpAndSettle();

      expect(invitations.identifiants, <String>['inv-sud']);
      expect(_ouverte(tester)?.stationId, _sud.stationId);
      // La page « Bienvenue » le dit déjà : pas de bandeau en plus.
      expect(find.textContaining(' est ouverte.'), findsNothing);
      tester.takeException();
    });
  });

  // -------------------------------------------------------------------
  // La Boîte, filtrée
  // -------------------------------------------------------------------

  testWidgets('la Boîte ne montre que la caserne ouverte, et sa passerelle '
      'mène à l\'autre', (tester) async {
    final notifications = FauxNotificationsRepository(
      notifications: <NotificationInterne>[
        notification(
          id: 'n-nord',
          titre: 'Rappel Nord',
          stationId: _nord.stationId,
        ),
        notification(
          id: 'n-sud',
          titre: 'Rappel Sud',
          stationId: _sud.stationId,
        ),
        notification(id: 'n-compte', titre: 'Rappel du compte'),
      ],
    );
    await monterApp(
      tester,
      session: sessionMembre,
      appartenances: _deux,
      notifications: notifications,
    );
    await ouvrirRoute(tester, '/boite');

    expect(find.text('Rappel Nord'), findsOneWidget);
    expect(find.text('Rappel du compte'), findsOneWidget);
    expect(find.text('Rappel Sud'), findsNothing);
    // Le titre ne compte que ce qui est à l'écran.
    expect(find.text(AppStrings.boiteTitre(2)), findsWidgets);
    expect(
      find.text(AppStrings.boitePasserelle(_sud.nomCaserne, 1)),
      findsOneWidget,
    );

    await tester.tap(find.text(AppStrings.boitePasserelleAction));
    await tester.pumpAndSettle();

    expect(_ouverte(tester)?.stationId, _sud.stationId);
    expect(emplacementCourant(tester), '/boite');
    expect(find.text('Rappel Sud'), findsOneWidget);
    expect(find.text('Rappel Nord'), findsNothing);
    expect(
      find.text(AppStrings.boitePasserelle(_nord.nomCaserne, 1)),
      findsOneWidget,
    );

    // « Tout marquer comme lu » ne marque que la caserne ouverte.
    await tester.tap(find.text(AppStrings.centreToutMarquerLu));
    await tester.pumpAndSettle();
    expect(notifications.casernesMarquees, <String?>[_sud.stationId]);
    expect(
      notifications.notifications
          .firstWhere((NotificationInterne n) => n.id == 'n-nord')
          .lue,
      isFalse,
    );
    tester.takeException();
  });
}
