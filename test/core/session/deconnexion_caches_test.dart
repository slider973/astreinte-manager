import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/appartenances_locales.dart';
import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/core/session/caserne_choisie.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_planning_caserne.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/domain/planning_caserne.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/demarrage/presentation/demarrage_screen.dart';
import 'package:astreinte_sp/features/dispos/data/file_locale.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/preferences_mois.dart';
import 'package:astreinte_sp/features/notifications/data/jeton_local.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_planning_caserne.dart';
import '../../support/faux_push.dart';

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

/// **Les seules clés qui ont le droit de survivre à une déconnexion**, chacune
/// avec sa raison.
///
/// Le filet ne connaît pas les caches : il relit **tout** le stockage de
/// l'appareil après la déconnexion, et n'y tolère que ce qui est nommé ici.
/// Le prochain cache qui oublie de se brancher sur `OubliLocal`
/// (`core/session/oubli_local.dart`) fait donc échouer ce test sans que
/// personne ait eu à l'y ajouter — c'est le défaut du ticket 057, où la clé
/// du jeton push échappait au filet parce qu'il ne cherchait que les préfixes
/// qu'on lui avait déclarés.
///
/// Ajouter une clé ici, c'est affirmer qu'elle ne dit rien de la personne
/// connectée : la raison est obligatoire, et elle se relit en revue.
final Map<String, String> _survivantsJustifies = <String, String>{
  for (final repere in RepereAccueil.values)
    repere.cle:
        'Repère d\'accueil (`core/preferences/reperes_locaux.dart`) : une '
        'marque de passage de l\'appareil — guide vu, aide d\'installation '
        'vue, geste découvert —, un booléen sans identifiant ni donnée de '
        'personne. La personne suivante reverrait au pire une aide de moins.',
};

/// Tout ce qui reste sur l'appareil, moins les survivants justifiés.
Future<Set<String>> _clesRestantes() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getKeys().difference(_survivantsJustifies.keys.toSet());
}

const String _chromeAndroid =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

/// Une PWA installée sur Android : les notifications y sont possibles, et le
/// jeton de l'appareil est donc publié au lancement.
final ContextePlateforme _androidInstalle = ContextePlateforme.depuisAgent(
  userAgent: _chromeAndroid,
  affichageAutonome: true,
);

/// Écrit le décor commun : **tout ce que l'application sait écrire sur
/// l'appareil**, avec les vrais dépôts. Le jeton push, lui, est écrit par le
/// lancement de l'application, comme en vrai.
Future<void> _remplirLesCaches({
  required CacheAstreintes astreintes,
  required AppartenancesLocales appartenances,
  required CachePlanningCaserne planning,
  required FileLocale file,
  required CaserneChoisieLocale caserneChoisie,
  required ReperesLocaux reperes,
}) async {
  await appartenances.ecrire(sessionMembre.userId, <Appartenance>[
    appartenanceMembre,
  ]);
  await caserneChoisie.ecrire(
    sessionMembre.userId,
    appartenanceMembre.stationId,
  );
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
  // La saisie hors ligne : une case et une préférence en attente.
  await file.enregistrer(
    stationId: appartenanceMembre.stationId,
    userId: sessionMembre.userId,
    mois: '2026-11',
    entrees: <CreneauCle, DisponibiliteEtat>{
      CreneauCle(DateTime(2026, 11, 4), CreneauType.nuit):
          DisponibiliteEtat.disponible,
    },
  );
  await file.enregistrerPreferences(
    stationId: appartenanceMembre.stationId,
    userId: sessionMembre.userId,
    periodId: 'p-2026-11',
    preferences: const PreferencesMois(maxAstreintes: 4),
  );
  // Un repère : il doit survivre, et le filet doit le savoir.
  await reperes.marquerVu(RepereAccueil.guide);
}

/// Monte l'application sur **les vrais dépôts de stockage**, notifications
/// accordées : tout ce qu'un parcours écrit sur l'appareil est réellement
/// écrit.
Future<AppMontee> _monterSurLeVraiStockage(WidgetTester tester) async {
  const cacheAstreintes = CacheAstreintesPartage();
  const appartenancesLocales = AppartenancesLocalesPartagees();
  const cachePlanning = CachePlanningCasernePartage();
  const file = FileLocalePartagee();
  const caserneChoisie = CaserneChoisieLocalePartagee();
  const reperes = ReperesLocauxPartages();

  await _remplirLesCaches(
    astreintes: cacheAstreintes,
    appartenances: appartenancesLocales,
    planning: cachePlanning,
    file: file,
    caserneChoisie: caserneChoisie,
    reperes: reperes,
  );

  // Le décor doit vraiment avoir tout écrit, sinon le filet serait vide par
  // construction et ne prouverait rien. Vérifié **avant** le lancement : la
  // file hors ligne est rejouée, donc vidée, dès que l'application démarre.
  final decor = await _clesRestantes();
  for (final prefixe in <String>[
    AppartenancesLocalesPartagees.prefixe,
    CaserneChoisieLocalePartagee.prefixe,
    CacheAstreintesPartage.prefixe,
    CachePlanningCasernePartage.prefixe,
    FileLocalePartagee.prefixe,
    FileLocalePartagee.prefixePreferences,
  ]) {
    expect(
      decor.any((String cle) => cle.startsWith(prefixe)),
      isTrue,
      reason: 'le décor doit avoir écrit « $prefixe »',
    );
  }
  final prefs = await SharedPreferences.getInstance();
  expect(
    prefs.getKeys(),
    contains(RepereAccueil.guide.cle),
    reason: 'le décor écrit aussi un survivant justifié',
  );

  final faux = await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    astreintes: FauxAstreintesRepository(),
    cacheAstreintes: cacheAstreintes,
    cachePlanningCaserne: cachePlanning,
    appartenancesLocales: appartenancesLocales,
    fileLocale: file,
    caserneChoisie: caserneChoisie,
    reperes: reperes,
    jetonLocal: const JetonLocalPartage(),
    firebase: FirebaseDemarrage.pret,
    plateforme: _androidInstalle,
    messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
  );

  expect(
    await _clesRestantes(),
    contains(JetonLocalPartage.cle),
    reason: 'le lancement a publié le jeton de l\'appareil',
  );

  return faux;
}

Future<void> _seDeconnecter(WidgetTester tester) async {
  await ouvrirProfil(tester);
  await defilerJusqua(tester, find.text(AppStrings.seDeconnecter));
  await tester.tap(find.text(AppStrings.seDeconnecter));
  await tester.pumpAndSettle();
}

void main() {
  group('la déconnexion n\'oublie rien sur l\'appareil', () {
    testWidgets('tout le stockage est vide après, sauf les survivants '
        'justifiés', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final faux = await _monterSurLeVraiStockage(tester);

      await _seDeconnecter(tester);

      expect(faux.auth.deconnexions, 1);
      expect(find.byType(ConnexionScreen), findsOneWidget);
      expect(
        await _clesRestantes(),
        isEmpty,
        reason:
            'Le nom de la caserne, les noms des équipiers et ceux de toute la '
            'caserne, la saisie en attente et le jeton push de l\'appareil ne '
            'restent pas sur le téléphone de qui vient de partir. Une clé '
            'listée ici a échappé à `OubliLocal` : la brancher, ou la justifier '
            'dans `_survivantsJustifies`.',
      );
      // Et le jeton est parti **côté serveur** avant de partir de l'appareil.
      expect(faux.jetons.oublies, <String>['jeton-de-test']);

      // Les survivants justifiés, eux, sont restés : le filet ne vide pas le
      // stockage à l'aveugle, il vérifie ce que `OubliLocal` a fait.
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getKeys(), contains(RepereAccueil.guide.cle));
    });

    testWidgets('une déconnexion qui échoue laisse quand même l\'appareil '
        'propre', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final faux = await _monterSurLeVraiStockage(tester);
      faux.auth.erreurDeconnexion = AuthErreur.reseau;
      // Hors ligne : la suppression du jeton échoue aussi.
      faux.jetons.echoue = true;

      await _seDeconnecter(tester);

      // La session n'est pas fermée, et l'écran le dit (ticket 005). Les
      // caches, eux, sont déjà partis : ils se refont à la première lecture
      // réussie, et les garder « au cas où » serait garder ce qu'on veut
      // justement ne plus avoir.
      expect(find.text(AuthErreur.reseau.message), findsOneWidget);
      expect(await _clesRestantes(), isEmpty);
    });
  });

  group('le cloisonnement par utilisateur', () {
    test(
      'deux membres ne lisent jamais la caserne l\'un de l\'autre',
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
      },
    );

    test(
      'deux membres ne lisent jamais les astreintes l\'un de l\'autre',
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
      },
    );

    test(
      'les mémoires de test rangent par les mêmes clés que les vraies',
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
      },
    );
  });

  group('le repli sur ce qui est gardé', () {
    testWidgets('rend la main à l\'application, mais pas les droits d\'admin', (
      WidgetTester tester,
    ) async {
      // Un chef de centre, hors réseau, au démarrage à froid.
      await monterApp(
        tester,
        session: sessionMembre,
        erreurAppartenances: AuthErreur.reseau,
        appartenancesLocales: AppartenancesLocalesMemoire(const <Appartenance>[
          _adminDeLaCaserne,
        ]),
        astreintes: FauxAstreintesRepository(),
      );

      // L'application s'ouvre : c'est tout l'intérêt du repli.
      expect(find.text(AppStrings.navAccueil), findsWidgets);
      expect(find.text(AppStrings.navAstreintes), findsWidgets);
      // Mais la cinquième destination n'est pas là : un rôle qu'on n'a pas pu
      // revérifier n'accorde rien.
      expect(find.text(AppStrings.navAdmin), findsNothing);
    });

    testWidgets('une lecture qui **se tait** n\'est pas « aucune caserne »', (
      WidgetTester tester,
    ) async {
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
    });

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
        appartenancesLocales: AppartenancesLocalesMemoire(const <Appartenance>[
          appartenanceMembre,
        ]),
        astreintes: FauxAstreintesRepository(),
      );

      expect(find.text(AppStrings.navAccueil), findsNothing);
      expect(find.text(AppStrings.erreurReseauTexte), findsOneWidget);
    });
  });
}
