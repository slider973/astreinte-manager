import 'dart:async';

import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/session/session_utilisateur.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/data/dispos_repository.dart';
import 'package:astreinte_sp/features/dispos/data/file_locale.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/dispos_providers.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/presentation/controllers/rafraichissement_periodes.dart';
import 'package:astreinte_sp/features/dispos/presentation/controllers/saisie_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';

/// Une horloge qu'on avance à la main.
class Horloge {
  DateTime maintenant = DateTime(2026, 9, 28, 10, 12);

  void avancer(Duration duree) => maintenant = maintenant.add(duree);
}

/// Au-delà du délai minimal entre deux relectures automatiques.
const Duration apresLIntervalle = Duration(seconds: 11);

/// Le scénario du propriétaire : septembre et octobre verrouillés, novembre
/// pas encore ouvert.
FauxDisposRepository depotDeProduction() => FauxDisposRepository(
  periodes: <PeriodeSaisie>[
    periodeVerrouillee(annee: 2026, mois: 9),
    periodeVerrouillee(annee: 2026, mois: 10),
  ],
);

PeriodeSaisie novembre() => periodeOuverte(
  annee: 2026,
  mois: 11,
  dateLimite: DateTime(2026, 10, 15, 23, 59, 59),
);

Future<ProviderContainer> ouvrir(
  WidgetTester tester, {
  required FauxDisposRepository depot,
  required Horloge horloge,
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
      horlogeRafraichissementProvider.overrideWithValue(
        () => horloge.maintenant,
      ),
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
    ..listen(saisieControllerProvider, (_, _) {})
    ..listen(rafraichissementPeriodesProvider, (_, _) {});

  for (var essai = 0; essai < 20; essai++) {
    await tester.pump();
    if (conteneur.read(saisieControllerProvider).hasValue) break;
  }
  return conteneur;
}

List<String> clesDe(ProviderContainer conteneur) => <String>[
  for (final periode in conteneur.read(periodesProvider).value!) periode.cle,
];

RafraichissementPeriodes coordinateur(ProviderContainer conteneur) =>
    conteneur.read(rafraichissementPeriodesProvider);

void main() {
  group('Un mois ouvert pendant que l\'app tourne', () {
    testWidgets('apparaît au retour, et devient le mois affiché', (
      tester,
    ) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      expect(clesDe(conteneur), <String>['2026-09', '2026-10']);
      expect(
        conteneur.read(saisieControllerProvider).value!.periode.cle,
        '2026-10',
      );

      depot.ajouterPeriode(novembre());
      horloge.avancer(apresLIntervalle);
      await coordinateur(conteneur).auRetour();
      await tester.pump();
      await tester.pump();

      expect(clesDe(conteneur), <String>['2026-09', '2026-10', '2026-11']);
      expect(
        conteneur.read(saisieControllerProvider).value!.periode.cle,
        '2026-11',
      );
      expect(conteneur.read(saisieControllerProvider).value!.modifiable, true);
    });

    testWidgets('apparaît sur un tirer pour actualiser, sans délai minimal', (
      tester,
    ) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);

      depot.ajouterPeriode(novembre());
      // Aucune avance d'horloge : le geste est délibéré.
      await coordinateur(conteneur).tirer();
      await tester.pump();

      expect(clesDe(conteneur), contains('2026-11'));
    });
  });

  group('Un mois choisi explicitement', () {
    testWidgets('ne bouge pas quand un nouveau mois s\'ouvre', (tester) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      // Ce que fait l'écran quand l'URL porte `?mois=2026-09`.
      conteneur.read(moisSelectionneProvider.notifier).definir('2026-09');
      await tester.pump();
      await tester.pump();
      expect(
        conteneur.read(saisieControllerProvider).value!.periode.cle,
        '2026-09',
      );

      depot.ajouterPeriode(novembre());
      horloge.avancer(apresLIntervalle);
      await coordinateur(conteneur).auRetour();
      await tester.pump();
      await tester.pump();

      expect(clesDe(conteneur), contains('2026-11'));
      expect(conteneur.read(periodeCouranteProvider)!.cle, '2026-09');
      expect(
        conteneur.read(saisieControllerProvider).value!.periode.cle,
        '2026-09',
      );
    });
  });

  group('Pas de relecture en rafale', () {
    testWidgets('dix retours d\'affilée ne font qu\'une lecture', (
      tester,
    ) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      final avant = depot.lecturesPeriodes;

      horloge.avancer(apresLIntervalle);
      for (var i = 0; i < 10; i++) {
        await coordinateur(conteneur).auRetour();
        horloge.avancer(const Duration(milliseconds: 300));
      }

      expect(depot.lecturesPeriodes, avant + 1);
    });

    testWidgets('aucune relecture moins de dix secondes après la dernière', (
      tester,
    ) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      final avant = depot.lecturesPeriodes;

      horloge.avancer(const Duration(seconds: 9));
      await coordinateur(conteneur).auRetour();

      expect(depot.lecturesPeriodes, avant);
    });

    testWidgets('des retours simultanés partagent la même lecture', (
      tester,
    ) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      final avant = depot.lecturesPeriodes;

      horloge.avancer(apresLIntervalle);
      await Future.wait(<Future<void>>[
        coordinateur(conteneur).auRetour(),
        coordinateur(conteneur).auRetour(),
        coordinateur(conteneur).tirer(),
      ]);

      expect(depot.lecturesPeriodes, avant + 1);
    });

    testWidgets('une liste inchangée ne relit pas le mois affiché', (
      tester,
    ) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      final lecturesPeriodes = depot.lecturesPeriodes;
      final lecturesMois = depot.lectures;

      horloge.avancer(apresLIntervalle);
      await coordinateur(conteneur).auRetour();
      await tester.pump();

      expect(depot.lecturesPeriodes, lecturesPeriodes + 1);
      expect(depot.lectures, lecturesMois);
    });
  });

  group('Aucune saisie perdue', () {
    FauxDisposRepository depotNovembreOuvert() => FauxDisposRepository(
      periodes: <PeriodeSaisie>[
        periodeVerrouillee(annee: 2026, mois: 10),
        novembre(),
      ],
    );
    final case2 = CreneauCle(DateTime(2026, 11, 2), CreneauType.jour);

    testWidgets('un retour pendant une écriture en file est différé, puis '
        'part quand la file est vide', (tester) async {
      final horloge = Horloge();
      final depot = depotNovembreOuvert();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      final avant = depot.lecturesPeriodes;

      conteneur.read(saisieControllerProvider.notifier).basculer(case2);
      horloge.avancer(apresLIntervalle);
      await coordinateur(conteneur).auRetour();

      expect(depot.lecturesPeriodes, avant, reason: 'rien sous une écriture');
      expect(coordinateur(conteneur).differee, isTrue);

      await tester.pump(SaisieController.delaiEnvoi * 2);
      await tester.pump();

      expect(depot.base[case2], DisponibiliteEtat.disponible);
      expect(depot.lecturesPeriodes, avant + 1);
      expect(coordinateur(conteneur).differee, isFalse);
    });

    testWidgets('le tirer envoie la file avant de relire', (tester) async {
      final horloge = Horloge();
      final depot = depotNovembreOuvert();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);

      depot.journal.clear();
      conteneur.read(saisieControllerProvider.notifier).basculer(case2);
      await coordinateur(conteneur).tirer();
      await tester.pump();

      expect(depot.journal, <String>['enregistrerLot', 'periodes', 'lireMois']);
      expect(depot.base[case2], DisponibiliteEtat.disponible);
      expect(
        conteneur.read(saisieControllerProvider).value!.mois.valeurs[case2],
        DisponibiliteEtat.disponible,
      );
    });

    testWidgets('hors ligne, le tirer ne relit rien et garde la file', (
      tester,
    ) async {
      final horloge = Horloge();
      final depot = depotNovembreOuvert();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      final avant = depot.lecturesPeriodes;

      depot.erreurEcriture = ErreurDispos.reseau;
      conteneur.read(saisieControllerProvider.notifier).basculer(case2);
      await coordinateur(conteneur).tirer();
      await tester.pump();

      expect(depot.lecturesPeriodes, avant);
      expect(
        conteneur.read(saisieControllerProvider).value!.mois.valeurs[case2],
        DisponibiliteEtat.disponible,
      );
      expect(
        conteneur.read(saisieControllerProvider.notifier).ecritureEnAttente,
        isTrue,
      );

      // Le minuteur de relance du contrôleur, vidé avant la fin du test.
      depot.erreurEcriture = null;
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('Un geste commencé pendant la lecture', () {
    // Octobre verrouillé, novembre ouvert : c'est novembre qu'on peint.
    FauxDisposRepository depotNovembreOuvert() => FauxDisposRepository(
      periodes: <PeriodeSaisie>[
        periodeVerrouillee(annee: 2026, mois: 10),
        novembre(),
      ],
    );
    final case2 = CreneauCle(DateTime(2026, 11, 2), CreneauType.jour);
    final case3 = CreneauCle(DateTime(2026, 11, 3), CreneauType.jour);

    EtatSaisie saisieDe(ProviderContainer conteneur) =>
        conteneur.read(saisieControllerProvider).value!;

    testWidgets('le tirer ne recharge pas la saisie sous le doigt, et relit '
        'le mois après le geste', (tester) async {
      final horloge = Horloge();
      final depot = depotNovembreOuvert();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      final saisie = conteneur.read(saisieControllerProvider.notifier);
      final lecturesPeriodes = depot.lecturesPeriodes;
      final lecturesMois = depot.lectures;

      final retenue = depot.retenueLecturePeriodes = Completer<void>();
      final tire = coordinateur(conteneur).tirer();
      await tester.pump();
      expect(depot.lecturesPeriodes, lecturesPeriodes + 1);

      // Le doigt se pose pendant que la lecture est en vol.
      saisie
        ..debutGeste()
        ..toucherPendantGeste(case2);
      final pinceau = saisieDe(conteneur).pinceau;
      expect(pinceau, isNotNull);

      retenue.complete();
      await tire;
      await tester.pump();
      await tester.pump();

      // Rien n'a été reconstruit : le trait continue avec le même pinceau.
      expect(saisieDe(conteneur).pinceau, pinceau);
      expect(saisieDe(conteneur).origine, case2);
      expect(saisieDe(conteneur).casesPeintes, 1);
      expect(saisieDe(conteneur).periode.cle, '2026-11');
      expect(depot.lectures, lecturesMois, reason: 'mois non relu');
      expect(coordinateur(conteneur).differee, isTrue);

      saisie.toucherPendantGeste(case3);
      expect(saisieDe(conteneur).casesPeintes, 2);
      expect(saisieDe(conteneur).mois.valeurs[case3], pinceau);

      depot.retenueLecturePeriodes = null;
      saisie.finGeste();
      await tester.pump(SaisieController.delaiEnvoi * 2);
      await tester.pump();
      await tester.pump();

      // Le trait est parti entier, d'une seule valeur ; puis la relecture
      // différée a relu la liste **et** le mois.
      expect(depot.base[case2], pinceau);
      expect(depot.base[case3], pinceau);
      expect(depot.lecturesPeriodes, lecturesPeriodes + 2);
      expect(depot.lectures, greaterThan(lecturesMois));
      expect(coordinateur(conteneur).differee, isFalse);
    });

    testWidgets('un retour qui découvre un mois ne bascule pas le mois sous '
        'le doigt, et le publie après le geste', (tester) async {
      final horloge = Horloge();
      final depot = depotNovembreOuvert();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      final saisie = conteneur.read(saisieControllerProvider.notifier);
      final lecturesPeriodes = depot.lecturesPeriodes;

      // Septembre rouvert : premier mois ouvert, il deviendrait le mois par
      // défaut, et la grille changerait de mois sous le doigt.
      depot.ajouterPeriode(periodeOuverte(annee: 2026, mois: 9));
      final retenue = depot.retenueLecturePeriodes = Completer<void>();
      horloge.avancer(apresLIntervalle);
      final retour = coordinateur(conteneur).auRetour();
      await tester.pump();

      saisie
        ..debutGeste()
        ..toucherPendantGeste(case2);
      final pinceau = saisieDe(conteneur).pinceau;

      retenue.complete();
      await retour;
      await tester.pump();
      await tester.pump();

      expect(clesDe(conteneur), <String>['2026-10', '2026-11']);
      expect(saisieDe(conteneur).periode.cle, '2026-11');
      expect(saisieDe(conteneur).pinceau, pinceau);
      expect(saisieDe(conteneur).origine, case2);
      expect(coordinateur(conteneur).differee, isTrue);

      depot.retenueLecturePeriodes = null;
      saisie
        ..toucherPendantGeste(case3)
        ..finGeste();
      await tester.pump(SaisieController.delaiEnvoi * 2);
      await tester.pump();
      await tester.pump();

      expect(depot.base[case2], pinceau);
      expect(depot.base[case3], pinceau);
      expect(depot.lecturesPeriodes, lecturesPeriodes + 2);
      // Publiée une fois le trait enregistré : la bascule arrive maintenant.
      expect(clesDe(conteneur), contains('2026-09'));
      await tester.pump();
      expect(saisieDe(conteneur).periode.cle, '2026-09');
      expect(coordinateur(conteneur).differee, isFalse);
    });

    testWidgets('un geste levé sans case peinte relance la relecture '
        'différée', (tester) async {
      final horloge = Horloge();
      final depot = depotNovembreOuvert();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);
      final saisie = conteneur.read(saisieControllerProvider.notifier);
      final lecturesPeriodes = depot.lecturesPeriodes;

      depot.ajouterPeriode(periodeOuverte(annee: 2026, mois: 12));
      final retenue = depot.retenueLecturePeriodes = Completer<void>();
      horloge.avancer(apresLIntervalle);
      final retour = coordinateur(conteneur).auRetour();
      await tester.pump();

      saisie.debutGeste();
      expect(saisie.ecritureEnAttente, isTrue, reason: 'doigt posé');

      retenue.complete();
      await retour;
      await tester.pump();
      expect(clesDe(conteneur), isNot(contains('2026-12')));
      expect(coordinateur(conteneur).differee, isTrue);

      depot.retenueLecturePeriodes = null;
      saisie.finGeste();
      await tester.pump();
      await tester.pump();

      expect(depot.lecturesPeriodes, lecturesPeriodes + 2);
      expect(clesDe(conteneur), contains('2026-12'));
      expect(coordinateur(conteneur).differee, isFalse);
    });
  });

  group('Une lecture en panne', () {
    testWidgets('garde la liste affichée', (tester) async {
      final horloge = Horloge();
      final depot = depotDeProduction();
      final conteneur = await ouvrir(tester, depot: depot, horloge: horloge);

      depot.erreurLecture = ErreurDispos.reseau;
      horloge.avancer(apresLIntervalle);
      await coordinateur(conteneur).auRetour();
      await tester.pump();

      expect(clesDe(conteneur), <String>['2026-09', '2026-10']);
      expect(conteneur.read(periodesProvider).hasError, isFalse);
    });
  });
}
