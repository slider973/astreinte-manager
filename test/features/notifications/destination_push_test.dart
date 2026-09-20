import 'package:astreinte_sp/features/notifications/domain/destination_push.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Liens publics des notifications (WORKFLOWS § 8)', () {
    test('/proposals ouvre les propositions', () {
      expect(
        destinationInterne('/proposals', admin: false),
        '/?onglet=1',
      );
    });

    test('/schedule/<mois> ouvre le planning', () {
      expect(
        destinationInterne('/schedule/2026-10', admin: false),
        '/?onglet=2',
      );
    });

    test('/availability/<mois> ouvre le mois demandé', () {
      expect(
        destinationInterne('/availability/2026-10', admin: false),
        '/?onglet=0&mois=2026-10',
      );
    });

    test('/admin/schedule/<mois> n\'ouvre que pour un admin', () {
      expect(
        destinationInterne('/admin/schedule/2026-10', admin: true),
        '/admin/periodes',
      );
      expect(
        destinationInterne('/admin/schedule/2026-10', admin: false),
        isNull,
      );
    });

    test('un mois mal formé ne devient jamais une URL', () {
      expect(destinationInterne('/availability/2026-13', admin: false), isNull);
      expect(destinationInterne('/availability/octobre', admin: false), isNull);
      expect(destinationInterne('/schedule/2026', admin: false), isNull);
    });

    test('un lien inconnu ou vide ne mène nulle part', () {
      expect(destinationInterne(null, admin: true), isNull);
      expect(destinationInterne('', admin: true), isNull);
      expect(destinationInterne('/nimporte-quoi', admin: true), isNull);
    });

    test('un mois est valide de 01 à 12, et seulement', () {
      expect(periodeValide('2026-01'), isTrue);
      expect(periodeValide('2026-12'), isTrue);
      expect(periodeValide('2026-00'), isFalse);
      expect(periodeValide('2026-13'), isFalse);
      expect(periodeValide(null), isFalse);
    });
  });
}
