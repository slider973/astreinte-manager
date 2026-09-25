import 'dart:convert';

import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';

/// Le jour de référence de tous les tests : un jeudi.
final DateTime aujourdhui = DateTime(2026, 10, 15);

MesAstreintes _donnees(List<Astreinte> astreintes, {DateTime? luLe}) =>
    MesAstreintes(
      astreintes: astreintes,
      luLe: luLe ?? DateTime(2026, 10, 15, 8),
    );

void main() {
  group('Astreinte', () {
    test('lit une ligne PostgREST sans inventer de colonne', () {
      final lue = Astreinte.depuisJson(
        <String, dynamic>{
          'id': 'a-1',
          'shift_id': 'c-1',
          'status': 'accepted',
          'shifts': <String, dynamic>{
            'id': 'c-1',
            'date': '2026-10-17',
            'slot': 'night',
            'schedule_id': 'plan-10',
            'schedules': <String, dynamic>{
              'id': 'plan-10',
              'status': 'validated',
            },
          },
        },
        equipiers: <String>['Thomas B.'],
      );

      expect(lue, isNotNull);
      expect(lue!.id, 'a-1');
      expect(lue.creneauId, 'c-1');
      expect(lue.planningId, 'plan-10');
      expect(lue.jour, DateTime(2026, 10, 17));
      expect(lue.creneau, CreneauType.nuit);
      expect(lue.planningEtat, PlanningEtat.valide);
      expect(lue.equipiers, <String>['Thomas B.']);
    });

    test(
      'une attribution dont le créneau est masqué n\'est pas une erreur',
      () {
        expect(
          Astreinte.depuisJson(<String, dynamic>{'id': 'a-1', 'shifts': null}),
          isNull,
        );
      },
    );

    test('les équipiers ne sont connus qu\'une fois le planning validé', () {
      final publiee = astreinte(
        id: 'a-1',
        jour: DateTime(2026, 10, 17),
        planningEtat: PlanningEtat.publie,
      );
      expect(publiee.equipiersConnus, isFalse);

      final validee = astreinte(id: 'a-2', jour: DateTime(2026, 10, 17));
      expect(validee.equipiersConnus, isTrue);
    });

    test('sur un mois archivé, les équipiers sont connus eux aussi', () {
      // L'écran remonte un an d'historique (`design/027 § 8.1`) et tout mois
      // révolu est archivé le 1er du mois suivant : sans ce cas, une garde
      // tenue en février afficherait « en attente de la validation »
      // indéfiniment (ticket 044).
      final archivee = astreinte(
        id: 'a-fevrier',
        jour: DateTime(2026, 2, 14),
        planningEtat: PlanningEtat.archive,
        equipiers: const <String>['Thomas B.'],
      );

      expect(archivee.equipiersConnus, isTrue);
      expect(caserneEntiereLisible(PlanningEtat.archive), isTrue);
      expect(caserneEntiereLisible(PlanningEtat.publie), isFalse);
      expect(caserneEntiereLisible(PlanningEtat.brouillon), isFalse);
    });

    test('la frontière du passé est le jour, pas l\'instant', () {
      // Une astreinte **de nuit** — le créneau par défaut du faux — le jour
      // même ne bascule pas dans les passées à 8 h du matin
      // (`design/027 § 7.2`).
      final ceSoir = astreinte(id: 'a-1', jour: DateTime(2026, 10, 15));
      expect(ceSoir.passee(DateTime(2026, 10, 15, 8)), isFalse);
      expect(ceSoir.passee(DateTime(2026, 10, 15, 23, 59)), isFalse);
      expect(ceSoir.passee(DateTime(2026, 10, 16)), isTrue);
    });

    test('l\'ordre est celui du calendrier : date, puis jour avant nuit', () {
      final nuit = astreinte(id: 'n', jour: DateTime(2026, 10, 17));
      final jour = astreinte(
        id: 'j',
        jour: DateTime(2026, 10, 17),
        creneau: CreneauType.jour,
      );
      final suivant = astreinte(id: 's', jour: DateTime(2026, 10, 18));

      final triees = <Astreinte>[suivant, nuit, jour]
        ..sort((Astreinte a, Astreinte b) => a.comparer(b));
      expect(triees.map((Astreinte a) => a.id).toList(), <String>[
        'j',
        'n',
        's',
      ]);
    });
  });

  group('MesAstreintes', () {
    test('les à venir montent, les passées descendent', () {
      final donnees = _donnees(<Astreinte>[
        astreinte(id: 'passe-1', jour: DateTime(2026, 10, 2)),
        astreinte(id: 'passe-2', jour: DateTime(2026, 10, 9)),
        astreinte(id: 'venir-1', jour: DateTime(2026, 10, 17)),
        astreinte(id: 'venir-2', jour: DateTime(2026, 11, 3)),
      ]);

      expect(
        donnees.aVenir(aujourdhui).map((Astreinte a) => a.id).toList(),
        <String>['venir-1', 'venir-2'],
      );
      // La plus récente d'abord : on regarde en arrière depuis aujourd'hui.
      expect(
        donnees.passees(aujourdhui).map((Astreinte a) => a.id).toList(),
        <String>['passe-2', 'passe-1'],
      );
    });

    test('range les astreintes du mois par jour, jour avant nuit', () {
      final donnees = _donnees(<Astreinte>[
        astreinte(id: 'nuit', jour: DateTime(2026, 10, 17)),
        astreinte(
          id: 'jour',
          jour: DateTime(2026, 10, 17),
          creneau: CreneauType.jour,
        ),
        astreinte(id: 'novembre', jour: DateTime(2026, 11, 3)),
      ]);

      final parJour = donnees.parJourDuMois(2026, 10);
      expect(parJour.keys, <int>[17]);
      expect(parJour[17]!.map((Astreinte a) => a.id).toList(), <String>[
        'jour',
        'nuit',
      ]);
    });

    test('l\'étendue du calendrier contient toujours le mois courant', () {
      final vide = _donnees(const <Astreinte>[]);
      final (DateTime premier, DateTime dernier) = vide.etendue(aujourdhui);
      expect(premier, DateTime(2026, 10));
      expect(dernier, DateTime(2026, 10));

      final large = _donnees(<Astreinte>[
        astreinte(id: 'a', jour: DateTime(2026, 8, 3)),
        astreinte(id: 'b', jour: DateTime(2026, 12, 24)),
      ]);
      final (DateTime debut, DateTime fin) = large.etendue(aujourdhui);
      expect(debut, DateTime(2026, 8));
      expect(fin, DateTime(2026, 12));
    });

    test('le calendrier s\'ouvre sur le mois de la prochaine astreinte', () {
      final donnees = _donnees(<Astreinte>[
        astreinte(id: 'passe', jour: DateTime(2026, 10, 2)),
        astreinte(id: 'venir', jour: DateTime(2026, 11, 3)),
      ]);
      expect(donnees.moisDouverture(aujourdhui), DateTime(2026, 11));

      // Rien à venir : le mois courant, faute de mieux.
      final passees = _donnees(<Astreinte>[
        astreinte(id: 'passe', jour: DateTime(2026, 10, 2)),
      ]);
      expect(passees.moisDouverture(aujourdhui), DateTime(2026, 10));
    });

    test('« jamais lu » distingue rien de pas encore lu', () {
      expect(const MesAstreintes().jamaisLu, isTrue);
      expect(_donnees(const <Astreinte>[]).jamaisLu, isFalse);
    });
  });

  group('aplatirAstreintes', () {
    test('groupe par mois, pose le repli, et le garde fermé', () {
      final elements = aplatirAstreintes(
        donnees: _donnees(<Astreinte>[
          astreinte(id: 'passe', jour: DateTime(2026, 9, 12)),
          astreinte(id: 'oct', jour: DateTime(2026, 10, 17)),
          astreinte(id: 'nov', jour: DateTime(2026, 11, 3)),
        ]),
        aujourdhui: aujourdhui,
        passeesOuvertes: false,
      );

      expect(elements, hasLength(5));
      expect(elements[0], isA<EnteteMoisAstreintes>());
      expect((elements[0] as EnteteMoisAstreintes).libelle, 'Octobre 2026');
      expect((elements[0] as EnteteMoisAstreintes).premier, isTrue);
      expect(elements[1], isA<LigneAstreinte>());
      expect((elements[2] as EnteteMoisAstreintes).libelle, 'Novembre 2026');
      expect(elements[3], isA<LigneAstreinte>());
      // Le repli est là, fermé, et l'en-tête de septembre n'est pas au-dessus
      // d'un contenu absent.
      expect(elements[4], isA<ReplisPassees>());
      expect((elements[4] as ReplisPassees).compte, 1);
      expect((elements[4] as ReplisPassees).ouvert, isFalse);
    });

    test('ouvert, le repli déroule les mois passés en ordre décroissant', () {
      final elements = aplatirAstreintes(
        donnees: _donnees(<Astreinte>[
          astreinte(id: 'aout', jour: DateTime(2026, 8, 2)),
          astreinte(id: 'sept', jour: DateTime(2026, 9, 12)),
        ]),
        aujourdhui: aujourdhui,
        passeesOuvertes: true,
      );

      expect(elements[0], isA<ReplisPassees>());
      expect((elements[1] as EnteteMoisAstreintes).libelle, 'Septembre 2026');
      expect((elements[2] as LigneAstreinte).astreinte.id, 'sept');
      expect((elements[2] as LigneAstreinte).passee, isTrue);
      expect((elements[3] as EnteteMoisAstreintes).libelle, 'Août 2026');
      expect((elements[4] as LigneAstreinte).astreinte.id, 'aout');
    });

    test('sans passées, aucun repli : un accordéon vide est un piège', () {
      final elements = aplatirAstreintes(
        donnees: _donnees(<Astreinte>[
          astreinte(id: 'oct', jour: DateTime(2026, 10, 17)),
        ]),
        aujourdhui: aujourdhui,
        passeesOuvertes: true,
      );

      expect(elements.whereType<ReplisPassees>(), isEmpty);
    });

    test('rien du tout rend une liste vide', () {
      expect(
        aplatirAstreintes(
          donnees: const MesAstreintes(),
          aujourdhui: aujourdhui,
          passeesOuvertes: false,
        ),
        isEmpty,
      );
    });
  });

  group('HeuresAffichage', () {
    test('la nuit est l\'intervalle complémentaire du jour', () {
      const heures = HeuresAffichage(debutJour: '08:00', finJour: '20:00');
      expect(heures.intervalle(CreneauType.jour), '08:00 – 20:00');
      expect(heures.intervalle(CreneauType.nuit), '20:00 – 08:00');
    });
  });

  group('CacheAstreintes', () {
    test('un aller-retour garde tout ce que l\'écran affiche', () {
      final donnees = MesAstreintes(
        astreintes: <Astreinte>[
          astreinte(
            id: 'a-1',
            planningId: 'plan-10',
            jour: DateTime(2026, 10, 17),
            equipiers: <String>['Thomas B.', 'Marie L.'],
          ),
          astreinte(
            id: 'a-2',
            jour: DateTime(2026, 11, 3),
            creneau: CreneauType.jour,
            planningEtat: PlanningEtat.publie,
          ),
        ],
        heures: const HeuresAffichage(debutJour: '08:00', finJour: '20:00'),
        luLe: DateTime(2026, 10, 15, 18, 42),
      );

      final relu = CacheAstreintesPartage.relire(
        _encode(CacheAstreintesPartage.composer(donnees)),
      );

      expect(relu, isNotNull);
      expect(relu!.astreintes, hasLength(2));
      expect(relu.astreintes.first.equipiers, <String>[
        'Thomas B.',
        'Marie L.',
      ]);
      expect(relu.astreintes.last.planningEtat, PlanningEtat.publie);
      // Les heures d'affichage sont dans le cache : sans elles, le détail
      // serait amputé hors ligne.
      expect(relu.heures.debutJour, '08:00');
      expect(relu.heures.finJour, '20:00');
      expect(relu.luLe, DateTime(2026, 10, 15, 18, 42));
    });

    test('un document d\'une autre version est ignoré, pas réparé', () {
      final document = CacheAstreintesPartage.composer(
        _donnees(<Astreinte>[
          astreinte(id: 'a-1', jour: DateTime(2026, 10, 17)),
        ]),
      )..['v'] = CacheAstreintesPartage.version + 1;

      expect(CacheAstreintesPartage.relire(_encode(document)), isNull);
    });

    test('un document illisible vaut un cache vide', () {
      expect(CacheAstreintesPartage.relire(null), isNull);
      expect(CacheAstreintesPartage.relire('pas du json'), isNull);
      expect(CacheAstreintesPartage.relire('[]'), isNull);
    });

    test('une entrée abîmée est écartée sans emporter les autres', () {
      final document = CacheAstreintesPartage.composer(
        _donnees(<Astreinte>[
          astreinte(id: 'a-1', jour: DateTime(2026, 10, 17)),
        ]),
      );
      (document['a'] as List<dynamic>).add(<String, dynamic>{'id': 'cassée'});

      final relu = CacheAstreintesPartage.relire(_encode(document));
      expect(relu!.astreintes, hasLength(1));
      expect(relu.astreintes.single.id, 'a-1');
    });

    test('la clé est préfixée par domaine, caserne et membre', () {
      expect(
        CacheAstreintesPartage.cleDe(stationId: 'st-1', userId: 'me'),
        'astreintes.cache.st-1.me',
      );
    });
  });
}

/// Encode comme le dépôt le fait avant d'écrire dans le stockage : le test
/// vérifie le **format rangé**, pas seulement l'objet en mémoire.
String _encode(Map<String, dynamic> document) => jsonEncode(document);
