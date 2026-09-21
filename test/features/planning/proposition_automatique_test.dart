import 'dart:math';

import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/disponibilite_mois.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:astreinte_sp/features/planning/domain/proposition_automatique.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';

/// Octobre 2026 : 31 jours, samedis les 3, 10, 17, 24 et 31. Le même mois que
/// les autres tests du planning, et celui dont les unités de weekend sont
/// vérifiées depuis le ticket 011.
const int _annee = 2026;
const int _mois = 10;

/// Une chaîne de mois où seuls les jours nommés portent [code].
String _mois31(String code, Iterable<int> jours) {
  final cases = List<String>.filled(31, '.');
  for (final jour in jours) {
    cases[jour - 1] = code;
  }
  return cases.join();
}

/// Un membre disponible **partout**, de jour comme de nuit.
LigneMatrice _partout(
  String id,
  String nom, {
  int? maxAstreintes,
  int? maxWeekends,
  int astreintes = 0,
  int unitesWeekend = 0,
  int accepteesPrecedentes = 0,
}) => ligneMatrice(
  userId: id,
  nom: nom,
  jours: moisUniforme('D'),
  nuits: moisUniforme('D'),
  maxAstreintes: maxAstreintes,
  maxWeekends: maxWeekends,
  astreintes: astreintes,
  unitesWeekend: unitesWeekend,
  accepteesPrecedentes: accepteesPrecedentes,
);

PlanningMois _planning({
  required List<CreneauPlanning> creneaux,
  List<Attribution> attributions = const <Attribution>[],
}) => PlanningMois(
  planning: planningBrouillon,
  creneaux: creneaux,
  attributions: attributions,
);

PropositionAutomatique _proposer(
  PlanningMois planning,
  List<LigneMatrice> lignes,
) => PropositionAutomatique.construire(
  planning: planning,
  lignes: lignes,
  annee: _annee,
  mois: _mois,
);

/// Le premier jour du mois, de jour et de nuit, et rien d'autre : la plupart
/// des cas se jugent sur deux créneaux.
List<CreneauPlanning> _deuxCreneaux({int effectifRequis = 1}) =>
    <CreneauPlanning>[
      creneau(id: 'c-1-j', jour: 1, effectifRequis: effectifRequis),
      creneau(
        id: 'c-1-n',
        jour: 1,
        creneau: CreneauType.nuit,
        effectifRequis: effectifRequis,
      ),
    ];

void main() {
  group('L\'ordre de choix — docs/PRD.md § 6.4', () {
    test('le quota restant passe avant la charge des trois derniers mois, '
        'même quand les deux critères s\'opposent', () {
      // **Le cas construit du ticket.** Deux pompiers, et les deux critères se
      // contredisent :
      //   « large »  — 5 astreintes restantes, mais 9 acceptées depuis 3 mois ;
      //   « repose » — 1 astreinte restante, et aucune acceptée.
      // Le PRD tranche : le quota restant d'abord. C'est « large » qui part.
      final proposition = _proposer(
        _planning(creneaux: _deuxCreneaux()),
        <LigneMatrice>[
          _partout('large', 'Alard', maxAstreintes: 5, accepteesPrecedentes: 9),
          _partout('repose', 'Bernard', maxAstreintes: 1),
        ],
      );

      expect(
        proposition.choix.map((ChoixAutomatique c) => c.userId),
        <String>['large', 'large'],
        reason: 'son reste passe de 5 à 4 : il reste devant',
      );
    });

    test('à quota égal, le moins chargé des trois derniers mois passe '
        'devant', () {
      final proposition = _proposer(
        _planning(creneaux: _deuxCreneaux()),
        <LigneMatrice>[
          _partout('charge', 'Alard', maxAstreintes: 4, accepteesPrecedentes: 6),
          _partout('repose', 'Bernard', maxAstreintes: 4),
        ],
      );

      expect(proposition.choix.first.userId, 'repose');
      // Le second créneau revient à « charge » : « repose » a consommé une
      // astreinte et les deux restes ne sont plus égaux.
      expect(proposition.choix.last.userId, 'charge');
    });

    test('deux illimités se partagent le mois au lieu qu\'un seul le prenne '
        'tout entier', () {
      // Sans départage sur la charge du mois, le reste de deux illimités est
      // `null` des deux côtés, il ne bouge jamais, et l'ordre alphabétique
      // donnerait les soixante-deux créneaux au même pompier. C'est la clause
      // « puis aléatoire » du ticket, rendue reproductible (`design/018 § 3`).
      final proposition = _proposer(
        _planning(creneaux: creneauxDuMois(31)),
        <LigneMatrice>[
          _partout('alpha', 'Alard'),
          _partout('beta', 'Bernard'),
        ],
      );

      final parMembre = <String, int>{};
      for (final choix in proposition.choix) {
        parMembre[choix.userId] = (parMembre[choix.userId] ?? 0) + 1;
      }

      expect(proposition.attributions, 62);
      expect(parMembre['alpha'], 31);
      expect(parMembre['beta'], 31);
    });

    test('l\'ordre du mois est chronologique, le jour avant la nuit', () {
      final proposition = _proposer(
        _planning(creneaux: creneauxDuMois(3)),
        <LigneMatrice>[_partout('seul', 'Alard')],
      );

      expect(
        proposition.choix.map((ChoixAutomatique c) => c.creneauId),
        <String>['c-1-j', 'c-1-n', 'c-2-j', 'c-2-n', 'c-3-j', 'c-3-n'],
      );
    });
  });

  group('Les quotas ne se dépassent jamais', () {
    test('le plafond d\'astreintes arrête le remplissage', () {
      final proposition = _proposer(
        _planning(creneaux: creneauxDuMois(31)),
        <LigneMatrice>[_partout('borne', 'Alard', maxAstreintes: 3)],
      );

      expect(proposition.attributions, 3);
      expect(proposition.creneauxRemplis, 3);
      expect(proposition.creneauxDecouverts, 59);
    });

    test('un plafond déjà atteint avant l\'appui ne se creuse pas', () {
      // Le membre tient déjà trois astreintes pour un plafond de trois : la
      // machine ne le désigne plus. Elle ne lui retire rien non plus.
      final proposition = _proposer(
        _planning(
          creneaux: creneauxDuMois(3),
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'plein'),
            Attribution(id: 'a2', creneauId: 'c-1-n', userId: 'plein'),
            Attribution(id: 'a3', creneauId: 'c-2-j', userId: 'plein'),
          ],
        ),
        <LigneMatrice>[
          _partout('plein', 'Alard', maxAstreintes: 3, astreintes: 3),
        ],
      );

      expect(proposition.vide, isTrue);
      expect(proposition.creneauxDecouverts, 3);
      expect(proposition.creneauxRemplis, 0);
    });

    test('un reste négatif — l\'admin a dépassé à la main — n\'est jamais '
        'aggravé', () {
      final proposition = _proposer(
        _planning(
          creneaux: creneauxDuMois(3),
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'au-dela'),
            Attribution(id: 'a2', creneauId: 'c-1-n', userId: 'au-dela'),
            Attribution(id: 'a3', creneauId: 'c-2-j', userId: 'au-dela'),
          ],
        ),
        <LigneMatrice>[
          _partout('au-dela', 'Alard', maxAstreintes: 2, astreintes: 3),
        ],
      );

      expect(proposition.vide, isTrue);
    });

    test('le plafond de weekends exclut le samedi et laisse la semaine', () {
      // Un seul weekend accepté. Le samedi 3 et le dimanche 4 font **une**
      // unité : les deux passent. Le samedi 10 en ouvrirait une seconde : il
      // est refusé. Le lundi 5, lui, ne coûte aucun weekend.
      final creneaux = <CreneauPlanning>[
        creneau(id: 'c-3-j', jour: 3),
        creneau(id: 'c-4-j', jour: 4),
        creneau(id: 'c-5-j', jour: 5),
        creneau(id: 'c-10-j', jour: 10),
      ];

      final proposition = _proposer(
        _planning(creneaux: creneaux),
        <LigneMatrice>[_partout('weekend', 'Alard', maxWeekends: 1)],
      );

      expect(
        proposition.choix.map((ChoixAutomatique c) => c.creneauId),
        <String>['c-3-j', 'c-4-j', 'c-5-j'],
      );
      expect(
        proposition.decouverts.single.date,
        DateTime(_annee, _mois, 10),
      );
    });

    test('un weekend déjà entamé avant l\'appui ne coûte pas une seconde '
        'unité', () {
      // Le membre tient déjà le samedi 3 : le dimanche 4 est dans la même
      // unité, il passe malgré un plafond d'un seul weekend.
      final creneaux = <CreneauPlanning>[
        creneau(id: 'c-3-j', jour: 3),
        creneau(id: 'c-4-j', jour: 4),
      ];

      final proposition = _proposer(
        _planning(
          creneaux: creneaux,
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-3-j', userId: 'weekend'),
          ],
        ),
        <LigneMatrice>[
          _partout(
            'weekend',
            'Alard',
            maxWeekends: 1,
            astreintes: 1,
            unitesWeekend: 1,
          ),
        ],
      );

      expect(proposition.choix.single.creneauId, 'c-4-j');
    });
  });

  group('Absents et non-saisis', () {
    test('ni l\'absent ni celui qui n\'a rien saisi n\'est désigné', () {
      final proposition = _proposer(
        _planning(creneaux: _deuxCreneaux()),
        <LigneMatrice>[
          // Absent le 1er de jour, rien saisi le 1er de nuit.
          ligneMatrice(
            userId: 'absent',
            nom: 'Alard',
            jours: _mois31('A', <int>[1]),
            nuits: moisUniforme('.'),
          ),
          // Rien saisi nulle part.
          ligneMatrice(
            userId: 'muet',
            nom: 'Bernard',
            jours: moisUniforme('.'),
            nuits: moisUniforme('.'),
          ),
        ],
      );

      expect(proposition.vide, isTrue);
      expect(proposition.creneauxDecouverts, 2);
    });

    test('une disponibilité saisie par l\'admin vaut une disponibilité', () {
      // La minuscule dit seulement **qui** a saisi ; l'état est le même
      // (`CelluleMatrice`, ticket 016). Un chef qui a saisi pour un pompier
      // absent de l'application ne doit pas voir ce pompier ignoré par la
      // machine.
      final proposition = _proposer(
        _planning(creneaux: _deuxCreneaux()),
        <LigneMatrice>[
          ligneMatrice(
            userId: 'procuration',
            nom: 'Alard',
            jours: _mois31('d', <int>[1]),
            nuits: _mois31('d', <int>[1]),
          ),
        ],
      );

      expect(proposition.attributions, 2);
    });
  });

  group('Rien de ce qui a été fait à la main ne bouge', () {
    test('un créneau déjà pourvu n\'ouvre aucune place', () {
      final proposition = _proposer(
        _planning(
          creneaux: _deuxCreneaux(),
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'manuel'),
          ],
        ),
        <LigneMatrice>[
          _partout('manuel', 'Alard', astreintes: 1),
          _partout('autre', 'Bernard'),
        ],
      );

      // Seul le créneau de nuit est rempli. Celui de jour n'est pas touché, et
      // le pompier qui y était reste le seul qui y soit.
      expect(proposition.choix.single.creneauId, 'c-1-n');
      expect(
        proposition.choix.any(
          (ChoixAutomatique c) => c.creneauId == 'c-1-j',
        ),
        isFalse,
      );
      // Et le créneau déjà pourvu ne compte pas comme « rempli » : le chiffre
      // annoncé est ce que l'appui change.
      expect(proposition.creneauxRemplis, 1);
    });

    test('un créneau à deux places dont une est tenue n\'en reçoit qu\'une', () {
      final proposition = _proposer(
        _planning(
          creneaux: <CreneauPlanning>[
            creneau(id: 'c-1-j', jour: 1, effectifRequis: 2),
          ],
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'manuel'),
          ],
        ),
        <LigneMatrice>[
          _partout('manuel', 'Alard', astreintes: 1),
          _partout('renfort', 'Bernard'),
          _partout('troisieme', 'Colin'),
        ],
      );

      expect(proposition.attributions, 1);
      expect(proposition.choix.single.userId, 'renfort');
      expect(proposition.creneauxRemplis, 1);
    });

    test('le pompier déjà attribué à un créneau n\'y est pas repris', () {
      final proposition = _proposer(
        _planning(
          creneaux: <CreneauPlanning>[
            creneau(id: 'c-1-j', jour: 1, effectifRequis: 2),
          ],
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'seul'),
          ],
        ),
        <LigneMatrice>[_partout('seul', 'Alard', astreintes: 1)],
      );

      // Personne d'autre n'est disponible : le créneau reste incomplet plutôt
      // que de compter deux fois la même personne.
      expect(proposition.vide, isTrue);
      expect(proposition.decouverts.single.pourvus, 1);
      expect(proposition.decouverts.single.requis, 2);
    });
  });

  group('Un créneau qui demande plusieurs personnes', () {
    test('reçoit autant de pompiers différents que son effectif requis', () {
      final proposition = _proposer(
        _planning(
          creneaux: <CreneauPlanning>[
            creneau(id: 'c-1-j', jour: 1, effectifRequis: 3),
          ],
        ),
        <LigneMatrice>[
          _partout('a', 'Alard'),
          _partout('b', 'Bernard'),
          _partout('c', 'Colin'),
          _partout('d', 'Dubois'),
        ],
      );

      expect(proposition.attributions, 3);
      expect(
        proposition.choix.map((ChoixAutomatique c) => c.userId).toSet().length,
        3,
        reason: 'trois pompiers distincts, jamais le même trois fois',
      );
      expect(proposition.creneauxRemplis, 1);
      expect(proposition.decouverts, isEmpty);
    });

    test('un créneau à zéro requis n\'appelle personne', () {
      final proposition = _proposer(
        _planning(
          creneaux: <CreneauPlanning>[
            creneau(id: 'c-1-j', jour: 1, effectifRequis: 0),
          ],
        ),
        <LigneMatrice>[_partout('a', 'Alard')],
      );

      expect(proposition.vide, isTrue);
      expect(proposition.decouverts, isEmpty);
      expect(proposition.creneauxRemplis, 0);
    });
  });

  group('Le récapitulatif', () {
    test('compte les créneaux remplis, les astreintes et ce qui reste à '
        'découvert', () {
      // Quatre créneaux, un seul candidat disponible et plafonné à deux
      // astreintes : deux créneaux se remplissent, deux restent vides.
      final creneaux = <CreneauPlanning>[
        creneau(id: 'c-1-j', jour: 1),
        creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit),
        creneau(id: 'c-2-j', jour: 2),
        creneau(id: 'c-2-n', jour: 2, creneau: CreneauType.nuit),
      ];

      final proposition = _proposer(
        _planning(creneaux: creneaux),
        <LigneMatrice>[_partout('borne', 'Alard', maxAstreintes: 2)],
      );

      expect(proposition.creneauxRemplis, 2);
      expect(proposition.attributions, 2);
      expect(proposition.membresMobilises, 1);
      expect(proposition.creneauxDecouverts, 2);
      expect(
        proposition.decouverts.map((c) => c.date.day),
        <int>[2, 2],
        reason: 'les deux créneaux du 2, dans l\'ordre du mois',
      );
      expect(proposition.decouverts.first.creneau, CreneauType.jour);
      expect(proposition.decouverts.last.creneau, CreneauType.nuit);
    });

    test('un mois sans planning ou sans membre ne propose rien', () {
      expect(
        PropositionAutomatique.construire(
          planning: PlanningMois.vide(),
          lignes: <LigneMatrice>[_partout('a', 'Alard')],
          annee: _annee,
          mois: _mois,
        ).vide,
        isTrue,
      );
      expect(
        _proposer(
          _planning(creneaux: _deuxCreneaux()),
          const <LigneMatrice>[],
        ).vide,
        isTrue,
      );
    });

    test('le plan part dans l\'ordre du mois, prêt pour auto-propose', () {
      final proposition = _proposer(
        _planning(creneaux: creneauxDuMois(2)),
        <LigneMatrice>[_partout('a', 'Alard')],
      );

      expect(proposition.picks, <Map<String, String>>[
        <String, String>{'shift_id': 'c-1-j', 'user_id': 'a'},
        <String, String>{'shift_id': 'c-1-n', 'user_id': 'a'},
        <String, String>{'shift_id': 'c-2-j', 'user_id': 'a'},
        <String, String>{'shift_id': 'c-2-n', 'user_id': 'a'},
      ]);
    });
  });

  group('Sur une caserne de la taille du seed', () {
    // **Le critère d'acceptation du ticket**, joué sur une caserne qui a la
    // forme de `supabase/seed.sql` : huit membres, un mois de 31 jours, une
    // disponibilité sur deux, une absence sur dix, et les quatre premiers
    // membres plafonnés comme le seed les plafonne.
    //
    // Le tirage est pseudo-aléatoire à graine fixe : le cas est réaliste, et il
    // est le même à chaque exécution.
    List<LigneMatrice> caserne() {
      const plafondsAstreintes = <int?>[4, 6, null, 8, null, null, null, null];
      const plafondsWeekends = <int?>[1, 2, 1, null, null, null, null, null];
      final tirage = Random(42);

      return <LigneMatrice>[
        for (var membre = 0; membre < 8; membre++)
          ligneMatrice(
            userId: 'membre$membre',
            nom: 'Membre $membre',
            jours: _tirerMois(tirage),
            nuits: _tirerMois(tirage),
            maxAstreintes: plafondsAstreintes[membre],
            maxWeekends: plafondsWeekends[membre],
          ),
      ];
    }

    test('tout créneau qui a un candidat éligible est rempli', () {
      final lignes = caserne();
      final proposition = _proposer(
        _planning(creneaux: creneauxDuMois(31)),
        lignes,
      );

      // La charge finale de chaque membre, telle que le plan la laisse.
      final astreintes = <String, int>{};
      final unites = <String, Set<DateTime>>{};
      final prises = <String, Set<String>>{};
      for (final choix in proposition.choix) {
        astreintes[choix.userId] = (astreintes[choix.userId] ?? 0) + 1;
        final unite = uniteWeekend(choix.date);
        if (unite != null) {
          (unites[choix.userId] ??= <DateTime>{}).add(unite);
        }
        (prises[choix.userId] ??= <String>{}).add(choix.creneauId);
      }

      // **Aucun quota dépassé.**
      for (final ligne in lignes) {
        final posees = astreintes[ligne.userId] ?? 0;
        if (ligne.maxAstreintes != null) {
          expect(
            posees,
            lessThanOrEqualTo(ligne.maxAstreintes!),
            reason: '${ligne.userId} dépasse son plafond d\'astreintes',
          );
        }
        if (ligne.maxWeekends != null) {
          expect(
            unites[ligne.userId]?.length ?? 0,
            lessThanOrEqualTo(ligne.maxWeekends!),
            reason: '${ligne.userId} dépasse son plafond de weekends',
          );
        }
      }

      // **Aucun créneau abandonné alors que quelqu'un pouvait le tenir.** La
      // charge d'un membre ne fait que croître : s'il est encore sous son
      // plafond à la fin, il l'était aussi quand ce créneau a été examiné.
      for (final decouvert in proposition.decouverts) {
        final jour = decouvert.date.day;
        final type = decouvert.creneau;
        final creneauId = 'c-$jour-${type == CreneauType.jour ? 'j' : 'n'}';
        final unite = uniteWeekend(decouvert.date);

        for (final ligne in lignes) {
          final disponible =
              ligne.etatDe(jour, type) == DisponibiliteEtat.disponible;
          if (!disponible) continue;
          if (prises[ligne.userId]?.contains(creneauId) ?? false) continue;

          final souPlafond =
              ligne.maxAstreintes == null ||
              (astreintes[ligne.userId] ?? 0) < ligne.maxAstreintes!;
          final weekendLibre =
              unite == null ||
              ligne.maxWeekends == null ||
              (unites[ligne.userId]?.contains(unite) ?? false) ||
              (unites[ligne.userId]?.length ?? 0) < ligne.maxWeekends!;

          expect(
            souPlafond && weekendLibre,
            isFalse,
            reason:
                '${ligne.userId} pouvait tenir $creneauId : le créneau '
                'n\'aurait pas dû rester à découvert',
          );
        }
      }

      // Et le récapitulatif reste cohérent avec lui-même.
      expect(
        proposition.creneauxRemplis + proposition.creneauxDecouverts,
        62,
      );
    });
  });
}

/// Un mois tiré comme le seed le tire : disponible une fois sur deux, absent
/// une fois sur dix, muet le reste du temps.
String _tirerMois(Random tirage) => <String>[
  for (var jour = 0; jour < 31; jour++)
    switch (tirage.nextDouble()) {
      < 0.50 => 'D',
      < 0.60 => 'A',
      _ => '.',
    },
].join();
