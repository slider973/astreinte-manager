import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/plateforme/selection_fichier.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_spacing.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/barre_actions_basse.dart';
import 'package:astreinte_sp/core/widgets/entete_section.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/membres/domain/fichier_membres.dart';
import 'package:astreinte_sp/features/membres/domain/import_membres.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';
import 'package:astreinte_sp/features/membres/presentation/importer_screen.dart';
import 'package:astreinte_sp/features/membres/presentation/membres_screen.dart';
import 'package:astreinte_sp/features/membres/presentation/widgets/ligne_apercu_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_export.dart';
import '../../support/faux_fichier.dart';
import '../../support/faux_invitations.dart';

const String _cheminImport = '/admin/membres/importer';

const MembreCaserne _membreMarie = MembreCaserne(
  id: 'm-1',
  userId: 'u-1',
  role: RoleMembre.membre,
  statut: StatutMembre.actif,
  prenom: 'Marie',
  nom: 'Lefebvre',
  email: 'marie@exemple.fr',
);

/// Un fichier de soixante pompiers, comme celui du premier jour d'une caserne.
String fichierDeSoixante() {
  final tampon = StringBuffer('prenom;nom;email;role\r\n');
  for (var i = 1; i <= 60; i++) {
    final role = i == 1 ? 'admin' : '';
    tampon.write('Pompier$i;Dupont$i;pompier$i@exemple.fr;$role\r\n');
  }
  return tampon.toString();
}

typedef Harnais = ({
  FauxMembresRepository depot,
  FauxSelecteurFichier selecteur,
  FauxTelechargement telechargement,
});

Future<Harnais> _ouvrirImport(
  WidgetTester tester, {
  FauxMembresRepository? depot,
  FauxSelecteurFichier? selecteur,
  FauxTelechargement? telechargement,
  Size taille = const Size(390, 844),
}) async {
  final membres = depot ?? FauxMembresRepository();
  final fichiers = selecteur ?? FauxSelecteurFichier();
  final remise = telechargement ?? FauxTelechargement();

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceAdmin],
    membres: membres,
    selecteurFichier: fichiers,
    telechargement: remise,
    taille: taille,
  );
  await ouvrirRoute(tester, _cheminImport);
  return (depot: membres, selecteur: fichiers, telechargement: remise);
}

/// Choisit le fichier préparé, puis attend l'aperçu.
Future<void> _choisir(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.importChoisir));
  await tester.pumpAndSettle();
}

Future<void> _faireDefilerVers(WidgetTester tester, Finder cible) async {
  await tester.scrollUntilVisible(
    cible,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ImporterScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Temps 1 — choisir', () {
    testWidgets('l\'écran dit ce que le fichier doit contenir', (tester) async {
      await _ouvrirImport(tester);

      expect(find.byType(ImporterScreen), findsOneWidget);
      expect(find.text(AppStrings.importFormatTitre), findsOneWidget);
      expect(find.text(AppStrings.importFormatEntetes), findsOneWidget);
      expect(find.text(AppStrings.importFormatLimites), findsOneWidget);
      expect(find.text(AppStrings.importChoisir), findsOneWidget);
    });

    testWidgets('le fichier d\'exemple se télécharge, et se relit', (
      tester,
    ) async {
      final harnais = await _ouvrirImport(tester);

      await tester.tap(find.text(AppStrings.importExemple));
      await tester.pumpAndSettle();

      final remis = harnais.telechargement.dernier!;
      expect(remis.nom, nomFichierExemple);
      expect(remis.typeMime, contains('text/csv'));
      expect(remis.contenu, contains('prenom;nom;email;role'));
    });

    testWidgets('fermer le sélecteur ne dit rien : ce n\'est pas un échec', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier();
      await _ouvrirImport(tester, selecteur: selecteur);

      await _choisir(tester);

      expect(find.byType(LigneApercuImport), findsNothing);
      expect(find.text(AppStrings.importChoisir), findsOneWidget);
      // La limite de taille est bien passée au sélecteur : c'est lui qui refuse
      // avant de charger le fichier en mémoire.
      expect(selecteur.demandes.single.tailleMaxOctets, maxOctetsFichier);
    });

    testWidgets('un fichier trop gros est refusé, avec sa taille', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier(
        selection: const FichierTropGros(
          octets: 1468006,
          limite: maxOctetsFichier,
        ),
      );
      await _ouvrirImport(tester, selecteur: selecteur);

      await _choisir(tester);

      expect(
        find.text(AppStrings.importTropGros('1,4 Mo', '512 Ko')),
        findsOneWidget,
      );
    });

    testWidgets('sans colonne d\'adresse, l\'écran dit quoi corriger', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier()
        ..posera('prenom;nom\nMarie;Lefèbvre\n');
      await _ouvrirImport(tester, selecteur: selecteur);

      await _choisir(tester);

      expect(find.text(AppStrings.importColonneAdresseAbsente), findsOneWidget);
      expect(find.byType(LigneApercuImport), findsNothing);
    });
  });

  group('Temps 2 — l\'aperçu', () {
    testWidgets('soixante lignes, rien n\'est parti', (tester) async {
      final selecteur = FauxSelecteurFichier()..posera(fichierDeSoixante());
      final harnais = await _ouvrirImport(tester, selecteur: selecteur);

      await _choisir(tester);

      expect(
        find.text(
          AppStrings.importApercuResume(lues: 60, aInviter: 60, ecartees: 0),
        ),
        findsOneWidget,
      );
      expect(find.text(AppStrings.importEnvoyer(60)), findsOneWidget);
      expect(find.text(AppStrings.importBudgetToutPasse(60)), findsOneWidget);

      // **Rien n'a été envoyé** : l'aperçu est une lecture.
      expect(harnais.depot.lotsImportes, isEmpty);
    });

    testWidgets('chaque cas du fichier a sa ligne et son motif', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier()
        ..posera(
          'prenom;nom;email;role\n'
          'Marie;Lefebvre;marie@exemple.fr;\n'
          'Recrue;Nouvelle;recrue@exemple.fr;\n'
          'Anne;Roux;anne@exemple.fr;admin\n'
          'Anne;Roux;ANNE@exemple.fr;\n'
          'Paul;Blanc;paul.exemple.fr;\n'
          'Sans;Adresse;;\n'
          ';;seul@exemple.fr;\n',
        );
      await _ouvrirImport(
        tester,
        depot: FauxMembresRepository(
          membresActifs: const <MembreCaserne>[_membreMarie],
          invitations: <Invitation>[invitationEnAttente()],
        ),
        selecteur: selecteur,
      );

      await _choisir(tester);

      expect(
        find.text(
          AppStrings.importApercuResume(lues: 7, aInviter: 2, ecartees: 5),
        ),
        findsOneWidget,
      );

      await _faireDefilerVers(tester, find.text('Marie Lefebvre'));
      expect(find.text(AppStrings.inviteDejaMembre), findsOneWidget);

      await _faireDefilerVers(tester, find.text('Recrue Nouvelle'));
      expect(find.text(AppStrings.importDejaInvitee), findsOneWidget);

      await _faireDefilerVers(tester, find.text(AppStrings.importDoublon(4)));
      expect(find.text(AppStrings.importDoublon(4)), findsOneWidget);

      await _faireDefilerVers(
        tester,
        find.text(AppStrings.inviteAdresseInvalide),
      );
      expect(find.text(AppStrings.inviteAdresseInvalide), findsOneWidget);

      await _faireDefilerVers(
        tester,
        find.text(AppStrings.importAdresseAbsente),
      );
      expect(find.text(AppStrings.importAdresseAbsente), findsOneWidget);

      await _faireDefilerVers(tester, find.text(AppStrings.importSansNom));
      expect(find.text('seul@exemple.fr'), findsOneWidget);

      expect(find.text(AppStrings.importEnvoyer(2)), findsOneWidget);
    });

    testWidgets('un fichier dont rien ne peut partir dit pourquoi', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier()
        ..posera('prenom;email\nMarie;marie.exemple.fr\n');
      await _ouvrirImport(tester, selecteur: selecteur);

      await _choisir(tester);

      // Le bouton reste, inerte, avec sa raison à côté (`DESIGN.md § Buttons`).
      expect(find.text(AppStrings.importRienAEnvoyer), findsOneWidget);
    });

    testWidgets('choisir un autre fichier ramène au temps 1', (tester) async {
      final selecteur = FauxSelecteurFichier()
        ..posera('email\nmarie@exemple.fr\n');
      await _ouvrirImport(tester, selecteur: selecteur);

      await _choisir(tester);
      expect(find.byType(LigneApercuImport), findsOneWidget);

      await tester.tap(find.text(AppStrings.importChoisirAutre));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.importFormatTitre), findsOneWidget);
      expect(find.byType(LigneApercuImport), findsNothing);
    });
  });

  group('L\'ordre de lecture de l\'aperçu', () {
    /// Assez haut pour que les deux sections tiennent sans défilement : on
    /// compare des ordonnées, pas des gestes.
    const posteHaut = Size(390, 1400);

    double dy(WidgetTester tester, Finder cible) =>
        tester.getTopLeft(cible).dy;

    testWidgets('les lignes écartées se lisent avant les justes', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier()
        ..posera(
          'prenom;nom;email;role\n'
          'Anne;Bernard;anne@exemple.fr;\n'
          'Paul;Blanc;paul.exemple.fr;\n'
          'Luc;Martin;luc@exemple.fr;\n'
          ';;;admin\n'
          'Zoe;Petit;zoe@exemple.fr;\n',
        );
      await _ouvrirImport(tester, selecteur: selecteur, taille: posteHaut);

      await _choisir(tester);

      // Deux intitulés, les écartées d'abord.
      expect(find.text(AppStrings.importSectionEcartees), findsOneWidget);
      expect(find.text(AppStrings.importSectionAInviter), findsOneWidget);
      expect(find.text(AppStrings.importApercuTitre), findsNothing);
      expect(
        dy(tester, find.text(AppStrings.importSectionEcartees)),
        lessThan(dy(tester, find.text(AppStrings.importSectionAInviter))),
      );

      // Les deux fautives sont au-dessus de la première ligne juste, alors
      // qu'elles étaient aux lignes 3 et 5 du fichier.
      final premiereJuste = dy(tester, find.text('Anne Bernard'));
      expect(dy(tester, find.text('Paul Blanc')), lessThan(premiereJuste));
      expect(
        dy(tester, find.text(AppStrings.importLigneNumero(5))),
        lessThan(premiereJuste),
      );

      // Remontée, une ligne sans nom garde son numéro de fichier : c'est le
      // seul repère qui permette de la retrouver dans le tableur.
      expect(find.text(AppStrings.importLigneNumero(5)), findsOneWidget);

      // Dans chaque section, l'ordre du fichier est conservé.
      expect(
        dy(tester, find.text('Paul Blanc')),
        lessThan(dy(tester, find.text(AppStrings.importLigneNumero(5)))),
      );
      expect(premiereJuste, lessThan(dy(tester, find.text('Luc Martin'))));
      expect(
        dy(tester, find.text('Luc Martin')),
        lessThan(dy(tester, find.text('Zoe Petit'))),
      );
    });

    testWidgets('sans aucune écartée, l\'aperçu garde sa forme d\'une seule '
        'section', (tester) async {
      final selecteur = FauxSelecteurFichier()..posera(fichierDeSoixante());
      await _ouvrirImport(tester, selecteur: selecteur, taille: posteHaut);

      await _choisir(tester);

      expect(find.byType(EnteteSection), findsOneWidget);
      expect(find.text(AppStrings.importApercuTitre), findsOneWidget);
      expect(find.text(AppStrings.importSectionEcartees), findsNothing);
      expect(find.text(AppStrings.importSectionAInviter), findsNothing);
    });
  });

  group('Temps 3 — le rapport', () {
    testWidgets('soixante invitations partent en trois lots, avec les noms', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier()..posera(fichierDeSoixante());
      final harnais = await _ouvrirImport(tester, selecteur: selecteur);

      await _choisir(tester);
      await tester.tap(find.text(AppStrings.importEnvoyer(60)));
      await tester.pumpAndSettle();

      // Trois lots de vingt : le plafond de l'appel est celui d'une requête,
      // pas celui d'un import.
      expect(
        harnais.depot.lotsImportes.map((List<PersonneAInviter> l) => l.length),
        <int>[20, 20, 20],
      );

      final premier = harnais.depot.lotsImportes.first.first;
      expect(premier.email, 'pompier1@exemple.fr');
      expect(premier.prenom, 'Pompier1');
      expect(premier.nom, 'Dupont1');
      // Le rôle est par ligne : la première porte « admin », les autres non.
      expect(premier.role, RoleMembre.admin);
      expect(harnais.depot.lotsImportes.first[1].role, RoleMembre.membre);

      // Le vocabulaire du ticket 006, sans un mot de plus.
      expect(find.text(AppStrings.inviterResultatsTitre), findsOneWidget);
      expect(
        find.text(AppStrings.inviterResume(envoyees: 60, echecs: 0)),
        findsOneWidget,
      );
    });

    testWidgets('les lignes écartées sont résumées, pas noyées dans le rapport', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier()
        ..posera(
          'prenom;email\n'
          'Marie;marie@exemple.fr\n'
          'Paul;paul.exemple.fr\n'
          'Anne;anne@exemple.fr\n',
        );
      await _ouvrirImport(
        tester,
        depot: FauxMembresRepository(
          membresActifs: const <MembreCaserne>[_membreMarie],
        ),
        selecteur: selecteur,
      );

      await _choisir(tester);
      await tester.tap(find.text(AppStrings.importEnvoyer(1)));
      await tester.pumpAndSettle();

      expect(
        find.text(
          AppStrings.importEcarteesResume(
            2,
            '${AppStrings.importEcarteesMotif(1, AppStrings.importMotifDejaMembre)}, '
            '${AppStrings.importEcarteesMotif(1, AppStrings.importMotifAdresseInvalide)}',
          ),
        ),
        findsOneWidget,
      );
      // Elles ne descendent pas dans « Résultat par adresse » : on n'y met que
      // ce qui a été tenté.
      expect(find.text('marie@exemple.fr'), findsNothing);
      expect(find.text('anne@exemple.fr'), findsOneWidget);
    });

    testWidgets('« Revenir aux membres » ramène à la liste', (tester) async {
      final selecteur = FauxSelecteurFichier()
        ..posera('email\nanne@exemple.fr\n');
      await _ouvrirImport(tester, selecteur: selecteur);

      await _choisir(tester);
      await tester.tap(find.text(AppStrings.importEnvoyer(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.inviterTerminer));
      await tester.pumpAndSettle();

      expect(find.byType(MembresScreen), findsOneWidget);
    });
  });

  group('Le plafond horaire (ticket 038)', () {
    /// Un budget de quarante places, dont le plus ancien envoi est parti à
    /// 14 h 12 : la place suivante rouvre donc à 15 h 12.
    BudgetInvitations budgetDeQuarante() {
      final base = DateTime.now().subtract(const Duration(minutes: 48));
      return BudgetInvitations(
        plafond: 60,
        envoisRecents: <DateTime>[
          for (var i = 0; i < 20; i++) base.add(Duration(seconds: i)),
        ],
      );
    }

    testWidgets('l\'aperçu annonce ce qui partira et à quelle heure', (
      tester,
    ) async {
      final budget = budgetDeQuarante();
      final selecteur = FauxSelecteurFichier()..posera(fichierDeSoixante());
      final harnais = await _ouvrirImport(
        tester,
        depot: FauxMembresRepository()..budget = budget,
        selecteur: selecteur,
      );

      await _choisir(tester);

      expect(
        find.text(
          AppStrings.importBudgetPartiel(
            maintenant: 40,
            reste: 20,
            heure: formaterHeureDuJour(
              budget.ouvertureApresEpuisement(DateTime.now()),
            ),
          ),
        ),
        findsOneWidget,
      );
      // **Avant de commencer** : rien n'est encore parti.
      expect(harnais.depot.lotsImportes, isEmpty);
    });

    testWidgets('un budget nul le dit sans crier à la panne', (tester) async {
      final selecteur = FauxSelecteurFichier()
        ..posera('email\nanne@exemple.fr\n');
      final budget = BudgetInvitations(
        plafond: 1,
        envoisRecents: <DateTime>[
          DateTime.now().subtract(const Duration(minutes: 48)),
        ],
      );
      await _ouvrirImport(
        tester,
        depot: FauxMembresRepository()..budget = budget,
        selecteur: selecteur,
      );

      await _choisir(tester);

      expect(
        find.text(
          AppStrings.importBudgetNul(
            formaterHeureDuJour(
              budget.ouvertureApresEpuisement(DateTime.now()),
            ),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('un budget illisible ne fabrique aucune inquiétude', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier()
        ..posera('email\nanne@exemple.fr\n');
      await _ouvrirImport(
        tester,
        depot: FauxMembresRepository()..budget = null,
        selecteur: selecteur,
      );

      await _choisir(tester);

      expect(find.text(AppStrings.importBudgetToutPasse(1)), findsNothing);
      expect(find.text(AppStrings.importEnvoyer(1)), findsOneWidget);
    });

    testWidgets(
      'le plafond atteint en cours d\'import n\'abandonne personne en silence',
      (tester) async {
        final reprise = DateTime.now().add(const Duration(minutes: 13));
        final depot = FauxMembresRepository()
          // Le deuxième lot est refusé : vingt sont passés, quarante attendent.
          ..lotQuiEchoue = 1
          ..echecInvitation = EchecInvitation(
            ErreurInvitation.debitAtteint,
            messageServeur:
                'Limite d\'invitations atteinte (60 par heure pour cette '
                'caserne). Réessaie dans 13 minutes.',
            plafond: PlafondInvitations(
              portee: PorteePlafond.caserne,
              plafond: 60,
              utilisees: 60,
              restantes: 0,
              fenetreMinutes: 60,
              reessayerLe: reprise,
              delaiAvantNouvelEssai: const Duration(minutes: 13),
            ),
          );
        final selecteur = FauxSelecteurFichier()..posera(fichierDeSoixante());
        await _ouvrirImport(tester, depot: depot, selecteur: selecteur);

        await _choisir(tester);
        await tester.tap(find.text(AppStrings.importEnvoyer(60)));
        await tester.pumpAndSettle();

        // On s'arrête franchement : le troisième lot n'est pas tenté.
        expect(depot.lotsImportes.length, 2);

        // Le rapport garde ce qui est passé — sinon l'administrateur
        // réessaierait des adresses déjà invitées.
        expect(
          find.text(AppStrings.inviterResume(envoyees: 20, echecs: 0)),
          findsOneWidget,
        );

        // La phrase du serveur, délai compris, et la suite à donner.
        expect(
          find.textContaining('Réessaie dans 13 minutes.'),
          findsOneWidget,
        );
        // Un fait, pas une panne : la bannière est `attention`, jamais rouge
        // (`design/047-import-membres.md § 3`).
        expect(
          tester.widget<AppBanner>(find.byType(AppBanner).first).variante,
          AppBannerVariante.attention,
        );
        expect(
          find.text(
            AppStrings.importReprendreApres(formaterHeureDuJour(reprise)),
          ),
          findsOneWidget,
        );
        expect(find.text(AppStrings.importReprendre), findsOneWidget);
      },
    );

    testWidgets('reprendre l\'import repart du choix du fichier', (
      tester,
    ) async {
      final depot = FauxMembresRepository()
        ..lotQuiEchoue = 1
        ..echecInvitation = EchecInvitation(
          ErreurInvitation.debitAtteint,
          messageServeur: 'Limite atteinte. Réessaie dans 13 minutes.',
          plafond: PlafondInvitations(
            portee: PorteePlafond.caserne,
            reessayerLe: DateTime.now().add(const Duration(minutes: 13)),
          ),
        );
      final selecteur = FauxSelecteurFichier()..posera(fichierDeSoixante());
      await _ouvrirImport(tester, depot: depot, selecteur: selecteur);

      await _choisir(tester);
      await tester.tap(find.text(AppStrings.importEnvoyer(60)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.importReprendre));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.importFormatTitre), findsOneWidget);
      expect(find.text(AppStrings.importChoisir), findsOneWidget);
    });

    testWidgets('un refus avant le premier envoi reste sur l\'aperçu', (
      tester,
    ) async {
      // Aucune adresse tentée : un « Résultat par adresse » vide ne dirait
      // rien. La bannière, elle, dit tout.
      final depot = FauxMembresRepository()
        ..lotQuiEchoue = 0
        ..echecInvitation = const EchecInvitation(
          ErreurInvitation.debitAtteint,
          messageServeur: 'Limite atteinte. Réessaie dans 42 minutes.',
        );
      final selecteur = FauxSelecteurFichier()
        ..posera('email\nanne@exemple.fr\n');
      await _ouvrirImport(tester, depot: depot, selecteur: selecteur);

      await _choisir(tester);
      await tester.tap(find.text(AppStrings.importEnvoyer(1)));
      await tester.pumpAndSettle();

      expect(
        find.text('Limite atteinte. Réessaie dans 42 minutes.'),
        findsOneWidget,
      );
      expect(
        tester.widget<AppBanner>(find.byType(AppBanner).first).variante,
        AppBannerVariante.attention,
      );
      expect(find.text(AppStrings.inviterResultatsTitre), findsNothing);
      expect(find.byType(LigneApercuImport), findsOneWidget);
    });
  });

  group('La barre d\'actions', () {
    /// Le chef de centre importe depuis un ordinateur : c'est la largeur où
    /// une barre non bornée se voyait le plus (ticket 048).
    const posteAdmin = Size(1280, 900);

    void verifierLargeur(WidgetTester tester, String libelle) {
      expect(
        tester.getSize(find.widgetWithText(PrimaryButton, libelle)).width,
        AppSpacing.colonneMax,
        reason: '« $libelle » déborde de la colonne du corps.',
      );
    }

    testWidgets('sur poste admin, elle tient dans la colonne aux trois temps', (
      tester,
    ) async {
      final selecteur = FauxSelecteurFichier()
        ..posera('prenom;nom;email\nAnne;Bernard;anne@exemple.fr\n');
      await _ouvrirImport(tester, selecteur: selecteur, taille: posteAdmin);

      expect(find.byType(BarreActionsBasse), findsOneWidget);
      verifierLargeur(tester, AppStrings.importChoisir);
      verifierLargeur(tester, AppStrings.importExemple);

      await _choisir(tester);
      verifierLargeur(tester, AppStrings.importEnvoyer(1));
      verifierLargeur(tester, AppStrings.importChoisirAutre);

      await tester.tap(find.text(AppStrings.importEnvoyer(1)));
      await tester.pumpAndSettle();
      verifierLargeur(tester, AppStrings.inviterTerminer);
    });
  });

  group('Le chemin depuis « Membres »', () {
    testWidgets('le bouton « Importer un fichier » y mène', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceAdmin],
        membres: FauxMembresRepository(),
      );
      await ouvrirRoute(tester, '/admin/membres');

      await tester.tap(find.text(AppStrings.membresImporter));
      await tester.pumpAndSettle();

      expect(find.byType(ImporterScreen), findsOneWidget);
    });
  });
}
