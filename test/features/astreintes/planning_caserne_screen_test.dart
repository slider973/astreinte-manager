import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_planning_caserne.dart';
import 'package:astreinte_sp/features/astreintes/data/planning_caserne_repository.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/domain/planning_caserne.dart';
import 'package:astreinte_sp/features/astreintes/presentation/widgets/bloc_attente_validation.dart';
import 'package:astreinte_sp/features/astreintes/presentation/widgets/journee_caserne.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_planning_caserne.dart';

/// Le jour de référence : un jeudi 15 octobre 2026.
final DateTime _aujourdhui = DateTime(2026, 10, 15, 9);

const String _lienNotification = '/schedule/2026-10';

final MoisPlanning _octobre = moisPlanning(annee: 2026, mois: 10);
final MoisPlanning _novembre = moisPlanning(
  annee: 2026,
  mois: 11,
  etat: PlanningEtat.publie,
);

final MoisPlanning _aout = moisPlanning(
  annee: 2026,
  mois: 8,
  etat: PlanningEtat.archive,
);

/// Août archivé le 1er septembre par `cron_archive_schedules` : le tableau de
/// garde du mois écoulé, trous compris (ticket 044).
PlanningCaserne _aoutArchive() => planningCaserne(
  mois: _aout,
  journees: <int, List<CreneauCaserne>>{
    14: <CreneauCaserne>[
      creneauCaserne(
        id: 'c-14-nuit',
        moi: true,
        noms: const <String>['Camille G.'],
      ),
    ],
    // Personne n'a tenu cette garde-là, et le mois est fini : c'est un fait.
    15: <CreneauCaserne>[creneauCaserne(id: 'c-15-nuit')],
  },
  luLe: _aujourdhui,
);

/// Octobre validé : trois journées, toute la caserne nommée.
PlanningCaserne _octobreValide() => planningCaserne(
  mois: _octobre,
  journees: <int, List<CreneauCaserne>>{
    3: <CreneauCaserne>[
      creneauCaserne(
        id: 'c-3-nuit',
        moi: true,
        noms: const <String>['Thomas M.'],
      ),
    ],
    10: <CreneauCaserne>[
      creneauCaserne(
        id: 'c-10-jour',
        creneau: CreneauType.jour,
        noms: const <String>['Camille G.', 'Lucas B.'],
      ),
      // Un trou : deux personnes demandées, personne d'accepté.
      creneauCaserne(id: 'c-10-nuit'),
    ],
  },
  luLe: _aujourdhui,
);

/// Novembre publié : **seuls les créneaux du lecteur** remontent de la base.
PlanningCaserne _novembrePublie() => planningCaserne(
  mois: _novembre,
  journees: <int, List<CreneauCaserne>>{
    7: <CreneauCaserne>[
      creneauCaserne(id: 'c-7-jour', creneau: CreneauType.jour),
      creneauCaserne(id: 'c-7-nuit', moi: true),
    ],
  },
  luLe: _aujourdhui,
);

FauxPlanningCaserneRepository _depotComplet() => FauxPlanningCaserneRepository(
  mois: <MoisPlanning>[_octobre, _novembre],
  plannings: <String, PlanningCaserne>{
    '2026-10': _octobreValide(),
    '2026-11': _novembrePublie(),
  },
);

/// Monte l'application, va sur l'onglet « Astreintes » et bascule sur « La
/// caserne ».
Future<FauxPlanningCaserneRepository> _ouvrirCaserne(
  WidgetTester tester, {
  FauxPlanningCaserneRepository? depot,
  CachePlanningCaserne? cache,
  Connectivite? reseau,
}) async {
  final planning = depot ?? _depotComplet();

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    planningCaserne: planning,
    cachePlanningCaserne: cache ?? CachePlanningCaserneMemoire(),
    horloge: () => _aujourdhui,
    reseau: reseau,
  );
  await ouvrirRoute(tester, _lienNotification);

  await tester.tap(find.text(AppStrings.porteeCaserne));
  await tester.pumpAndSettle();
  return planning;
}

void main() {
  group('la portée', () {
    testWidgets(
      'l\'écran s\'ouvre sur « Moi » et le sélecteur mène à la caserne',
      (WidgetTester tester) async {
        await monterApp(
          tester,
          session: sessionMembre,
          appartenances: const <Appartenance>[appartenanceMembre],
          planningCaserne: _depotComplet(),
          horloge: () => _aujourdhui,
        );
        await ouvrirRoute(tester, _lienNotification);

        // Une seule destination, deux portées : le ticket 023 n'ajoute aucun
        // onglet (`design/027 § 4`).
        expect(find.text(AppStrings.astreintesTitre), findsOneWidget);
        expect(find.text(AppStrings.porteeMoi), findsOneWidget);
        expect(find.text(AppStrings.porteeCaserne), findsOneWidget);

        await tester.tap(find.text(AppStrings.porteeCaserne));
        await tester.pumpAndSettle();

        // Le titre suit la portée : c'est ce qu'un lecteur d'écran annonce.
        expect(find.text(AppStrings.planningCaserneTitre), findsOneWidget);
        expect(find.text(AppStrings.astreintesTitre), findsNothing);
        // La bascule de vue appartient à « Moi » et disparaît avec elle.
        expect(find.text(AppStrings.astreintesVueCalendrier), findsNothing);
      },
    );
  });

  group('un planning validé', () {
    testWidgets('nomme toute la caserne, et marque le lecteur', (
      WidgetTester tester,
    ) async {
      await _ouvrirCaserne(tester);

      expect(find.text('Octobre 2026'), findsOneWidget);
      expect(find.byType(JourneeCaserneBloc), findsNWidgets(2));
      expect(find.text('samedi 3 octobre'), findsOneWidget);
      expect(find.text('samedi 10 octobre'), findsOneWidget);

      // Les autres, nommés. Le lecteur, marqué « Toi » et en tête.
      expect(find.text('Thomas M.'), findsOneWidget);
      expect(find.text('Camille G.'), findsOneWidget);
      expect(find.text('Lucas B.'), findsOneWidget);
      expect(find.text(AppStrings.planningCaserneToi), findsOneWidget);

      // Aucun bloc d'attente : le planning est validé, la vue est entière.
      expect(find.byType(BlocAttenteValidation), findsNothing);
    });

    testWidgets('un créneau que personne ne couvre le dit', (
      WidgetTester tester,
    ) async {
      await _ouvrirCaserne(tester);

      // Le 10 octobre au soir : deux personnes demandées, personne d'accepté.
      // C'est un trou du planning, donc une information.
      expect(
        find.text(AppStrings.planningCaserneCreneauVide),
        findsOneWidget,
      );
    });

    testWidgets('affiche les heures de la caserne, pas 7 h – 19 h en dur', (
      WidgetTester tester,
    ) async {
      await _ouvrirCaserne(
        tester,
        depot: FauxPlanningCaserneRepository(
          mois: <MoisPlanning>[_octobre],
          plannings: <String, PlanningCaserne>{
            '2026-10': planningCaserne(
              mois: _octobre,
              journees: <int, List<CreneauCaserne>>{
                3: <CreneauCaserne>[
                  creneauCaserne(id: 'c-3', noms: const <String>['Thomas M.']),
                ],
              },
              heures: const HeuresAffichage(
                debutJour: '08:00',
                finJour: '20:00',
              ),
              luLe: _aujourdhui,
            ),
          },
        ),
      );

      expect(find.text('20:00 → 08:00'), findsOneWidget);
    });
  });

  group('un planning seulement publié', () {
    testWidgets(
      'dit pourquoi la vue est partielle, au lieu de la laisser passer pour '
      'un planning vide',
      (WidgetTester tester) async {
        await _ouvrirCaserne(tester);
        await tester.tap(find.byTooltip(AppStrings.astreintesMoisSuivant));
        await tester.pumpAndSettle();

        expect(find.text('Novembre 2026'), findsOneWidget);
        expect(find.byType(BlocAttenteValidation), findsOneWidget);
        expect(
          find.text(AppStrings.planningCaserneAttenteTitre),
          findsOneWidget,
        );
        expect(
          find.text(AppStrings.planningCaserneAttenteTexte),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'n\'écrit **jamais** « personne » sur un créneau qu\'il n\'a pas le '
      'droit de lire',
      (WidgetTester tester) async {
        await _ouvrirCaserne(tester);
        await tester.tap(find.byTooltip(AppStrings.astreintesMoisSuivant));
        await tester.pumpAndSettle();

        // Le 7 novembre, le lecteur est de nuit. Son créneau de jour existe et
        // porte sûrement quelqu'un : la base ne l'a simplement pas rendu.
        expect(find.text(AppStrings.planningCaserneToi), findsOneWidget);
        expect(
          find.text(AppStrings.planningCaserneCreneauVide),
          findsNothing,
        );
        // Le créneau de jour n'est pas affiché du tout.
        expect(find.text('07:00 → 19:00'), findsNothing);
        expect(find.text('19:00 → 07:00'), findsOneWidget);
      },
    );

    testWidgets(
      'un mois publié où le lecteur n\'a rien garde le bloc d\'attente : '
      'c\'est lui qui distingue « personne » de « pas le droit »',
      (WidgetTester tester) async {
        await _ouvrirCaserne(
          tester,
          depot: FauxPlanningCaserneRepository(
            mois: <MoisPlanning>[_novembre],
            plannings: <String, PlanningCaserne>{
              '2026-11': planningCaserne(mois: _novembre, luLe: _aujourdhui),
            },
          ),
        );

        expect(find.byType(BlocAttenteValidation), findsOneWidget);
        expect(
          find.text(
            AppStrings.planningCaserneSansMoiTitre(_novembre.libelle),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('un planning archivé', () {
    testWidgets(
      'reste atteignable et se lit en entier : le tableau du mois écoulé',
      (WidgetTester tester) async {
        // Sans le ticket 044, août aurait disparu du sélecteur le 1er
        // septembre — et chaque mois passé après lui.
        await _ouvrirCaserne(
          tester,
          depot: FauxPlanningCaserneRepository(
            mois: <MoisPlanning>[_aout, _octobre],
            plannings: <String, PlanningCaserne>{
              '2026-08': _aoutArchive(),
              '2026-10': _octobreValide(),
            },
          ),
        );

        expect(find.text('Octobre 2026'), findsOneWidget);

        await tester.tap(find.byTooltip(AppStrings.astreintesMoisPrecedent));
        await tester.pumpAndSettle();

        expect(find.text('Août 2026'), findsOneWidget);
        // Toute la caserne, comme sur un mois validé : les gardes tenues sont
        // rendues par `assignments_select_station_archived`.
        expect(find.text('Camille G.'), findsOneWidget);
        expect(find.text(AppStrings.planningCaserneToi), findsOneWidget);
        expect(find.text(AppStrings.planningCaserneCreneauVide), findsOneWidget);
        // Et **aucune** attente de validation : le mois est terminé, plus
        // personne ne le validera.
        expect(find.byType(BlocAttenteValidation), findsNothing);
      },
    );
  });

  group('le sélecteur de mois', () {
    testWidgets('marche de planning en planning, bornes désactivées', (
      WidgetTester tester,
    ) async {
      final depot = await _ouvrirCaserne(tester);

      // Octobre est le mois courant : c'est là qu'on ouvre.
      expect(find.text('Octobre 2026'), findsOneWidget);

      // Sur la borne basse, la flèche porte sa raison — désactivée, jamais
      // cachée (`DESIGN.md § Écarts, ticket 027`).
      expect(
        find.byTooltip(AppStrings.planningCaserneMoisAvantDebut),
        findsOneWidget,
      );
      final precedent = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_left),
          matching: find.byType(IconButton),
        ),
      );
      expect(precedent.onPressed, isNull);

      await tester.tap(find.byTooltip(AppStrings.astreintesMoisSuivant));
      await tester.pumpAndSettle();

      expect(find.text('Novembre 2026'), findsOneWidget);
      expect(
        find.byTooltip(AppStrings.planningCaserneMoisApresFin),
        findsOneWidget,
      );
      expect(depot.demandes, contains('2026-11'));

      await tester.tap(find.byTooltip(AppStrings.astreintesMoisPrecedent));
      await tester.pumpAndSettle();
      expect(find.text('Octobre 2026'), findsOneWidget);
    });

    testWidgets(
      'un mois sans planning n\'est pas une destination : seuls les publiés '
      'et les validés sont proposés',
      (WidgetTester tester) async {
        // Septembre et novembre, pas octobre : « › » depuis septembre saute
        // directement à novembre.
        final septembre = moisPlanning(annee: 2026, mois: 9);
        await _ouvrirCaserne(
          tester,
          depot: FauxPlanningCaserneRepository(
            mois: <MoisPlanning>[septembre, _novembre],
            plannings: <String, PlanningCaserne>{
              '2026-09': planningCaserne(mois: septembre, luLe: _aujourdhui),
              '2026-11': _novembrePublie(),
            },
          ),
        );

        // Le mois courant n'a pas de planning : on ouvre sur le premier à
        // venir.
        expect(find.text('Novembre 2026'), findsOneWidget);

        await tester.tap(find.byTooltip(AppStrings.astreintesMoisPrecedent));
        await tester.pumpAndSettle();

        expect(find.text('Septembre 2026'), findsOneWidget);
        expect(find.text('Octobre 2026'), findsNothing);
      },
    );
  });

  group('les mois sans planning', () {
    testWidgets('aucun planning publié : un état vide qui explique', (
      WidgetTester tester,
    ) async {
      await _ouvrirCaserne(
        tester,
        depot: FauxPlanningCaserneRepository(mois: const <MoisPlanning>[]),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(AppStrings.planningCaserneAucunTitre), findsOneWidget);
      expect(find.text(AppStrings.planningCaserneAucunTexte), findsOneWidget);
      // Pas de barre de mois : il n'y a aucun mois à choisir.
      expect(find.byIcon(Icons.chevron_left), findsNothing);

      // L'action ramène à « Moi ».
      await tester.tap(find.text(AppStrings.planningCaserneAucunAction));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.astreintesTitre), findsOneWidget);
    });

    testWidgets(
      'un mois listé dont le planning a disparu le dit, sans faire croire '
      'qu\'il est vide',
      (WidgetTester tester) async {
        final depot = FauxPlanningCaserneRepository(
          mois: <MoisPlanning>[_octobre],
          plannings: <String, PlanningCaserne>{'2026-10': _octobreValide()},
        )..oublierPlanning('2026-10');

        await _ouvrirCaserne(tester, depot: depot);

        expect(
          find.text(AppStrings.planningCaserneIntrouvableTitre),
          findsOneWidget,
        );
        expect(find.byType(JourneeCaserneBloc), findsNothing);
      },
    );
  });

  group('sans réseau', () {
    testWidgets(
      'le mois gardé sur l\'appareil reste lisible, avec l\'âge de la lecture',
      (WidgetTester tester) async {
        final cache = CachePlanningCaserneMemoire(
          mois: <MoisPlanning>[_octobre],
          plannings: <PlanningCaserne>[
            _octobreValide().copie(
              luLe: _aujourdhui.subtract(const Duration(hours: 2)),
            ),
          ],
        );

        await _ouvrirCaserne(
          tester,
          cache: cache,
          depot: FauxPlanningCaserneRepository(
            mois: <MoisPlanning>[_octobre],
            erreurMois: ErreurPlanningCaserne.reseau,
          ),
          reseau: ConnectiviteMemoire(enLigne: false),
        );

        // Le planning est là, lu sur l'appareil.
        expect(find.byType(JourneeCaserneBloc), findsNWidgets(2));
        expect(find.text('Thomas M.'), findsOneWidget);

        // Et l'écran dit **l'âge de ce qu'on lit**, pas qu'il ne peut rien
        // envoyer : cet écran n'écrit rien (`design/027 § 9`).
        final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
        expect(banniere.variante, AppBannerVariante.horsLigne);
        expect(banniere.texte, AppStrings.astreintesHorsLigne);
        expect(banniere.detail, contains('il y a 2 h'));
      },
    );

    testWidgets(
      'en ligne mais lecture ratée : le contenu reste, le bandeau le dit',
      (WidgetTester tester) async {
        final cache = CachePlanningCaserneMemoire(
          mois: <MoisPlanning>[_octobre],
          plannings: <PlanningCaserne>[_octobreValide()],
        );

        await _ouvrirCaserne(
          tester,
          cache: cache,
          depot: FauxPlanningCaserneRepository(
            mois: <MoisPlanning>[_octobre],
            erreurMois: ErreurPlanningCaserne.reseau,
          ),
        );

        expect(find.byType(JourneeCaserneBloc), findsNWidgets(2));
        final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
        expect(banniere.variante, AppBannerVariante.attention);
        expect(banniere.texte, AppStrings.planningCaserneNonActualise);
      },
    );

    testWidgets(
      'rien en cache et rien sur le réseau : l\'écran nomme ce qui manque, '
      'au lieu de se faire passer pour une caserne sans planning',
      (WidgetTester tester) async {
        await _ouvrirCaserne(
          tester,
          depot: FauxPlanningCaserneRepository(
            erreurMois: ErreurPlanningCaserne.reseau,
          ),
          reseau: ConnectiviteMemoire(enLigne: false),
        );

        expect(find.text(AppStrings.erreurReseauTitre), findsOneWidget);
        expect(find.text(AppStrings.planningCaserneAucunTitre), findsNothing);
      },
    );

    testWidgets('en ligne, un échec sans rien en cache nomme la lecture', (
      WidgetTester tester,
    ) async {
      await _ouvrirCaserne(
        tester,
        depot: FauxPlanningCaserneRepository(
          erreurMois: ErreurPlanningCaserne.inconnue,
        ),
      );

      expect(find.text(AppStrings.planningCaserneErreurTexte), findsOneWidget);
      expect(find.text(AppStrings.planningCaserneAucunTitre), findsNothing);
    });

    testWidgets('une lecture réussie remplace le cache', (
      WidgetTester tester,
    ) async {
      final cache = CachePlanningCaserneMemoire();
      await _ouvrirCaserne(tester, cache: cache);

      expect(cache.ecritures, greaterThan(0));
      const prefixe =
          '${CachePlanningCaserneMemoire.stationDeTestId}.'
          '${CachePlanningCaserneMemoire.membreDeTestUserId}';
      expect(
        cache.clesGardees,
        containsAll(<String>[prefixe, '$prefixe.2026-10']),
      );
    });
  });
}
