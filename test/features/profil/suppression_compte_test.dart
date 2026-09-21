import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/appartenances_locales.dart';
import 'package:astreinte_sp/core/session/caserne_choisie.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_planning_caserne.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/dispos/data/file_locale.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/profil/domain/profil.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_profil.dart';

/// La seconde caserne : elle sert à prouver que l'effacement ne s'arrête pas à
/// celle qui est affichée.
const Appartenance _secondeCaserne = Appartenance(
  id: 'm-9',
  stationId: 'bbbbbbbb-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Val-de-Loue',
  role: RoleMembre.membre,
  statut: StatutMembre.actif,
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

typedef Decor = ({
  FauxProfilRepository profils,
  CacheAstreintesMemoire astreintes,
  CachePlanningCaserneMemoire planning,
  FileLocaleMemoire file,
  AppartenancesLocalesMemoire appartenancesLocales,
  CaserneChoisieLocaleMemoire caserneChoisie,
  AppMontee app,
});

Future<Decor> _ouvrirProfil(
  WidgetTester tester, {
  FauxProfilRepository? profils,
  List<Appartenance> appartenances = const <Appartenance>[appartenanceMembre],
}) async {
  final depot = profils ?? FauxProfilRepository();
  final astreintes = CacheAstreintesMemoire();
  final planning = CachePlanningCaserneMemoire();
  final file = FileLocaleMemoire();
  final locales = AppartenancesLocalesMemoire(appartenances);
  final caserneChoisie = CaserneChoisieLocaleMemoire(<String, String>{
    sessionMembre.userId: appartenances.first.stationId,
  });

  final app = await monterApp(
    tester,
    session: sessionMembre,
    appartenances: appartenances,
    profils: depot,
    astreintes: FauxAstreintesRepository(),
    cacheAstreintes: astreintes,
    cachePlanningCaserne: planning,
    fileLocale: file,
    appartenancesLocales: locales,
    caserneChoisie: caserneChoisie,
  );

  await tester.tap(find.text(AppStrings.navProfil));
  await tester.pumpAndSettle();
  await defilerJusqua(tester, find.text(AppStrings.profilSupprimerCompte));

  return (
    profils: depot,
    astreintes: astreintes,
    planning: planning,
    file: file,
    appartenancesLocales: locales,
    caserneChoisie: caserneChoisie,
    app: app,
  );
}

Future<void> _ouvrirLaFeuille(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.profilSupprimerCompte));
  await tester.pumpAndSettle();
}

void main() {
  group('Suppression de compte', () {
    testWidgets('la feuille dit ce qui part, ce qui reste, et que c\'est '
        'définitif', (tester) async {
      final decor = await _ouvrirProfil(tester);
      await _ouvrirLaFeuille(tester);

      expect(find.text(AppStrings.suppressionTitre), findsOneWidget);
      expect(find.text(AppStrings.suppressionDefinitif), findsOneWidget);
      expect(find.text(AppStrings.suppressionCeQuiPart), findsOneWidget);
      // Le critère du produit, écrit là où quelqu'un le lira avant de décider.
      expect(find.text(AppStrings.suppressionCeQuiReste), findsOneWidget);
      expect(
        find.text(AppStrings.suppressionCeQuiReste),
        findsOneWidget,
        reason: 'La mention « Membre supprimé » doit être annoncée à l\'avance.',
      );

      // Rien n'est parti tant qu'on n'a pas confirmé.
      expect(decor.profils.suppressions, 0);

      await tester.tap(find.text(AppStrings.suppressionAnnuler));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.suppressionTitre), findsNothing);
      expect(decor.profils.suppressions, 0);
    });

    testWidgets('confirmer supprime, ferme la session et nettoie l\'appareil', (
      tester,
    ) async {
      final decor = await _ouvrirProfil(
        tester,
        appartenances: const <Appartenance>[
          appartenanceMembre,
          _secondeCaserne,
        ],
      );

      // Le décor : des données de tiers dans les trois caches, pour **les deux**
      // casernes, plus une saisie en attente.
      for (final stationId in <String>[
        appartenanceMembre.stationId,
        _secondeCaserne.stationId,
      ]) {
        await decor.astreintes.ecrire(
          stationId: stationId,
          userId: sessionMembre.userId,
          donnees: _uneAstreinte(),
        );
      }
      await decor.file.enregistrer(
        stationId: appartenanceMembre.stationId,
        userId: sessionMembre.userId,
        mois: '2026-10',
        entrees: <CreneauCle, DisponibiliteEtat>{
          CreneauCle(DateTime(2026, 10, 3), CreneauType.jour):
              DisponibiliteEtat.disponible,
        },
      );

      await _ouvrirLaFeuille(tester);
      await tester.tap(find.text(AppStrings.suppressionConfirmer));
      await tester.pumpAndSettle();

      expect(decor.profils.suppressions, 1);

      // **La feuille est refermée avant que la session tombe.** Une route
      // impérative laissée au sommet pendant que `go_router` remplace ses
      // pages laisse un écran blanc jusqu'au rechargement — vu dans Chrome,
      // PWA, après une vraie suppression (`design/007-profil.md § 8`).
      expect(find.text(AppStrings.suppressionTitre), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);

      // La session est fermée et le routeur a suivi : l'appareil ne reste pas
      // ouvert sur un compte qui n'existe plus.
      expect(decor.app.auth.deconnexions, 1);
      expect(find.byType(ConnexionScreen), findsOneWidget);

      // **Aussi propre qu'une déconnexion**, et pour les deux casernes.
      expect(decor.appartenancesLocales.utilisateursGardes, isEmpty);
      expect(decor.caserneChoisie.utilisateursGardes, isEmpty);
      expect(decor.astreintes.effacements, greaterThanOrEqualTo(2));
      expect(decor.planning.effacements, greaterThanOrEqualTo(2));
      expect(decor.file.effacements, greaterThanOrEqualTo(1));
      expect(
        await decor.astreintes.lire(
          stationId: _secondeCaserne.stationId,
          userId: sessionMembre.userId,
        ),
        isNull,
        reason:
            'L\'instantané de la seconde caserne porte des noms de tiers : il '
            'ne reste pas sur le téléphone de qui vient de partir.',
      );
    });

    testWidgets('le dernier administrateur est refusé, et la sortie est '
        'écrite dans la feuille', (tester) async {
      final depot = FauxProfilRepository()
        ..echecSuppression = const EchecSuppression(
          ErreurSuppression.dernierAdmin,
          caserne: 'CIS Saint-Martin',
        );
      final decor = await _ouvrirProfil(tester, profils: depot);

      await _ouvrirLaFeuille(tester);
      await tester.tap(find.text(AppStrings.suppressionConfirmer));
      await tester.pumpAndSettle();

      // Le motif reste **dans la feuille**, pas dans un message qui part.
      expect(
        find.text(
          AppStrings.suppressionDernierAdminCaserne('CIS Saint-Martin'),
        ),
        findsOneWidget,
      );
      expect(find.text(AppStrings.suppressionTitre), findsOneWidget);

      // Un refus ne touche ni la session ni les caches : l'application marche
      // encore, et c'est dans celle-là qu'il faut nommer un successeur.
      expect(decor.app.auth.deconnexions, 0);
      expect(decor.appartenancesLocales.utilisateursGardes, isNotEmpty);
      expect(find.byType(ConnexionScreen), findsNothing);
    });

    testWidgets('sans réseau, rien n\'est supprimé et l\'écran le dit', (
      tester,
    ) async {
      final depot = FauxProfilRepository()
        ..echecSuppression = const EchecSuppression(ErreurSuppression.reseau);
      final decor = await _ouvrirProfil(tester, profils: depot);

      await _ouvrirLaFeuille(tester);
      await tester.tap(find.text(AppStrings.suppressionConfirmer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.suppressionReseau), findsOneWidget);
      expect(decor.app.auth.deconnexions, 0);
      expect(decor.appartenancesLocales.utilisateursGardes, isNotEmpty);
    });

    testWidgets('l\'accès resté ouvert est dit tel quel', (tester) async {
      // Le pire des cas : les données sont parties, l'accès non. Le message ne
      // prétend pas que tout va bien.
      final depot = FauxProfilRepository()
        ..echecSuppression = const EchecSuppression(
          ErreurSuppression.accesNonFerme,
        );
      await _ouvrirProfil(tester, profils: depot);

      await _ouvrirLaFeuille(tester);
      await tester.tap(find.text(AppStrings.suppressionConfirmer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.suppressionAccesNonFerme), findsOneWidget);
    });

    testWidgets('le ticket 034 n\'a encore rien posé ici', (tester) async {
      await _ouvrirProfil(tester);
      await _ouvrirLaFeuille(tester);

      // L'export des données personnelles a sa place réservée, pas de bouton
      // mort : un contrôle qui ne fait rien est pire qu'un contrôle absent.
      expect(find.textContaining('Exporter'), findsNothing);
    });

    test('la file de saisie s\'efface vraiment du stockage', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const file = FileLocalePartagee();
      const stationId = 'aaaaaaaa-0000-4000-8000-000000000001';

      await file.enregistrer(
        stationId: stationId,
        userId: sessionMembre.userId,
        mois: '2026-10',
        entrees: <CreneauCle, DisponibiliteEtat>{
          CreneauCle(DateTime(2026, 10, 3), CreneauType.jour):
              DisponibiliteEtat.disponible,
        },
      );
      expect(
        await file.moisEnAttente(
          stationId: stationId,
          userId: sessionMembre.userId,
        ),
        isNotEmpty,
      );

      await file.effacer(stationId: stationId, userId: sessionMembre.userId);

      expect(
        await file.moisEnAttente(
          stationId: stationId,
          userId: sessionMembre.userId,
        ),
        isEmpty,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(
        prefs.getKeys().where(
          (String cle) => cle.startsWith(FileLocalePartagee.prefixe),
        ),
        isEmpty,
      );
    });
  });
}
