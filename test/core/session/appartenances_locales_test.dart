import 'dart:convert';

import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/appartenances_locales.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';

const Appartenance _adminDeLaCaserne = Appartenance(
  id: 'm-0',
  stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
  nomAffiche: 'Jean D.',
);

void main() {
  group('le document gardé', () {
    test('un aller-retour garde la caserne et le statut', () {
      final relu = AppartenancesLocalesPartagees.relire(
        jsonEncode(
          AppartenancesLocalesPartagees.composer(<Appartenance>[
            appartenanceMembre,
          ]),
        ),
      );

      expect(relu, hasLength(1));
      expect(relu.single.id, appartenanceMembre.id);
      expect(relu.single.stationId, appartenanceMembre.stationId);
      expect(relu.single.nomCaserne, 'CIS Saint-Martin');
      expect(relu.single.statut, StatutMembre.actif);
      expect(relu.single.nomAffiche, 'Marie L.');
    });

    test('un rôle qu\'on n\'a pas pu revérifier n\'accorde rien', () {
      final relu = AppartenancesLocalesPartagees.relire(
        jsonEncode(
          AppartenancesLocalesPartagees.composer(<Appartenance>[
            _adminDeLaCaserne,
          ]),
        ),
      );

      // Le chef de centre revient en simple membre : hors ligne, l'onglet
      // « Admin » n'ouvrirait que des listes vides et des formulaires qui
      // échouent.
      expect(relu.single.estAdmin, isFalse);
      expect(relu.single.role, RoleMembre.membre);
    });

    test('un document d\'une autre version ou illisible ne rend rien', () {
      final document = AppartenancesLocalesPartagees.composer(
        <Appartenance>[appartenanceMembre],
      )..['v'] = AppartenancesLocalesPartagees.version + 1;

      expect(AppartenancesLocalesPartagees.relire(jsonEncode(document)), isEmpty);
      expect(AppartenancesLocalesPartagees.relire(null), isEmpty);
      expect(AppartenancesLocalesPartagees.relire('pas du json'), isEmpty);
    });

    test('la clé est préfixée par domaine et par utilisateur', () {
      expect(
        AppartenancesLocalesPartagees.cleDe('me'),
        'session.appartenances.me',
      );
    });
  });

}
