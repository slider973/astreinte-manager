import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/features/abonnement/data/abonnement_repository.dart';
import 'package:astreinte_sp/features/abonnement/domain/abonnement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatutAbonnement', () {
    test('lit les cinq valeurs de subscription_status', () {
      expect(StatutAbonnement.depuisSql('trialing'), StatutAbonnement.essai);
      expect(StatutAbonnement.depuisSql('active'), StatutAbonnement.actif);
      expect(
        StatutAbonnement.depuisSql('past_due'),
        StatutAbonnement.retardPaiement,
      );
      expect(
        StatutAbonnement.depuisSql('suspended'),
        StatutAbonnement.suspendu,
      );
      expect(StatutAbonnement.depuisSql('cancelled'), StatutAbonnement.resilie);
    });

    test('un statut inconnu ne met jamais une caserne en lecture seule', () {
      // Une valeur qu'on ne comprend pas ne doit pas faire croire à une
      // suspension : c'est la base qui tranche (`station_writable`).
      expect(StatutAbonnement.depuisSql('mystere'), StatutAbonnement.essai);
      expect(StatutAbonnement.depuisSql(null), StatutAbonnement.essai);
      expect(StatutAbonnement.depuisSql(null).lectureSeule, isFalse);
    });

    test('seuls suspendu et résilié sont en lecture seule', () {
      expect(StatutAbonnement.suspendu.lectureSeule, isTrue);
      expect(StatutAbonnement.resilie.lectureSeule, isTrue);
      // Un retard de paiement laisse écrire : quatorze jours avant bascule.
      expect(StatutAbonnement.retardPaiement.lectureSeule, isFalse);
      expect(StatutAbonnement.essai.lectureSeule, isFalse);
      expect(StatutAbonnement.actif.lectureSeule, isFalse);
    });
  });

  group('Abonnement', () {
    final maintenant = DateTime(2026, 9, 21, 10);

    test('lit la réponse de l\'Edge Function', () {
      final abonnement = Abonnement.depuisJson(const <String, dynamic>{
        'status': 'active',
        'plan': 'yearly',
        'trial_ends_at': '2026-11-20T00:00:00Z',
        'current_period_end': '2027-09-21T00:00:00Z',
        'has_customer': true,
      });

      expect(abonnement.statut, StatutAbonnement.actif);
      expect(abonnement.formule, FormuleAbonnement.annuelle);
      expect(abonnement.possedeClient, isTrue);
      expect(abonnement.finPeriode, isNotNull);
    });

    test('une ligne vide reste lisible, sans date inventée', () {
      final abonnement = Abonnement.depuisJson(const <String, dynamic>{
        'status': 'trialing',
      });

      expect(abonnement.statut, StatutAbonnement.essai);
      expect(abonnement.formule, isNull);
      expect(abonnement.dateCle, isNull);
      expect(abonnement.possedeClient, isFalse);
    });

    test('compte les jours d\'essai restants, arrondis au jour supérieur', () {
      final abonnement = Abonnement(
        statut: StatutAbonnement.essai,
        finEssai: DateTime(2026, 9, 24, 12),
      );

      // 3 jours et 2 heures : on annonce 4 jours, jamais 3 — un essai qui
      // finit « dans 3 jours » alors qu'il reste une nuit de plus est un
      // mensonge du mauvais côté.
      expect(abonnement.joursEssaiRestants(maintenant: maintenant), 4);
      expect(abonnement.essaiExpire(maintenant: maintenant), isFalse);
    });

    test('un essai passé est vu comme expiré, même sans suspension', () {
      // La tâche quotidienne n'a pas encore tourné : cette fenêtre existe, et
      // l'écran ne doit ni mentir ni paniquer.
      final abonnement = Abonnement(
        statut: StatutAbonnement.essai,
        finEssai: DateTime(2026, 9),
      );

      expect(abonnement.essaiExpire(maintenant: maintenant), isTrue);
      expect(abonnement.joursEssaiRestants(maintenant: maintenant), 0);
    });

    test('hors essai, il n\'y a pas de jours restants', () {
      const abonnement = Abonnement(statut: StatutAbonnement.actif);
      expect(abonnement.joursEssaiRestants(), isNull);
      expect(abonnement.essaiExpire(), isFalse);
    });

    test('la bascule d\'un impayé tombe quatorze jours après la période', () {
      final abonnement = Abonnement(
        statut: StatutAbonnement.retardPaiement,
        finPeriode: DateTime(2026, 11, 20),
      );

      // La même règle que `cron_suspend_subscriptions` (migration 0023).
      expect(abonnement.bascule, DateTime(2026, 12, 4));
    });

    test('aucune bascule hors du retard de paiement', () {
      final abonnement = Abonnement(
        statut: StatutAbonnement.actif,
        finPeriode: DateTime(2026, 11, 20),
      );
      expect(abonnement.bascule, isNull);
    });

    test('la date qui compte dépend de l\'état', () {
      final essai = Abonnement(
        statut: StatutAbonnement.essai,
        finEssai: DateTime(2026, 11, 20),
        finPeriode: DateTime(2027),
      );
      final actif = Abonnement(
        statut: StatutAbonnement.actif,
        finEssai: DateTime(2026, 11, 20),
        finPeriode: DateTime(2027),
      );

      expect(essai.dateCle, DateTime(2026, 11, 20));
      expect(actif.dateCle, DateTime(2027));
    });
  });

  group('TarifsAbonnement', () {
    test('les tarifs par défaut sont ceux du PRD', () {
      expect(TarifsAbonnement.parDefaut.mensuelCentimes, 1200);
      expect(TarifsAbonnement.parDefaut.annuelCentimes, 12000);
    });

    test('l\'économie annuelle est calculée, jamais écrite', () {
      expect(TarifsAbonnement.parDefaut.economieCentimes, 2400);

      // Un tarif annuel sans remise ne doit rien annoncer.
      const sansRemise = TarifsAbonnement(
        mensuelCentimes: 1000,
        annuelCentimes: 12000,
      );
      expect(sansRemise.economieCentimes, 0);
    });

    test('des tarifs absents retombent sur ceux du PRD', () {
      final tarifs = TarifsAbonnement.depuisJson(null);
      expect(tarifs, TarifsAbonnement.parDefaut);

      final partiels = TarifsAbonnement.depuisJson(const <String, dynamic>{
        'monthly': 1500,
      });
      expect(partiels.mensuelCentimes, 1500);
      expect(partiels.annuelCentimes, 12000);
    });
  });

  group('EtatAbonnement', () {
    test('sans configuration, on ne peut pas souscrire, et on le dit', () {
      const etat = EtatAbonnement.sansConfiguration;

      expect(etat.peutSouscrire, isFalse);
      // Les formules restent visibles : le tarif est une information.
      expect(etat.montreFormules, isTrue);
      expect(
        etat.raisonSouscriptionImpossible,
        AppStrings.abonnementBientotDisponible,
      );
    });

    test('une caserne abonnée ne voit plus les formules', () {
      const etat = EtatAbonnement(
        abonnement: Abonnement(statut: StatutAbonnement.actif),
        tarifs: TarifsAbonnement.parDefaut,
        configure: true,
        portailDisponible: true,
      );

      expect(etat.montreFormules, isFalse);
      expect(etat.peutSouscrire, isFalse);
      expect(
        etat.raisonSouscriptionImpossible,
        AppStrings.abonnementDejaAbonne,
      );
    });

    test('lit la réponse complète de l\'action « state »', () {
      final etat = EtatAbonnement.depuisJson(const <String, dynamic>{
        'configured': true,
        'portal_available': true,
        'prices': <String, dynamic>{
          'monthly': 1500,
          'yearly': 15000,
          'currency': 'eur',
        },
        'subscription': <String, dynamic>{
          'status': 'past_due',
          'plan': 'monthly',
          'current_period_end': '2026-11-20T00:00:00Z',
          'has_customer': true,
        },
      });

      expect(etat.configure, isTrue);
      expect(etat.portailDisponible, isTrue);
      expect(etat.tarifs.mensuelCentimes, 1500);
      expect(etat.abonnement.statut, StatutAbonnement.retardPaiement);
      expect(etat.peutSouscrire, isTrue);
    });

    test('une caserne sans ligne d\'abonnement est lue comme en essai', () {
      final etat = EtatAbonnement.depuisJson(const <String, dynamic>{
        'configured': false,
        'subscription': null,
      });

      expect(etat.abonnement, Abonnement.sansLigne);
      expect(etat.abonnement.statut, StatutAbonnement.essai);
    });
  });

  group('AppStrings.abonnementMontant', () {
    test('écrit un montant sans centimes quand ils sont nuls', () {
      expect(AppStrings.abonnementMontant(1200), '12 €');
      expect(AppStrings.abonnementMontant(12000), '120 €');
      expect(AppStrings.abonnementMontant(1250), '12,50 €');
      expect(AppStrings.abonnementMontant(1205), '12,05 €');
    });

    test('suit la devise annoncée par le serveur', () {
      expect(AppStrings.abonnementMontant(1200, devise: 'chf'), '12 CHF');
      expect(AppStrings.abonnementMontant(1200, devise: 'usd'), '12 \$');
    });
  });

  group('ErreurAbonnement', () {
    test('traduit les codes de l\'Edge Function', () {
      expect(
        ErreurAbonnement.depuisCode('stripe_not_configured'),
        ErreurAbonnement.nonConfigure,
      );
      expect(ErreurAbonnement.depuisCode('not_admin'), ErreurAbonnement.droits);
      expect(
        ErreurAbonnement.depuisCode('already_subscribed'),
        ErreurAbonnement.dejaAbonne,
      );
      expect(
        ErreurAbonnement.depuisCode('no_customer'),
        ErreurAbonnement.sansClient,
      );
      expect(
        ErreurAbonnement.depuisCode('stripe_error'),
        ErreurAbonnement.prestataire,
      );
      expect(ErreurAbonnement.depuisCode(null), ErreurAbonnement.inconnue);
    });

    test('chaque erreur nomme le problème et la sortie', () {
      for (final erreur in ErreurAbonnement.values) {
        expect(erreur.message, isNotEmpty);
      }
      // « Pas configuré » ne doit pas ressembler à une panne.
      expect(
        ErreurAbonnement.nonConfigure.message,
        contains('fonctionne normalement'),
      );
    });
  });
}
