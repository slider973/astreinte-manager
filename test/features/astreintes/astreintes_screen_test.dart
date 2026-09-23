import 'dart:async';

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/appartenances_locales.dart';
import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/entete_section.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/features/astreintes/data/astreintes_repository.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/presentation/widgets/calendrier_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/presentation/widgets/feuille_astreinte.dart';
import 'package:astreinte_sp/features/astreintes/presentation/widgets/ligne_astreinte.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';

/// Un téléphone : la composition de référence de cet écran.
const Size _telephone = Size(390, 844);

/// Le jour de référence : un jeudi 15 octobre 2026.
final DateTime _aujourdhui = DateTime(2026, 10, 15, 9);

/// Le lien public d'une notification de planning validé
/// (`docs/WORKFLOWS.md § 8`).
const String _lienNotification = '/schedule/2026-10';

/// Deux astreintes à venir, deux passées. Le 17 octobre nuit, le 3 novembre
/// jour ; le 2 et le 9 octobre derrière le repli.
List<Astreinte> _quatre() => <Astreinte>[
  astreinte(
    id: 'a-17',
    creneauId: 'c-17',
    jour: DateTime(2026, 10, 17),
    equipiers: const <String>['Thomas B.'],
  ),
  astreinte(
    id: 'a-nov',
    creneauId: 'c-nov',
    planningId: 'plan-11',
    jour: DateTime(2026, 11, 3),
    creneau: CreneauType.jour,
    planningEtat: PlanningEtat.publie,
  ),
  astreinte(id: 'a-09', creneauId: 'c-09', jour: DateTime(2026, 10, 9)),
  astreinte(id: 'a-02', creneauId: 'c-02', jour: DateTime(2026, 10, 2)),
];

Future<FauxAstreintesRepository> _ouvrir(
  WidgetTester tester, {
  FauxAstreintesRepository? depot,
  CacheAstreintes? cache,
  Connectivite? reseau,
  Size taille = _telephone,
  bool stabiliser = true,
}) async {
  final astreintes =
      depot ?? FauxAstreintesRepository(astreintes: _quatre());

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    astreintes: astreintes,
    cacheAstreintes: cache ?? CacheAstreintesMemoire(),
    horloge: () => _aujourdhui,
    reseau: reseau,
    taille: taille,
    stabiliser: stabiliser,
  );
  await ouvrirRoute(tester, _lienNotification, stabiliser: stabiliser);
  return astreintes;
}

void main() {
  testWidgets(
    'le lien /schedule mène à la destination « Astreintes »',
    (WidgetTester tester) async {
      await _ouvrir(tester);

      expect(emplacementCourant(tester), '/?onglet=2');
      expect(find.text(AppStrings.astreintesTitre), findsOneWidget);
      expect(find.text(AppStrings.navAstreintes), findsWidgets);
    },
  );

  group('la liste', () {
    testWidgets('ouvre sur les à venir, groupées par mois', (
      WidgetTester tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text('Octobre 2026'), findsOneWidget);
      expect(find.text('Novembre 2026'), findsOneWidget);
      expect(find.byType(EnteteSection), findsNWidgets(2));

      // Deux lignes seulement : les passées sont derrière le repli.
      expect(find.byType(LigneDAstreinte), findsNWidgets(2));
      expect(find.text('samedi 17 octobre'), findsOneWidget);
      expect(find.text('mardi 3 novembre'), findsOneWidget);
      expect(find.text('vendredi 2 octobre'), findsNothing);
    });

    testWidgets('affiche les heures de la caserne, pas 7 h – 19 h en dur', (
      WidgetTester tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(
          astreintes: _quatre(),
          heures: const HeuresAffichage(debutJour: '08:00', finJour: '20:00'),
        ),
      );

      // Le 17 est de nuit : l'intervalle complémentaire du jour.
      expect(find.text('20:00 → 08:00'), findsOneWidget);
      // Le 3 novembre est de jour.
      expect(find.text('08:00 → 20:00'), findsOneWidget);
    });

    testWidgets('une ligne se lit en une phrase complète', (
      WidgetTester tester,
    ) async {
      await _ouvrir(tester);

      final semantique = tester.getSemantics(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is LigneDAstreinte && widget.astreinte.id == 'a-17',
        ),
      );
      expect(
        semantique.label,
        'samedi 17 octobre, nuit, de 19:00 à 07:00. Voir le détail.',
      );
    });

    testWidgets('le squelette n\'apparaît que sans rien en cache', (
      WidgetTester tester,
    ) async {
      final depot = _DepotLent();
      await _ouvrir(tester, depot: depot, stabiliser: false);

      expect(find.byType(LoadingSkeleton), findsOneWidget);

      depot.liberer();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingSkeleton), findsNothing);
    });

    testWidgets('une lecture qui échoue sans cache propose de réessayer', (
      WidgetTester tester,
    ) async {
      final depot = await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(erreur: ErreurAstreintes.inconnue),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(AppStrings.astreintesErreurTexte), findsOneWidget);

      final avant = depot.lectures;
      depot
        ..erreur = null
        ..definir(_quatre());
      await tester.tap(find.text(AppStrings.actionReessayer));
      await tester.pumpAndSettle();

      expect(depot.lectures, greaterThan(avant));
      expect(find.byType(LigneDAstreinte), findsNWidgets(2));
    });
  });

  group('le repli des passées', () {
    testWidgets('est fermé, compté, et s\'ouvre d\'une touche', (
      WidgetTester tester,
    ) async {
      await _ouvrir(tester);

      final repli = find.text(AppStrings.astreintesPassees(2));
      expect(repli, findsOneWidget);
      expect(find.text('vendredi 2 octobre'), findsNothing);

      await tester.tap(repli);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('vendredi 2 octobre'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('vendredi 9 octobre'), findsOneWidget);
      expect(find.text('vendredi 2 octobre'), findsOneWidget);
      // La plus récente d'abord.
      expect(
        tester.getTopLeft(find.text('vendredi 9 octobre')).dy,
        lessThan(tester.getTopLeft(find.text('vendredi 2 octobre')).dy),
      );
    });

    testWidgets('n\'existe pas quand il n\'y a rien derrière', (
      WidgetTester tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(
          astreintes: <Astreinte>[
            astreinte(id: 'a-17', jour: DateTime(2026, 10, 17)),
          ],
        ),
      );

      expect(find.textContaining('Astreintes passées'), findsNothing);
    });
  });

  group('la vue calendrier', () {
    testWidgets('marque les jours d\'astreinte et n\'ouvre que ceux-là', (
      WidgetTester tester,
    ) async {
      await _ouvrir(tester);

      await tester.tap(find.text(AppStrings.astreintesVueCalendrier));
      await tester.pumpAndSettle();

      expect(find.byType(CalendrierAstreintes), findsOneWidget);
      expect(find.text('Octobre 2026'), findsOneWidget);

      // Le 17 est marqué, le 16 ne l'est pas.
      expect(
        find.bySemanticsLabel(
          'samedi 17 octobre, nuit. Voir le détail.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('vendredi 16 octobre, pas d\'astreinte'),
        findsOneWidget,
      );
    });

    testWidgets('les flèches sont bornées à l\'étendue connue', (
      WidgetTester tester,
    ) async {
      await _ouvrir(tester);
      await tester.tap(find.text(AppStrings.astreintesVueCalendrier));
      await tester.pumpAndSettle();

      // Octobre est le premier mois connu : la flèche arrière est inerte, et
      // elle dit pourquoi.
      final precedent = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(precedent.onPressed, isNull);
      expect(precedent.tooltip, AppStrings.astreintesMoisAvantDebut);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('Novembre 2026'), findsOneWidget);
    });

    testWidgets('cède la place à la liste à très grande échelle de texte', (
      WidgetTester tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        astreintes: FauxAstreintesRepository(astreintes: _quatre()),
        cacheAstreintes: CacheAstreintesMemoire(),
        horloge: () => _aujourdhui,
      );
      await ouvrirRoute(tester, _lienNotification);

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.astreintesCalendrierTropGrand), findsOneWidget);
      expect(find.byType(CalendrierAstreintes), findsNothing);
      expect(find.byType(LigneDAstreinte), findsWidgets);
    });
  });

  group('le détail', () {
    testWidgets('nomme les équipiers quand le planning est validé', (
      WidgetTester tester,
    ) async {
      await _ouvrir(tester);

      await tester.tap(find.text('samedi 17 octobre'));
      await tester.pumpAndSettle();

      expect(find.byType(DetailAstreinte), findsOneWidget);
      expect(find.text('Samedi 17 octobre 2026'), findsOneWidget);
      expect(find.text(AppStrings.astreintesEquipiersTitre), findsOneWidget);
      expect(find.text('Thomas B.'), findsOneWidget);
      expect(find.text('19:00 → 07:00'), findsWidgets);
    });

    testWidgets('dit pourquoi les noms manquent quand il est publié', (
      WidgetTester tester,
    ) async {
      await _ouvrir(tester);

      await tester.tap(find.text('mardi 3 novembre'));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.astreintesEquipiersAttente),
        findsOneWidget,
      );
      // Ni liste de noms, ni « tu es seul » : on ne sait pas, et on le dit.
      expect(find.text(AppStrings.astreintesEquipiersTitre), findsNothing);
      expect(find.text(AppStrings.astreintesSeul), findsNothing);
    });

    testWidgets(
      'un mois archivé nomme ses équipiers : pas d\'attente sur un mois '
      'terminé',
      (WidgetTester tester) async {
        // L'écran remonte un an d'historique, et tout mois révolu est archivé
        // le 1er du mois suivant (ticket 044). Sans ce cas, une garde tenue en
        // février afficherait « en attente de la validation du planning »
        // jusqu'à la fin des temps.
        await _ouvrir(
          tester,
          depot: FauxAstreintesRepository(
            astreintes: <Astreinte>[
              astreinte(
                id: 'a-fev',
                creneauId: 'c-fev',
                planningId: 'plan-02',
                jour: DateTime(2026, 2, 14),
                planningEtat: PlanningEtat.archive,
                equipiers: const <String>['Camille G.'],
              ),
            ],
          ),
        );

        await tester.tap(find.text(AppStrings.astreintesPassees(1)));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('samedi 14 février'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('samedi 14 février'));
        await tester.pumpAndSettle();

        expect(find.byType(DetailAstreinte), findsOneWidget);
        expect(find.text(AppStrings.astreintesEquipiersTitre), findsOneWidget);
        expect(find.text('Camille G.'), findsOneWidget);
        expect(find.text(AppStrings.astreintesEquipiersAttente), findsNothing);
      },
    );

    testWidgets('« tu es seul » est une information, pas une absence', (
      WidgetTester tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(
          astreintes: <Astreinte>[
            astreinte(id: 'a-17', jour: DateTime(2026, 10, 17)),
          ],
        ),
      );

      await tester.tap(find.text('samedi 17 octobre'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.astreintesSeul), findsOneWidget);
    });

    testWidgets('s\'ouvre aussi depuis le calendrier, et se ferme', (
      WidgetTester tester,
    ) async {
      await _ouvrir(tester);
      await tester.tap(find.text(AppStrings.astreintesVueCalendrier));
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsLabel('samedi 17 octobre, nuit. Voir le détail.'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DetailAstreinte), findsOneWidget);

      await tester.tap(find.text(AppStrings.astreintesFermer));
      await tester.pumpAndSettle();
      expect(find.byType(DetailAstreinte), findsNothing);
    });
  });

  group('sans réseau', () {
    testWidgets('l\'écran reste entier et dit de quand datent les données', (
      WidgetTester tester,
    ) async {
      final cache = CacheAstreintesMemoire(
        MesAstreintes(
          astreintes: _quatre(),
          luLe: _aujourdhui.subtract(const Duration(hours: 2)),
        ),
      );

      await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(erreur: ErreurAstreintes.reseau),
        cache: cache,
        reseau: ConnectiviteMemoire(enLigne: false),
      );

      // La liste est là, entière : aucun état ne remplace la liste par un
      // message.
      expect(find.byType(LigneDAstreinte), findsNWidgets(2));
      expect(find.text('samedi 17 octobre'), findsOneWidget);

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.horsLigne);
      expect(banniere.texte, AppStrings.astreintesHorsLigne);
      expect(banniere.detail, contains('Dernière mise à jour'));
      expect(banniere.detail, contains('il y a 2 h'));
    });

    testWidgets('le détail s\'ouvre sans réseau : rien n\'est rechargé', (
      WidgetTester tester,
    ) async {
      final cache = CacheAstreintesMemoire(
        MesAstreintes(astreintes: _quatre(), luLe: _aujourdhui),
      );
      final depot = await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(erreur: ErreurAstreintes.reseau),
        cache: cache,
        reseau: ConnectiviteMemoire(enLigne: false),
      );

      final avant = depot.lectures;
      await tester.tap(find.text('samedi 17 octobre'));
      await tester.pumpAndSettle();

      expect(find.text('Thomas B.'), findsOneWidget);
      expect(depot.lectures, avant);
    });

    testWidgets('sans cache ni réseau, l\'écran le dit et propose la sortie', (
      WidgetTester tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(erreur: ErreurAstreintes.reseau),
        reseau: ConnectiviteMemoire(enLigne: false),
      );

      expect(find.text(AppStrings.erreurReseauTexte), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
    });

    testWidgets('en ligne, une lecture ratée laisse le cache et le signale', (
      WidgetTester tester,
    ) async {
      final cache = CacheAstreintesMemoire(
        MesAstreintes(
          astreintes: _quatre(),
          luLe: _aujourdhui.subtract(const Duration(days: 1)),
        ),
      );

      final depot = await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(erreur: ErreurAstreintes.inconnue),
        cache: cache,
      );

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.attention);
      expect(banniere.texte, AppStrings.astreintesNonActualisees);
      expect(banniere.detail, contains('hier'));
      expect(find.byType(LigneDAstreinte), findsNWidgets(2));

      // « Réessayer » relit vraiment, et une lecture réussie efface le
      // bandeau.
      depot.erreur = null;
      await tester.tap(find.text(AppStrings.actionReessayer));
      await tester.pumpAndSettle();
      expect(find.byType(AppBanner), findsNothing);
    });

    testWidgets('un démarrage à froid sans réseau atteint quand même l\'écran', (
      WidgetTester tester,
    ) async {
      // **La scène du ticket** : la PWA rouverte dans une remise. La session
      // se restaure depuis le stockage local, mais `memberships` échoue. Sans
      // la caserne gardée sur l'appareil, l'application s'arrêterait sur
      // « Pas de connexion » et le cache d'astreintes ne servirait jamais.
      await monterApp(
        tester,
        session: sessionMembre,
        erreurAppartenances: AuthErreur.reseau,
        appartenancesLocales: AppartenancesLocalesMemoire(
          const <Appartenance>[appartenanceMembre],
        ),
        astreintes: FauxAstreintesRepository(
          erreur: ErreurAstreintes.reseau,
        ),
        cacheAstreintes: CacheAstreintesMemoire(
          MesAstreintes(
            astreintes: _quatre(),
            luLe: _aujourdhui.subtract(const Duration(hours: 5)),
          ),
        ),
        horloge: () => _aujourdhui,
        reseau: ConnectiviteMemoire(enLigne: false),
      );
      await ouvrirRoute(tester, _lienNotification);

      expect(find.text(AppStrings.astreintesTitre), findsOneWidget);
      expect(find.byType(LigneDAstreinte), findsNWidgets(2));

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.horsLigne);
      expect(banniere.detail, contains('il y a 5 h'));
    });

    testWidgets('une lecture réussie réécrit le cache en entier', (
      WidgetTester tester,
    ) async {
      final cache = CacheAstreintesMemoire();
      await _ouvrir(tester, cache: cache);

      expect(cache.ecritures, greaterThanOrEqualTo(1));
      expect(cache.garde, isNotNull);
      expect(cache.garde!.astreintes, hasLength(4));
      expect(cache.garde!.luLe, isNotNull);
    });
  });

  group('l\'écran vide', () {
    testWidgets('explique et mène aux propositions', (
      WidgetTester tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(astreintes: const <Astreinte>[]),
      );

      expect(find.text(AppStrings.videAstreintesTitre), findsOneWidget);
      expect(find.text(AppStrings.videAstreintesTexte), findsOneWidget);

      await tester.tap(find.text(AppStrings.astreintesVideAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.videPropositionsTitre), findsOneWidget);
    });

    testWidgets('rien à venir mais un passé : l\'état vide reste au-dessus', (
      WidgetTester tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAstreintesRepository(
          astreintes: <Astreinte>[
            astreinte(id: 'a-02', jour: DateTime(2026, 10, 2)),
          ],
        ),
      );

      expect(find.text(AppStrings.videAstreintesTitre), findsOneWidget);
      expect(find.text(AppStrings.astreintesPassees(1)), findsOneWidget);
    });
  });
}

/// Un dépôt dont la lecture ne rend la main que sur commande.
///
/// Le squelette reste alors à l'écran le temps qu'on l'y regarde, quel que
/// soit le nombre d'images pompées : depuis que les destinations changent sans
/// transition (ticket 063), la réponse arrive une image plus tôt, et l'attente
/// ne dure plus assez pour qu'on compte dessus.
class _DepotLent extends FauxAstreintesRepository {
  _DepotLent() : super(astreintes: const <Astreinte>[]);

  final Completer<void> _verrou = Completer<void>();

  void liberer() => _verrou.complete();

  @override
  Future<MesAstreintes> lire({
    required String userId,
    required String stationId,
    required DateTime depuis,
  }) async {
    await _verrou.future;
    return super.lire(userId: userId, stationId: stationId, depuis: depuis);
  }
}
