import 'dart:io';

import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:flutter_test/flutter_test.dart';

/// Une ligne PostgREST telle que la rendrait `assignments` avec sa jointure.
Map<String, dynamic> _ligne({
  String id = 'a-1',
  String date = '2026-10-12',
  String slot = 'night',
  String statutPlanning = 'published',
  Object? proposeLe = '2026-09-20T18:30:00Z',
  int relances = 0,
}) => <String, dynamic>{
  'id': id,
  'status': 'proposed',
  'proposed_at': proposeLe,
  'reminder_count': relances,
  'last_reminder_at': null,
  'shifts': <String, dynamic>{
    'id': 'c-1',
    'date': date,
    'slot': slot,
    'schedule_id': 'plan-10',
    'schedules': <String, dynamic>{'id': 'plan-10', 'status': statutPlanning},
  },
};

void main() {
  group('Proposition — la lecture', () {
    test('elle lit le créneau et son planning sans rien inventer', () {
      final lue = Proposition.depuisJson(_ligne())!;

      expect(lue.id, 'a-1');
      expect(lue.creneauId, 'c-1');
      expect(lue.planningId, 'plan-10');
      expect(lue.jour, DateTime(2026, 10, 12));
      expect(lue.creneau, CreneauType.nuit);
      expect(lue.planningEtat, PlanningEtat.publie);
    });

    test('un jour est un jour local, jamais un instant UTC', () {
      // Une colonne `date` lue comme un horodatage reculerait d'un jour à
      // l'affichage à l'ouest de Greenwich.
      final lue = Proposition.depuisJson(_ligne(date: '2026-10-01'))!;
      expect(lue.jour.day, 1);
      expect(lue.jour.hour, 0);
    });

    test('une ligne sans créneau lisible est écartée, pas devinée', () {
      final sansCreneau = <String, dynamic>{'id': 'a-1', 'status': 'proposed'};
      expect(Proposition.depuisJson(sansCreneau), isNull);
    });

    test('les colonnes lues ne contiennent aucune étoile', () {
      expect(Proposition.colonnes, isNot(contains('*')));
      // Rien qui ressemble à une colonne que le client n'a pas à connaître.
      expect(Proposition.colonnes, isNot(contains('station_id')));
      expect(Proposition.colonnes, isNot(contains('was_available')));
    });

    test('le mois du créneau nomme le planning', () {
      final lue = Proposition.depuisJson(_ligne(date: '2026-11-03'))!;
      expect(lue.cleMois, '2026-11');
      expect(lue.libelleMois, 'Novembre 2026');
      expect(lue.nomMois, 'novembre');
    });
  });

  group('Proposition — l\'ordre du calendrier', () {
    test('par date, puis jour avant nuit', () {
      final jour = Proposition.depuisJson(
        _ligne(id: 'j', slot: 'day'),
      )!;
      final nuit = Proposition.depuisJson(_ligne(id: 'n'))!;
      final lendemain = Proposition.depuisJson(
        _ligne(id: 'l', date: '2026-10-13', slot: 'day'),
      )!;

      final liste = <Proposition>[lendemain, nuit, jour]
        ..sort((Proposition a, Proposition b) => a.comparer(b));

      expect(
        liste.map((Proposition p) => p.id),
        <String>['j', 'n', 'l'],
      );
    });
  });

  group('aplatir — les groupes de mois', () {
    Proposition p(String id, DateTime jour) => Proposition(
      id: id,
      creneauId: 'c-$id',
      planningId: 'plan',
      jour: jour,
      creneau: CreneauType.jour,
      planningEtat: PlanningEtat.publie,
      proposeeLe: DateTime(2026, 9, 20),
    );

    test('un en-tête par mois, et il porte son compte', () {
      final elements = aplatir(<Proposition>[
        p('nov', DateTime(2026, 11, 3)),
        p('oct-19', DateTime(2026, 10, 19)),
        p('oct-12', DateTime(2026, 10, 12)),
      ]);

      expect(elements, hasLength(5));
      expect(elements.first, isA<EnteteMois>());

      final entetes = elements.whereType<EnteteMois>().toList();
      expect(entetes.map((EnteteMois e) => e.cle), <String>[
        '2026-10',
        '2026-11',
      ]);
      expect(entetes.map((EnteteMois e) => e.compte), <int>[2, 1]);
      // Le premier en-tête n'a pas besoin du grand écart du dessus.
      expect(entetes.first.premier, isTrue);
      expect(entetes.last.premier, isFalse);
    });

    test('une liste vide n\'invente pas d\'en-tête', () {
      expect(aplatir(const <Proposition>[]), isEmpty);
    });
  });

  group('La charge utile d\'une réponse', () {
    /// **Le garde-fou du ticket, au niveau du source.**
    ///
    /// `assignments_member_transition` compare l'avant et l'après en dehors
    /// d'une liste blanche de quatre colonnes : une sérialisation complète du
    /// modèle ferait échouer la requête entière, même à valeurs identiques
    /// (`docs/SCHEMA.md § 4`, `design/021 § 3`).
    String code(String chemin) => File(chemin)
        .readAsLinesSync()
        .where((String ligne) => !ligne.trimLeft().startsWith('//'))
        .join('\n');

    final source = code(
      'lib/features/propositions/data/propositions_repository.dart',
    );
    final domaine = code(
      'lib/features/propositions/domain/proposition.dart',
    );

    /// Le corps de `repondre`, seul endroit de l'application qui écrit dans
    /// `assignments`.
    String corpsDeRepondre() {
      // `lastIndexOf` : la signature apparaît deux fois, dans l'interface
      // puis dans l'implémentation. C'est la seconde qui écrit.
      final debut = source.lastIndexOf('Future<ResultatReponse> repondre(');
      expect(debut, greaterThan(0));
      final fin = source.indexOf('Future<PlanningEtat?> etatPlanning', debut);
      expect(fin, greaterThan(debut));
      return source.substring(debut, fin);
    }

    test('aucun modèle de la fonctionnalité ne sait se sérialiser', () {
      expect(domaine, isNot(contains('toJson')));
      expect(source, isNot(contains('toJson')));
    });

    test('le dépôt n\'écrit que deux colonnes, jamais l\'horodatage', () {
      final ecrites = RegExp(r"'([a-z_]+)'")
          .allMatches(corpsDeRepondre())
          .map((RegExpMatch m) => m.group(1))
          .toSet();

      expect(ecrites, containsAll(<String>['status', 'decline_reason']));
      // Les colonnes que la base pose elle-même, et celles qu'un membre ne
      // fait jamais varier.
      for (final interdite in <String>[
        'responded_at',
        'proposed_at',
        'station_id',
        'was_available',
        'reminder_count',
        'replaced_by',
        'updated_at',
      ]) {
        expect(
          ecrites,
          isNot(contains(interdite)),
          reason: '$interdite ne doit jamais partir dans une charge utile.',
        );
      }
    });

    test('la mise à jour est conditionnée au statut « proposed »', () {
      // Sans cette condition, une attribution déjà annulée déclencherait
      // `invalid transition` et l'écran verrait une panne là où il y a une
      // nouvelle.
      expect(corpsDeRepondre(), contains(".eq('status', 'proposed')"));
    });
  });
}
