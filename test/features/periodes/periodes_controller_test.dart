import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/dispos_providers.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/periodes/data/periodes_repository.dart';
import 'package:astreinte_sp/features/periodes/domain/periodes_providers.dart';
import 'package:astreinte_sp/features/periodes/domain/taux_saisie.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_periodes.dart';

/// Monte le contrôleur seul, avec l'appartenance voulue. Même montage que le
/// test du contrôleur des paramètres : l'abonnement n'est pas décoratif, sans
/// lui l'appartenance n'est pas là au moment où le contrôleur la demande.
Future<(ProviderContainer, PeriodesController)> _ouvrir(
  FauxPeriodesRepository depot, {
  Appartenance appartenance = appartenanceAdmin,
  FauxDisposRepository? dispos,
}) async {
  final conteneur = ProviderContainer(
    overrides: [
      appartenancesProvider.overrideWith(
        (ref) async => <Appartenance>[appartenance],
      ),
      periodesRepositoryProvider.overrideWithValue(depot),
      disposRepositoryProvider.overrideWithValue(
        dispos ?? FauxDisposRepository(),
      ),
    ],
  );
  addTearDown(conteneur.dispose);

  conteneur.listen(appartenancesProvider, (_, _) {});
  await conteneur.read(appartenancesProvider.future);

  conteneur.listen(periodesControllerProvider, (_, _) {});
  for (var essai = 0; essai < 100; essai++) {
    if (!conteneur.read(periodesControllerProvider).isLoading) break;
    await Future<void>.delayed(Duration.zero);
  }

  return (conteneur, conteneur.read(periodesControllerProvider.notifier));
}

EtatPeriodes _etat(ProviderContainer conteneur) =>
    conteneur.read(periodesControllerProvider).requireValue;

void main() {
  group('EtatPeriodes', () {
    final maintenant = DateTime(2026, 9, 20);

    final etat = EtatPeriodes(
      periodes: <PeriodeSaisie>[
        periodeVerrouillee(annee: 2026, mois: 7),
        periodeVerrouillee(annee: 2026, mois: 8),
        periodeOuverte(annee: 2026, mois: 9),
        periodeOuverte(annee: 2026, mois: 10),
      ],
    );

    test('les mois à venir vont du plus proche au plus lointain', () {
      expect(
        etat.aVenir(maintenant).map((PeriodeSaisie p) => p.cle),
        <String>['2026-09', '2026-10'],
      );
    });

    test('le mois courant n\'est pas écoulé tant qu\'il n\'est pas fini', () {
      expect(etat.aVenir(maintenant).first.mois, 9);
    });

    test('les mois écoulés remontent du plus récent au plus ancien', () {
      expect(
        etat.ecoulees(maintenant).map((PeriodeSaisie p) => p.cle),
        <String>['2026-08', '2026-07'],
      );
    });

    test('une année précédente est écoulée', () {
      final ancienne = EtatPeriodes(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2025, mois: 12)],
      );
      expect(ancienne.aVenir(maintenant), isEmpty);
      expect(ancienne.ecoulees(maintenant), hasLength(1));
    });
  });

  group('TauxSaisie', () {
    test('sans membre actif, il n\'y a pas de taux', () {
      const taux = TauxSaisie(saisis: 0, effectif: 0);
      expect(taux.mesurable, isFalse);
      expect(taux.libelle, AppStrings.periodeTauxAucunMembre);
    });

    test('le taux se dit en membres avant de se dire en pourcentage', () {
      const taux = TauxSaisie(saisis: 3, effectif: 4);
      expect(taux.libelle, AppStrings.periodeTauxSaisie(3, 4));
      expect(taux.pourcentage, 75);
      expect(taux.complet, isFalse);
    });

    test('un mois entièrement saisi est complet', () {
      const taux = TauxSaisie(saisis: 4, effectif: 4);
      expect(taux.complet, isTrue);
      expect(taux.part, 1);
    });
  });

  group('PeriodesController', () {
    test('lit les mois de la caserne administrée', () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 11)],
      );
      final (conteneur, _) = await _ouvrir(depot);

      expect(depot.lectures, 1);
      expect(_etat(conteneur).periodes, hasLength(1));
    });

    test('un membre ordinaire n\'a rien à lire', () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 11)],
      );
      final (conteneur, _) = await _ouvrir(
        depot,
        appartenance: appartenanceMembre,
      );

      expect(depot.lectures, 0);
      expect(_etat(conteneur).vide, isTrue);
    });

    test('verrouiller remplace la période par celle que la base a rendue',
        () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 11)],
      );
      final (conteneur, controleur) = await _ouvrir(depot);

      final resultat = await controleur.verrouiller(
        _etat(conteneur).periodes.single,
      );

      expect(resultat.reussi, isTrue);
      final ecrite = _etat(conteneur).periodes.single;
      expect(ecrite.statut, PeriodeEtat.verrouillee);
      // La date de verrouillage vient de la base, jamais du client.
      expect(ecrite.verrouilleeLe, isNotNull);
    });

    test('rouvrir sans repousser la date limite est refusé par la base',
        () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeFermeeDepuis(annee: 2026, mois: 11)],
      );
      final (conteneur, controleur) = await _ouvrir(depot);
      final periode = _etat(conteneur).periodes.single;

      final resultat = await controleur.rouvrir(periode, periode.dateLimite);

      expect(resultat.reussi, isFalse);
      expect(resultat.message, AppStrings.periodeRefusDeadlinePassee);
      expect(_etat(conteneur).periodes.single.statut, PeriodeEtat.verrouillee);
    });

    test('rouvrir avec une date future rouvre et repousse', () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeFermeeDepuis(annee: 2026, mois: 11)],
      );
      final (conteneur, controleur) = await _ouvrir(depot);
      final limite = DateTime.now().add(const Duration(days: 3));

      final resultat = await controleur.rouvrir(
        _etat(conteneur).periodes.single,
        limite,
      );

      expect(resultat.reussi, isTrue);
      final ecrite = _etat(conteneur).periodes.single;
      expect(ecrite.statut, PeriodeEtat.ouverte);
      expect(ecrite.dateLimite, limite);
      expect(ecrite.verrouilleeLe, isNull);
    });

    test('ouvrir un mois l\'ajoute à la liste, au bon rang', () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 12)],
      );
      final (conteneur, controleur) = await _ouvrir(depot);

      final resultat = await controleur.creer(2026, 11);

      expect(resultat.reussi, isTrue);
      expect(
        _etat(conteneur).periodes.map((PeriodeSaisie p) => p.cle),
        <String>['2026-11', '2026-12'],
      );
    });

    test('un mois déjà ouvert le dit, au lieu de feindre une création',
        () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 11)],
      );
      final (conteneur, controleur) = await _ouvrir(depot);

      final resultat = await controleur.creer(2026, 11);

      expect(resultat.reussi, isTrue);
      expect(
        resultat.message,
        AppStrings.periodeDejaOuverteConfirmation(
          AppStrings.moisNomEtAnnee(11, 2026),
        ),
      );
      expect(_etat(conteneur).periodes, hasLength(1));
    });

    test('un refus de droits est rendu tel qu\'il se dit', () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 11)],
        erreurEcriture: ErreurPeriodes.droits,
      );
      final (conteneur, controleur) = await _ouvrir(depot);

      final resultat = await controleur.verrouiller(
        _etat(conteneur).periodes.single,
      );

      expect(resultat.reussi, isFalse);
      expect(resultat.message, AppStrings.periodeRefusDroits);
    });

    test('une action rafraîchit la liste que lit « Mon mois »', () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 11)],
      );
      final dispos = FauxDisposRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 11)],
      );
      final (conteneur, controleur) = await _ouvrir(depot, dispos: dispos);

      conteneur.listen(periodesProvider, (_, _) {});
      await conteneur.read(periodesProvider.future);
      expect(dispos.lecturesPeriodes, 1);

      await controleur.verrouiller(_etat(conteneur).periodes.single);
      await conteneur.read(periodesProvider.future);

      expect(
        dispos.lecturesPeriodes,
        2,
        reason: 'sinon le sélecteur de « Mon mois » garde l\'état d\'avant',
      );
    });

    test('relire jette les comptes de saisie en même temps que la liste',
        () async {
      final depot = FauxPeriodesRepository(
        periodes: <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 11)],
      );
      final (conteneur, controleur) = await _ouvrir(depot);

      conteneur.listen(
        tauxSaisieProvider((annee: 2026, mois: 11)),
        (_, _) {},
      );
      await conteneur.read(tauxSaisieProvider((annee: 2026, mois: 11)).future);
      expect(depot.comptages, 1);

      await controleur.rafraichir();
      await conteneur.read(tauxSaisieProvider((annee: 2026, mois: 11)).future);

      expect(depot.lectures, 2);
      expect(depot.comptages, 2);
    });
  });
}
