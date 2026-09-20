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
import 'package:astreinte_sp/features/dispos/domain/preferences_mois.dart';
import 'package:astreinte_sp/features/dispos/presentation/controllers/saisie_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';

const String idOctobre = 'periode-2026-10';
const String idNovembre = 'periode-2026-11';

/// Un peu plus que le délai d'envoi : la file doit être partie.
const Duration apresLeDelai = Duration(milliseconds: 600);

/// Les deux mois de la caserne de test : octobre puis novembre, tous deux
/// ouverts sauf mention contraire.
List<PeriodeSaisie> deuxMois({bool novembreOuvert = true}) => <PeriodeSaisie>[
  periodeOuverte(annee: 2026, mois: 10, id: idOctobre),
  if (novembreOuvert)
    periodeOuverte(annee: 2026, mois: 11, id: idNovembre)
  else
    periodeVerrouillee(annee: 2026, mois: 11),
];

Future<ProviderContainer> ouvrir(
  WidgetTester tester, {
  required FauxDisposRepository depot,
  ConnectiviteMemoire? reseau,
  FileLocaleMemoire? fileLocale,
  String? mois,
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

  if (mois != null) {
    conteneur.read(moisSelectionneProvider.notifier).definir(mois);
  }

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
  group('Les valeurs par défaut', () {
    testWidgets('sans ligne ni mois précédent : autant que nécessaire', (
      tester,
    ) async {
      final depot = FauxDisposRepository(periodes: deuxMois());
      final conteneur = await ouvrir(tester, depot: depot);

      final preferences = etatDe(conteneur).preferences;
      expect(preferences.valeurs, PreferencesMois.sansLimite);
      expect(preferences.ligneAuChargement, isFalse);
      expect(preferences.reprise, isFalse);

      await tester.pump(apresLeDelai);
      expect(
        depot.ecrituresPreferences,
        isEmpty,
        reason: 'rien à dire, rien à écrire',
      );
    });

    testWidgets('une ligne existante fait foi, sans reprise', (tester) async {
      final depot = FauxDisposRepository(
        periodes: deuxMois(),
        preferences: <String, PreferencesMois>{
          idOctobre: const PreferencesMois(maxAstreintes: 6, maxWeekends: 2),
          idNovembre: const PreferencesMois(maxAstreintes: 9),
        },
      );
      final conteneur = await ouvrir(tester, depot: depot, mois: '2026-11');

      final preferences = etatDe(conteneur).preferences;
      expect(preferences.valeurs.maxAstreintes, 9);
      expect(preferences.valeurs.maxWeekends, isNull);
      expect(preferences.ligneAuChargement, isTrue);
      expect(preferences.reprise, isFalse);

      await tester.pump(apresLeDelai);
      expect(depot.ecrituresPreferences, isEmpty);
    });

    testWidgets('les deux mois sont lus en une seule requête', (tester) async {
      final depot = FauxDisposRepository(periodes: deuxMois());
      await ouvrir(tester, depot: depot, mois: '2026-11');

      expect(depot.lecturesPreferences, 1);
    });
  });

  group('La reprise du mois précédent', () {
    testWidgets('reprend les trois valeurs, les écrit, et le dit', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        periodes: deuxMois(),
        preferences: <String, PreferencesMois>{
          idOctobre: const PreferencesMois(
            maxAstreintes: 4,
            maxWeekends: 1,
            commentaire: 'Garde des enfants.',
          ),
        },
      );
      final conteneur = await ouvrir(tester, depot: depot, mois: '2026-11');

      final preferences = etatDe(conteneur).preferences;
      expect(preferences.valeurs.maxAstreintes, 4);
      expect(preferences.valeurs.maxWeekends, 1);
      expect(preferences.valeurs.commentaire, 'Garde des enfants.');
      expect(
        preferences.repriseDe,
        10,
        reason: 'la reprise est annoncée, jamais silencieuse',
      );

      await tester.pump(apresLeDelai);
      expect(
        depot.ecrituresPreferences.single.key,
        idNovembre,
        reason: 'sans écriture, l\'admin ne verrait pas ce que le membre voit',
      );
      expect(depot.basePreferences[idNovembre]!.maxWeekends, 1);
    });

    testWidgets('rien à reprendre : aucune écriture', (tester) async {
      final depot = FauxDisposRepository(periodes: deuxMois());
      await ouvrir(tester, depot: depot, mois: '2026-11');

      await tester.pump(apresLeDelai);
      expect(depot.ecrituresPreferences, isEmpty);
    });

    testWidgets('mois verrouillé : aucune reprise, aucune écriture', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        periodes: deuxMois(novembreOuvert: false),
        preferences: <String, PreferencesMois>{
          idOctobre: const PreferencesMois(maxAstreintes: 4, maxWeekends: 1),
        },
      );
      final conteneur = await ouvrir(tester, depot: depot, mois: '2026-11');

      expect(etatDe(conteneur).preferences.valeurs, PreferencesMois.sansLimite);
      await tester.pump(apresLeDelai);
      expect(depot.ecrituresPreferences, isEmpty);
    });

    testWidgets('la mention tombe à la première modification', (tester) async {
      final depot = FauxDisposRepository(
        periodes: deuxMois(),
        preferences: <String, PreferencesMois>{
          idOctobre: const PreferencesMois(maxAstreintes: 4),
        },
      );
      final conteneur = await ouvrir(tester, depot: depot, mois: '2026-11');
      expect(etatDe(conteneur).preferences.reprise, isTrue);

      pilote(conteneur).definirPlafondAstreintes(7);
      await tester.pump();

      expect(etatDe(conteneur).preferences.reprise, isFalse);
      expect(etatDe(conteneur).preferences.valeurs.maxAstreintes, 7);

      // Laisser partir la file : un minuteur encore armé au démontage est
      // une fuite, et le binding de test la refuse à juste titre.
      await tester.pump(apresLeDelai);
    });
  });

  group('Poser, retirer, effacer un plafond', () {
    testWidgets('un plafond posé part en une requête après le délai', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).definirPlafondWeekends(1);
      await tester.pump();
      expect(etatDe(conteneur).sync, SyncEtat.enregistrement);
      expect(depot.requetes, 0, reason: 'rien ne part avant le délai');

      await tester.pump(apresLeDelai);
      expect(depot.requetes, 1);
      expect(depot.basePreferences[idOctobre]!.maxWeekends, 1);
      expect(etatDe(conteneur).sync, SyncEtat.enregistre);
    });

    testWidgets('« autant que nécessaire » écrit null, jamais zéro', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        preferences: <String, PreferencesMois>{
          idOctobre: const PreferencesMois(maxAstreintes: 4, maxWeekends: 1),
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).definirPlafondWeekends(null);
      await tester.pump(apresLeDelai);

      expect(depot.basePreferences[idOctobre]!.maxWeekends, isNull);
      expect(
        depot.basePreferences[idOctobre]!.maxAstreintes,
        4,
        reason: 'retirer un plafond ne touche pas l\'autre',
      );
    });

    testWidgets('zéro est une valeur, distincte de « sans limite »', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).definirPlafondAstreintes(0);
      await tester.pump(apresLeDelai);

      expect(depot.basePreferences[idOctobre]!.maxAstreintes, 0);
    });

    testWidgets('tout remettre à « sans limite » ne supprime pas la ligne', (
      tester,
    ) async {
      final depot = FauxDisposRepository(
        preferences: <String, PreferencesMois>{
          idOctobre: const PreferencesMois(maxAstreintes: 4, maxWeekends: 1),
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur)
        ..definirPlafondAstreintes(null)
        ..definirPlafondWeekends(null);
      await tester.pump(apresLeDelai);

      expect(
        depot.basePreferences.containsKey(idOctobre),
        isTrue,
        reason: '« a dit : sans limite » n\'est pas « n\'a rien dit » : '
            'supprimer relancerait la reprise au prochain chargement',
      );
      expect(depot.basePreferences[idOctobre], PreferencesMois.sansLimite);
    });

    testWidgets('reposer la même valeur n\'écrit rien', (tester) async {
      final depot = FauxDisposRepository(
        preferences: <String, PreferencesMois>{
          idOctobre: const PreferencesMois(maxWeekends: 1),
        },
      );
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).definirPlafondWeekends(1);
      await tester.pump(apresLeDelai);

      expect(depot.requetes, 0);
    });

    testWidgets('le commentaire est borné à 280 caractères', (tester) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).definirCommentaire('a' * 400);
      await tester.pump(apresLeDelai);

      expect(
        depot.basePreferences[idOctobre]!.commentaire.length,
        PreferencesMois.commentaireMax,
      );
    });

    testWidgets('un mois verrouillé n\'accepte aucun plafond', (tester) async {
      final depot = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 10)],
      );
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).definirPlafondWeekends(1);
      await tester.pump(apresLeDelai);

      expect(etatDe(conteneur).preferences.valeurs, PreferencesMois.sansLimite);
      expect(depot.requetes, 0);
    });
  });

  group('L\'enregistrement automatique', () {
    testWidgets('trois frappes de commentaire ne font qu\'une requête', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      final controleur = pilote(conteneur);
      controleur.definirCommentaire('Pas');
      await tester.pump(const Duration(milliseconds: 100));
      controleur.definirCommentaire('Pas plus');
      await tester.pump(const Duration(milliseconds: 100));
      controleur.definirCommentaire('Pas plus d\'un weekend.');
      await tester.pump(apresLeDelai);

      expect(depot.requetes, 1, reason: 'chaque frappe réarme le même délai');
      expect(
        depot.basePreferences[idOctobre]!.commentaire,
        'Pas plus d\'un weekend.',
      );
    });

    testWidgets('un plafond et dix cases partent dans le même lot', (
      tester,
    ) async {
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(tester, depot: depot);

      final controleur = pilote(conteneur);
      for (var numero = 1; numero <= 10; numero++) {
        controleur.basculer(CreneauCle(DateTime(2026, 10, numero), CreneauType.nuit));
      }
      controleur.definirPlafondWeekends(1);
      await tester.pump(apresLeDelai);

      expect(
        depot.requetes,
        2,
        reason: 'un envoi groupé de cases, un upsert de préférence',
      );
      expect(etatDe(conteneur).sync, SyncEtat.enregistre);
    });

    testWidgets('gardé sur l\'appareil avant de partir, oublié après', (
      tester,
    ) async {
      final fichier = FileLocaleMemoire();
      final depot = FauxDisposRepository();
      final conteneur = await ouvrir(
        tester,
        depot: depot,
        fileLocale: fichier,
      );

      pilote(conteneur).definirPlafondAstreintes(4);
      await tester.pump();
      expect(
        fichier.preferences[idOctobre]?.maxAstreintes,
        4,
        reason: 'la promesse de la bannière hors ligne vaut aussi pour un '
            'maximum',
      );

      await tester.pump(apresLeDelai);
      expect(
        fichier.preferences,
        isEmpty,
        reason: 'confirmé par le serveur, il n\'a plus rien à faire là',
      );
    });

    testWidgets('hors ligne : conservé, puis rejoué au retour du réseau', (
      tester,
    ) async {
      final reseau = ConnectiviteMemoire(enLigne: false);
      final depot = FauxDisposRepository()
        ..erreurEcriture = ErreurDispos.reseau;
      final conteneur = await ouvrir(tester, depot: depot, reseau: reseau);

      pilote(conteneur).definirPlafondWeekends(2);
      await tester.pump(apresLeDelai);
      expect(etatDe(conteneur).sync, SyncEtat.horsLigne);
      expect(etatDe(conteneur).preferences.valeurs.maxWeekends, 2);

      depot.erreurEcriture = null;
      reseau.definir(enLigne: true);
      await tester.pump();
      await tester.pump(apresLeDelai);

      expect(depot.basePreferences[idOctobre]!.maxWeekends, 2);
    });

    testWidgets('refus du serveur : la valeur reste, la section est marquée', (
      tester,
    ) async {
      final depot = FauxDisposRepository()..filtreSansLever = true;
      final conteneur = await ouvrir(tester, depot: depot);

      pilote(conteneur).definirPlafondWeekends(1);
      await tester.pump(apresLeDelai);
      await tester.pump(apresLeDelai);

      final etat = etatDe(conteneur);
      expect(
        etat.preferences.valeurs.maxWeekends,
        1,
        reason: 'la valeur affichée reste celle que le membre a voulue',
      );
      expect(etat.preferences.enErreur, isTrue);
      expect(etat.refusServeur, isNotNull);
    });
  });
}
