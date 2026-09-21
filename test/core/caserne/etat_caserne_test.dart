import 'package:astreinte_sp/core/caserne/etat_caserne.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/banniere_caserne.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'horloge des tests : le 21 septembre 2026 à 10 h.
final DateTime _maintenant = DateTime(2026, 9, 21, 10);

EtatCaserne _essaiDans(int jours) => EtatCaserne(
  statut: StatutAbonnement.essai,
  ecriture: true,
  finEssai: _maintenant.add(Duration(days: jours)),
);

FaitCaserne? _fait(EtatCaserne? etat, {required bool admin}) => faitCaserne(
  etat: etat,
  admin: admin,
  maintenant: _maintenant,
  versAbonnement: () {},
);

void main() {
  group('EtatCaserne.depuisJson', () {
    test('lit les quatre faits de station_access', () {
      final etat = EtatCaserne.depuisJson(const <String, dynamic>{
        'station_id': 'a-1',
        'writable': false,
        'status': 'suspended',
        'trial_ends_at': '2026-11-20T00:00:00Z',
        'suspended_at': '2026-12-04T03:30:00Z',
      });

      expect(etat.statut, StatutAbonnement.suspendu);
      expect(etat.lectureSeule, isTrue);
      expect(etat.suspendueLe, isNotNull);
    });

    test('un statut inconnu ne met personne en lecture seule', () {
      // Le backend peut gagner un statut avant que la PWA soit redéployée.
      final etat = EtatCaserne.depuisJson(const <String, dynamic>{
        'writable': true,
        'status': 'grace_period',
      });

      expect(etat.statut, StatutAbonnement.essai);
      expect(etat.lectureSeule, isFalse);
    });

    test('sans `writable`, le statut décide — et jamais dans le doute', () {
      expect(
        EtatCaserne.depuisJson(const <String, dynamic>{
          'status': 'cancelled',
        }).lectureSeule,
        isTrue,
      );
      expect(
        EtatCaserne.depuisJson(const <String, dynamic>{}).lectureSeule,
        isFalse,
      );
    });

    test('ce qu\'on ne sait pas lire est une caserne qui écrit', () {
      expect(EtatCaserne.inconnue.lectureSeule, isFalse);
    });
  });

  group('Les jours d\'essai', () {
    test('sont arrondis au jour supérieur', () {
      final etat = EtatCaserne(
        statut: StatutAbonnement.essai,
        ecriture: true,
        finEssai: _maintenant.add(const Duration(days: 2, hours: 3)),
      );
      expect(etat.joursEssaiRestants(maintenant: _maintenant), 3);
    });

    test('n\'existent pas hors essai', () {
      const etat = EtatCaserne(statut: StatutAbonnement.actif, ecriture: true);
      expect(etat.joursEssaiRestants(maintenant: _maintenant), isNull);
      expect(etat.essaiExpire(maintenant: _maintenant), isFalse);
    });

    test('un essai dépassé se voit avant que la tâche ne tourne', () {
      expect(_essaiDans(-1).essaiExpire(maintenant: _maintenant), isTrue);
      expect(_essaiDans(-1).joursEssaiRestants(maintenant: _maintenant), 0);
    });
  });

  group('La bannière de caserne', () {
    test('rien tant que l\'état n\'est pas lu', () {
      expect(_fait(null, admin: true), isNull);
    });

    test(
      'suspendue : lecture seule, grise, pour le membre comme pour l\'admin',
      () {
        final membre = _fait(
          const EtatCaserne(statut: StatutAbonnement.suspendu, ecriture: false),
          admin: false,
        );
        expect(membre, isNotNull);
        expect(membre!.variante, AppBannerVariante.lectureSeule);
        // « Rien n'a été supprimé » est une promesse du produit (PRD § 6.6).
        expect(membre.banniere.detail, contains('Rien n\'a été supprimé'));
        // Un membre n'a pas de sortie : pas de bouton qui mène à une porte close.
        expect(membre.banniere.onAction, isNull);

        final admin = _fait(
          const EtatCaserne(statut: StatutAbonnement.suspendu, ecriture: false),
          admin: true,
        );
        expect(admin!.banniere.libelleAction, AppStrings.lectureSeuleAction);
        expect(admin.banniere.onAction, isNotNull);
      },
    );

    test('suspendue avec date : la bannière la nomme', () {
      final fait = _fait(
        EtatCaserne(
          statut: StatutAbonnement.suspendu,
          ecriture: false,
          suspendueLe: DateTime(2026, 9, 4),
        ),
        admin: false,
      );
      expect(fait!.banniere.texte, contains('4 septembre 2026'));
    });

    test('résiliée est en lecture seule comme suspendue', () {
      final fait = _fait(
        const EtatCaserne(statut: StatutAbonnement.resilie, ecriture: false),
        admin: true,
      );
      expect(fait!.variante, AppBannerVariante.lectureSeule);
    });

    test('un membre ne voit jamais l\'essai : il n\'a rien à y faire', () {
      expect(_fait(_essaiDans(2), admin: false), isNull);
      expect(_fait(_essaiDans(-1), admin: false), isNull);
    });

    test('au-delà de quatorze jours, aucune bannière', () {
      expect(_fait(_essaiDans(60), admin: true), isNull);
      expect(_fait(_essaiDans(15), admin: true), isNull);
    });

    test('à J-14, une information ; à J-3, l\'ocre', () {
      final quatorze = _fait(_essaiDans(14), admin: true);
      expect(quatorze!.variante, AppBannerVariante.information);
      expect(quatorze.banniere.texte, contains('il reste 14 jours'));
      expect(quatorze.banniere.texte, contains('5 octobre 2026'));

      expect(
        _fait(_essaiDans(4), admin: true)!.variante,
        AppBannerVariante.information,
      );

      final trois = _fait(_essaiDans(3), admin: true);
      expect(trois!.variante, AppBannerVariante.attention);
      expect(trois.banniere.texte, contains('il reste 3 jours'));
    });

    test('un jour restant se dit au singulier', () {
      expect(
        _fait(_essaiDans(1), admin: true)!.banniere.texte,
        contains('il reste 1 jour.'),
      );
    });

    test(
      'essai terminé, caserne pas encore suspendue : l\'écran ne ment pas',
      () {
        // La tâche de suspension passe une fois par jour : cette fenêtre existe.
        final fait = _fait(_essaiDans(-1), admin: true);
        expect(fait!.variante, AppBannerVariante.attention);
        expect(fait.banniere.texte, AppStrings.essaiTermine);
      },
    );

    test('la lecture seule l\'emporte sur toute échéance d\'essai', () {
      final fait = _fait(
        EtatCaserne(
          statut: StatutAbonnement.suspendu,
          ecriture: false,
          finEssai: _maintenant.add(const Duration(days: 2)),
        ),
        admin: true,
      );
      expect(fait!.variante, AppBannerVariante.lectureSeule);
    });
  });
}
