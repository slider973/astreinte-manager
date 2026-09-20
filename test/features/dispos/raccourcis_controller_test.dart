import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/session/session_utilisateur.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/data/dispos_repository.dart';
import 'package:astreinte_sp/features/dispos/data/file_locale.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/dispos_providers.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/domain/raccourci.dart';
import 'package:astreinte_sp/features/dispos/presentation/controllers/saisie_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';

CreneauCle jour(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.jour);
CreneauCle nuit(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.nuit);

const Duration apresLeDelai = Duration(milliseconds: 600);

Future<ProviderContainer> ouvrir(
  WidgetTester tester, {
  required FauxDisposRepository depot,
  ConnectiviteMemoire? reseau,
}) async {
  final conteneur = ProviderContainer(
    overrides: [
      appartenancesProvider.overrideWith(
        (ref) async => <Appartenance>[appartenanceMembre],
      ),
      sessionProvider.overrideWith(
        (ref) => Stream<SessionUtilisateur?>.value(sessionMembre),
      ),
      disposRepositoryProvider.overrideWithValue(depot),
      fileLocaleProvider.overrideWithValue(FileLocaleMemoire()),
      if (reseau != null) connectiviteProvider.overrideWithValue(reseau),
    ],
  );
  addTearDown(conteneur.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: conteneur,
      child: const SizedBox.shrink(),
    ),
  );

  conteneur
    ..listen(appartenancesProvider, (_, _) {})
    ..listen(periodesProvider, (_, _) {})
    ..listen(saisieControllerProvider, (_, _) {});

  for (var essai = 0; essai < 20; essai++) {
    await tester.pump();
    if (conteneur.read(saisieControllerProvider).hasValue) break;
  }
  return conteneur;
}

EtatSaisie etatDe(ProviderContainer conteneur) =>
    conteneur.read(saisieControllerProvider).value!;

SaisieController pilote(ProviderContainer conteneur) =>
    conteneur.read(saisieControllerProvider.notifier);

/// Toutes les cases d'octobre 2026, dans l'ordre du registre.
Map<CreneauCle, DisponibiliteEtat> moisComplet(DisponibiliteEtat etat) {
  final valeurs = <CreneauCle, DisponibiliteEtat>{};
  for (var numero = 1; numero <= 31; numero++) {
    valeurs[jour(numero)] = etat;
    valeurs[nuit(numero)] = etat;
  }
  return valeurs;
}

void main() {
  group('Les six raccourcis', () {
    testWidgets('« les weekends, nuit » ne coche que les samedis et dimanches', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.weekends, CibleCreneau.nuit);
      await tester.pump(apresLeDelai);

      final ecrites = depot.base.keys.toList();
      expect(ecrites, isNotEmpty);
      for (final cle in ecrites) {
        expect(cle.creneau, CreneauType.nuit);
        expect(
          cle.date.weekday,
          anyOf(DateTime.saturday, DateTime.sunday),
        );
      }
      // Octobre 2026 : samedis 3, 10, 17, 24, 31 ; dimanches 4, 11, 18, 25.
      expect(ecrites.length, 9);
    });

    testWidgets('« la semaine, nuit » est « toutes les nuits en semaine »', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.semaine, CibleCreneau.nuit);
      await tester.pump(apresLeDelai);

      expect(depot.base.length, 22);
      for (final cle in depot.base.keys) {
        expect(cle.creneau, CreneauType.nuit);
        expect(cle.date.weekday, lessThanOrEqualTo(DateTime.friday));
      }
    });

    testWidgets('« la semaine, jour » est « tous les jours en semaine »', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.semaine, CibleCreneau.jour);
      await tester.pump(apresLeDelai);

      expect(depot.base.length, 22);
      expect(
        depot.base.keys.every((cle) => cle.creneau == CreneauType.jour),
        isTrue,
      );
    });

    testWidgets('« tout le mois, jour et nuit » pose les 62 cases', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.moisEntier, CibleCreneau.lesDeux);
      await tester.pump(apresLeDelai);

      expect(depot.base.length, 62);
    });

    testWidgets('« tout effacer » vide le mois', (tester) async {
      final depot = FauxDisposRepository(
        disponibilites: moisComplet(DisponibiliteEtat.disponible),
      );
      final conteneur = await ouvrir(tester, depot: depot);
      expect(etatDe(conteneur).mois.valeurs.length, 62);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.effacer, CibleCreneau.lesDeux);
      await tester.pump(apresLeDelai);

      expect(etatDe(conteneur).mois.estVierge, isTrue);
      expect(depot.base, isEmpty);
    });

    testWidgets(
      '« copier le mois précédent » lit le mois précédent et l\'aligne',
      (tester) async {
        // Septembre 2026 : les nuits de weekend. Novembre n'existe pas dans ce
        // test ; on copie septembre dans octobre.
        final septembre = <CreneauCle, DisponibiliteEtat>{
          for (var numero = 1; numero <= 30; numero++)
            if (DateTime(2026, 9, numero).weekday == DateTime.saturday ||
                DateTime(2026, 9, numero).weekday == DateTime.sunday)
              CreneauCle(DateTime(2026, 9, numero), CreneauType.nuit):
                  DisponibiliteEtat.disponible,
        };
        final depot = FauxDisposRepository(disponibilites: septembre);
        final conteneur = await ouvrir(tester, depot: depot);

        final lecturesAvant = depot.lectures;
        await pilote(conteneur).appliquerRaccourci(
          PorteeRaccourci.copieMoisPrecedent,
          CibleCreneau.nuit,
        );
        await tester.pump(apresLeDelai);

        expect(
          depot.lectures - lecturesAvant,
          1,
          reason: 'une lecture du mois source, pas une par jour',
        );

        final octobre = <CreneauCle>[
          for (final cle in depot.base.keys)
            if (cle.date.month == 10) cle,
        ];
        expect(octobre, isNotEmpty);
        for (final cle in octobre) {
          expect(
            cle.date.weekday,
            anyOf(DateTime.saturday, DateTime.sunday),
            reason: 'un samedi de septembre reste un samedi en octobre',
          );
        }
      },
    );
  });

  group('L\'opération groupée', () {
    testWidgets('62 modifications d\'un coup font une seule requête', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.moisEntier, CibleCreneau.lesDeux);
      // L'écran a déjà les 62 cases avant que quoi que ce soit ne parte.
      expect(etatDe(conteneur).mois.valeurs.length, 62);
      expect(depot.requetes, 0, reason: 'rien ne part avant le délai');

      await tester.pump(apresLeDelai);

      expect(
        depot.requetes,
        1,
        reason: '62 upserts en une requête, pas 62 requêtes',
      );
      expect(depot.ecritures.single.length, 62);
      expect(depot.suppressions, isEmpty);
      expect(etatDe(conteneur).sync, SyncEtat.enregistre);
    });

    testWidgets(
      'un raccourci qui écrit et supprime coûte une requête par type',
      (tester) async {
        // La moitié du mois est en base : effacer supprime, et le même lot ne
        // contient rien à écrire.
        final depot = FauxDisposRepository(
          disponibilites: moisComplet(DisponibiliteEtat.disponible),
        );
        final conteneur = await ouvrir(tester, depot: depot);

        // Un raccourci qui pose 31 cases « jour » déjà posées ne change rien ;
        // on efface les nuits, ce qui ne produit que des suppressions.
        await pilote(
          conteneur,
        ).appliquerRaccourci(PorteeRaccourci.effacer, CibleCreneau.nuit);
        await tester.pump(apresLeDelai);

        expect(depot.requetes, 1);
        expect(depot.suppressions.single.length, 31);
        expect(depot.ecritures, isEmpty);
        expect(depot.base.length, 31, reason: 'les jours sont intacts');
      },
    );

    testWidgets('la file coalesce deux raccourcis enchaînés', (tester) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.moisEntier, CibleCreneau.lesDeux);
      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.effacer, CibleCreneau.jour);
      await tester.pump(apresLeDelai);

      expect(
        depot.requetes,
        1,
        reason: 'les 31 cases « jour » n\'ont jamais atteint la base : '
            'la file les a coalescées avant l\'envoi',
      );
      expect(depot.ecritures.single.length, 31);
      expect(depot.base.length, 31);
    });

    testWidgets('un raccourci sans effet ne produit aucune requête', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.effacer, CibleCreneau.lesDeux);
      await tester.pump(apresLeDelai);

      expect(depot.requetes, 0);
      expect(etatDe(conteneur).dernierRaccourci, isNull);
      expect(
        etatDe(conteneur).messageRaccourci,
        AppStrings.raccourciAucunChangement,
      );
    });

    testWidgets('hors ligne, le raccourci s\'empile sans partir', (
      tester,
    ) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.reseau;
      final reseau = ConnectiviteMemoire();
      addTearDown(reseau.dispose);

      final conteneur = await ouvrir(tester, depot: depot, reseau: reseau);
      reseau.definir(enLigne: false);
      await tester.pump();

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.moisEntier, CibleCreneau.nuit);
      await tester.pump(apresLeDelai);

      expect(etatDe(conteneur).mois.valeurs.length, 31);
      expect(etatDe(conteneur).sync, SyncEtat.horsLigne);
      expect(depot.base, isEmpty);

      depot
        ..erreurEcriture = null
        ..requetes = 0;
      reseau.definir(enLigne: true);
      await tester.pump();
      await tester.pump(apresLeDelai);

      expect(depot.requetes, 1, reason: 'une seule requête au retour du réseau');
      expect(depot.base.length, 31);
    });
  });

  group('L\'annulation', () {
    testWidgets('remet les 62 cases dans leur état d\'avant', (tester) async {
      final depot = FauxDisposRepository(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          jour(4): DisponibiliteEtat.absent,
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.moisEntier, CibleCreneau.lesDeux);
      await tester.pump(apresLeDelai);
      expect(depot.base.length, 62);
      expect(
        etatDe(conteneur).dernierRaccourci?.cases,
        62,
        reason: 'la case « absent » change elle aussi : elle passe disponible',
      );

      pilote(conteneur).annulerRaccourci();
      await tester.pump(apresLeDelai);

      expect(
        etatDe(conteneur).mois.valeurs,
        <CreneauCle, DisponibiliteEtat>{jour(4): DisponibiliteEtat.absent},
        reason: 'la case déjà saisie retrouve sa valeur, pas « non saisi »',
      );
      expect(depot.base, <CreneauCle, DisponibiliteEtat>{
        jour(4): DisponibiliteEtat.absent,
      });
      expect(etatDe(conteneur).dernierRaccourci, isNull);
      expect(etatDe(conteneur).annonce, AppStrings.raccourciAnnule);
    });

    testWidgets('annuler « tout effacer » restitue le mois', (tester) async {
      final depot = FauxDisposRepository(
        disponibilites: moisComplet(DisponibiliteEtat.disponible),
      );
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.effacer, CibleCreneau.lesDeux);
      await tester.pump(apresLeDelai);
      expect(depot.base, isEmpty);

      pilote(conteneur).annulerRaccourci();
      await tester.pump(apresLeDelai);

      expect(depot.base.length, 62);
      expect(
        depot.base.values.every((e) => e == DisponibiliteEtat.disponible),
        isTrue,
      );
    });

    testWidgets('l\'annulation coûte une requête, pas soixante-deux', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.moisEntier, CibleCreneau.lesDeux);
      await tester.pump(apresLeDelai);
      final apresRaccourci = depot.requetes;

      pilote(conteneur).annulerRaccourci();
      await tester.pump(apresLeDelai);

      expect(depot.requetes - apresRaccourci, 1);
      expect(depot.suppressions.single.length, 62);
    });

    testWidgets('une touche à la main retire l\'offre d\'annulation', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.weekends, CibleCreneau.nuit);
      expect(etatDe(conteneur).dernierRaccourci, isNotNull);

      pilote(conteneur).basculer(jour(4));
      expect(
        etatDe(conteneur).dernierRaccourci,
        isNull,
        reason: 'annuler emporterait la retouche : l\'offre tombe',
      );

      // Et l'annulation devenue invisible ne fait plus rien.
      pilote(conteneur).annulerRaccourci();
      expect(etatDe(conteneur).etat(jour(4)), DisponibiliteEtat.disponible);
      await tester.pump(apresLeDelai);
    });

    testWidgets('l\'annulation ne survit pas à un changement de mois', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      );
      final conteneur = await ouvrir(tester, depot: depot);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.weekends, CibleCreneau.nuit);
      await tester.pump(apresLeDelai);

      await pilote(conteneur).choisirMois('2026-11');
      await tester.pump(apresLeDelai);

      expect(etatDe(conteneur).periode.cle, '2026-11');
      expect(etatDe(conteneur).dernierRaccourci, isNull);

      pilote(conteneur).annulerRaccourci();
      await tester.pump(apresLeDelai);
      expect(
        depot.base.length,
        9,
        reason: 'les weekends d\'octobre restent en base',
      );
    });
  });

  group('Période verrouillée', () {
    testWidgets('aucun raccourci ne s\'applique', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          jour(4): DisponibiliteEtat.disponible,
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);
      expect(etatDe(conteneur).modifiable, isFalse);

      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.moisEntier, CibleCreneau.lesDeux);
      await pilote(
        conteneur,
      ).appliquerRaccourci(PorteeRaccourci.effacer, CibleCreneau.lesDeux);
      await tester.pump(apresLeDelai);

      expect(depot.requetes, 0);
      expect(etatDe(conteneur).mois.valeurs.length, 1);
      expect(etatDe(conteneur).dernierRaccourci, isNull);
    });

    testWidgets('« copier » ne lit même pas le mois précédent', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
      );
      final conteneur = await ouvrir(tester, depot: depot);
      final lecturesAvant = depot.lectures;

      await pilote(conteneur).appliquerRaccourci(
        PorteeRaccourci.copieMoisPrecedent,
        CibleCreneau.lesDeux,
      );
      await tester.pump(apresLeDelai);

      expect(depot.lectures, lecturesAvant);
    });
  });
}
