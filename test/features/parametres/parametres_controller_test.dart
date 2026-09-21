import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/parametres/data/parametres_repository.dart';
import 'package:astreinte_sp/features/parametres/domain/parametres_caserne.dart';
import 'package:astreinte_sp/features/parametres/domain/parametres_providers.dart';
import 'package:astreinte_sp/features/parametres/domain/validation_parametres.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_parametres.dart';

/// Monte le contrôleur seul, avec l'appartenance voulue.
///
/// `appartenancesProvider` est surchargé plutôt que reconstitué depuis une
/// fausse session : le contrôleur ne connaît que l'appartenance courante, et la
/// chaîne session → appartenances est déjà testée ailleurs. L'abonnement
/// [ProviderContainer.listen] n'est pas décoratif — sans lui, un provider sans
/// auditeur est recalculé à chaque lecture et l'appartenance n'est jamais là au
/// moment où le contrôleur la demande.
Future<(ProviderContainer, EtatParametres?)> _ouvrir(
  FauxParametresRepository depot, {
  Appartenance appartenance = appartenanceAdmin,
}) async {
  final conteneur = ProviderContainer(
    overrides: [
      appartenancesProvider.overrideWith(
        (ref) async => <Appartenance>[appartenance],
      ),
      parametresRepositoryProvider.overrideWithValue(depot),
    ],
  );
  addTearDown(conteneur.dispose);

  conteneur.listen(appartenancesProvider, (_, _) {});
  await conteneur.read(appartenancesProvider.future);

  // On observe l'état comme le ferait l'écran, plutôt que d'attendre
  // `.future` : une lecture en échec laisserait sinon une exception sans
  // destinataire au moment de fermer le conteneur.
  conteneur.listen(parametresControllerProvider, (_, _) {});
  for (var essai = 0; essai < 100; essai++) {
    if (!conteneur.read(parametresControllerProvider).isLoading) break;
    await Future<void>.delayed(Duration.zero);
  }

  return (conteneur, conteneur.read(parametresControllerProvider).value);
}

void main() {
  group('ParametresController', () {
    test('lit les réglages de la caserne administrée', () async {
      final depot = FauxParametresRepository();
      final (_, etat) = await _ouvrir(depot);

      expect(depot.lectures, 1);
      expect(etat!.enregistres, parametresSeed);
      expect(etat.brouillon, parametresSeed);
      expect(etat.modifie, isFalse);
      expect(etat.sync, SyncEtat.repos);
    });

    test('un membre ordinaire n\'a rien à lire', () async {
      final depot = FauxParametresRepository();
      final (_, etat) = await _ouvrir(depot, appartenance: appartenanceMembre);

      expect(etat, isNull);
      expect(depot.lectures, 0);
    });

    test('modifier le brouillon rend l\'écran « modifié »', () async {
      final depot = FauxParametresRepository();
      final (conteneur, etat) = await _ouvrir(depot);

      conteneur
          .read(parametresControllerProvider.notifier)
          .modifier(etat!.brouillon.copyWith(effectifJour: 3));

      final apres = conteneur.read(parametresControllerProvider).value!;
      expect(apres.modifie, isTrue);
      expect(apres.enregistres.effectifJour, 1);
      expect(apres.brouillon.effectifJour, 3);
    });

    test('sans modification, rien n\'est envoyé', () async {
      final depot = FauxParametresRepository();
      final (conteneur, _) = await _ouvrir(depot);

      final resultat = await conteneur
          .read(parametresControllerProvider.notifier)
          .enregistrer();

      expect(resultat.reussi, isFalse);
      expect(resultat.message, AppStrings.parametresAucuneModification);
      expect(depot.ecritures, isEmpty);
    });

    test(
      'un document invalide ne part pas, et toutes les erreurs s\'ouvrent',
      () async {
        final depot = FauxParametresRepository();
        final (conteneur, etat) = await _ouvrir(depot);
        final controleur = conteneur.read(
          parametresControllerProvider.notifier,
        );

        controleur.modifier(etat!.brouillon.copyWith(nom: '', jourLimite: 31));
        final resultat = await controleur.enregistrer();

        expect(depot.ecritures, isEmpty);
        expect(resultat.reussi, isFalse);
        expect(resultat.message, AppStrings.parametresACorriger(2));

        final apres = conteneur.read(parametresControllerProvider).value!;
        expect(apres.tentative, isTrue);
        // Aucun champ n'a été « quitté », et pourtant les deux erreurs sont
        // désormais montrables : c'est le seul moment où on peut les montrer
        // toutes.
        expect(apres.erreurVisible(ChampParametre.nom), isNotNull);
        expect(apres.erreurVisible(ChampParametre.jourLimite), isNotNull);
      },
    );

    test('un enregistrement réussi remet le brouillon à plat', () async {
      final depot = FauxParametresRepository();
      final (conteneur, etat) = await _ouvrir(depot);
      final controleur = conteneur.read(parametresControllerProvider.notifier);

      controleur.modifier(
        etat!.brouillon.copyWith(effectifJour: 2, jourLimite: 10),
      );
      final resultat = await controleur.enregistrer();

      expect(resultat.reussi, isTrue);
      expect(resultat.message, AppStrings.parametresEnregistres);
      expect(depot.ecritures.single.effectifJour, 2);
      expect(depot.ecritures.single.jourLimite, 10);

      final apres = conteneur.read(parametresControllerProvider).value!;
      expect(apres.modifie, isFalse);
      expect(apres.enregistres.jourLimite, 10);
      expect(apres.sync, SyncEtat.enregistre);
      expect(apres.echecServeur, isNull);
    });

    test('un refus du serveur garde le brouillon et dit pourquoi', () async {
      final depot = FauxParametresRepository(
        erreurEcriture: ErreurParametres.droits,
      );
      final (conteneur, etat) = await _ouvrir(depot);
      final controleur = conteneur.read(parametresControllerProvider.notifier);

      controleur.modifier(etat!.brouillon.copyWith(effectifNuit: 4));
      final resultat = await controleur.enregistrer();

      expect(resultat.reussi, isFalse);
      expect(resultat.message, AppStrings.parametresRefusDroits);

      final apres = conteneur.read(parametresControllerProvider).value!;
      expect(
        apres.brouillon.effectifNuit,
        4,
        reason: 'la saisie n\'est pas perdue',
      );
      expect(apres.modifie, isTrue);
      expect(apres.sync, SyncEtat.echec);
      expect(apres.echecServeur, AppStrings.parametresRefusDroits);
    });

    test('toucher à la saisie efface le refus précédent', () async {
      final depot = FauxParametresRepository(
        erreurEcriture: ErreurParametres.document,
      );
      final (conteneur, etat) = await _ouvrir(depot);
      final controleur = conteneur.read(parametresControllerProvider.notifier);

      controleur.modifier(etat!.brouillon.copyWith(effectifNuit: 4));
      await controleur.enregistrer();
      controleur.modifier(etat.brouillon.copyWith(effectifNuit: 5));

      final apres = conteneur.read(parametresControllerProvider).value!;
      expect(apres.echecServeur, isNull);
      expect(apres.sync, SyncEtat.repos);
    });

    test('relire jette le brouillon et reprend l\'état réel', () async {
      final depot = FauxParametresRepository();
      final (conteneur, etat) = await _ouvrir(depot);
      final controleur = conteneur.read(parametresControllerProvider.notifier);

      controleur.modifier(etat!.brouillon.copyWith(nom: 'Autre chose'));
      depot.parametres = parametresSeed.copyWith(effectifNuit: 7);
      await controleur.relire();

      final apres = conteneur.read(parametresControllerProvider).value!;
      expect(apres.modifie, isFalse);
      expect(apres.brouillon.nom, parametresSeed.nom);
      expect(apres.brouillon.effectifNuit, 7);
    });

    test('une erreur de lecture remonte telle quelle', () async {
      final depot = FauxParametresRepository(
        erreurLecture: ErreurParametres.inconnue,
      );
      final (conteneur, etat) = await _ouvrir(depot);

      expect(etat, isNull);
      expect(conteneur.read(parametresControllerProvider).hasError, isTrue);
      expect(
        conteneur.read(parametresControllerProvider).error,
        isA<EchecParametres>(),
      );
    });

    test(
      'une surcharge posée puis vidée disparaît du document envoyé',
      () async {
        final depot = FauxParametresRepository();
        final (conteneur, etat) = await _ouvrir(depot);
        final controleur = conteneur.read(
          parametresControllerProvider.notifier,
        );

        controleur.modifier(
          etat!.brouillon.avecSurcharge(
            const SurchargeEffectif(cle: 'sat', effectifJour: 2),
          ),
        );
        await controleur.enregistrer();

        expect(
          depot.ecritures.single.settingsJson['required_overrides'],
          <String, dynamic>{
            'sat': <String, dynamic>{'day': 2},
          },
        );

        final apres = conteneur.read(parametresControllerProvider).value!;
        controleur.modifier(apres.brouillon.sansSurcharge('sat'));
        await controleur.enregistrer();

        expect(
          depot.ecritures.last.settingsJson.containsKey('required_overrides'),
          isFalse,
        );
      },
    );

    // Ticket 038 : la caserne règle son plafond horaire d'invitations dans
    // `settings`, l'écran ne le montre pas. Un enregistrement qui ne
    // réécrirait que ses propres champs le ferait disparaître sans bruit, et
    // la caserne retomberait sur le défaut de la base.
    test('un enregistrement ne perd aucune clé que l\'écran ignore', () async {
      final lu = ParametresCaserne.depuisJson(<String, dynamic>{
        'id': stationTest,
        'name': parametresSeed.nom,
        'timezone': parametresSeed.fuseau,
        'settings': <String, dynamic>{
          ...parametresSeed.settingsJson,
          'invitation_hourly_limit': 120,
          'reglage_dune_version_plus_recente': const <String, dynamic>{'x': 1},
        },
      });
      final depot = FauxParametresRepository(parametres: lu);
      final (conteneur, etat) = await _ouvrir(depot);
      final controleur = conteneur.read(parametresControllerProvider.notifier);

      controleur.modifier(etat!.brouillon.copyWith(effectifJour: 3));
      final resultat = await controleur.enregistrer();

      expect(resultat.reussi, isTrue);
      final envoye = depot.ecritures.single.settingsJson;
      expect(envoye['required_day'], 3, reason: 'la modification part');
      expect(envoye['invitation_hourly_limit'], 120);
      expect(envoye['reglage_dune_version_plus_recente'], <String, dynamic>{
        'x': 1,
      });

      // Et l'aller-retour suivant les garde aussi : la relecture de la ligne
      // écrite ne doit pas les avoir dissoutes en route.
      final apres = conteneur.read(parametresControllerProvider).value!;
      expect(
        apres.enregistres.settingsJson['invitation_hourly_limit'],
        120,
      );
    });
  });
}
