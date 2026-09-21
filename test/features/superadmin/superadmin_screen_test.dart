import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/champ_texte.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/superadmin/data/superadmin_repository.dart';
import 'package:astreinte_sp/features/superadmin/domain/caserne_supervisee.dart';
import 'package:astreinte_sp/features/superadmin/presentation/superadmin_screen.dart';
import 'package:astreinte_sp/features/superadmin/presentation/widgets/bloc_caserne.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_superadmin.dart';

/// Un écran de bureau : c'est là que l'éditeur travaille, et trois blocs
/// doivent y tenir sans défilement acrobatique.
const Size _fenetre = Size(900, 1400);

typedef Montage = ({
  FauxSuperAdminRepository editeur,
  FauxMembresRepository membres,
});

Future<Montage> _ouvrir(
  WidgetTester tester, {
  FauxSuperAdminRepository? editeur,
  FauxMembresRepository? membres,
  List<Appartenance> appartenances = const <Appartenance>[],
}) async {
  final depot = editeur ?? FauxSuperAdminRepository();
  final depotMembres = membres ?? FauxMembresRepository();
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: appartenances,
    membres: depotMembres,
    superAdmin: depot,
    taille: _fenetre,
  );
  await ouvrirRoute(tester, '/superadmin');
  return (editeur: depot, membres: depotMembres);
}

/// Touche un bouton d'action d'une ligne, désigné par son libellé annoncé.
Future<void> _toucher(
  WidgetTester tester,
  String action,
  String caserne,
) async {
  final cible = find.bySemanticsLabel(
    AppStrings.superAdminActionSemantique(action, caserne),
  );
  expect(cible, findsOneWidget, reason: '$action sur $caserne');
  await tester.tap(cible);
  await tester.pumpAndSettle();
}

Future<void> _remplirEtValider(
  WidgetTester tester, {
  required String champ,
  required String valeur,
  required String bouton,
}) async {
  await tester.enterText(_champ(champ), valeur);
  await tester.pumpAndSettle();
  await tester.tap(_bouton(bouton));
  await tester.pumpAndSettle();
}

/// Le champ de saisie sous un libellé : `ChampTexte` place le libellé **à
/// côté** du `TextField`, jamais dedans (`DESIGN.md § Inputs`).
Finder _champ(String libelle) => find.descendant(
  of: find.widgetWithText(ChampTexte, libelle),
  matching: find.byType(TextField),
);

Finder _bouton(String libelle) => find.widgetWithText(PrimaryButton, libelle);

void main() {
  group('La porte de /superadmin', () {
    testWidgets('un administrateur de caserne est renvoyé à l\'accueil', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(autorise: false),
        appartenances: <Appartenance>[appartenanceAdmin],
      );

      expect(find.byType(SuperAdminScreen), findsNothing);
      expect(emplacementCourant(tester), '/');
    });

    testWidgets('un simple membre aussi', (tester) async {
      await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(autorise: false),
        appartenances: <Appartenance>[appartenanceMembre],
      );

      expect(find.byType(SuperAdminScreen), findsNothing);
      expect(emplacementCourant(tester), '/');
    });

    testWidgets('et il ne lit rien au passage : aucune liste n\'est demandée', (
      tester,
    ) async {
      final montage = await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(autorise: false),
        appartenances: <Appartenance>[appartenanceAdmin],
      );

      expect(montage.editeur.lectures, 0);
    });

    // Le cas nominal : l'éditeur n'est membre d'aucune caserne. Sans la branche
    // `sansCaserne` de la garde, il atterrirait sur « Aucune caserne ».
    testWidgets('l\'éditeur, membre d\'aucune caserne, entre', (tester) async {
      await _ouvrir(tester);

      expect(find.byType(SuperAdminScreen), findsOneWidget);
      expect(emplacementCourant(tester), '/superadmin');
    });
  });

  group('La liste des casernes', () {
    testWidgets('les cinq faits de chaque ligne sont là', (tester) async {
      await _ouvrir(tester);

      expect(find.text(caserneA.nom), findsOneWidget);
      expect(find.text(AppStrings.superAdminEffectif(9, 1)), findsOneWidget);
      expect(find.text(AppStrings.abonnementEtatEssai), findsWidgets);
      expect(find.textContaining('3 mars 2026'), findsOneWidget);
      expect(find.textContaining('novembre 2026'), findsOneWidget);
    });

    testWidgets('une caserne sans planning publié le dit, au lieu d\'un vide', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text(AppStrings.superAdminAucunPlanning), findsOneWidget);
    });

    testWidgets('une caserne sans administrateur porte son défaut', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text(AppStrings.superAdminSansAdmin), findsOneWidget);
    });

    testWidgets('une caserne suspendue propose « Réactiver », pas '
        '« Suspendre »', (tester) async {
      await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(
          casernes: <CaserneSupervisee>[caserneSuspendue],
        ),
      );

      expect(
        find.bySemanticsLabel(
          AppStrings.superAdminActionSemantique(
            AppStrings.superAdminReactiver,
            caserneSuspendue.nom,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          AppStrings.superAdminActionSemantique(
            AppStrings.superAdminSuspendre,
            caserneSuspendue.nom,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('un parc vide explique et propose une action', (tester) async {
      await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(
          casernes: const <CaserneSupervisee>[],
        ),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(AppStrings.superAdminVideTexte), findsOneWidget);
      expect(find.text(AppStrings.superAdminCreer), findsOneWidget);
    });

    testWidgets('chaque ligne est un bloc, jamais une carte ombrée', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.byType(BlocCaserne), findsNWidgets(2));
      expect(find.byType(Card), findsNothing);
    });
  });

  group('Créer une caserne', () {
    testWidgets('le nom et le fuseau suffisent — le slug n\'est pas demandé', (
      tester,
    ) async {
      final montage = await _ouvrir(tester);

      await tester.tap(find.text(AppStrings.superAdminCreer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.superAdminCreerTitre), findsOneWidget);
      expect(find.text(AppStrings.superAdminChampNom), findsOneWidget);
      expect(find.text(AppStrings.superAdminChampFuseau), findsOneWidget);
      expect(find.textContaining('slug'), findsNothing);

      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampNom,
        valeur: 'CIS Forêt-sur-Sèvre',
        bouton: AppStrings.superAdminCreerValider,
      );

      expect(montage.editeur.creations, hasLength(1));
      expect(montage.editeur.creations.single.nom, 'CIS Forêt-sur-Sèvre');
      expect(montage.editeur.creations.single.fuseau, 'Europe/Paris');
    });

    testWidgets('un nom vide est refusé avant l\'envoi', (tester) async {
      final montage = await _ouvrir(tester);

      await tester.tap(find.text(AppStrings.superAdminCreer));
      await tester.pumpAndSettle();
      await tester.tap(_bouton(AppStrings.superAdminCreerValider));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.superAdminRefusNom), findsOneWidget);
      expect(montage.editeur.creations, isEmpty);
    });

    // Une caserne sans administrateur est un cul-de-sac : la création enchaîne
    // sur l'invitation plutôt que de laisser l'éditeur y arriver par
    // distraction (`design/031 § 4`).
    testWidgets('la création enchaîne sur le premier administrateur', (
      tester,
    ) async {
      await _ouvrir(tester);

      await tester.tap(find.text(AppStrings.superAdminCreer));
      await tester.pumpAndSettle();
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampNom,
        valeur: 'CIS Neuve',
        bouton: AppStrings.superAdminCreerValider,
      );

      expect(find.text(AppStrings.superAdminInviterTitre), findsOneWidget);
    });

    testWidgets('un refus du serveur reste lisible', (tester) async {
      await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(
          echecCreation: ErreurSuperAdmin.fuseau,
        ),
      );

      await tester.tap(find.text(AppStrings.superAdminCreer));
      await tester.pumpAndSettle();
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampNom,
        valeur: 'CIS Ailleurs',
        bouton: AppStrings.superAdminCreerValider,
      );

      expect(find.text(AppStrings.superAdminRefusFuseau), findsOneWidget);
    });
  });

  group('Nommer le premier administrateur', () {
    // Le point du ticket : **le chemin du 006 et aucun autre**. L'invitation
    // part par `MembresRepository.inviter`, donc par l'Edge Function
    // `invite-member`, donc par `create_invitation`.
    testWidgets('l\'invitation emprunte le chemin du ticket 006', (
      tester,
    ) async {
      final montage = await _ouvrir(tester);

      await _toucher(
        tester,
        AppStrings.superAdminInviterAdmin,
        caserneSansAdmin.nom,
      );
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampEmail,
        valeur: 'chef@cis-neuve.test',
        bouton: AppStrings.superAdminInviterValider,
      );

      expect(montage.membres.envois, <List<String>>[
        <String>['chef@cis-neuve.test'],
      ]);
      expect(montage.membres.rolesEnvoyes, <RoleMembre>[RoleMembre.admin]);
      expect(montage.membres.casernesInvitees, <String>[caserneSansAdmin.id]);
    });

    testWidgets('la réussite est annoncée, jamais silencieuse', (tester) async {
      await _ouvrir(tester);

      await _toucher(
        tester,
        AppStrings.superAdminInviterAdmin,
        caserneSansAdmin.nom,
      );
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampEmail,
        valeur: 'chef@cis-neuve.test',
        bouton: AppStrings.superAdminInviterValider,
      );

      expect(
        find.text(
          AppStrings.superAdminInvitationEnvoyee('chef@cis-neuve.test'),
        ),
        findsOneWidget,
      );
    });
  });

  group('Suspendre et réactiver', () {
    testWidgets('suspendre demande une raison et promet que rien n\'est '
        'supprimé', (tester) async {
      final montage = await _ouvrir(tester);

      await _toucher(tester, AppStrings.superAdminSuspendre, caserneA.nom);

      expect(
        find.text(AppStrings.superAdminSuspendreTitre(caserneA.nom)),
        findsOneWidget,
      );
      // La promesse du produit (`PRD § 6.6`, § 7.6), due ici comme au 030.
      expect(find.text(AppStrings.superAdminSuspendreAide), findsOneWidget);
      expect(montage.editeur.suspensions, isEmpty);

      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampRaison,
        valeur: 'Impayé constaté hors Stripe, demande du trésorier',
        bouton: AppStrings.superAdminSuspendreValider,
      );

      expect(montage.editeur.suspensions, hasLength(1));
      expect(montage.editeur.suspensions.single.stationId, caserneA.id);
      expect(montage.editeur.suspensions.single.suspendue, isTrue);
      expect(
        montage.editeur.suspensions.single.raison,
        'Impayé constaté hors Stripe, demande du trésorier',
      );
    });

    testWidgets('une raison trop courte ne part pas', (tester) async {
      final montage = await _ouvrir(tester);

      await _toucher(tester, AppStrings.superAdminSuspendre, caserneA.nom);
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampRaison,
        valeur: 'pourquoi',
        bouton: AppStrings.superAdminSuspendreValider,
      );

      expect(find.text(AppStrings.superAdminRefusRaison), findsOneWidget);
      expect(montage.editeur.suspensions, isEmpty);
    });

    testWidgets('la suspension est annoncée et la ligne change d\'état', (
      tester,
    ) async {
      await _ouvrir(tester);

      await _toucher(tester, AppStrings.superAdminSuspendre, caserneA.nom);
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampRaison,
        valeur: 'Impayé constaté hors Stripe, demande du trésorier',
        bouton: AppStrings.superAdminSuspendreValider,
      );

      expect(
        find.text(AppStrings.superAdminSuspendue(caserneA.nom)),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          AppStrings.superAdminActionSemantique(
            AppStrings.superAdminReactiver,
            caserneA.nom,
          ),
        ),
        findsOneWidget,
      );
    });

    // Réactiver ne détruit rien : pas de confirmation, un geste, un résultat.
    testWidgets('réactiver ne passe pas par une confirmation', (tester) async {
      final montage = await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(
          casernes: <CaserneSupervisee>[caserneSuspendue],
        ),
      );

      await _toucher(
        tester,
        AppStrings.superAdminReactiver,
        caserneSuspendue.nom,
      );

      expect(montage.editeur.suspensions, hasLength(1));
      expect(montage.editeur.suspensions.single.suspendue, isFalse);
      // La raison part quand même : c'est elle qui sera au journal d'audit.
      expect(
        montage.editeur.suspensions.single.raison.length,
        greaterThanOrEqualTo(10),
      );
      expect(
        find.text(AppStrings.superAdminReactivee(caserneSuspendue.nom)),
        findsOneWidget,
      );
    });
  });

  group('La consultation de support', () {
    // Le point de sécurité central, vu depuis l'écran : **rien n'est lu tant
    // qu'une raison n'a pas été écrite**, parce que c'est elle qui fait la
    // ligne d'audit.
    testWidgets('aucun planning n\'est lu sans raison écrite', (tester) async {
      final montage = await _ouvrir(tester);

      await _toucher(tester, AppStrings.superAdminConsulter, caserneA.nom);
      expect(montage.editeur.consultations, isEmpty);

      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampRaison,
        valeur: 'court',
        bouton: AppStrings.superAdminSupportValider,
      );

      expect(find.text(AppStrings.superAdminRefusRaison), findsOneWidget);
      expect(montage.editeur.consultations, isEmpty);
    });

    testWidgets('la feuille annonce la trace avant d\'ouvrir, pas après', (
      tester,
    ) async {
      await _ouvrir(tester);

      await _toucher(tester, AppStrings.superAdminConsulter, caserneA.nom);

      expect(find.text(AppStrings.superAdminSupportAide), findsOneWidget);
      expect(find.text(AppStrings.superAdminSupportPortee), findsOneWidget);
    });

    testWidgets('avec une raison, la consultation part avec elle', (
      tester,
    ) async {
      final montage = await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(
          plannings_: <PlanningSupervise>[planningSupport],
        ),
      );

      await _toucher(tester, AppStrings.superAdminConsulter, caserneA.nom);
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampRaison,
        valeur: 'Ticket support 42 : le planning de mars ne se valide pas',
        bouton: AppStrings.superAdminSupportValider,
      );

      expect(montage.editeur.consultations, hasLength(1));
      expect(montage.editeur.consultations.single.stationId, caserneA.id);
      expect(
        montage.editeur.consultations.single.raison,
        'Ticket support 42 : le planning de mars ne se valide pas',
      );
    });

    testWidgets('ce qui s\'affiche, c\'est de l\'avancement — jamais un nom', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(
          plannings_: <PlanningSupervise>[planningSupport],
        ),
      );

      await _toucher(tester, AppStrings.superAdminConsulter, caserneA.nom);
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampRaison,
        valeur: 'Ticket support 42 : le planning de mars ne se valide pas',
        bouton: AppStrings.superAdminSupportValider,
      );

      expect(find.text('Novembre 2026'), findsOneWidget);
      expect(
        find.textContaining(
          AppStrings.superAdminSupportCreneaux(planningSupport.creneaux),
        ),
        findsOneWidget,
      );
      // Le modèle ne porte aucun identifiant de personne : si la feuille en
      // affichait un, il viendrait d'ailleurs que de la fonction de support.
      expect(find.textContaining('aaaaaaaa-0000'), findsNothing);
    });

    testWidgets('une caserne sans planning le dit, au lieu d\'un vide muet', (
      tester,
    ) async {
      await _ouvrir(tester);

      await _toucher(
        tester,
        AppStrings.superAdminConsulter,
        caserneSansAdmin.nom,
      );
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampRaison,
        valeur: 'Ticket support 43 : rien ne se publie chez eux',
        bouton: AppStrings.superAdminSupportValider,
      );

      expect(
        find.text(AppStrings.superAdminSupportVideTexte),
        findsOneWidget,
      );
    });

    testWidgets('un refus du serveur reste lisible', (tester) async {
      await _ouvrir(
        tester,
        editeur: FauxSuperAdminRepository(
          echecSupport: ErreurSuperAdmin.droits,
        ),
      );

      await _toucher(tester, AppStrings.superAdminConsulter, caserneA.nom);
      await _remplirEtValider(
        tester,
        champ: AppStrings.superAdminChampRaison,
        valeur: 'Ticket support 44 : vérification après incident',
        bouton: AppStrings.superAdminSupportValider,
      );

      expect(find.text(AppStrings.superAdminRefusDroits), findsOneWidget);
    });
  });
}
