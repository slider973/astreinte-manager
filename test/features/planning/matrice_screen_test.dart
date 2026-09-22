import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/data/matrice_repository.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/matrice_screen.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/grille_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/vue_jour.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';

const String _chemin = '/admin/planning';

/// Un poste d'administration : classe `large`, la composition de référence.
const Size _poste = Size(1440, 900);

/// Un téléphone : la matrice n'y existe pas, la vue par jour prend la main.
const Size _telephone = Size(390, 844);

final DateTime _maintenant = DateTime.now();

/// Le premier jour d'un mois relatif au mois courant.
DateTime _mois(int decalage) =>
    DateTime(_maintenant.year, _maintenant.month + decalage);

PeriodeSaisie _ouverte(int decalage) {
  final jour = _mois(decalage);
  return periodeOuverte(annee: jour.year, mois: jour.month);
}

PeriodeSaisie _verrouillee(int decalage) {
  final jour = _mois(decalage);
  return periodeVerrouillee(annee: jour.year, mois: jour.month);
}

String _libelleMois(int decalage) {
  final jour = _mois(decalage);
  return AppStrings.moisNomEtAnnee(jour.month, jour.year);
}

/// Le premier jour du mois affiché par défaut (le mois courant).
DateTime _premierJour() => _mois(0);

int _joursDuMois(int decalage) {
  final jour = _mois(decalage);
  return DateTime(jour.year, jour.month + 1, 0).day;
}

List<LigneMatrice> _deuxMembres({int decalage = 0}) {
  final jours = _joursDuMois(decalage);
  return <LigneMatrice>[
    ligneMatrice(
      userId: 'u1',
      nom: 'Dubois Jean-Marc',
      // Jour 1 disponible, jour 2 absent (saisi par un admin).
      jours: 'Da${'.' * (jours - 2)}',
      nuits: 'D${'.' * (jours - 1)}',
      commentaire: 'Pas plus d\'un weekend, garde des enfants.',
      maxAstreintes: 3,
      astreintes: 1,
      maxWeekends: 1,
      accepteesPrecedentes: 4,
    ),
    ligneMatrice(
      userId: 'u2',
      nom: 'Martin Alice',
      jours: '.' * jours,
      nuits: '.' * jours,
      maxAstreintes: 4,
      astreintes: 5,
      accepteesPrecedentes: 1,
    ),
  ];
}

/// Trouve une case par le début de sa phrase de sémantique : « Dubois
/// Jean-Marc, mercredi 1er octobre, jour ». C'est la phrase que lira un
/// lecteur d'écran, donc le meilleur sélecteur possible.
Finder _case(String membre, DateTime date, CreneauType creneau) {
  final prefixe =
      '$membre, ${dateAvecJourSemaine(date)}, '
      '${creneau == CreneauType.jour ? 'jour' : 'nuit'}';
  return find.byWidgetPredicate(
    (Widget widget) =>
        widget is SlotChip && widget.libelleSemantique.startsWith(prefixe),
    description: 'case « $prefixe »',
  );
}

Future<FauxMatriceRepository> _ouvrir(
  WidgetTester tester, {
  List<LigneMatrice>? lignes,
  List<PeriodeSaisie>? periodes,
  Appartenance appartenance = appartenanceAdmin,
  Size taille = _poste,
  ReperesLocaux? reperes,
  Connectivite? reseau,
  ErreurMatrice? erreurLecture,
  ErreurMatrice? erreurEcriture,
}) async {
  final depot = FauxMatriceRepository(
    lignes: lignes ?? _deuxMembres(),
    erreurLecture: erreurLecture,
    erreurEcriture: erreurEcriture,
  );

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    dispos: FauxDisposRepository(
      periodes: periodes ?? <PeriodeSaisie>[_ouverte(0)],
    ),
    matrice: depot,
    reperes:
        reperes ??
        ReperesLocauxMemoire(<RepereAccueil>{
          // Par défaut, la confirmation de première fois est déjà passée : les
          // tests qui l'exercent la redemandent explicitement.
          RepereAccueil.saisieProcuration,
        }),
    reseau: reseau,
    taille: taille,
  );
  await ouvrirRoute(tester, _chemin);
  return depot;
}

/// Arme la saisie par procuration depuis la barre de commande.
Future<void> _armer(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.matriceModeSaisie));
  await tester.pumpAndSettle();
}

void main() {
  group('MatriceScreen — la matrice', () {
    testWidgets('affiche une ligne par membre, ses quotas et son '
        'commentaire', (tester) async {
      await _ouvrir(tester);

      expect(find.byType(MatriceScreen), findsOneWidget);
      expect(find.byType(GrilleMatrice), findsOneWidget);

      // Une ligne par membre, nom affiché en clair.
      expect(find.text('Dubois Jean-Marc'), findsOneWidget);
      expect(find.text('Martin Alice'), findsOneWidget);

      // Les quotas : la barre de fraction **est** le signe qu'un plafond
      // existe, et le dépassement garde son signe moins.
      expect(find.text('2/3'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('-1/4'), findsOneWidget);
      // Aucun plafond de weekends : la charge seule, sans fraction.
      expect(find.text('0'), findsWidgets);

      // Le commentaire est **affiché**, pas caché derrière une icône.
      expect(
        find.text('Pas plus d\'un weekend, garde des enfants.'),
        findsOneWidget,
      );

      // Le mois affiché est celui du sélecteur, et **il n'est écrit qu'une
      // fois** : le sélecteur le porte avec l'état de la période, le bandeau
      // du mois juste dessous ne le répète pas.
      expect(find.text(_libelleMois(0)), findsOneWidget);
    });

    testWidgets('une case saisie par un admin porte sa marque, et elle '
        'survit au rechargement', (tester) async {
      final depot = await _ouvrir(tester);

      final absentParAdmin = tester.widget<SlotChip>(
        _case(
          'Dubois Jean-Marc',
          _premierJour().add(const Duration(days: 1)),
          CreneauType.jour,
        ),
      );
      expect(absentParAdmin.etat, DisponibiliteEtat.absent);
      expect(absentParAdmin.saisiParAdmin, isTrue);
      // La marque se double d'un mot : jamais la couleur seule.
      final semantique = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(
              _case(
                'Dubois Jean-Marc',
                _premierJour().add(const Duration(days: 1)),
                CreneauType.jour,
              ),
            )
            .label,
        contains(AppStrings.matriceCaseSaisieParAdmin),
      );
      semantique.dispose();

      final saisieMembre = tester.widget<SlotChip>(
        _case('Dubois Jean-Marc', _premierJour(), CreneauType.jour),
      );
      expect(saisieMembre.etat, DisponibiliteEtat.disponible);
      expect(saisieMembre.saisiParAdmin, isFalse);

      expect(depot.lectures, 1);
    });

    testWidgets('les cases sont inertes tant que la saisie n\'est pas '
        'armée', (tester) async {
      await _ouvrir(tester);

      final avant = tester.widget<SlotChip>(
        _case('Martin Alice', _premierJour(), CreneauType.jour),
      );
      expect(avant.onTap, isNull);
      expect(find.text(AppStrings.matriceModeSaisieActif), findsNothing);

      await _armer(tester);

      final apres = tester.widget<SlotChip>(
        _case('Martin Alice', _premierJour(), CreneauType.jour),
      );
      expect(apres.onTap, isNotNull);
      // Le mode se voit sans qu'on ait à le lire, et il se lit aussi.
      expect(find.text(AppStrings.matriceModeSaisieActif), findsOneWidget);
    });

    testWidgets('la confirmation de première fois s\'affiche une fois, pas '
        'deux', (tester) async {
      final reperes = ReperesLocauxMemoire();
      await _ouvrir(tester, reperes: reperes);

      await tester.tap(find.text(AppStrings.matriceModeSaisie));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matriceConfirmationTexte), findsOneWidget);
      await tester.tap(find.text(AppStrings.matriceConfirmationValider));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.matriceModeSaisieActif), findsOneWidget);

      // Désarmer puis réarmer : le dialogue ne revient pas.
      await tester.tap(find.text(AppStrings.matriceModeSaisie));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.matriceModeSaisie));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matriceConfirmationTexte), findsNothing);
      expect(find.text(AppStrings.matriceModeSaisieActif), findsOneWidget);
      expect(await reperes.dejaVu(RepereAccueil.saisieProcuration), isTrue);
    });

    testWidgets('annuler la confirmation n\'arme pas', (tester) async {
      await _ouvrir(tester, reperes: ReperesLocauxMemoire());

      await tester.tap(find.text(AppStrings.matriceModeSaisie));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.matriceConfirmationAnnuler));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matriceModeSaisieActif), findsNothing);
      final case_ = tester.widget<SlotChip>(
        _case('Martin Alice', _premierJour(), CreneauType.jour),
      );
      expect(case_.onTap, isNull);
    });

    testWidgets('saisir à la place d\'un membre écrit la case et la marque '
        'comme posée par un admin', (tester) async {
      final depot = await _ouvrir(tester);
      await _armer(tester);

      await tester.tap(_case('Martin Alice', _premierJour(), CreneauType.nuit));
      await tester.pumpAndSettle();

      // **Un enregistrement ordinaire**, jamais une RPC d'écriture, et
      // jamais `set_by` : la base le pose elle-même.
      expect(depot.ecritures, hasLength(1));
      expect(depot.ecritures.single.userId, 'u2');
      expect(depot.ecritures.single.etat, DisponibiliteEtat.disponible);
      expect(depot.ecritures.single.date, isoJour(_premierJour()));

      final apres = tester.widget<SlotChip>(
        _case('Martin Alice', _premierJour(), CreneauType.nuit),
      );
      expect(apres.etat, DisponibiliteEtat.disponible);
      expect(apres.saisiParAdmin, isTrue);

      // Le cycle : disponible → absent.
      await tester.tap(_case('Martin Alice', _premierJour(), CreneauType.nuit));
      await tester.pumpAndSettle();
      expect(depot.ecritures.last.etat, DisponibiliteEtat.absent);

      // Puis absent → non saisi, qui **supprime** la ligne.
      await tester.tap(_case('Martin Alice', _premierJour(), CreneauType.nuit));
      await tester.pumpAndSettle();
      expect(depot.suppressions, hasLength(1));
    });

    testWidgets('un échec d\'écriture garde la valeur demandée, marque la '
        'case et le dit', (tester) async {
      final depot = await _ouvrir(tester, erreurEcriture: ErreurMatrice.reseau);
      await _armer(tester);

      await tester.tap(_case('Martin Alice', _premierJour(), CreneauType.jour));
      await tester.pumpAndSettle();

      final case_ = tester.widget<SlotChip>(
        _case('Martin Alice', _premierJour(), CreneauType.jour),
      );
      expect(case_.erreur, isTrue);
      // La valeur demandée reste : un rechargement rétablira celle du serveur.
      expect(case_.etat, DisponibiliteEtat.disponible);
      expect(find.text(AppStrings.matriceErreurEcriture), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
      expect(depot.ecritures, hasLength(1));
    });

    testWidgets('le mode armé se désarme au changement de mois', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        periodes: <PeriodeSaisie>[_ouverte(0), _ouverte(1)],
      );
      await _armer(tester);
      expect(find.text(AppStrings.matriceModeSaisieActif), findsOneWidget);

      await tester.tap(find.text(_libelleMois(1)));
      await tester.pumpAndSettle();

      // Le mois quitté ne laisse jamais un écran armé derrière lui.
      expect(find.text(AppStrings.matriceModeSaisieActif), findsNothing);
      final case_ = tester.widget<SlotChip>(find.byType(SlotChip).first);
      expect(case_.onTap, isNull);
    });

    testWidgets('Échap désarme la saisie', (tester) async {
      await _ouvrir(tester);
      await _armer(tester);
      expect(find.text(AppStrings.matriceModeSaisieActif), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matriceModeSaisieActif), findsNothing);
    });

    testWidgets('sur un mois verrouillé, l\'admin saisit quand même et la '
        'bannière le dit', (tester) async {
      await _ouvrir(
        tester,
        periodes: <PeriodeSaisie>[_verrouillee(0)],
        lignes: _deuxMembres(),
      );

      expect(
        find.textContaining('Tu peux encore saisir à la place d\'un membre.'),
        findsOneWidget,
      );

      await _armer(tester);
      final case_ = tester.widget<SlotChip>(
        _case('Martin Alice', _premierJour(), CreneauType.jour),
      );
      // La matrice reste vivante : aucune case verrouillée.
      expect(case_.verrouille, isFalse);
      expect(case_.onTap, isNotNull);
    });

    testWidgets('hors ligne, l\'interrupteur est désactivé **avec sa '
        'raison**', (tester) async {
      await _ouvrir(tester, reseau: ConnectiviteMemoire(enLigne: false));

      expect(
        find.text(AppStrings.matriceSaisieIndisponibleHorsLigne),
        findsOneWidget,
      );
      expect(find.text(AppStrings.horsLigneDetail), findsOneWidget);
    });
  });

  group('MatriceScreen — les filtres', () {
    testWidgets('la recherche filtre les lignes sans requête', (tester) async {
      final depot = await _ouvrir(tester);

      await tester.enterText(find.byType(TextField).first, 'dupond');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Aucun membre ne correspond : la barre de commande reste.
      expect(find.text(AppStrings.matriceAucunResultatTitre), findsOneWidget);
      expect(find.byType(GrilleMatrice), findsNothing);
      expect(find.text(AppStrings.matriceRechercheLibelle), findsWidgets);
      // **Aucune requête** : les soixante lignes sont déjà en mémoire.
      expect(depot.lectures, 1);

      await tester.tap(find.text(AppStrings.matriceToutAfficher).last);
      await tester.pumpAndSettle();
      expect(find.byType(GrilleMatrice), findsOneWidget);
      expect(depot.lectures, 1);
    });

    testWidgets('« Masquer ceux qui n\'ont rien saisi » retire la ligne vide '
        'et affiche le compte', (tester) async {
      final depot = await _ouvrir(tester);

      await tester.tap(find.text(AppStrings.matriceMasquerNonSaisis));
      await tester.pumpAndSettle();

      expect(find.text('Dubois Jean-Marc'), findsOneWidget);
      expect(find.text('Martin Alice'), findsNothing);
      expect(find.text(AppStrings.matriceCompteFiltre(1, 2)), findsOneWidget);
      expect(depot.lectures, 1);
    });

    testWidgets('l\'interrupteur « Commentaires » replie les secondes '
        'lignes', (tester) async {
      await _ouvrir(tester);
      const commentaire = 'Pas plus d\'un weekend, garde des enfants.';
      expect(find.text(commentaire), findsOneWidget);

      await tester.tap(find.text(AppStrings.matriceAfficherCommentaires));
      await tester.pumpAndSettle();

      expect(find.text(commentaire), findsNothing);
      expect(find.text('Dubois Jean-Marc'), findsOneWidget);
    });

    testWidgets('le tri par astreintes restantes réordonne sans requête', (
      tester,
    ) async {
      final depot = await _ouvrir(tester);

      await tester.tap(find.textContaining(AppStrings.matriceTrier));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.matriceTriAstreintes).last);
      await tester.pumpAndSettle();

      final dubois = tester.getTopLeft(find.text('Dubois Jean-Marc'));
      final martin = tester.getTopLeft(find.text('Martin Alice'));
      // 2 restantes avant −1 : le dépassement passe en dernier.
      expect(dubois.dy, lessThan(martin.dy));
      expect(depot.lectures, 1);
    });
  });

  group('MatriceScreen — la vue par jour', () {
    testWidgets('sur un téléphone, la matrice laisse place à la vue par '
        'jour, et on y saisit', (tester) async {
      final depot = await _ouvrir(tester, taille: _telephone);

      expect(find.byType(VueJour), findsOneWidget);
      expect(find.byType(GrilleMatrice), findsNothing);
      expect(find.text(AppStrings.matriceEcranLarge), findsOneWidget);

      await _armer(tester);
      // La vue s'ouvre sur **aujourd'hui** quand il est dans le mois affiché.
      final jour = DateTime(
        _maintenant.year,
        _maintenant.month,
        _maintenant.day,
      );
      // La liste défile : la ligne est amenée à l'écran avant d'être touchée,
      // comme un doigt le ferait.
      final defilement = find
          .descendant(
            of: find.byType(VueJour),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        _case('Dubois Jean-Marc', jour, CreneauType.nuit),
        120,
        scrollable: defilement,
      );
      await tester.pumpAndSettle();

      await tester.tap(_case('Dubois Jean-Marc', jour, CreneauType.nuit));
      await tester.pumpAndSettle();

      expect(depot.ecritures, hasLength(1));
      expect(depot.ecritures.single.userId, 'u1');

      // Les cases y sont servies au doigt : 48 dp.
      final taille = tester.getSize(
        _case('Dubois Jean-Marc', jour, CreneauType.nuit),
      );
      expect(taille.width, greaterThanOrEqualTo(44));
      expect(taille.height, greaterThanOrEqualTo(44));
    });

    testWidgets('au-delà de ×1.6, la vue par jour reprend même sur un '
        'poste', (tester) async {
      // L'échelle doit exister **avant** le montage : elle décide de la
      // composition, pas de la taille des glyphes.
      tester.platformDispatcher.textScaleFactorTestValue = 1.7;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _ouvrir(tester);

      expect(find.byType(VueJour), findsOneWidget);
      expect(find.byType(GrilleMatrice), findsNothing);
    });
  });

  group('MatriceScreen — états vides et refus', () {
    testWidgets('un membre ordinaire n\'atteint pas l\'écran', (tester) async {
      await _ouvrir(tester, appartenance: appartenanceMembre);

      expect(find.byType(MatriceScreen), findsNothing);
    });

    testWidgets('un refus de la fonction se dit en toutes lettres', (
      tester,
    ) async {
      await _ouvrir(tester, erreurLecture: ErreurMatrice.reserveAdmin);

      expect(find.text(AppStrings.matriceReserveAdmin), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('une caserne dont personne n\'a saisi affiche quand même la '
        'matrice', (tester) async {
      final jours = _joursDuMois(0);
      await _ouvrir(
        tester,
        lignes: <LigneMatrice>[
          ligneMatrice(
            userId: 'u1',
            nom: 'Dubois Jean-Marc',
            jours: '.' * jours,
            nuits: '.' * jours,
          ),
          ligneMatrice(
            userId: 'u2',
            nom: 'Martin Alice',
            jours: '.' * jours,
            nuits: '.' * jours,
          ),
        ],
      );

      // La grille s'affiche : c'est la vérité du mois.
      expect(find.byType(GrilleMatrice), findsOneWidget);
      expect(find.text('Dubois Jean-Marc'), findsOneWidget);
      expect(
        find.text(
          AppStrings.matriceMoisViergeTexte(
            AppStrings.moisLongs[_mois(0).month - 1],
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('une caserne sans membre actif propose d\'en inviter un', (
      tester,
    ) async {
      await _ouvrir(tester, lignes: const <LigneMatrice>[]);

      expect(find.text(AppStrings.matriceAucunMembreTitre), findsOneWidget);
      expect(find.text(AppStrings.matriceAucunMembreAction), findsOneWidget);
    });

    testWidgets('aucun mois ouvert : l\'écran propose d\'en ouvrir un', (
      tester,
    ) async {
      await _ouvrir(tester, periodes: const <PeriodeSaisie>[]);

      expect(find.text(AppStrings.matriceAucunePeriodeTitre), findsOneWidget);
      expect(find.text(AppStrings.matriceAucunePeriodeAction), findsOneWidget);
    });
  });

  group('MatriceScreen — le budget', () {
    testWidgets('60 membres × 62 colonnes : la grille ne construit que ce '
        'qui est à l\'écran', (tester) async {
      final jours = _joursDuMois(0);
      final chrono = Stopwatch()..start();

      await _ouvrir(
        tester,
        taille: const Size(1920, 1080),
        lignes: <LigneMatrice>[
          for (var index = 0; index < 60; index++)
            ligneMatrice(
              userId: 'u$index',
              nom: 'Pompier ${index.toString().padLeft(2, '0')}',
              jours: 'DA' * (jours ~/ 2) + (jours.isOdd ? '.' : ''),
              nuits: '.D' * (jours ~/ 2) + (jours.isOdd ? '.' : ''),
              maxAstreintes: 4,
              astreintes: index % 5,
            ),
        ],
      );
      chrono.stop();

      expect(find.byType(GrilleMatrice), findsOneWidget);

      // **Le garde-fou, pas le budget** : la mesure des deux secondes se fait
      // au navigateur, sur un build `--profile` (`DESIGN.md § Coût de la case
      // dense, mesuré`). Ici, on attrape un blocage ou une régression d'un
      // facteur dix, et rien de plus fin.
      expect(chrono.elapsed, lessThan(const Duration(seconds: 10)));

      // Ce qui est vraiment vérifiable en test de widgets : la
      // virtualisation. 60 × 62 = 3 720 cases existent, une fraction est
      // construite.
      final construites = find.byType(SlotChip).evaluate().length;
      expect(construites, lessThan(60 * jours * 2 ~/ 2));
      expect(construites, greaterThan(0));
    });

    testWidgets('soixante membres ne coûtent **qu\'une** lecture, et rien ne '
        'la redéclenche', (tester) async {
      final jours = _joursDuMois(0);
      final depot = await _ouvrir(
        tester,
        taille: const Size(1920, 1080),
        lignes: <LigneMatrice>[
          for (var index = 0; index < 60; index++)
            ligneMatrice(
              userId: 'u$index',
              nom: 'Pompier ${index.toString().padLeft(2, '0')}',
              jours: index.isEven ? 'D' * jours : '.' * jours,
              nuits: '.' * jours,
              maxAstreintes: 4,
              astreintes: index % 5,
            ),
        ],
      );

      // **Une ligne par membre ne veut pas dire une requête par membre.**
      // Soixante appels de quinze millisecondes feraient exactement les neuf
      // cents millisecondes d'un budget perdu — c'est le piège trouvé au
      // ticket 014 sur le taux de saisie, et il ne reviendra pas ici sans
      // faire rougir ce test.
      expect(depot.lectures, 1);

      // Défiler ne relit rien : la virtualisation construit des cases, elle
      // ne redemande pas de données.
      final defilements = find.descendant(
        of: find.byType(GrilleMatrice),
        matching: find.byType(Scrollable),
      );
      tester.state<ScrollableState>(defilements.at(3)).position.jumpTo(600);
      tester.state<ScrollableState>(defilements.at(2)).position.jumpTo(900);
      await tester.pumpAndSettle();
      expect(depot.lectures, 1);

      // Filtrer, chercher et trier non plus.
      await tester.tap(find.text(AppStrings.matriceMasquerNonSaisis));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'pompier 1');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(AppStrings.matriceTrier));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.matriceTriAstreintes).last);
      await tester.pumpAndSettle();

      expect(depot.lectures, 1);
      expect(find.byType(GrilleMatrice), findsOneWidget);
    });

    testWidgets('la destination « Admin » ouvre la matrice', (tester) async {
      await _ouvrir(tester);

      await tester.tap(find.text(AppStrings.navAdmin));
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), contains(_chemin));
      expect(find.byType(MatriceScreen), findsOneWidget);
    });
  });

  group('MatriceScreen — les deux axes figés', () {
    testWidgets('la colonne figée et l\'en-tête suivent la grille au pixel '
        'près', (tester) async {
      final jours = _joursDuMois(0);
      await _ouvrir(
        tester,
        lignes: <LigneMatrice>[
          for (var index = 0; index < 40; index++)
            ligneMatrice(
              userId: 'u$index',
              nom: 'Pompier ${index.toString().padLeft(2, '0')}',
              jours: 'D' * jours,
              nuits: '.' * jours,
            ),
        ],
      );

      final defilements = find.descendant(
        of: find.byType(GrilleMatrice),
        matching: find.byType(Scrollable),
      );
      // Dans l'ordre de l'arbre : en-tête (horizontal), colonne figée
      // (vertical), grille (horizontal), grille (vertical).
      expect(defilements, findsNWidgets(4));

      ScrollPosition position(int index) =>
          tester.state<ScrollableState>(defilements.at(index)).position;

      position(2).jumpTo(240);
      await tester.pump();
      // **Un décalage d'un seul pixel rendrait l'écran faux** : le nom ne
      // serait plus en face de sa ligne, la date plus au-dessus de sa colonne.
      expect(position(0).pixels, 240);

      position(3).jumpTo(96);
      await tester.pump();
      expect(position(1).pixels, 96);

      // Et le lien joue dans les deux sens : la molette au-dessus de la
      // colonne des noms doit emporter la grille avec elle.
      position(1).jumpTo(32);
      await tester.pump();
      expect(position(3).pixels, 32);
    });

    testWidgets('en thème sombre, la matrice se rend sans exception', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _ouvrir(
        tester,
        lignes: <LigneMatrice>[
          // Une journée sans personne : c'est la case hachurée du compte
          // « 0 disponible », celle qu'il fallait vérifier sur fond sombre.
          ligneMatrice(
            userId: 'u1',
            nom: 'Dubois Jean-Marc',
            jours: '.' * _joursDuMois(0),
            nuits: '.' * _joursDuMois(0),
          ),
        ],
      );

      expect(find.byType(GrilleMatrice), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
