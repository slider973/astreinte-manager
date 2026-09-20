import 'dart:async';

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/count_stat.dart';
import 'package:astreinte_sp/core/widgets/day_cell.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/core/widgets/peinture_grille.dart';
import 'package:astreinte_sp/core/widgets/save_indicator.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/features/dispos/data/dispos_repository.dart';
import 'package:astreinte_sp/features/dispos/data/file_locale.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/presentation/mois_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';

CreneauCle jour(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.jour);
CreneauCle nuit(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.nuit);

/// La case du créneau [creneau] du [numero]ᵉ jour visible du registre.
///
/// L'ordre des `SlotChip` est celui de la lecture : jour puis nuit, ligne
/// après ligne.
Finder caseDe(int rang, CreneauType creneau) =>
    find.byType(SlotChip).at(rang * 2 + (creneau == CreneauType.jour ? 0 : 1));

Future<void> ouvrirMois(
  WidgetTester tester, {
  FauxDisposRepository? depot,
  ReperesLocaux? reperes,
  FileLocale? fileLocale,
  ConnectiviteMemoire? reseau,
  Size taille = const Size(390, 844),
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    dispos: depot ?? FauxDisposRepository(),
    fileLocale: fileLocale,
    reseau: reseau,
    reperes:
        reperes ??
        ReperesLocauxMemoire(<RepereAccueil>{RepereAccueil.peintureDispos}),
    taille: taille,
  );
}

/// Choisit un mois dans le sélecteur, en l'amenant d'abord sous le doigt :
/// la rangée de mois défile horizontalement dès que les boutons ne tiennent
/// plus côte à côte.
Future<void> choisirMois(WidgetTester tester, int mois, int annee) async {
  final bouton = find.text(AppStrings.moisNomEtAnnee(mois, annee));
  await tester.ensureVisible(bouton);
  await tester.pumpAndSettle();
  await tester.tap(bouton);
  await tester.pumpAndSettle();
}

/// L'URL courante, telle que la barre d'adresse la montre.
String adresse(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(MoisScreen)),
).read(appRouterProvider).routerDelegate.currentConfiguration.uri.toString();

/// Un appui long, puis un glissement vertical : la peinture.
Future<void> peindre(
  WidgetTester tester, {
  required Finder depart,
  required Finder arrivee,
}) async {
  final geste = await tester.startGesture(tester.getCenter(depart));
  await tester.pump(PeintureGrille.delaiAppuiLong * 2);
  await geste.moveTo(tester.getCenter(arrivee));
  await tester.pump();
  await geste.up();
  await tester.pump();
}

void main() {
  group('MoisScreen — le registre', () {
    testWidgets('montre le sélecteur, l\'en-tête et les jours du mois', (
      tester,
    ) async {
      await ouvrirMois(tester);

      expect(find.text(AppStrings.moisNomEtAnnee(10, 2026)), findsOneWidget);
      expect(find.text(AppStrings.grilleColonneDate), findsOneWidget);
      expect(find.text(AppStrings.creneauJour), findsOneWidget);
      expect(find.text(AppStrings.creneauNuit), findsOneWidget);
      expect(find.byType(DayCell), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chaque jour porte deux cases, jour puis nuit', (tester) async {
      await ouvrirMois(tester);

      final premiere = tester.widget<SlotChip>(caseDe(0, CreneauType.jour));
      final seconde = tester.widget<SlotChip>(caseDe(0, CreneauType.nuit));
      expect(premiere.creneau, CreneauType.jour);
      expect(seconde.creneau, CreneauType.nuit);
    });

    testWidgets('l\'écran n\'a aucun bouton « Enregistrer »', (tester) async {
      await ouvrirMois(tester);

      expect(find.text(AppStrings.actionEnregistrer), findsNothing);
      expect(find.byType(SaveIndicator), findsOneWidget);
    });

    testWidgets('la ligne d\'un jour férié le nomme en clair', (tester) async {
      await ouvrirMois(tester);

      // Le mois par défaut est octobre 2026 : sans férié. On passe à novembre.
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 11)],
      );
      await ouvrirMois(tester, depot: depot);

      expect(find.text(AppStrings.ferieToussaint), findsOneWidget);
      expect(find.byIcon(Icons.star), findsWidgets);
    });
  });

  group('MoisScreen — la touche', () {
    testWidgets('fait avancer la case et monte le compteur', (tester) async {
      final depot = FauxDisposRepository();
      await ouvrirMois(tester, depot: depot);

      await tester.tap(caseDe(0, CreneauType.nuit));
      await tester.pump();

      expect(
        tester.widget<SlotChip>(caseDe(0, CreneauType.nuit)).etat,
        DisponibiliteEtat.disponible,
      );
      expect(
        tester
            .widget<CountStat>(
              find.widgetWithText(CountStat, AppStrings.compteurNuits),
            )
            .valeur,
        1,
      );

      await tester.pump(const Duration(seconds: 1));
      expect(depot.base[nuit(1)], DisponibiliteEtat.disponible);
    });

    testWidgets('trois appuis ramènent la case au vide', (tester) async {
      final depot = FauxDisposRepository();
      await ouvrirMois(tester, depot: depot);

      for (var appui = 0; appui < 3; appui++) {
        await tester.tap(caseDe(0, CreneauType.jour));
        await tester.pump();
      }

      expect(
        tester.widget<SlotChip>(caseDe(0, CreneauType.jour)).etat,
        DisponibiliteEtat.nonSaisi,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(depot.requetes, 0, reason: 'rien n\'a changé en base');
    });

    testWidgets('l\'indicateur passe de « À jour » à « Enregistré »', (
      tester,
    ) async {
      await ouvrirMois(tester);
      expect(find.text(AppStrings.saveAuRepos), findsOneWidget);

      await tester.tap(caseDe(0, CreneauType.jour));
      await tester.pump();
      expect(find.text(AppStrings.saveEnCours), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text(AppStrings.saveTermine), findsOneWidget);
    });
  });

  group('MoisScreen — la peinture', () {
    testWidgets('un appui long puis un glissement coche toute la colonne', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      // **Fenêtre plus haute que le téléphone de référence, et c'est
      // délibéré.** La police des tests dessine chaque glyphe comme un carré
      // de la taille de la fonte : tout bloc de texte y est environ deux fois
      // plus haut qu'à l'écran. Depuis que le ticket 013 pose la section des
      // maximums dès la première case cochée, un rig de 390 × 844 ne
      // construit plus quatre lignes de jour — alors que le vrai écran, lui,
      // en garde trois (`design/013 § 3`, section mesurée à 94 dp). Ce que ce
      // test prouve, c'est qu'un geste vertical coche une colonne entière
      // sans toucher l'autre ; il lui faut des rangs, pas un téléphone.
      await ouvrirMois(tester, depot: depot, taille: const Size(390, 1100));
      await peindre(
        tester,
        depart: caseDe(0, CreneauType.nuit),
        arrivee: caseDe(3, CreneauType.nuit),
      );

      for (var rang = 0; rang <= 3; rang++) {
        expect(
          tester.widget<SlotChip>(caseDe(rang, CreneauType.nuit)).etat,
          DisponibiliteEtat.disponible,
          reason: 'la nuit du rang $rang doit être cochée',
        );
        expect(
          tester.widget<SlotChip>(caseDe(rang, CreneauType.jour)).etat,
          DisponibiliteEtat.nonSaisi,
          reason: 'le geste vertical ne touche pas la colonne du jour',
        );
      }

      await tester.pump(const Duration(seconds: 1));
      expect(depot.requetes, 1, reason: 'quatre cases, une requête');
      expect(depot.ecritures.single, hasLength(4));
    });

    testWidgets('pendant le geste, la barre annonce le pinceau', (
      tester,
    ) async {
      await ouvrirMois(tester);

      final geste = await tester.startGesture(
        tester.getCenter(caseDe(0, CreneauType.nuit)),
      );
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);

      expect(
        find.text(AppStrings.peintureEnCours(AppStrings.etatDisponible)),
        findsOneWidget,
      );
      expect(
        find.byType(SaveIndicator),
        findsNothing,
        reason: 'l\'indicateur laisse la place au pinceau',
      );
      expect(
        tester.widget<SlotChip>(caseDe(0, CreneauType.nuit)).selectionne,
        isTrue,
        reason: 'la case d\'origine prend le contour de sélection',
      );

      await geste.up();
      await tester.pump();
      expect(find.byType(SaveIndicator), findsOneWidget);
      expect(
        tester.widget<SlotChip>(caseDe(0, CreneauType.nuit)).selectionne,
        isFalse,
        reason: 'le contour part avec le doigt',
      );
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('un glissement sans appui long fait défiler et ne peint rien', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      await ouvrirMois(tester, depot: depot);

      final avant = tester.widget<SlotChip>(caseDe(0, CreneauType.nuit)).etat;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 1));
      expect(depot.requetes, 0);
      expect(avant, DisponibiliteEtat.nonSaisi);
    });

    testWidgets('Échap annule la peinture et rend les cases', (tester) async {
      final depot = FauxDisposRepository();
      await ouvrirMois(tester, depot: depot);

      final geste = await tester.startGesture(
        tester.getCenter(caseDe(0, CreneauType.nuit)),
      );
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      await geste.moveTo(tester.getCenter(caseDe(3, CreneauType.nuit)));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await geste.up();
      await tester.pump();

      for (var rang = 0; rang <= 3; rang++) {
        expect(
          tester.widget<SlotChip>(caseDe(rang, CreneauType.nuit)).etat,
          DisponibiliteEtat.nonSaisi,
        );
      }
      await tester.pump(const Duration(seconds: 1));
      expect(depot.requetes, 0);
    });
  });

  group('MoisScreen — les compteurs', () {
    testWidgets('comptent jours, nuits et weekends du mois lu', (tester) async {
      // Samedi 3 et dimanche 4 octobre 2026 : un seul weekend.
      final depot = FauxDisposRepository(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          jour(1): DisponibiliteEtat.disponible,
          nuit(3): DisponibiliteEtat.disponible,
          nuit(4): DisponibiliteEtat.disponible,
          jour(2): DisponibiliteEtat.absent,
        },
      );
      await ouvrirMois(tester, depot: depot);

      int valeur(String libelle) => tester
          .widget<CountStat>(find.widgetWithText(CountStat, libelle))
          .valeur;

      expect(valeur(AppStrings.compteurJours), 1);
      expect(valeur(AppStrings.compteurNuits), 2);
      expect(valeur(AppStrings.compteurWeekends), 1);
    });

    testWidgets('la barre est annoncée en une phrase', (tester) async {
      final handle = tester.ensureSemantics();
      await ouvrirMois(tester);

      expect(
        find.bySemanticsLabel(AppStrings.compteursResume(0, 0, 0)),
        findsOneWidget,
      );

      handle.dispose();
    });
  });

  group('MoisScreen — les états de l\'écran', () {
    testWidgets(
      'mois verrouillé : bannière, cases inertes, pas d\'indicateur',
      (tester) async {
        final depot = FauxDisposRepository(
          periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
          disponibilites: <CreneauCle, DisponibiliteEtat>{
            jour(1): DisponibiliteEtat.disponible,
          },
        );
        await ouvrirMois(tester, depot: depot);

        final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
        expect(banniere.variante, AppBannerVariante.verrouille);

        final premiere = tester.widget<SlotChip>(caseDe(0, CreneauType.jour));
        expect(premiere.verrouille, isTrue);
        expect(premiere.onTap, isNull);
        expect(
          premiere.etat,
          DisponibiliteEtat.disponible,
          reason: 'les valeurs restent parfaitement lisibles',
        );

        expect(
          find.byType(SaveIndicator),
          findsNothing,
          reason: 'il n\'y a plus rien à enregistrer',
        );
        // Les compteurs, eux, sont maintenus.
        expect(find.byType(CountStat), findsNWidgets(3));
      },
    );

    testWidgets('mois verrouillé : aucune case focalisable', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
      );
      await ouvrirMois(tester, depot: depot);

      expect(
        find.descendant(of: find.byType(DayCell), matching: find.byType(Focus)),
        findsNothing,
      );
    });

    testWidgets('aucune période : un état vide sans bouton mort', (
      tester,
    ) async {
      final depot = FauxDisposRepository(periodes: <PeriodeSaisie>[]);
      await ouvrirMois(tester, depot: depot);

      expect(find.text(AppStrings.moisAucunePeriodeTitre), findsOneWidget);
      expect(find.text(AppStrings.moisAucunePeriodeTexte), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(SlotChip), findsNothing);
    });

    testWidgets('chargement impossible : « Réessayer », jamais une roue', (
      tester,
    ) async {
      final depot = FauxDisposRepository()..erreurLecture = ErreurDispos.reseau;
      await ouvrirMois(tester, depot: depot);

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'échec d\'enregistrement : la case porte le contour d\'erreur',
      (tester) async {
        final depot = FauxDisposRepository()
          ..erreurEcriture = ErreurDispos.inconnue;
        // Rig plus haut : bannière d'échec, sélecteur, raccourcis et section
        // des maximums empilés au-dessus de la grille ne laissent plus de
        // ligne de jour dans la police des tests (voir la note du geste de
        // peinture).
        await ouvrirMois(tester, depot: depot, taille: const Size(390, 1100));

        await tester.tap(caseDe(0, CreneauType.jour));
        await tester.pump(const Duration(seconds: 10));

        expect(
          tester.widget<SlotChip>(caseDe(0, CreneauType.jour)).erreur,
          isTrue,
        );
        expect(
          tester.widget<SlotChip>(caseDe(0, CreneauType.nuit)).erreur,
          isFalse,
          reason: 'les seules cases concernées',
        );
        expect(find.text(AppStrings.saveEchecDetail), findsWidgets);
        expect(find.text(AppStrings.actionReessayer), findsWidgets);
      },
    );

    testWidgets('refus du serveur : bannière d\'erreur et « Recharger »', (
      tester,
    ) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.verrouille;
      await ouvrirMois(tester, depot: depot);

      await tester.tap(caseDe(0, CreneauType.jour));
      await tester.pump(const Duration(seconds: 2));

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.erreur);
      expect(find.text(AppStrings.actionRecharger), findsOneWidget);
    });

    testWidgets('mois vierge : la grille est là, avec le bloc d\'aide', (
      tester,
    ) async {
      await ouvrirMois(tester, reperes: ReperesLocauxMemoire());

      expect(find.text(AppStrings.astuceSaisieTouche), findsOneWidget);
      expect(find.text(AppStrings.astuceSaisieGlissement), findsOneWidget);
      expect(find.byType(SlotChip), findsWidgets);
    });

    testWidgets('le bloc d\'aide s\'efface dès la première saisie', (
      tester,
    ) async {
      await ouvrirMois(
        tester,
        reperes: ReperesLocauxMemoire(<RepereAccueil>{
          RepereAccueil.peintureDispos,
        }),
      );
      expect(find.text(AppStrings.astuceSaisieTouche), findsOneWidget);

      await tester.tap(caseDe(0, CreneauType.jour));
      await tester.pump();

      expect(find.text(AppStrings.astuceSaisieTouche), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('sur un mois verrouillé, le bloc d\'aide ne paraît jamais', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
      );
      await ouvrirMois(tester, depot: depot, reperes: ReperesLocauxMemoire());

      expect(find.text(AppStrings.astuceSaisieTouche), findsNothing);
      expect(find.text(AppStrings.astuceSaisieGlissement), findsNothing);
    });
  });

  group('MoisScreen — le sélecteur de mois', () {
    testWidgets('montre chaque période avec son état', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeVerrouillee(annee: 2026, mois: 9),
          periodeOuverte(annee: 2026, mois: 10),
        ],
      );
      await ouvrirMois(tester, depot: depot);

      expect(find.text(AppStrings.moisNomEtAnnee(9, 2026)), findsOneWidget);
      expect(find.text(AppStrings.moisNomEtAnnee(10, 2026)), findsOneWidget);
      expect(find.text(AppStrings.moisVerrouilleCourt), findsOneWidget);
    });

    testWidgets('range les mois du plus ancien au plus récent', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeVerrouillee(annee: 2026, mois: 9),
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      );
      await ouvrirMois(tester, depot: depot);

      double gaucheDe(int mois) => tester
          .getTopLeft(find.text(AppStrings.moisNomEtAnnee(mois, 2026)))
          .dx;

      expect(gaucheDe(9), lessThan(gaucheDe(10)));
      expect(gaucheDe(10), lessThan(gaucheDe(11)));
    });

    testWidgets('changer de mois vide la file avant de partir', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      );
      await ouvrirMois(tester, depot: depot);

      await tester.tap(caseDe(0, CreneauType.jour));
      await tester.pump();
      await choisirMois(tester, 11, 2026);

      expect(depot.requetes, 1);
      expect(depot.base.keys.single, jour(1));
      expect(
        tester.widgetList<DayCell>(find.byType(DayCell)).first.nomJour,
        'dim.',
        reason: 'le 1er novembre 2026 est un dimanche',
      );
    });
  });

  group('MoisScreen — la file gardée sur l\'appareil', () {
    testWidgets('une file gardée sur un mois verrouillé se dit en bannière', (
      tester,
    ) async {
      final locale = FileLocaleMemoire();
      await locale.enregistrer(
        stationId: '',
        userId: '',
        mois: '2026-09',
        entrees: <CreneauCle, DisponibiliteEtat>{
          CreneauCle(DateTime(2026, 9, 7), CreneauType.nuit):
              DisponibiliteEtat.disponible,
        },
      );

      await ouvrirMois(
        tester,
        depot: FauxDisposRepository(
          periodes: <PeriodeSaisie>[
            periodeVerrouillee(annee: 2026, mois: 9),
            periodeOuverte(annee: 2026, mois: 10),
          ],
        ),
        fileLocale: locale,
      );

      expect(find.text(AppStrings.moisFilePerimeeBanniere), findsOneWidget);

      await tester.tap(find.text(AppStrings.actionFermer));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.moisFilePerimeeBanniere), findsNothing);
    });

    testWidgets('changer de mois hors ligne ne perd pas les cases posées', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      )..erreurEcriture = ErreurDispos.reseau;
      final reseau = ConnectiviteMemoire();
      addTearDown(reseau.dispose);
      await ouvrirMois(tester, depot: depot, reseau: reseau);

      reseau.definir(enLigne: false);
      await tester.pump();
      await tester.tap(caseDe(0, CreneauType.jour));
      await tester.tap(caseDe(1, CreneauType.jour));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(AppStrings.horsLigneDetail), findsOneWidget);

      await choisirMois(tester, 11, 2026);
      expect(
        tester.widgetList<DayCell>(find.byType(DayCell)).first.nomJour,
        'dim.',
        reason: 'le 1er novembre 2026 est un dimanche',
      );

      // Le réseau revient : les deux cases d'octobre partent.
      depot.erreurEcriture = null;
      reseau.definir(enLigne: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(depot.base.keys.map((cle) => cle.cleMois).toSet(), <String>{
        '2026-10',
      });
      expect(depot.base, hasLength(2));
    });
  });

  group('MoisScreen — le mois dans l\'URL', () {
    testWidgets('le mois choisi part dans l\'URL', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      );
      await ouvrirMois(tester, depot: depot);

      await choisirMois(tester, 11, 2026);

      expect(adresse(tester), contains('mois=2026-11'));
    });

    testWidgets('le retour du navigateur ramène au mois précédent', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      );
      await ouvrirMois(tester, depot: depot);
      expect(find.byType(DayCell), findsWidgets);

      await choisirMois(tester, 11, 2026);
      expect(
        tester.widgetList<DayCell>(find.byType(DayCell)).first.nomJour,
        'dim.',
        reason: 'le 1er novembre 2026 est un dimanche',
      );

      // Le retour du navigateur ramène à l'entrée précédente, sans mois :
      // c'est le mois par défaut qui doit revenir.
      await ouvrirRoute(tester, '/?onglet=0');
      expect(
        tester.widgetList<DayCell>(find.byType(DayCell)).first.nomJour,
        'jeu.',
        reason: 'le 1er octobre 2026 est un jeudi',
      );
    });
  });

  group('MoisScreen — tailles et classes de fenêtre', () {
    testWidgets('chargement : un squelette, jamais une roue', (tester) async {
      final depot = _DepotLent();
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        dispos: depot,
        stabiliser: false,
      );

      expect(find.byType(LoadingSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      depot.liberer();
      await tester.pumpAndSettle();
      expect(find.byType(SlotChip), findsWidgets);
    });

    testWidgets('sur grand écran, la vue calendaire prend sept colonnes', (
      tester,
    ) async {
      await ouvrirMois(tester, taille: const Size(1280, 900));

      expect(find.text(AppStrings.grilleJoursInitiales.first), findsWidgets);
      // Une semaine complète, jours des mois voisins compris.
      expect(find.byType(DayCell), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    for (final taille in <Size>[
      const Size(320, 720),
      const Size(360, 800),
      const Size(390, 844),
      const Size(430, 932),
      const Size(844, 390),
    ]) {
      testWidgets(
        'tient sur ${taille.width.toInt()} × ${taille.height.toInt()}',
        (tester) async {
          await ouvrirMois(tester, taille: taille);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('à ×2.0, la ligne passe à deux niveaux sans troncature', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await ouvrirMois(tester);

      expect(tester.takeException(), isNull);
      final cellules = tester.widgetList<DayCell>(
        find.byType(DayCell, skipOffstage: false),
      );
      expect(cellules, isNotEmpty);
      expect(
        cellules.first.orientation,
        DayCellOrientation.ligne,
        reason: 'la grille change de forme plutôt que de rogner',
      );
      expect(cellules.first.deuxNiveaux, isTrue);
    });
  });
}

/// Un dépôt dont la lecture ne rend la main que sur commande.
class _DepotLent extends FauxDisposRepository {
  final Completer<void> _verrou = Completer<void>();

  void liberer() => _verrou.complete();

  @override
  Future<Map<CreneauCle, DisponibiliteEtat>> lireMois({
    required String stationId,
    required String userId,
    required int annee,
    required int mois,
  }) async {
    await _verrou.future;
    return super.lireMois(
      stationId: stationId,
      userId: userId,
      annee: annee,
      mois: mois,
    );
  }
}
