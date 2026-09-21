import 'dart:convert';

import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_planning_caserne.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/domain/planning_caserne.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_planning_caserne.dart';

/// Un jeudi 15 octobre 2026.
final DateTime _aujourdhui = DateTime(2026, 10, 15, 9);

void main() {
  group('assemblerJournees — la règle de visibilité', () {
    test('planning validé : toutes les journées, trous compris', () {
      final journees = assemblerJournees(
        etat: PlanningEtat.valide,
        parJour: <DateTime, List<CreneauCaserne>>{
          DateTime(2026, 10, 3): <CreneauCaserne>[
            creneauCaserne(
              id: 'c-3-jour',
              creneau: CreneauType.jour,
              noms: const <String>['Marie L.'],
            ),
            // Personne, mais deux personnes demandées : c'est un **trou**, et
            // c'est une information.
            creneauCaserne(id: 'c-3-nuit'),
          ],
          DateTime(2026, 10, 4): <CreneauCaserne>[
            // Personne, et personne demandé : la caserne ne veut personne, la
            // ligne n'a rien à dire.
            creneauCaserne(id: 'c-4-jour', creneau: CreneauType.jour, requis: 0),
            creneauCaserne(id: 'c-4-nuit', requis: 0),
          ],
        },
      );

      expect(journees, hasLength(1));
      expect(journees.single.date, DateTime(2026, 10, 3));
      expect(journees.single.creneaux, hasLength(2));
      expect(journees.single.creneaux.first.creneau, CreneauType.jour);
      expect(journees.single.creneaux.last.personne, isTrue);
    });

    test(
      'planning publié : **le tri se fait au créneau**, pas à la journée',
      () {
        // Le défaut vu dans Chrome : sur un samedi où le lecteur est de nuit,
        // le créneau de jour s'affichait « Personne n'est d'astreinte » alors
        // que quelqu'un y est sûrement — la RLS n'a simplement pas rendu la
        // ligne.
        final journees = assemblerJournees(
          etat: PlanningEtat.publie,
          parJour: <DateTime, List<CreneauCaserne>>{
            DateTime(2026, 11, 7): <CreneauCaserne>[
              creneauCaserne(id: 'c-7-jour', creneau: CreneauType.jour),
              creneauCaserne(id: 'c-7-nuit', moi: true),
            ],
            DateTime(2026, 11, 8): <CreneauCaserne>[
              creneauCaserne(id: 'c-8-jour', creneau: CreneauType.jour),
              creneauCaserne(id: 'c-8-nuit'),
            ],
          },
        );

        // Une seule journée, un seul créneau : le mien.
        expect(journees, hasLength(1));
        expect(journees.single.date, DateTime(2026, 11, 7));
        expect(journees.single.creneaux, hasLength(1));
        expect(journees.single.creneaux.single.id, 'c-7-nuit');
      },
    );

    test('les créneaux sont rangés jour avant nuit, les journées par date', () {
      final journees = assemblerJournees(
        etat: PlanningEtat.valide,
        parJour: <DateTime, List<CreneauCaserne>>{
          DateTime(2026, 10, 24): <CreneauCaserne>[
            creneauCaserne(id: 'c-24', noms: const <String>['Lucas B.']),
          ],
          DateTime(2026, 10, 3): <CreneauCaserne>[
            creneauCaserne(id: 'c-3-nuit', noms: const <String>['Marie L.']),
            creneauCaserne(
              id: 'c-3-jour',
              creneau: CreneauType.jour,
              noms: const <String>['Thomas M.'],
            ),
          ],
        },
      );

      expect(
        journees.map((JourneeCaserne j) => j.date),
        <DateTime>[DateTime(2026, 10, 3), DateTime(2026, 10, 24)],
      );
      expect(
        journees.first.creneaux.map((CreneauCaserne c) => c.creneau),
        <CreneauType>[CreneauType.jour, CreneauType.nuit],
      );
    });

    test(
      'planning archivé : le tableau du mois écoulé, trous compris',
      () {
        // La décision du ticket 044 : un mois archivé se lit comme le tableau
        // de garde punaisé au mur. `assignments_select_station_archived` rend
        // les gardes tenues par tout le monde, donc l'écran affiche le mois
        // entier — et un créneau que personne n'a tenu reste une information,
        // celle d'un trou qui n'a jamais été comblé.
        final journees = assemblerJournees(
          etat: PlanningEtat.archive,
          parJour: <DateTime, List<CreneauCaserne>>{
            DateTime(2026, 8, 3): <CreneauCaserne>[
              creneauCaserne(
                id: 'c-3-nuit',
                moi: true,
                noms: const <String>['Marie L.'],
              ),
            ],
            DateTime(2026, 8, 4): <CreneauCaserne>[
              // Personne n'a tenu cette garde : la journée s'affiche quand
              // même. Sur un planning seulement publié, elle serait masquée.
              creneauCaserne(id: 'c-4-nuit'),
            ],
          },
        );

        expect(
          journees.map((JourneeCaserne j) => j.date),
          <DateTime>[DateTime(2026, 8, 3), DateTime(2026, 8, 4)],
        );
        expect(journees.last.creneaux.single.personne, isTrue);
      },
    );

    test('un mois archivé est un mois complet, comme un mois validé', () {
      expect(
        moisPlanning(annee: 2026, mois: 8, etat: PlanningEtat.archive).complet,
        isTrue,
      );
      expect(
        moisPlanning(annee: 2026, mois: 11, etat: PlanningEtat.publie).complet,
        isFalse,
      );
    });
  });

  group('le mois d\'ouverture', () {
    test('le mois courant quand il a un planning', () {
      final mois = <MoisPlanning>[
        moisPlanning(annee: 2026, mois: 9),
        moisPlanning(annee: 2026, mois: 10),
        moisPlanning(annee: 2026, mois: 11),
      ];
      expect(moisDouverturePlanning(mois, _aujourdhui)?.cle, '2026-10');
    });

    test('sinon le premier à venir : le 28 octobre, on pense à novembre', () {
      final mois = <MoisPlanning>[
        moisPlanning(annee: 2026, mois: 9),
        moisPlanning(annee: 2026, mois: 11),
      ];
      expect(moisDouverturePlanning(mois, _aujourdhui)?.cle, '2026-11');
    });

    test('sinon le plus récent passé', () {
      final mois = <MoisPlanning>[
        moisPlanning(annee: 2026, mois: 8),
        moisPlanning(annee: 2026, mois: 9),
      ];
      expect(moisDouverturePlanning(mois, _aujourdhui)?.cle, '2026-09');
    });

    test(
      'les mois archivés restent atteignables, sans devenir le mois '
      'd\'ouverture',
      () {
        // Le 15 octobre, août et septembre sont archivés depuis le 1er
        // septembre et le 1er octobre. Ils restent dans la liste — c'est
        // l'historique du produit (`docs/PRD.md § 7.6`) — mais l'écran
        // s'ouvre sur le mois courant.
        final mois = <MoisPlanning>[
          moisPlanning(annee: 2026, mois: 8, etat: PlanningEtat.archive),
          moisPlanning(annee: 2026, mois: 9, etat: PlanningEtat.archive),
          moisPlanning(annee: 2026, mois: 10),
        ];
        expect(moisDouverturePlanning(mois, _aujourdhui)?.cle, '2026-10');

        // Et quand il ne reste que du passé, on ouvre sur le plus récent.
        expect(
          moisDouverturePlanning(mois.sublist(0, 2), _aujourdhui)?.cle,
          '2026-09',
        );
      },
    );

    test('aucun mois : aucun mois d\'ouverture', () {
      expect(moisDouverturePlanning(const <MoisPlanning>[], _aujourdhui), isNull);
    });
  });

  group('le cache local', () {
    test('un mois fait l\'aller-retour sans rien perdre', () {
      final planning = planningCaserne(
        mois: moisPlanning(annee: 2026, mois: 10),
        journees: <int, List<CreneauCaserne>>{
          3: <CreneauCaserne>[
            creneauCaserne(
              id: 'c-3',
              moi: true,
              noms: const <String>['Thomas M.'],
              anonymes: 1,
            ),
          ],
        },
        heures: const HeuresAffichage(debutJour: '08:00', finJour: '20:00'),
      );

      final relu = CachePlanningCasernePartage.relirePlanning(
        _encode(CachePlanningCasernePartage.composerPlanning(planning)),
      );

      expect(relu, isNotNull);
      expect(relu!.mois.cle, '2026-10');
      expect(relu.mois.etat, PlanningEtat.valide);
      expect(relu.heures.debutJour, '08:00');
      expect(relu.journees.single.creneaux.single.moi, isTrue);
      expect(relu.journees.single.creneaux.single.noms, <String>['Thomas M.']);
      expect(relu.journees.single.creneaux.single.anonymes, 1);
    });

    test(
      'l\'état du planning est gardé : le bloc d\'attente est juste hors ligne',
      () {
        final planning = planningCaserne(
          mois: moisPlanning(annee: 2026, mois: 11, etat: PlanningEtat.publie),
          journees: <int, List<CreneauCaserne>>{
            7: <CreneauCaserne>[creneauCaserne(id: 'c-7', moi: true)],
          },
        );

        final relu = CachePlanningCasernePartage.relirePlanning(
          _encode(CachePlanningCasernePartage.composerPlanning(planning)),
        );

        expect(relu!.complet, isFalse);
      },
    );

    test('un document d\'une autre version est ignoré, jamais réparé', () {
      expect(
        CachePlanningCasernePartage.relirePlanning(
          '{"v":99,"le":"2026-10-15T09:00:00Z","mois":{},"j":[]}',
        ),
        isNull,
      );
      expect(
        CachePlanningCasernePartage.relireMois('{"v":99,"m":[]}'),
        isNull,
      );
    });

    test('un cache abîmé vaut un cache vide', () {
      expect(CachePlanningCasernePartage.relirePlanning('{pas du json'), isNull);
      expect(CachePlanningCasernePartage.relireMois(null), isNull);
    });

    test('la liste des mois revient triée', () {
      final relu = CachePlanningCasernePartage.relireMois(
        _encode(
          CachePlanningCasernePartage.composerMois(<MoisPlanning>[
            moisPlanning(annee: 2027, mois: 1),
            moisPlanning(annee: 2026, mois: 11),
          ]),
        ),
      );
      expect(
        relu!.map((MoisPlanning m) => m.cle),
        <String>['2026-11', '2027-01'],
      );
    });

    test(
      'la mémoire de test range par caserne et par membre, comme la vraie',
      () async {
        final cache = CachePlanningCaserneMemoire();
        await cache.ecrireMois(
          stationId: 'caserne-a',
          userId: 'marie',
          mois: <MoisPlanning>[moisPlanning(annee: 2026, mois: 10)],
        );

        expect(
          await cache.lireMois(stationId: 'caserne-a', userId: 'thomas'),
          isNull,
        );
        expect(
          await cache.lireMois(stationId: 'caserne-b', userId: 'marie'),
          isNull,
        );
        expect(
          await cache.lireMois(stationId: 'caserne-a', userId: 'marie'),
          hasLength(1),
        );
      },
    );

    test('l\'effacement balaie **tous** les mois, pas un seul', () async {
      final cache = CachePlanningCaserneMemoire();
      await cache.ecrireMois(
        stationId: 'caserne-a',
        userId: 'marie',
        mois: <MoisPlanning>[moisPlanning(annee: 2026, mois: 10)],
      );
      for (final mois in <int>[10, 11, 12]) {
        await cache.ecrirePlanning(
          stationId: 'caserne-a',
          userId: 'marie',
          planning: planningCaserne(
            mois: moisPlanning(annee: 2026, mois: mois),
          ),
        );
      }
      expect(cache.clesGardees, hasLength(4));

      await cache.effacer(stationId: 'caserne-a', userId: 'marie');

      expect(cache.clesGardees, isEmpty);
    });
  });
}

String _encode(Map<String, dynamic> document) => jsonEncode(document);
