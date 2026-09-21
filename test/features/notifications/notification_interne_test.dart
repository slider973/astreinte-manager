import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/features/notifications/domain/centre_providers.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_notifications.dart';

void main() {
  group('TypeNotification', () {
    test('les douze types de docs/SCHEMA.md § 1 sont couverts', () {
      const attendus = <String>{
        'invitation',
        'availability_reminder',
        'assignment_proposed',
        'assignment_reminder',
        'assignment_declined',
        'assignment_changed',
        'assignment_cancelled',
        'schedule_validated',
        'schedule_all_accepted',
        'late_responders',
        'subscription_trial_ending',
        'subscription_suspended',
      };

      final connus = <String>{
        for (final type in TypeNotification.values)
          if (type != TypeNotification.inconnu) type.valeurSql,
      };
      expect(connus, attendus);

      for (final valeur in attendus) {
        expect(
          TypeNotification.depuisSql(valeur),
          isNot(TypeNotification.inconnu),
          reason: '$valeur devrait être reconnu.',
        );
      }
    });

    test('un type que cette version ne connaît pas ne lève jamais', () {
      // Le backend peut en ajouter un avant que la PWA soit redéployée.
      expect(
        TypeNotification.depuisSql('assignment_swapped'),
        TypeNotification.inconnu,
      );
      expect(TypeNotification.depuisSql(null), TypeNotification.inconnu);
      expect(TypeNotification.depuisSql(''), TypeNotification.inconnu);
    });
  });

  group('NotificationInterne.depuisJson', () {
    test('lit les colonnes de la table et la destination de data', () {
      final lue = NotificationInterne.depuisJson(<String, dynamic>{
        'id': 'n-1',
        'type': 'assignment_proposed',
        'title': 'Une astreinte t\'est proposée',
        'body': 'Samedi 4 octobre, nuit.',
        'data': <String, dynamic>{
          'route': '/proposals',
          'type': 'assignment_proposed',
          'station_id': 'st-1',
          'period': '2026-10',
        },
        'read_at': null,
        'error': null,
        'created_at': '2026-09-20T07:00:00Z',
      });

      expect(lue.id, 'n-1');
      expect(lue.type, TypeNotification.astreinteProposee);
      expect(lue.route, '/proposals');
      expect(lue.periode, '2026-10');
      expect(lue.lue, isFalse);
      expect(lue.enEchec, isFalse);
      expect(lue.creeLe, DateTime.utc(2026, 9, 20, 7).toLocal());
    });

    test('une ligne bancale ne fait pas tomber la liste', () {
      final lue = NotificationInterne.depuisJson(<String, dynamic>{
        'id': 'n-2',
        'type': 'quelque_chose_de_neuf',
        'title': null,
        'body': null,
        'data': 'pas un objet',
        'read_at': 'pas une date',
        'created_at': null,
      });

      expect(lue.type, TypeNotification.inconnu);
      expect(lue.titre, isEmpty);
      expect(lue.route, isNull);
      expect(lue.lue, isFalse);
    });

    test('une ligne qui porte une erreur est signalée comme telle', () {
      final lue = NotificationInterne.depuisJson(<String, dynamic>{
        'id': 'n-3',
        'type': 'assignment_proposed',
        'title': 'Une astreinte t\'est proposée',
        'body': 'Samedi 4 octobre, nuit.',
        'data': <String, dynamic>{'route': '/proposals'},
        'error': 'fcm_unavailable',
        'created_at': '2026-09-20T07:00:00Z',
      });

      expect(lue.enEchec, isTrue);
    });
  });

  group('EtatCentre', () {
    test('compte les non-lues et les marque toutes d\'un coup', () {
      final etat = EtatCentre(
        notifications: <NotificationInterne>[
          notification(id: 'n-1'),
          notification(id: 'n-2'),
          notification(id: 'n-3', lueLe: DateTime(2026, 9, 19)),
        ],
      );

      expect(etat.nonLues, 2);
      expect(etat.vide, isFalse);

      final instant = DateTime(2026, 9, 20, 10);
      final toutes = etat.toutesLues(instant);
      expect(toutes.nonLues, 0);
      // La date de première lecture d'une ligne déjà lue n'est pas repoussée.
      expect(toutes.notifications.last.lueLe, DateTime(2026, 9, 19));
    });

    test('remplacer une ligne ne retrie pas la liste', () {
      final etat = EtatCentre(
        notifications: <NotificationInterne>[
          notification(id: 'n-1', creeLe: DateTime(2026, 9, 20)),
          notification(id: 'n-2', creeLe: DateTime(2026, 9, 18)),
        ],
      );

      final apres = etat.avec(
        etat.notifications.last.avecLecture(DateTime(2026, 9, 20, 10)),
      );
      expect(
        apres.notifications.map((n) => n.id).toList(),
        <String>['n-1', 'n-2'],
      );
      expect(apres.nonLues, 1);
    });
  });

  group('formaterInstantRelatif', () {
    final maintenant = DateTime(2026, 9, 20, 14, 30);

    test('dit l\'ancienneté comme on la dit à l\'oral', () {
      String dire(DateTime instant) =>
          formaterInstantRelatif(instant, maintenant: maintenant);

      expect(
        dire(maintenant.subtract(const Duration(seconds: 20))),
        AppStrings.instantMaintenant,
      );
      expect(
        dire(maintenant.subtract(const Duration(minutes: 20))),
        AppStrings.instantMinutes(20),
      );
      expect(
        dire(maintenant.subtract(const Duration(hours: 2))),
        AppStrings.instantHeures(2),
      );
      expect(dire(DateTime(2026, 9, 19, 23)), AppStrings.instantHier);
      expect(dire(DateTime(2026, 9, 17, 8)), AppStrings.instantJours(3));
    });

    test('repasse à la date au-delà d\'une semaine', () {
      expect(
        formaterInstantRelatif(DateTime(2026, 9, 5), maintenant: maintenant),
        formaterDateCourte(DateTime(2026, 9, 5)),
      );
      // Une autre année : la date porte l'année.
      expect(
        formaterInstantRelatif(DateTime(2025, 12, 24), maintenant: maintenant),
        formaterDateLongue(DateTime(2025, 12, 24)),
      );
    });

    test('une horloge en retard sur le serveur ne dit pas « il y a -3 min »', () {
      expect(
        formaterInstantRelatif(
          maintenant.add(const Duration(minutes: 3)),
          maintenant: maintenant,
        ),
        AppStrings.instantMaintenant,
      );
    });
  });
}
