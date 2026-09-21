import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/appartenances_locales.dart';
import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_planning_caserne.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/domain/planning_caserne.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/demarrage/presentation/demarrage_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_planning_caserne.dart';

/// Un second compte, sur la même caserne : il sert à prouver que rien ne
/// traverse d'un membre à l'autre.
const String _autreUserId = 'aaaaaaaa-0000-4000-8000-000000000199';

const Appartenance _adminDeLaCaserne = Appartenance(
  id: 'm-0',
  stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
  nomAffiche: 'Jean D.',
);

MesAstreintes _uneAstreinte() => MesAstreintes(
  astreintes: <Astreinte>[
    astreinte(
      id: 'a-17',
      jour: DateTime(2026, 10, 17),
      // **Des données de tiers** : c'est ce qui rend l'effacement obligatoire.
      equipiers: const <String>['Thomas B.'],
    ),
  ],
  luLe: DateTime(2026, 10, 15, 8),
);

/// Deux mois du planning de la caserne, **chargés de noms de tiers** : c'est le
/// cache le plus exposé du produit.
List<PlanningCaserne> _deuxMois() => <PlanningCaserne>[
  for (final mois in <int>[10, 11])
    planningCaserne(
      mois: moisPlanning(annee: 2026, mois: mois),
      journees: <int, List<CreneauCaserne>>{
        3: <CreneauCaserne>[
          creneauCaserne(
            id: 'c-$mois-3',
            noms: const <String>['Thomas M.', 'Camille G.'],
          ),
        ],
      },
    ),
];

/// Les clés que les trois dépôts posent dans le stockage partagé.
Set<String> _clesDesCaches(SharedPreferences prefs) => prefs
    .getKeys()
    .where(
      (String cle) =>
          cle.startsWith(CacheAstreintesPartage.prefixe) ||
          cle.startsWith(CachePlanningCasernePartage.prefixe) ||
          cle.startsWith(AppartenancesLocalesPartagees.prefixe),
    )
    .toSet();

/// Écrit le décor commun : les trois caches, avec les vrais dépôts.
Future<void> _remplirLesCaches({
  required CacheAstreintes astreintes,
  required AppartenancesLocales appartenances,
  required CachePlanningCaserne planning,
}) async {
  await appartenances.ecrire(sessionMembre.userId, <Appartenance>[
    appartenanceMembre,
  ]);
  await astreintes.ecrire(
    stationId: appartenanceMembre.stationId,
    userId: sessionMembre.userId,
    donnees: _uneAstreinte(),
  );
  await planning.ecrireMois(
    stationId: appartenanceMembre.stationId,
    userId: sessionMembre.userId,
    mois: <MoisPlanning>[
      moisPlanning(annee: 2026, mois: 10),
      moisPlanning(annee: 2026, mois: 11),
    ],
  );
  for (final mois in _deuxMois()) {
    await planning.ecrirePlanning(
      stationId: appartenanceMembre.stationId,
      userId: sessionMembre.userId,
      planning: mois,
    );
  }
}

void main() {
  group('la déconnexion n\'oublie rien sur l\'appareil', () {
    testWidgets('les trois caches partent avant la fermeture de session', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      // **Les vrais dépôts**, pas des mémoires : c'est le stockage qu'on
      // vérifie, et c'est lui qui reste sur un téléphone prêté.
      const cacheAstreintes = CacheAstreintesPartage();
      const appartenancesLocales = AppartenancesLocalesPartagees();
      const cachePlanning = CachePlanningCasernePartage();

      await _remplirLesCaches(
        astreintes: cacheAstreintes,
        appartenances: appartenancesLocales,
        planning: cachePlanning,
      );

      final avant = await SharedPreferences.getInstance();
      await avant.reload();
      expect(
        _clesDesCaches(avant),
        // Appartenances, astreintes, liste des mois, et **un document par mois
        // visité** : un pompier qui a consulté deux mois en a laissé deux.
        hasLength(5),
        reason: 'Le décor du test doit vraiment avoir écrit les trois caches.',
      );

      final faux = await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        astreintes: FauxAstreintesRepository(),
        cacheAstreintes: cacheAstreintes,
        cachePlanningCaserne: cachePlanning,
        appartenancesLocales: appartenancesLocales,
      );

      await tester.tap(find.text(AppStrings.navProfil));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(AppStrings.seDeconnecter),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.seDeconnecter));
      await tester.pumpAndSettle();

      expect(faux.auth.deconnexions, 1);
      expect(find.byType(ConnexionScreen), findsOneWidget);

      final apres = await SharedPreferences.getInstance();
      await apres.reload();
      expect(
        _clesDesCaches(apres),
        isEmpty,
        reason:
            'Le nom de la caserne, les noms des équipiers et ceux de toute la '
            'caserne ne restent pas sur le téléphone de qui vient de partir.',
      );
    });

    testWidgets('une déconnexion qui échoue laisse quand même l\'appareil '
        'propre', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const cacheAstreintes = CacheAstreintesPartage();
      const appartenancesLocales = AppartenancesLocalesPartagees();
      const cachePlanning = CachePlanningCasernePartage();

      await _remplirLesCaches(
        astreintes: cacheAstreintes,
        appartenances: appartenancesLocales,
        planning: cachePlanning,
      );

      final faux = await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        astreintes: FauxAstreintesRepository(),
        cacheAstreintes: cacheAstreintes,
        cachePlanningCaserne: cachePlanning,
        appartenancesLocales: appartenancesLocales,
      );
      faux.auth.erreurDeconnexion = AuthErreur.reseau;

      await tester.tap(find.text(AppStrings.navProfil));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(AppStrings.seDeconnecter),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.seDeconnecter));
      await tester.pumpAndSettle();

      // La session n'est pas fermée, et l'écran le dit (ticket 005). Les
      // caches, eux, sont déjà partis : ils se refont à la première lecture
      // réussie, et les garder « au cas où » serait garder ce qu'on veut
      // justement ne plus avoir.
      expect(find.text(AuthErreur.reseau.message), findsOneWidget);

      final apres = await SharedPreferences.getInstance();
      await apres.reload();
      expect(_clesDesCaches(apres), isEmpty);
    });
  });

  group('le cloisonnement par utilisateur', () {
    test('deux membres ne lisent jamais la caserne l\'un de l\'autre',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const local = AppartenancesLocalesPartagees();

      await local.ecrire(sessionMembre.userId, <Appartenance>[
        appartenanceMembre,
      ]);

      expect(await local.lire(sessionMembre.userId), hasLength(1));
      expect(await local.lire(_autreUserId), isEmpty);

      // Et l'effacement de l'un ne touche pas l'autre.
      await local.ecrire(_autreUserId, <Appartenance>[_adminDeLaCaserne]);
      await local.effacer(sessionMembre.userId);
      expect(await local.lire(sessionMembre.userId), isEmpty);
      expect(await local.lire(_autreUserId), hasLength(1));
    });

    test('deux membres ne lisent jamais les astreintes l\'un de l\'autre',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const cache = CacheAstreintesPartage();
      const stationId = 'aaaaaaaa-0000-4000-8000-000000000001';

      await cache.ecrire(
        stationId: stationId,
        userId: sessionMembre.userId,
        donnees: _uneAstreinte(),
      );

      expect(
        await cache.lire(stationId: stationId, userId: sessionMembre.userId),
        isNotNull,
      );
      // Même caserne, autre membre : rien. Le document porte les noms des
      // équipiers, il ne se partage pas.
      expect(
        await cache.lire(stationId: stationId, userId: _autreUserId),
        isNull,
      );
      // Même membre, autre caserne : rien non plus.
      expect(
        await cache.lire(
          stationId: 'bbbbbbbb-0000-4000-8000-000000000001',
          userId: sessionMembre.userId,
        ),
        isNull,
      );
    });

    test('les mémoires de test rangent par les mêmes clés que les vraies',
        () async {
      final local = AppartenancesLocalesMemoire(<Appartenance>[
        appartenanceMembre,
      ]);
      expect(await local.lire(sessionMembre.userId), hasLength(1));
      expect(await local.lire(_autreUserId), isEmpty);

      final cache = CacheAstreintesMemoire(_uneAstreinte());
      expect(
        await cache.lire(
          stationId: appartenanceMembre.stationId,
          userId: sessionMembre.userId,
        ),
        isNotNull,
      );
      expect(
        await cache.lire(
          stationId: appartenanceMembre.stationId,
          userId: _autreUserId,
        ),
        isNull,
      );
    });
  });

  group('le repli sur ce qui est gardé', () {
    testWidgets('rend la main à l\'application, mais pas les droits d\'admin',
        (WidgetTester tester) async {
      // Un chef de centre, hors réseau, au démarrage à froid.
      await monterApp(
        tester,
        session: sessionMembre,
        erreurAppartenances: AuthErreur.reseau,
        appartenancesLocales: AppartenancesLocalesMemoire(
          const <Appartenance>[_adminDeLaCaserne],
        ),
        astreintes: FauxAstreintesRepository(),
      );

      // L'application s'ouvre : c'est tout l'intérêt du repli.
      expect(find.text(AppStrings.navMonMois), findsWidgets);
      expect(find.text(AppStrings.navAstreintes), findsWidgets);
      // Mais la cinquième destination n'est pas là : un rôle qu'on n'a pas pu
      // revérifier n'accorde rien.
      expect(find.text(AppStrings.navAdmin), findsNothing);
    });

    testWidgets(
      'une lecture qui **se tait** n\'est pas « aucune caserne »',
      (WidgetTester tester) async {
        // Le réseau des zones rurales n'est pas un refus, c'est un trou noir :
        // la requête part et ne revient jamais.
        //
        // `appartenancesProvider` observe `sessionProvider` : il est d'abord
        // calculé sans session — liste vide — puis recalculé quand la session
        // est restaurée. Riverpod **garde la valeur précédente** pendant ce
        // recalcul, et décider dessus envoyait un membre parfaitement rattaché
        // sur « Aucune caserne », écran qui ne propose que la déconnexion.
        // Vu dans Chrome, API coupée (`design/023 § 10`).
        final faux = await monterApp(
          tester,
          sessionEnAttente: true,
          appartenancesSuspendues: true,
          astreintes: FauxAstreintesRepository(),
          stabiliser: false,
        );
        expect(find.byType(DemarrageScreen), findsOneWidget);

        // La session se restaure. La caserne, elle, ne répond pas.
        faux.auth.ouvrirSession(sessionMembre);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.text(AppStrings.aucuneCaserneTitre), findsNothing);
        expect(find.byType(DemarrageScreen), findsOneWidget);
      },
    );

    testWidgets('un refus n\'est jamais masqué par le cache', (
      WidgetTester tester,
    ) async {
      // Retiré de sa caserne, jeton périmé, réponse illisible : tout ce qui
      // n'est pas une panne de transport remonte tel quel. Sinon un membre
      // révoqué continuerait de voir sa caserne.
      await monterApp(
        tester,
        session: sessionMembre,
        erreurAppartenances: AuthErreur.inconnue,
        appartenancesLocales: AppartenancesLocalesMemoire(
          const <Appartenance>[appartenanceMembre],
        ),
        astreintes: FauxAstreintesRepository(),
      );

      expect(find.text(AppStrings.navMonMois), findsNothing);
      expect(find.text(AppStrings.erreurReseauTexte), findsOneWidget);
    });
  });
}
