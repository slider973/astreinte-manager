// Le parcours complet d'un mois d'astreintes, d'un bout à l'autre (ticket 035).
//
//   1. l'administrateur invite une recrue ;
//   2. la recrue ouvre le lien et rejoint la caserne ;
//   3. elle saisit ses disponibilités du mois ;
//   4. l'administrateur construit le planning et le publie ;
//   5. la recrue refuse un créneau et en accepte un autre ;
//   6. l'administrateur réattribue le créneau refusé ;
//   7. le second pompier accepte, et le planning se valide tout seul.
//
// Comment ce test est piloté, et pourquoi
// ---------------------------------------
// **Par l'arbre de widgets, jamais par les pixels.** Flutter web dessine dans
// un canevas : un clic envoyé par un pilote de navigateur vise une coordonnée,
// pas un bouton, et les nœuds d'accessibilité ne reçoivent pas toujours ce
// clic. Plusieurs tentatives ont buté là-dessus au fil du projet.
// `WidgetTester` tourne **dans** l'application : `tester.tap(find.text(…))`
// touche le widget, dans le navigateur, sans passer par une coordonnée.
//
// D'où la commande :
//
//     flutter test --platform chrome test/parcours
//
// C'est du Chrome sans interface — le même moteur, le même JavaScript compilé,
// le même arbre — et c'est ce que la CI exécute (`.github/workflows/ci.yml`,
// tâche « parcours »).
//
// Le paquet `integration_test` n'est **pas** utilisé, et ce n'est pas un
// oubli : sur Flutter 3.38, `flutter test -d chrome` répond « Web devices are
// not supported for integration tests yet ». Le seul chemin vers un navigateur
// est `--platform chrome`, et il donne exactement ce qu'on cherchait : le
// vrai moteur, sans pilote extérieur. `test/parcours/README.md` détaille le
// choix et dit ce qui reste hors CI.
//
// Le serveur de ce parcours est [BackendMemoire] : une caserne en mémoire qui
// rejoue les règles de la base. Ce qu'elle ne rejoue pas — la RLS, les
// fonctions SQL, les tâches planifiées — est éprouvé là où il vit, par
// `supabase/tests/parcours_complet_test.sql` et `scripts/test_rls.sh`.
//
// Les sept étapes sont sept tests qui **partagent un état**, dans l'ordre.
// C'est voulu : un parcours est une suite de conséquences, et une étape qui
// échoue doit se nommer elle-même plutôt que de se perdre dans un test de
// trois cents lignes.

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/session_utilisateur.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/presentation/mois_screen.dart';
import 'package:astreinte_sp/features/invitation/presentation/invitation_screen.dart';
import 'package:astreinte_sp/features/membres/presentation/inviter_screen.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/ligne_candidat.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/panneau_creneau.dart';
import 'package:astreinte_sp/features/propositions/presentation/widgets/ligne_proposition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/faux_auth.dart';
import 'backend_memoire.dart';

/// La caserne du parcours.
const String _stationId = 'aaaaaaaa-0000-4000-8000-000000000001';
const String _nomCaserne = 'CIS Saint-Martin';

/// L'adresse invitée à l'étape 1. Tout le reste en découle.
const String _adresseRecrue = 'marie.lefebvre@exemple.fr';

/// Le poste du chef de centre : c'est là que le panneau du créneau vit dans le
/// volet de droite.
const Size _poste = Size(1440, 900);

/// Le mois du parcours est **le mois courant** : c'est celui que la matrice,
/// le planning et le suivi ouvrent par défaut, et forcer un autre mois ne
/// vérifierait que le sélecteur.
final DateTime _moisAffiche = DateTime(
  DateTime.now().year,
  DateTime.now().month,
);

String get _nomMois => AppStrings.moisLongs[_moisAffiche.month - 1];

late BackendMemoire backend;
late String adminId;
late String thomasId;

/// La recrue n'a d'identifiant qu'une fois invitée : c'est l'invitation qui
/// crée son compte.
String get _marieId => backend.membreParEmail(_adresseRecrue)!.userId;

/// Les deux seuls créneaux que cette caserne demande ce mois-ci : le 1er, de
/// jour et de nuit.
///
/// Un planning n'est **validé** que lorsque *tous* ses créneaux atteignent
/// leur effectif requis en attributions acceptées (`schedule_complet`,
/// migration 0019). Soixante attributions posées à la main ne diraient rien de
/// plus que deux : elles feraient de ce test une épreuve de patience. Un
/// effectif requis de zéro est une valeur légitime des réglages de caserne —
/// « pas d'astreinte ce jour-là » est une décision (migration 0018).
const String _creneauRefuse = 'c-1-j';
const String _creneauAccepte = 'c-1-n';

void main() {
  setUpAll(() {
    backend = BackendMemoire(
      stationId: _stationId,
      nomCaserne: _nomCaserne,
      annee: _moisAffiche.year,
      mois: _moisAffiche.month,
      effectifRequis: (int jour, CreneauType creneau) => jour == 1 ? 1 : 0,
    )..annuaire[_adresseRecrue] = (prenom: 'Marie', nom: 'Lefebvre');

    // L'existant de la caserne : un chef de centre et un pompier.
    backend.membres.addAll(<MembreMemoire>[
      MembreMemoire(
        membershipId: 'm-admin',
        userId: 'u-admin',
        prenom: 'Jean',
        nom: 'Dupont',
        email: 'admin@caserne-a.test',
        role: RoleMembre.admin,
      ),
      MembreMemoire(
        membershipId: 'm-thomas',
        userId: 'u-thomas',
        prenom: 'Thomas',
        nom: 'Moreau',
        email: 'membre2@caserne-a.test',
      ),
    ]);
    adminId = 'u-admin';
    thomasId = 'u-thomas';

    // Thomas a saisi son mois avant que le parcours commence : il est
    // disponible le 1er, de jour comme de nuit. C'est ce qui le rend
    // réattribuable à l'étape 6 sans forcer la main à l'administrateur.
    backend.dispos[thomasId] = <CreneauCle, DisponibiliteEtat>{
      for (final creneau in CreneauType.values)
        CreneauCle(DateTime(_moisAffiche.year, _moisAffiche.month), creneau):
            DisponibiliteEtat.disponible,
    };
  });

  group('Parcours complet d\'un mois', () {
    testWidgets('1. l\'administrateur invite une recrue', (tester) async {
      await _monterAdmin(tester);
      await ouvrirRoute(tester, '/admin/membres/inviter');
      expect(find.byType(InviterScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), _adresseRecrue);
      await tester.tap(find.text(AppStrings.inviterEnvoyer));
      await tester.pumpAndSettle();

      expect(
        find.text(
          AppStrings.invitationsResume(
            creees: 1,
            relancees: 0,
            parties: 1,
            echecs: 0,
          ),
        ),
        findsOneWidget,
      );

      final invitation = backend.invitations.single;
      expect(invitation.email, _adresseRecrue);
      expect(invitation.enAttente, isTrue);
      expect(invitation.role, RoleMembre.membre);
      // Le compte existe, l'appartenance non : on n'entre pas dans une caserne
      // par une invitation, on y entre en l'acceptant.
      expect(backend.membreParEmail(_adresseRecrue)!.actif, isFalse);
    });

    testWidgets('2. la recrue ouvre le lien et rejoint la caserne', (
      tester,
    ) async {
      final montee = await monterApp(
        tester,
        session: SessionUtilisateur(userId: _marieId, email: _adresseRecrue),
        invitations: backend.invitationRepository,
      );

      // La relecture de `memberships` que fait l'application au retour de
      // l'Edge Function : sans elle, la session ne connaîtrait pas encore la
      // caserne qu'elle vient de rejoindre.
      backend.apresAcceptation = (MembreMemoire recrue) =>
          montee.memberships.appartenances = <Appartenance>[
            backend.appartenanceDe(recrue.userId),
          ];

      await ouvrirRoute(tester, '/invite/${jetonPour(_adresseRecrue)}');

      expect(find.byType(InvitationScreen), findsOneWidget);
      expect(
        find.text(AppStrings.invitationRejointe(_nomCaserne)),
        findsOneWidget,
      );
      expect(backend.membreParEmail(_adresseRecrue)!.actif, isTrue);
      expect(backend.invitations.single.enAttente, isFalse);
    });

    testWidgets('3. elle saisit ses disponibilités du mois', (tester) async {
      await _monterMembre(tester, _marieId, _adresseRecrue);
      await ouvrirRoute(tester, AppRoutes.calendrier);
      expect(find.byType(MoisScreen), findsOneWidget);

      // Le 1er du mois, de jour puis de nuit. Une touche, un état.
      await tester.tap(_case(0, CreneauType.jour));
      await tester.pump();
      await tester.tap(_case(0, CreneauType.nuit));
      await tester.pump();

      // L'écran n'a pas de bouton « Enregistrer » : il coalesce et envoie.
      await tester.pump(const Duration(seconds: 2));

      final saisies = backend.dispos[_marieId]!;
      final premier = DateTime(_moisAffiche.year, _moisAffiche.month);
      expect(
        saisies[CreneauCle(premier, CreneauType.jour)],
        DisponibiliteEtat.disponible,
      );
      expect(
        saisies[CreneauCle(premier, CreneauType.nuit)],
        DisponibiliteEtat.disponible,
      );
    });

    testWidgets('4. l\'administrateur construit le planning et le publie', (
      tester,
    ) async {
      await _monterAdmin(tester);
      await ouvrirRoute(tester, '/admin/planning');

      // 4a. Le planning du mois n'existe pas : la barre propose de le créer.
      await _toucher(tester, find.text(AppStrings.planningCreer(_nomMois)));
      expect(backend.planning, isNotNull);
      expect(backend.creneaux, hasLength(_joursDuMois * 2));

      // 4b. Marie est attribuée sur les deux créneaux que la caserne demande.
      //     Elle y est disponible : aucune confirmation « hors dispo » ne doit
      //     s'ouvrir.
      for (final creneauId in <String>[_creneauRefuse, _creneauAccepte]) {
        await _toucher(tester, _creneau(creneauId));
        await _toucher(tester, _candidat('Marie Lefebvre'));
        expect(
          find.text(AppStrings.planningHorsDispoValider),
          findsNothing,
          reason: 'Marie est disponible : rien à forcer',
        );
      }

      final attribuees = backend.attributions
          .where((AttributionMemoire a) => a.userId == _marieId)
          .toList(growable: false);
      expect(attribuees, hasLength(2));
      expect(
        attribuees.every((AttributionMemoire a) => a.etaitDisponible),
        isTrue,
      );
      // En brouillon, rien n'est parti : `proposed_at` est nul.
      expect(
        attribuees.every((AttributionMemoire a) => a.proposeeLe == null),
        isTrue,
      );

      // 4c. La publication. Un récapitulatif, puis l'envoi.
      //
      // Les messages qui confirment les attributions couvrent le bas de
      // l'écran, et c'est là que vit le bouton « Publier ».
      await _ecarterLesMessages(tester);

      await _toucher(tester, find.text(AppStrings.publierAction));
      await _toucher(tester, find.text(AppStrings.publierConfirmer));

      // Deux attributions, **un seul pompier** : c'est le nombre de téléphones
      // qui sonnent, et c'est ce que l'écran annonce.
      expect(find.text(AppStrings.publiePourMois(_nomMois, 1)), findsOneWidget);
      expect(backend.etatPlanning, PlanningEtat.publie);
      expect(
        backend.attributions.every(
          (AttributionMemoire a) => a.proposeeLe != null,
        ),
        isTrue,
      );
      // `assignment_proposed`, une entrée par pompier
      // (`docs/WORKFLOWS.md § 8`).
      expect(backend.notifications.last.type, 'assignment_proposed');
      expect(backend.notifications.last.destinataires, <String>[_marieId]);
    });

    testWidgets('5. la recrue refuse un créneau et accepte l\'autre', (
      tester,
    ) async {
      await _monterMembre(tester, _marieId, _adresseRecrue);
      await ouvrirRoute(tester, '/proposals');

      expect(find.byType(LigneDeProposition), findsNWidgets(2));

      // L'ordre de la liste est celui du calendrier : jour avant nuit. La
      // première ligne est donc le créneau de jour du 1er.
      await tester.tap(_refuser().first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'en formation');
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.refusConfirmer));
      await tester.pumpAndSettle();

      expect(find.byType(LigneDeProposition), findsOneWidget);
      final refusee = _attributionDe(_creneauRefuse, _marieId)!;
      expect(refusee.etat, AttributionEtat.refuse);
      expect(refusee.motifRefus, 'en formation');

      // Et elle accepte celui de nuit.
      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      expect(
        _attributionDe(_creneauAccepte, _marieId)!.etat,
        AttributionEtat.accepte,
      );
      // Un créneau sur deux est accepté : le planning n'est pas complet, il
      // reste publié.
      expect(backend.etatPlanning, PlanningEtat.publie);
    });

    testWidgets('6. l\'administrateur réattribue le créneau refusé', (
      tester,
    ) async {
      await _monterAdmin(tester);
      await ouvrirRoute(tester, '/admin/suivi');

      // Un créneau qui porte un refus non couvert se répare : le geste se
      // nomme « Réattribuer », pas « Pourvoir ».
      await _toucher(tester, find.text(AppStrings.reattribuerAction));
      await _toucher(tester, _candidat('Thomas Moreau'));
      await _toucher(tester, find.text(AppStrings.reattribuerConfirmer));

      final nouvelle = _attributionDe(_creneauRefuse, thomasId)!;
      expect(nouvelle.etat, AttributionEtat.propose);
      expect(nouvelle.proposeeLe, isNotNull);
      // Le fil de l'historique : le refus dit ce qui l'a couvert.
      expect(
        _attributionDe(_creneauRefuse, _marieId)!.remplaceParId,
        nouvelle.id,
      );
      expect(backend.aNotifie('assignment_proposed'), isTrue);
      expect(backend.etatPlanning, PlanningEtat.publie);
    });

    testWidgets('7. le second pompier accepte, le planning se valide', (
      tester,
    ) async {
      await _monterMembre(tester, thomasId, 'membre2@caserne-a.test');
      await ouvrirRoute(tester, '/proposals');

      expect(find.byType(LigneDeProposition), findsOneWidget);
      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      // Tous les créneaux requis sont acceptés : `schedule_reevaluer` bascule
      // le planning, et tout le monde l'apprend.
      expect(backend.etatPlanning, PlanningEtat.valide);
      expect(backend.aNotifie('schedule_validated'), isTrue);
      expect(
        find.text(AppStrings.propositionsPlanningValide(_nomMois)),
        findsOneWidget,
      );
    });
  });
}

// ===========================================================================
// Montage : une session par personne, comme un appareil par personne
// ===========================================================================

int get _joursDuMois =>
    DateTime(_moisAffiche.year, _moisAffiche.month + 1, 0).day;

/// Le poste de l'administrateur, avec tous les dépôts que ses écrans lisent.
Future<void> _monterAdmin(WidgetTester tester) async {
  await monterApp(
    tester,
    session: const SessionUtilisateur(
      userId: 'u-admin',
      email: 'admin@caserne-a.test',
    ),
    appartenances: <Appartenance>[backend.appartenanceDe(adminId)],
    membres: backend.membresRepository,
    dispos: backend.disposDe(adminId),
    matrice: backend.matriceRepository,
    planning: backend.planningDe(adminId),
    suivi: backend.suiviDe(adminId),
    propositions: backend.propositionsRepository,
    taille: _poste,
  );
}

/// Le téléphone d'un pompier — la taille par défaut de `monterApp`, 390 × 844,
/// la composition de référence de `DESIGN.md`. Le repère de peinture est déjà
/// vu : la première visite d'un écran n'est pas l'objet de ce parcours.
Future<void> _monterMembre(
  WidgetTester tester,
  String userId,
  String email,
) async {
  await monterApp(
    tester,
    session: SessionUtilisateur(userId: userId, email: email),
    appartenances: <Appartenance>[backend.appartenanceDe(userId)],
    dispos: backend.disposDe(userId),
    propositions: backend.propositionsRepository,
    invitations: backend.invitationRepository,
    reperes: ReperesLocauxMemoire(<RepereAccueil>{
      RepereAccueil.peintureDispos,
    }),
  );
}

// ===========================================================================
// Finders : ceux des tests d'écran, repris tels quels
// ===========================================================================

/// La case du créneau [creneau] du [rang]ᵉ jour du registre. L'ordre des
/// `SlotChip` est celui de la lecture : jour puis nuit, ligne après ligne.
Finder _case(int rang, CreneauType creneau) =>
    find.byType(SlotChip).at(rang * 2 + (creneau == CreneauType.jour ? 0 : 1));

/// La case de la ligne des créneaux, ou le bouton de la vue par jour : les
/// deux portent la même clé, parce qu'ils désignent le même créneau.
Finder _creneau(String id) => find.byKey(ValueKey<String>('creneau-$id'));

/// Le bouton d'action de la ligne d'un membre, **dans le panneau**.
///
/// `find.byType` compare le type exact : `TextButton.icon` construit un
/// `_TextButtonWithIcon`, qui n'est pas un `TextButton` à ses yeux. Le
/// prédicat, lui, voit l'héritage.
Finder _candidat(String nom) => find.descendant(
  of: find.ancestor(
    of: find.descendant(
      of: find.byType(PanneauCreneau),
      matching: find.text(nom),
    ),
    matching: find.byType(LigneCandidat),
  ),
  matching: find.byWidgetPredicate((Widget w) => w is TextButton),
);

Finder _accepter() =>
    find.widgetWithText(PrimaryButton, AppStrings.propositionsAccepter);

Finder _refuser() =>
    find.widgetWithText(PrimaryButton, AppStrings.propositionsRefuser);

/// Fait disparaître les messages de confirmation encore à l'écran.
///
/// Un `SnackBar` se pose **par-dessus** le bas du contenu, et c'est là que vit
/// la barre « Publier ». Chaque attribution en produit un, ils s'empilent en
/// file et tiennent quatre secondes chacun : toucher au travers échouerait au
/// test de contact, et ce serait le vrai comportement de l'écran, pas un
/// artefact de test. Le chef de centre, lui, les balaie ou attend.
Future<void> _ecarterLesMessages(WidgetTester tester) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
      .clearSnackBars();
  await tester.pumpAndSettle();
}

/// Amène un widget dans la fenêtre puis le touche : le panneau défile, et une
/// cible hors écran ne dit rien de ce qu'on voulait vérifier.
Future<void> _toucher(WidgetTester tester, Finder quoi) async {
  await tester.ensureVisible(quoi);
  await tester.pumpAndSettle();
  await tester.tap(quoi);
  await tester.pumpAndSettle();
}

AttributionMemoire? _attributionDe(String creneauId, String userId) {
  for (final attribution in backend.attributionsDe(creneauId)) {
    if (attribution.userId == userId) return attribution;
  }
  return null;
}
