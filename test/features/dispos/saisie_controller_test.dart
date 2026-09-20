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
import 'package:astreinte_sp/features/dispos/presentation/controllers/saisie_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';

/// Une case d'octobre 2026.
CreneauCle jour(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.jour);
CreneauCle nuit(int numero) =>
    CreneauCle(DateTime(2026, 10, numero), CreneauType.nuit);

/// Un peu plus que le délai d'envoi : la file doit être partie.
const Duration apresLeDelai = Duration(milliseconds: 600);

/// Monte le contrôleur seul, sous un `ProviderScope` réel pour que les
/// minuteurs tombent dans l'horloge simulée du test.
Future<ProviderContainer> ouvrir(
  WidgetTester tester, {
  required FauxDisposRepository depot,
  ConnectiviteMemoire? reseau,
  FileLocaleMemoire? fileLocale,
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
      fileLocaleProvider.overrideWithValue(fileLocale ?? FileLocaleMemoire()),
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

void main() {
  group('La touche cyclique', () {
    testWidgets('fait avancer la case d\'un cran à chaque appui', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur);

      expect(etatDe(conteneur).etat(jour(4)), DisponibiliteEtat.nonSaisi);

      controleur.basculer(jour(4));
      expect(etatDe(conteneur).etat(jour(4)), DisponibiliteEtat.disponible);

      controleur.basculer(jour(4));
      expect(etatDe(conteneur).etat(jour(4)), DisponibiliteEtat.absent);

      controleur.basculer(jour(4));
      expect(etatDe(conteneur).etat(jour(4)), DisponibiliteEtat.nonSaisi);

      await tester.pump(apresLeDelai);
    });

    testWidgets('une case revenue au vide sans ligne n\'envoie rien', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur)
        ..basculer(jour(4))
        ..basculer(jour(4))
        ..basculer(jour(4));
      await tester.pump(apresLeDelai);

      expect(
        depot.requetes,
        0,
        reason: 'rien à écrire, rien à supprimer : rien ne part',
      );
      expect(etatDe(conteneur).sync, SyncEtat.enregistre);
    });

    testWidgets('une case déjà en base et effacée part en suppression', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          jour(4): DisponibiliteEtat.absent,
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);

      // « absent » → « non saisi » en un cran.
      pilote(conteneur).basculer(jour(4));
      await tester.pump(apresLeDelai);

      expect(depot.requetes, 1);
      expect(depot.suppressions.single, <CreneauCle>[jour(4)]);
      expect(depot.base, isEmpty);
    });
  });

  group('La peinture', () {
    testWidgets('pose la valeur du premier cran sur tout le chemin', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..debutGeste();

      for (var numero = 1; numero <= 5; numero++) {
        controleur.toucherPendantGeste(nuit(numero));
      }
      controleur.finGeste();

      for (var numero = 1; numero <= 5; numero++) {
        expect(
          etatDe(conteneur).etat(nuit(numero)),
          DisponibiliteEtat.disponible,
        );
      }
      await tester.pump(apresLeDelai);
    });

    testWidgets('ne cycle pas une case déjà à la valeur du pinceau', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          nuit(3): DisponibiliteEtat.disponible,
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..debutGeste();

      controleur
        ..toucherPendantGeste(nuit(1))
        ..toucherPendantGeste(nuit(2))
        ..toucherPendantGeste(nuit(3))
        // Un aller-retour : repasser dessus ne fait rien.
        ..toucherPendantGeste(nuit(3))
        ..toucherPendantGeste(nuit(2));

      expect(etatDe(conteneur).etat(nuit(3)), DisponibiliteEtat.disponible);
      expect(etatDe(conteneur).etat(nuit(2)), DisponibiliteEtat.disponible);
      expect(
        etatDe(conteneur).casesPeintes,
        2,
        reason: 'seules les cases réellement changées sont comptées',
      );

      controleur.finGeste();
      await tester.pump(apresLeDelai);
    });

    testWidgets('le pinceau « absent » part de la case d\'origine', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          jour(1): DisponibiliteEtat.disponible,
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..debutGeste();

      // La case d'origine est « disponible » : son cran suivant est
      // « absent », et c'est ce que le geste pose sur tout le chemin.
      controleur
        ..toucherPendantGeste(jour(1))
        ..toucherPendantGeste(jour(2));

      expect(etatDe(conteneur).pinceau, DisponibiliteEtat.absent);
      expect(etatDe(conteneur).etat(jour(2)), DisponibiliteEtat.absent);

      controleur.finGeste();
      await tester.pump(apresLeDelai);
    });

    testWidgets('rien ne part sur le réseau tant que le doigt est posé', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..debutGeste();

      for (var numero = 1; numero <= 20; numero++) {
        controleur.toucherPendantGeste(nuit(numero));
      }

      // Bien au-delà du délai de 500 ms : la file est retenue.
      await tester.pump(const Duration(seconds: 5));
      expect(depot.requetes, 0);

      controleur.finGeste();
      await tester.pump(apresLeDelai);
      expect(depot.requetes, 1);
    });

    testWidgets('annonce le résultat du geste', (tester) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..debutGeste();

      controleur
        ..toucherPendantGeste(nuit(1))
        ..toucherPendantGeste(nuit(2))
        ..finGeste();

      expect(
        etatDe(conteneur).annonce,
        AppStrings.peintureResultat(2, AppStrings.etatDisponible),
      );
      await tester.pump(apresLeDelai);
    });
  });

  group('L\'annulation', () {
    testWidgets('restitue exactement l\'état d\'avant-geste', (tester) async {
      final depot = FauxDisposRepository(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          nuit(2): DisponibiliteEtat.absent,
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur);

      final avant = <CreneauCle, DisponibiliteEtat>{
        for (var numero = 1; numero <= 5; numero++)
          nuit(numero): etatDe(conteneur).etat(nuit(numero)),
      };

      controleur.debutGeste();
      for (var numero = 1; numero <= 5; numero++) {
        controleur.toucherPendantGeste(nuit(numero));
      }
      controleur.annulerGeste();

      for (final entree in avant.entries) {
        expect(
          etatDe(conteneur).etat(entree.key),
          entree.value,
          reason: 'la case ${entree.key} doit reprendre sa valeur',
        );
      }
      expect(etatDe(conteneur).annonce, AppStrings.peintureAnnulee);
      expect(etatDe(conteneur).pinceau, isNull);

      await tester.pump(const Duration(seconds: 5));
      expect(depot.requetes, 0, reason: 'une annulation ne coûte rien');
    });

    testWidgets('n\'efface pas une modification antérieure au geste', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..basculer(jour(9));

      controleur
        ..debutGeste()
        ..toucherPendantGeste(nuit(1))
        ..annulerGeste();

      expect(etatDe(conteneur).etat(jour(9)), DisponibiliteEtat.disponible);
      expect(etatDe(conteneur).etat(nuit(1)), DisponibiliteEtat.nonSaisi);

      await tester.pump(apresLeDelai);
      expect(depot.ecritures.single.single.cle, jour(9));
    });
  });

  group('La file d\'écriture', () {
    testWidgets('quarante modifications coalescées partent en 2 requêtes', (
      tester,
    ) async {
      // Vingt cases déjà en base, qu'on efface ; vingt cases vides, qu'on
      // coche. Quarante modifications, deux lots.
      final depot = FauxDisposRepository(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          for (var numero = 1; numero <= 20; numero++)
            jour(numero): DisponibiliteEtat.absent,
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..debutGeste();

      // Les cases de jour : « absent » → « non saisi ».
      for (var numero = 1; numero <= 20; numero++) {
        controleur.toucherPendantGeste(jour(numero));
      }
      controleur.finGeste();

      // Les cases de nuit : « non saisi » → « disponible ».
      controleur.debutGeste();
      for (var numero = 1; numero <= 20; numero++) {
        controleur.toucherPendantGeste(nuit(numero));
      }
      controleur.finGeste();

      await tester.pump(apresLeDelai);

      expect(
        depot.requetes,
        2,
        reason: '40 cases modifiées, 2 requêtes : un envoi, une suppression',
      );
      expect(depot.ecritures.single, hasLength(20));
      expect(depot.suppressions.single, hasLength(20));
    });

    testWidgets('une peinture d\'une seule couleur ne coûte qu\'une requête', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..debutGeste();

      for (var numero = 1; numero <= 31; numero++) {
        controleur.toucherPendantGeste(nuit(numero));
      }
      controleur.finGeste();
      await tester.pump(apresLeDelai);

      expect(depot.requetes, 1);
      expect(depot.ecritures.single, hasLength(31));
    });

    testWidgets('quarante touches sur la même case n\'envoient qu\'une ligne', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur);

      for (var essai = 0; essai < 40; essai++) {
        controleur.basculer(jour(4));
      }
      await tester.pump(apresLeDelai);

      // 40 crans depuis « non saisi » : 40 % 3 == 1, donc « disponible ».
      expect(depot.requetes, 1);
      expect(depot.ecritures.single, hasLength(1));
      expect(depot.ecritures.single.single.etat, DisponibiliteEtat.disponible);
    });

    testWidgets('le délai se réarme à chaque modification', (tester) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur);

      controleur.basculer(jour(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(depot.requetes, 0);

      controleur.basculer(jour(2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(depot.requetes, 0, reason: 'le calme a été rompu');

      await tester.pump(apresLeDelai);
      expect(depot.requetes, 1);
      expect(depot.ecritures.single, hasLength(2));
    });

    testWidgets('quitter l\'écran vide la file sans attendre le délai', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..basculer(jour(4));

      await controleur.viderMaintenant();
      await tester.pump();

      expect(depot.requetes, 1);
    });
  });

  group('L\'indicateur d\'enregistrement', () {
    testWidgets('une session de peinture produit deux transitions', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      final vus = <SyncEtat>[etatDe(conteneur).sync];
      conteneur.listen(saisieControllerProvider, (_, suivant) {
        final etat = suivant.value?.sync;
        if (etat != null && (vus.isEmpty || vus.last != etat)) vus.add(etat);
      });

      expect(etatDe(conteneur).sync, SyncEtat.repos);

      final controleur = pilote(conteneur)..debutGeste();
      for (var numero = 1; numero <= 31; numero++) {
        controleur.toucherPendantGeste(nuit(numero));
      }
      controleur.finGeste();
      await tester.pump(apresLeDelai);

      expect(vus, <SyncEtat>[
        SyncEtat.repos,
        SyncEtat.enregistrement,
        SyncEtat.enregistre,
      ], reason: '31 cases peintes, deux transitions depuis le repos');
    });

    testWidgets('« Enregistré » reste jusqu\'à la modification suivante', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..basculer(jour(1));

      await tester.pump(apresLeDelai);
      expect(etatDe(conteneur).sync, SyncEtat.enregistre);

      await tester.pump(const Duration(seconds: 10));
      expect(etatDe(conteneur).sync, SyncEtat.enregistre);

      controleur.basculer(jour(2));
      expect(etatDe(conteneur).sync, SyncEtat.enregistrement);
      await tester.pump(apresLeDelai);
    });
  });

  group('Hors ligne', () {
    testWidgets('n\'est pas une erreur : aucune case marquée, file gardée', (
      tester,
    ) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.reseau;
      final reseau = ConnectiviteMemoire();
      addTearDown(reseau.dispose);

      final conteneur = await ouvrir(tester, depot: depot, reseau: reseau);
      pilote(conteneur).basculer(jour(4));
      await tester.pump(apresLeDelai);

      final etat = etatDe(conteneur);
      expect(etat.sync, SyncEtat.horsLigne);
      expect(
        etat.enErreur,
        isEmpty,
        reason: 'hors ligne ne marque aucune case',
      );
      expect(
        etat.etat(jour(4)),
        DisponibiliteEtat.disponible,
        reason: 'la valeur voulue reste affichée',
      );
      expect(etat.echecPersistant, isFalse);
    });

    testWidgets('la grille reste éditable et la file s\'empile', (
      tester,
    ) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.reseau;
      final reseau = ConnectiviteMemoire();
      addTearDown(reseau.dispose);

      final conteneur = await ouvrir(tester, depot: depot, reseau: reseau);
      final controleur = pilote(conteneur)..basculer(jour(1));
      await tester.pump(apresLeDelai);

      controleur.basculer(jour(2));
      await tester.pump(apresLeDelai);

      expect(etatDe(conteneur).etat(jour(2)), DisponibiliteEtat.disponible);
      expect(etatDe(conteneur).enErreur, isEmpty);
    });

    testWidgets('le retour du réseau rejoue la file tout seul', (tester) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.reseau;
      final reseau = ConnectiviteMemoire();
      addTearDown(reseau.dispose);

      final conteneur = await ouvrir(tester, depot: depot, reseau: reseau);
      reseau.definir(enLigne: false);
      await tester.pump();

      pilote(conteneur)
        ..basculer(jour(1))
        ..basculer(nuit(1));
      await tester.pump(apresLeDelai);
      expect(etatDe(conteneur).sync, SyncEtat.horsLigne);

      depot.erreurEcriture = null;
      reseau.definir(enLigne: true);
      await tester.pump();
      await tester.pump(apresLeDelai);

      expect(etatDe(conteneur).sync, SyncEtat.enregistre);
      expect(depot.base.keys.toSet(), <CreneauCle>{jour(1), nuit(1)});
    });

    testWidgets('la perte du réseau bascule l\'indicateur', (tester) async {
      final depot = FauxDisposRepository();
      final reseau = ConnectiviteMemoire();
      addTearDown(reseau.dispose);

      final conteneur = await ouvrir(tester, depot: depot, reseau: reseau);
      reseau.definir(enLigne: false);
      await tester.pump();

      expect(etatDe(conteneur).horsLigne, isTrue);
      expect(etatDe(conteneur).sync, SyncEtat.horsLigne);
    });
  });

  group('Échec d\'enregistrement', () {
    testWidgets('marque les seules cases concernées', (tester) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.inconnue;
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur)
        ..basculer(jour(1))
        ..basculer(nuit(1));
      await tester.pump(apresLeDelai);

      final etat = etatDe(conteneur);
      expect(etat.sync, SyncEtat.echec);
      expect(etat.enErreur, <CreneauCle>{jour(1), nuit(1)});
      expect(etat.enErreur.contains(jour(2)), isFalse);
      expect(
        etat.etat(jour(1)),
        DisponibiliteEtat.disponible,
        reason: 'un échec ne remet aucune case à son ancienne valeur',
      );

      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('relance une fois à 1 s, une fois à 4 s, puis s\'arrête', (
      tester,
    ) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.inconnue;
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).basculer(jour(1));
      await tester.pump(apresLeDelai);
      expect(depot.requetes, 1);

      await tester.pump(const Duration(milliseconds: 1100));
      expect(depot.requetes, 2);

      await tester.pump(const Duration(seconds: 5));
      expect(depot.requetes, 3);
      expect(etatDe(conteneur).echecPersistant, isTrue);

      await tester.pump(const Duration(seconds: 30));
      expect(depot.requetes, 3, reason: 'on attend l\'humain, pas plus');
    });

    testWidgets('« Réessayer » rejoue toute la file', (tester) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.inconnue;
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur)
        ..basculer(jour(1))
        ..basculer(nuit(1));
      await tester.pump(const Duration(seconds: 10));
      expect(etatDe(conteneur).echecPersistant, isTrue);

      depot
        ..erreurEcriture = null
        ..requetes = 0;
      await pilote(conteneur).reessayer();
      await tester.pump();

      final etat = etatDe(conteneur);
      expect(depot.requetes, 1);
      expect(etat.enErreur, isEmpty);
      expect(etat.sync, SyncEtat.enregistre);
      expect(depot.base.keys.toSet(), <CreneauCle>{jour(1), nuit(1)});
    });

    testWidgets('reposer une case en échec efface son contour', (tester) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.inconnue;
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).basculer(jour(1));
      await tester.pump(const Duration(seconds: 10));
      expect(etatDe(conteneur).enErreur, <CreneauCle>{jour(1)});

      depot.erreurEcriture = null;
      pilote(conteneur).basculer(jour(1));
      expect(etatDe(conteneur).enErreur, isEmpty);

      await tester.pump(apresLeDelai);
    });
  });

  group('Période verrouillée et refus du serveur', () {
    testWidgets('un mois verrouillé n\'accepte aucune saisie', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
      );
      final conteneur = await ouvrir(tester, depot: depot);

      expect(etatDe(conteneur).modifiable, isFalse);
      pilote(conteneur).basculer(jour(4));
      expect(etatDe(conteneur).etat(jour(4)), DisponibiliteEtat.nonSaisi);

      await tester.pump(apresLeDelai);
      expect(depot.requetes, 0);
    });

    testWidgets('une RLS qui filtre sans lever est traitée comme un refus', (
      tester,
    ) async {
      // Le cas du ticket 008 : la période s'est verrouillée pendant la saisie.
      // Le `delete` part, répond 200, et n'affecte aucune ligne.
      final depot = FauxDisposRepository(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          jour(4): DisponibiliteEtat.disponible,
        },
      )..filtreSansLever = true;
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur)
        ..basculer(jour(4))
        ..basculer(jour(4));
      await tester.pump(apresLeDelai);
      await tester.pump();

      final etat = etatDe(conteneur);
      expect(
        etat.sync,
        SyncEtat.echec,
        reason: 'zéro ligne affectée n\'est pas un succès',
      );
      expect(etat.refusServeur, isNotNull);
      expect(etat.enErreur, contains(jour(4)));
    });

    testWidgets('un envoi partiellement accepté est traité comme un refus', (
      tester,
    ) async {
      final depot = _DepotAvare();
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur)
        ..basculer(jour(1))
        ..basculer(jour(2));
      await tester.pump(apresLeDelai);
      await tester.pump();

      expect(etatDe(conteneur).sync, SyncEtat.echec);
    });

    testWidgets('le refus nomme le verrouillage quand le mois l\'est devenu', (
      tester,
    ) async {
      final depot = _DepotQuiSeVerrouille();
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).basculer(jour(4));
      await tester.pump(apresLeDelai);
      await tester.pump();

      expect(
        etatDe(conteneur).refusServeur,
        AppStrings.moisErreurVerrouilleEnCours,
      );
      expect(etatDe(conteneur).lectureSeule, isFalse);
    });

    testWidgets('le refus nomme la lecture seule quand le mois reste ouvert', (
      tester,
    ) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.verrouille;
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).basculer(jour(4));
      await tester.pump(apresLeDelai);
      await tester.pump();

      final etat = etatDe(conteneur);
      expect(etat.refusServeur, AppStrings.moisErreurSuspendueEnCours);
      expect(etat.lectureSeule, isTrue);
      expect(
        etat.modifiable,
        isFalse,
        reason: 'la grille passe en lecture seule',
      );
    });
  });

  group('Les compteurs', () {
    testWidgets('suivent la peinture, weekends compris', (tester) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..debutGeste();

      // Samedi 3 et dimanche 4 octobre 2026 : un seul weekend.
      controleur
        ..toucherPendantGeste(nuit(3))
        ..toucherPendantGeste(nuit(4))
        ..toucherPendantGeste(jour(5));

      final compteurs = etatDe(conteneur).compteurs;
      expect(compteurs.nuits, 2);
      expect(compteurs.jours, 1);
      expect(compteurs.weekends, 1);

      controleur.finGeste();
      await tester.pump(apresLeDelai);
    });

    testWidgets('ne comptent pas les absents', (tester) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur)
        ..basculer(nuit(3))
        ..basculer(nuit(3));

      expect(etatDe(conteneur).etat(nuit(3)), DisponibiliteEtat.absent);
      expect(etatDe(conteneur).compteurs.weekends, 0);
      expect(etatDe(conteneur).compteurs.nuits, 0);

      await tester.pump(apresLeDelai);
    });
  });

  group('Le mois affiché', () {
    testWidgets('lit ce que la base contient', (tester) async {
      final depot = FauxDisposRepository(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          jour(2): DisponibiliteEtat.disponible,
          nuit(2): DisponibiliteEtat.absent,
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);

      expect(etatDe(conteneur).etat(jour(2)), DisponibiliteEtat.disponible);
      expect(etatDe(conteneur).etat(nuit(2)), DisponibiliteEtat.absent);
      expect(etatDe(conteneur).mois.estVierge, isFalse);
    });

    testWidgets('ouvre la première période ouverte', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeVerrouillee(annee: 2026, mois: 9),
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      );
      final conteneur = await ouvrir(tester, depot: depot);

      expect(etatDe(conteneur).periode.cle, '2026-10');
    });

    testWidgets(
      'sans période ouverte, retombe sur la verrouillée la plus récente',
      (tester) async {
        final depot = FauxDisposRepository(
          periodes: <PeriodeSaisie>[
            periodeVerrouillee(annee: 2026, mois: 8),
            periodeVerrouillee(annee: 2026, mois: 9),
          ],
        );
        final conteneur = await ouvrir(tester, depot: depot);

        expect(etatDe(conteneur).periode.cle, '2026-09');
      },
    );

    testWidgets('changer de mois vide la file d\'abord', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      );
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).basculer(jour(4));
      await pilote(conteneur).choisirMois('2026-11');
      await tester.pump();

      expect(depot.requetes, 1, reason: 'le mois quitté ne laisse rien');
      expect(depot.base.keys.single, jour(4));

      for (var essai = 0; essai < 20; essai++) {
        await tester.pump();
        if (etatDe(conteneur).periode.cle == '2026-11') break;
      }
      expect(etatDe(conteneur).periode.cle, '2026-11');
    });

    testWidgets('aucune période : l\'état est nul', (tester) async {
      final depot = FauxDisposRepository(periodes: <PeriodeSaisie>[]);
      final conteneur = await ouvrir(tester, depot: depot);

      expect(conteneur.read(saisieControllerProvider).value, isNull);
    });
  });

  group('Bloquant 1 — changer de mois ne perd jamais la file', () {
    testWidgets('hors ligne, la file survit au changement de mois et repart', (
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

      final conteneur = await ouvrir(tester, depot: depot, reseau: reseau);
      reseau.definir(enLigne: false);
      await tester.pump();

      // Dix cases peintes, hors ligne : la bannière promet un envoi au
      // retour du réseau.
      final controleur = pilote(conteneur)..debutGeste();
      for (var numero = 1; numero <= 10; numero++) {
        controleur.toucherPendantGeste(nuit(numero));
      }
      controleur.finGeste();
      await tester.pump(apresLeDelai);
      expect(etatDe(conteneur).sync, SyncEtat.horsLigne);

      // Changement de mois : l'envoi échoue encore, le mois change quand
      // même, et **la file reste intacte**.
      await controleur.choisirMois('2026-11');
      for (var essai = 0; essai < 20; essai++) {
        await tester.pump();
        if (etatDe(conteneur).periode.cle == '2026-11') break;
      }
      expect(etatDe(conteneur).periode.cle, '2026-11');

      // Le réseau revient : les dix cases d'octobre partent.
      depot.erreurEcriture = null;
      reseau.definir(enLigne: true);
      await tester.pump();
      await tester.pump(apresLeDelai);

      expect(depot.base, hasLength(10));
      for (var numero = 1; numero <= 10; numero++) {
        expect(
          depot.base[nuit(numero)],
          DisponibiliteEtat.disponible,
          reason: 'la nuit du $numero octobre ne doit pas avoir disparu',
        );
      }
    });

    testWidgets('viderMaintenant dit si la file est réellement partie', (
      tester,
    ) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.reseau;
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).basculer(jour(4));
      expect(await pilote(conteneur).viderMaintenant(), isFalse);

      depot.erreurEcriture = null;
      expect(await pilote(conteneur).viderMaintenant(), isTrue);
      await tester.pump();
    });

    testWidgets('un envoi de deux mois part dans le même lot', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      )..erreurEcriture = ErreurDispos.reseau;

      final conteneur = await ouvrir(tester, depot: depot);
      pilote(conteneur).basculer(jour(4));
      await tester.pump(apresLeDelai);

      // Le changement de mois a lieu alors que l'envoi échoue encore.
      await pilote(conteneur).choisirMois('2026-11');
      for (var essai = 0; essai < 20; essai++) {
        await tester.pump();
        if (etatDe(conteneur).periode.cle == '2026-11') break;
      }
      depot
        ..erreurEcriture = null
        ..requetes = 0;

      // Une case de novembre, alors que la file porte encore octobre.
      pilote(
        conteneur,
      ).basculer(CreneauCle(DateTime(2026, 11, 4), CreneauType.jour));
      await tester.pump(apresLeDelai);

      expect(depot.requetes, 1, reason: 'les deux mois tiennent dans un lot');
      expect(depot.base.keys.map((cle) => cle.cleMois).toSet(), <String>{
        '2026-10',
        '2026-11',
      });
    });
  });

  group('Bloquant 2 — rien ne part pendant un geste', () {
    testWidgets('un geste ouvert juste après une touche retient l\'envoi', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..basculer(jour(4));

      // Le délai de 500 ms est armé ; le geste s'ouvre 200 ms plus tard.
      await tester.pump(const Duration(milliseconds: 200));
      controleur
        ..debutGeste()
        ..toucherPendantGeste(nuit(4));

      await tester.pump(const Duration(seconds: 5));
      expect(
        depot.requetes,
        0,
        reason: 'le minuteur armé avant le geste a été désarmé',
      );

      // L'annulation rend l'écran **et** la base à leur état d'avant-geste.
      controleur.annulerGeste();
      await tester.pump(apresLeDelai);

      expect(etatDe(conteneur).etat(nuit(4)), DisponibiliteEtat.nonSaisi);
      expect(depot.base.keys.single, jour(4));
    });

    testWidgets('une relance programmée ne part pas pendant un geste', (
      tester,
    ) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.inconnue;
      final conteneur = await ouvrir(tester, depot: depot);
      final controleur = pilote(conteneur)..basculer(jour(4));

      await tester.pump(apresLeDelai);
      expect(depot.requetes, 1);

      // La relance est armée à 1 s. Le geste s'ouvre avant.
      controleur
        ..debutGeste()
        ..toucherPendantGeste(nuit(4));
      await tester.pump(const Duration(seconds: 5));

      expect(depot.requetes, 1, reason: 'aucune relance ne part sous le doigt');

      controleur.annulerGeste();
      await tester.pump(const Duration(seconds: 10));
      expect(etatDe(conteneur).etat(nuit(4)), DisponibiliteEtat.nonSaisi);
    });
  });

  group('Bloquant 3 — la file est gardée sur l\'appareil', () {
    testWidgets('une saisie est gardée avant même de partir', (tester) async {
      final locale = FileLocaleMemoire();
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.reseau;
      final conteneur = await ouvrir(tester, depot: depot, fileLocale: locale);

      pilote(conteneur).basculer(jour(4));
      await tester.pump();

      final gardee = await locale.lire(stationId: '', userId: '');
      expect(gardee[jour(4)], DisponibiliteEtat.disponible);
      await tester.pump(apresLeDelai);
    });

    testWidgets('une file gardée repart au démarrage suivant', (tester) async {
      final locale = FileLocaleMemoire();
      await locale.enregistrer(
        stationId: '',
        userId: '',
        mois: '2026-10',
        entrees: <CreneauCle, DisponibiliteEtat>{
          nuit(7): DisponibiliteEtat.disponible,
          jour(8): DisponibiliteEtat.absent,
        },
      );

      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot, fileLocale: locale);

      // Affichée dès l'ouverture, avant même d'être partie.
      expect(etatDe(conteneur).etat(nuit(7)), DisponibiliteEtat.disponible);
      expect(etatDe(conteneur).etat(jour(8)), DisponibiliteEtat.absent);

      await tester.pump(apresLeDelai);
      expect(depot.base[nuit(7)], DisponibiliteEtat.disponible);
      expect(depot.base[jour(8)], DisponibiliteEtat.absent);
    });

    testWidgets('une entrée confirmée est oubliée du stockage', (tester) async {
      final locale = FileLocaleMemoire();
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot, fileLocale: locale);

      pilote(conteneur).basculer(jour(4));
      await tester.pump(apresLeDelai);
      await tester.pump();

      expect(await locale.lire(stationId: '', userId: ''), isEmpty);
      expect(await locale.moisEnAttente(stationId: '', userId: ''), isEmpty);
    });

    testWidgets(
      'une file gardée sur un mois verrouillé est abandonnée, et l\'écran '
      'le dit',
      (tester) async {
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

        final depot = FauxDisposRepository(
          periodes: <PeriodeSaisie>[
            periodeVerrouillee(annee: 2026, mois: 9),
            periodeOuverte(annee: 2026, mois: 10),
          ],
        );
        final conteneur = await ouvrir(
          tester,
          depot: depot,
          fileLocale: locale,
        );

        expect(etatDe(conteneur).filePerimee, isTrue);
        await tester.pump(const Duration(seconds: 5));
        expect(
          depot.requetes,
          0,
          reason: 'on ne rejoue pas contre un mois verrouillé',
        );
        expect(await locale.lire(stationId: '', userId: ''), isEmpty);

        pilote(conteneur).accuserFilePerimee();
        expect(etatDe(conteneur).filePerimee, isFalse);
      },
    );

    testWidgets('« Recharger » ne jette pas une file encore valable', (
      tester,
    ) async {
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.inconnue;
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).basculer(jour(4));
      await tester.pump(const Duration(seconds: 10));
      expect(etatDe(conteneur).echecPersistant, isTrue);

      depot.erreurEcriture = null;
      pilote(conteneur).recharger();
      for (var essai = 0; essai < 30; essai++) {
        await tester.pump();
        if (conteneur.read(saisieControllerProvider).hasValue) break;
      }
      await tester.pump(apresLeDelai);

      expect(depot.base[jour(4)], DisponibiliteEtat.disponible);
    });
  });

  group('Zéro ligne supprimée n\'est pas toujours un verrouillage', () {
    testWidgets('une ligne déjà disparue n\'accuse pas le mois', (
      tester,
    ) async {
      // La ligne est connue du serveur au chargement, puis effacée ailleurs.
      final depot = _DepotSansLigne();
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).basculer(jour(4));
      await tester.pump(apresLeDelai);
      await tester.pump();
      await tester.pump();

      final etat = etatDe(conteneur);
      expect(etat.sync, SyncEtat.enregistre);
      expect(etat.refusServeur, isNull);
      expect(etat.enErreur, isEmpty);
    });

    testWidgets('un envoi accepté dans le même lot innocente la période', (
      tester,
    ) async {
      final depot = _DepotSuppressionMuette(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          jour(4): DisponibiliteEtat.absent,
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur)
        // jour(4) : absent → non saisi, donc une suppression.
        ..basculer(jour(4))
        // nuit(4) : non saisi → disponible, donc un envoi.
        ..basculer(nuit(4));
      await tester.pump(apresLeDelai);
      await tester.pump();

      expect(
        etatDe(conteneur).sync,
        SyncEtat.enregistre,
        reason: 'l\'envoi accepté prouve que la période est ouverte',
      );
      expect(depot.lectures, 1, reason: 'aucune relecture n\'a été nécessaire');
    });
  });
}

/// Un dépôt qui accepte moins de lignes qu'on ne lui en donne : la clause
/// `using` d'une politique a filtré une partie de l'envoi.
class _DepotAvare extends FauxDisposRepository {
  @override
  Future<int> enregistrerLot({
    required String stationId,
    required String userId,
    required List<LigneDisponibilite> lignes,
  }) async {
    await super.enregistrerLot(
      stationId: stationId,
      userId: userId,
      lignes: lignes,
    );
    return lignes.length - 1;
  }
}

/// Un dépôt qui refuse l'écriture **et** dont la période est passée
/// verrouillée entre-temps.
class _DepotQuiSeVerrouille extends FauxDisposRepository {
  bool _refuse = true;

  @override
  Future<List<PeriodeSaisie>> periodes(String stationId) async => _refuse
      ? <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 10)]
      : <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)];

  @override
  Future<int> enregistrerLot({
    required String stationId,
    required String userId,
    required List<LigneDisponibilite> lignes,
  }) async {
    requetes++;
    _refuse = false;
    throw const EchecDispos(ErreurDispos.verrouille);
  }
}

/// Un dépôt dont la ligne à supprimer a déjà disparu : la suppression
/// n'affecte rien, et la relecture le confirme.
class _DepotSansLigne extends FauxDisposRepository {
  _DepotSansLigne()
    : super(
        disponibilites: <CreneauCle, DisponibiliteEtat>{
          jour(4): DisponibiliteEtat.absent,
        },
      ) {
    // Le contrôleur a lu « absent » ; quelqu'un d'autre a supprimé la ligne.
    base.clear();
  }
}

/// Un dépôt qui supprime pour de bon mais **rapporte zéro ligne**, comme le
/// fait une politique RLS qui filtre. L'envoi du même lot, lui, passe.
class _DepotSuppressionMuette extends FauxDisposRepository {
  _DepotSuppressionMuette({super.disponibilites});

  @override
  Future<int> supprimerLot({
    required String stationId,
    required String userId,
    required List<CreneauCle> cles,
  }) async {
    await super.supprimerLot(stationId: stationId, userId: userId, cles: cles);
    return 0;
  }
}
