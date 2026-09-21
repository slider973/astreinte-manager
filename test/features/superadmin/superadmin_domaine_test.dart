import 'package:astreinte_sp/core/caserne/etat_caserne.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/superadmin/data/superadmin_repository.dart';
import 'package:astreinte_sp/features/superadmin/domain/caserne_supervisee.dart';
import 'package:flutter_test/flutter_test.dart';

/// Une ligne de `super_admin_stations()`, telle que PostgREST la rend.
Map<String, dynamic> _ligne({
  Object? writable = true,
  Object? status = 'trialing',
  Object? publie = '2026-10-18T09:00:00+00:00',
  Object? annee = 2026,
  Object? mois = 11,
}) => <String, dynamic>{
  'station_id': 'aaaaaaaa-0000-4000-8000-000000000001',
  'name': '  CIS Saint-Martin  ',
  'slug': 'saint-martin',
  'timezone': 'Europe/Paris',
  'created_at': '2026-03-03T08:00:00+00:00',
  'active_members': 9,
  'active_admins': 1,
  'pending_invites': 0,
  'status': status,
  'trial_ends_at': '2026-11-20T22:59:59+00:00',
  'suspended_at': null,
  'writable': writable,
  'last_published_at': publie,
  'last_published_year': annee,
  'last_published_month': mois,
};

void main() {
  group('CaserneSupervisee', () {
    test('lit les faits d\'une ligne de super_admin_stations', () {
      final caserne = CaserneSupervisee.depuisJson(_ligne());

      expect(caserne.nom, 'CIS Saint-Martin');
      expect(caserne.membresActifs, 9);
      expect(caserne.adminsActifs, 1);
      expect(caserne.statut, StatutAbonnement.essai);
      expect(caserne.ecriture, isTrue);
      expect(caserne.dernierPlanningMois, 11);
      expect(caserne.aUnPlanningPublie, isTrue);
    });

    test('une caserne sans planning publié n\'en invente pas un', () {
      final caserne = CaserneSupervisee.depuisJson(
        _ligne(publie: null, annee: null, mois: null),
      );

      expect(caserne.aUnPlanningPublie, isFalse);
      expect(caserne.dernierPlanningLe, isNull);
    });

    // `writable` vient de `station_writable()`, la seule définition du droit
    // d'écrire : l'interface ne peut pas la contredire (`design/030 § 1`).
    test('writable fait autorité sur le statut', () {
      final caserne = CaserneSupervisee.depuisJson(
        _ligne(writable: false, status: 'past_due'),
      );

      expect(caserne.ecriture, isFalse);
      expect(caserne.statut, StatutAbonnement.retardPaiement);
    });

    test('writable absent : on relit le statut plutôt que de supposer', () {
      expect(
        CaserneSupervisee.depuisJson(
          _ligne(writable: null, status: 'suspended'),
        ).ecriture,
        isFalse,
      );
      expect(
        CaserneSupervisee.depuisJson(
          _ligne(writable: null, status: 'active'),
        ).ecriture,
        isTrue,
      );
    });

    test('une caserne sans administrateur est signalée', () {
      final caserne = CaserneSupervisee.depuisJson(<String, dynamic>{
        ..._ligne(),
        'active_admins': 0,
        'active_members': 0,
      });

      expect(caserne.sansAdministrateur, isTrue);
      expect(caserne.invitationEnRoute, isFalse);
    });

    test('une invitation en attente change le message, pas le défaut', () {
      final caserne = CaserneSupervisee.depuisJson(<String, dynamic>{
        ..._ligne(),
        'active_admins': 0,
        'pending_invites': 1,
      });

      expect(caserne.sansAdministrateur, isTrue);
      expect(caserne.invitationEnRoute, isTrue);
    });
  });

  // La forme rendue par `super_admin_create_station` n'est **pas** celle d'une
  // ligne de `super_admin_stations` : elle porte `id`, pas `station_id`.
  // Confondre les deux annonçait un échec sur une caserne pourtant créée — vu
  // dans Chrome, et c'est ce test qui l'aurait attrapé.
  group('CaserneSupervisee.depuisCreation', () {
    test('lit la caserne que la fonction de création vient de rendre', () {
      final creee = CaserneSupervisee.depuisCreation(const <String, dynamic>{
        'id': 'dddddddd-0000-4000-8000-000000000001',
        'name': 'CIS Forêt-sur-Sèvre',
        'slug': 'cis-foret-sur-sevre',
        'timezone': 'Europe/Paris',
        'created_at': '2026-09-21T04:38:54+00:00',
      });

      expect(creee.id, 'dddddddd-0000-4000-8000-000000000001');
      expect(creee.nom, 'CIS Forêt-sur-Sèvre');
      expect(creee.slug, 'cis-foret-sur-sevre');
      // Ce qui se déduit : elle naît vide, en essai, et écrivable.
      expect(creee.membresActifs, 0);
      expect(creee.sansAdministrateur, isTrue);
      expect(creee.statut, StatutAbonnement.essai);
      expect(creee.ecriture, isTrue);
      expect(creee.aUnPlanningPublie, isFalse);
    });
  });

  group('PlanningSupervise', () {
    test('lit l\'avancement d\'un mois', () {
      final planning = PlanningSupervise.depuisJson(const <String, dynamic>{
        'year': 2026,
        'month': 11,
        'period_status': 'locked',
        'status': 'published',
        'published_at': '2026-10-18T09:00:00+00:00',
        'validated_at': null,
        'shifts': 60,
        'assignments': <String, dynamic>{'accepted': 48, 'proposed': 12},
      });

      expect(planning.mois, 11);
      expect(planning.etat, PlanningEtat.publie);
      expect(planning.periode, PeriodeEtat.verrouillee);
      expect(planning.creneaux, 60);
      expect(planning.compte(AttributionEtat.accepte), 48);
      expect(planning.compte(AttributionEtat.propose), 12);
      expect(planning.total, 60);
      expect(planning.valideLe, isNull);
    });

    test('les états sortent dans l\'ordre de l\'enum, pas celui du JSON', () {
      final planning = PlanningSupervise.depuisJson(const <String, dynamic>{
        'year': 2026,
        'month': 11,
        'period_status': 'locked',
        'status': 'published',
        'shifts': 3,
        'assignments': <String, dynamic>{'declined': 1, 'proposed': 2},
      });

      expect(planning.etatsPresents, const <AttributionEtat>[
        AttributionEtat.propose,
        AttributionEtat.refuse,
      ]);
    });

    test('un planning sans attribution ne compte rien, et ne casse pas', () {
      final planning = PlanningSupervise.depuisJson(const <String, dynamic>{
        'year': 2026,
        'month': 12,
        'period_status': 'open',
        'status': 'draft',
        'shifts': 0,
        'assignments': <String, dynamic>{},
      });

      expect(planning.total, 0);
      expect(planning.etatsPresents, isEmpty);
      expect(planning.etat, PlanningEtat.brouillon);
    });
  });

  group('ErreurSuperAdmin', () {
    test('chaque code des fonctions SQL a sa phrase', () {
      expect(ErreurSuperAdmin.depuisCode('forbidden'), ErreurSuperAdmin.droits);
      expect(ErreurSuperAdmin.depuisCode('invalid_name'), ErreurSuperAdmin.nom);
      expect(
        ErreurSuperAdmin.depuisCode('invalid_timezone'),
        ErreurSuperAdmin.fuseau,
      );
      expect(
        ErreurSuperAdmin.depuisCode('reason_required'),
        ErreurSuperAdmin.raison,
      );
      expect(
        ErreurSuperAdmin.depuisCode('station_not_found'),
        ErreurSuperAdmin.caserneInconnue,
      );
    });

    test('un code inconnu ne reste pas muet', () {
      final erreur = ErreurSuperAdmin.depuisCode('quelque_chose_de_neuf');

      expect(erreur, ErreurSuperAdmin.inconnue);
      expect(erreur.message, isNotEmpty);
    });

    test('toutes les phrases sont écrites', () {
      for (final erreur in ErreurSuperAdmin.values) {
        expect(erreur.message, isNotEmpty, reason: erreur.name);
      }
    });
  });
}
