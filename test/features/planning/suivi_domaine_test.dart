import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:astreinte_sp/features/planning/domain/recapitulatif_publication.dart';
import 'package:astreinte_sp/features/planning/domain/suivi_planning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';
import '../../support/faux_suivi.dart';

/// Un mois de référence, fixe : un test qui dépend de l'horloge de la machine
/// échoue une fois par jour, à l'heure où personne ne regarde.
const int _annee = 2026;
const int _mois = 10;
final DateTime _maintenant = DateTime(_annee, _mois, 20, 9);

PlanningMois _planning({
  required List<CreneauPlanning> creneaux,
  required List<Attribution> attributions,
}) => PlanningMois(
  planning: planningBrouillon,
  creneaux: creneaux,
  attributions: attributions,
);

SuiviPlanning _suivi({
  required List<CreneauPlanning> creneaux,
  required List<AttributionSuivi> attributions,
  int delaiRetardHeures = 72,
}) => SuiviPlanning(
  planning: planningPublie(),
  progression: ProgressionPlanning.vide,
  creneaux: creneaux,
  attributions: attributions,
  annee: _annee,
  mois: _mois,
  delaiRetardHeures: delaiRetardHeures,
);

void main() {
  group('Le récapitulatif de publication', () {
    test('sans réserve, il le dit et compte ce qui part', () {
      final recapitulatif = RecapitulatifPublication.construire(
        annee: _annee,
        mois: _mois,
        planning: _planning(
          creneaux: <CreneauPlanning>[
            creneau(id: 'c1', jour: 1),
            creneau(id: 'c2', jour: 2),
          ],
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c1', userId: 'aubry'),
            Attribution(id: 'a2', creneauId: 'c2', userId: 'aubry'),
          ],
        ),
        lignes: <LigneMatrice>[
          ligneMatrice(
            userId: 'aubry',
            nom: 'Aubry I.',
            jours: moisUniforme('D'),
            nuits: moisUniforme('D'),
            maxAstreintes: 5,
            astreintes: 2,
          ),
        ],
      );

      expect(recapitulatif.sansReserve, isTrue);
      expect(recapitulatif.creneaux, 2);
      expect(recapitulatif.attributions, 2);
      // **Des personnes, pas des attributions** : c'est le nombre de
      // téléphones qui vont sonner.
      expect(recapitulatif.membres, 1);
    });

    test('premier cas : les créneaux que personne ne couvre', () {
      final recapitulatif = RecapitulatifPublication.construire(
        annee: _annee,
        mois: _mois,
        planning: _planning(
          creneaux: <CreneauPlanning>[
            creneau(id: 'c1', jour: 1),
            creneau(id: 'c2', jour: 2, effectifRequis: 2),
            // Un effectif requis de zéro est **pourvu** d'office : « pas
            // d'astreinte ce jour-là » est une décision, pas un trou.
            creneau(id: 'c3', jour: 3, effectifRequis: 0),
          ],
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c2', userId: 'aubry'),
          ],
        ),
        lignes: <LigneMatrice>[
          ligneMatrice(
            userId: 'aubry',
            nom: 'Aubry I.',
            jours: moisUniforme('D'),
            nuits: moisUniforme('D'),
          ),
        ],
      );

      expect(recapitulatif.sansReserve, isFalse);
      expect(recapitulatif.nonPourvus, hasLength(2));
      expect(recapitulatif.nonPourvus.first.date, DateTime(_annee, _mois));
      expect(recapitulatif.nonPourvus.first.pourvus, 0);
      expect(recapitulatif.nonPourvus.last.pourvus, 1);
      expect(recapitulatif.nonPourvus.last.requis, 2);
    });

    test('deuxième cas : les membres au-delà de leur quota', () {
      final recapitulatif = RecapitulatifPublication.construire(
        annee: _annee,
        mois: _mois,
        planning: _planning(
          creneaux: <CreneauPlanning>[creneau(id: 'c1', jour: 1)],
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c1', userId: 'camus'),
          ],
        ),
        lignes: <LigneMatrice>[
          // Plafond dépassé : 5 astreintes pour 4.
          ligneMatrice(
            userId: 'camus',
            nom: 'Camus A.',
            jours: moisUniforme('D'),
            nuits: moisUniforme('D'),
            maxAstreintes: 4,
            astreintes: 5,
          ),
          // Plafond atteint, pas dépassé : ce n'est pas une réserve.
          ligneMatrice(
            userId: 'aubry',
            nom: 'Aubry I.',
            jours: moisUniforme('D'),
            nuits: moisUniforme('D'),
            maxAstreintes: 4,
            astreintes: 4,
          ),
          // **Un illimité n'est jamais hors quota.**
          ligneMatrice(
            userId: 'bernard',
            nom: 'Bernard L.',
            jours: moisUniforme('D'),
            nuits: moisUniforme('D'),
            astreintes: 30,
          ),
        ],
      );

      expect(recapitulatif.horsQuota, hasLength(1));
      expect(recapitulatif.horsQuota.single.nom, 'Camus A.');
      expect(recapitulatif.horsQuota.single.astreintesDepassees, isTrue);
      expect(recapitulatif.horsQuota.single.weekendsDepasses, isFalse);
    });

    test('le quota de weekends se dépasse tout seul', () {
      final recapitulatif = RecapitulatifPublication.construire(
        annee: _annee,
        mois: _mois,
        planning: _planning(
          creneaux: <CreneauPlanning>[creneau(id: 'c1', jour: 1)],
          attributions: const <Attribution>[],
        ),
        lignes: <LigneMatrice>[
          ligneMatrice(
            userId: 'roux',
            nom: 'Roux É.',
            jours: moisUniforme('D'),
            nuits: moisUniforme('D'),
            maxAstreintes: 20,
            astreintes: 4,
            maxWeekends: 1,
            unitesWeekend: 2,
          ),
        ],
      );

      expect(recapitulatif.horsQuota, hasLength(1));
      expect(recapitulatif.horsQuota.single.astreintesDepassees, isFalse);
      expect(recapitulatif.horsQuota.single.weekendsDepasses, isTrue);
    });

    test('troisième cas : les membres attribués hors disponibilité', () {
      final recapitulatif = RecapitulatifPublication.construire(
        annee: _annee,
        mois: _mois,
        planning: _planning(
          creneaux: <CreneauPlanning>[
            creneau(id: 'c1', jour: 1),
            creneau(id: 'c2', jour: 2, creneau: CreneauType.nuit),
          ],
          attributions: const <Attribution>[
            // `etaitDisponible` est **posé par la base**, jamais déclaré par
            // le client : le récapitulatif le lit, il ne le recalcule pas.
            Attribution(
              id: 'a1',
              creneauId: 'c1',
              userId: 'dupuis',
              etaitDisponible: false,
            ),
            Attribution(
              id: 'a2',
              creneauId: 'c2',
              userId: 'dupuis',
              etaitDisponible: false,
            ),
            Attribution(id: 'a3', creneauId: 'c1', userId: 'aubry'),
          ],
        ),
        lignes: <LigneMatrice>[
          ligneMatrice(
            userId: 'dupuis',
            nom: 'Dupuis T.',
            jours: moisUniforme('A'),
            nuits: moisUniforme('.'),
          ),
          ligneMatrice(
            userId: 'aubry',
            nom: 'Aubry I.',
            jours: moisUniforme('D'),
            nuits: moisUniforme('D'),
          ),
        ],
      );

      expect(recapitulatif.horsDispo, hasLength(1));
      expect(recapitulatif.horsDispo.single.nom, 'Dupuis T.');
      expect(recapitulatif.horsDispo.single.creneaux, hasLength(2));
      expect(recapitulatif.membres, 2);
    });
  });

  group('Le suivi d\'un planning', () {
    test('les journées sont ordonnées, jour avant nuit', () {
      final suivi = _suivi(
        creneaux: <CreneauPlanning>[
          creneau(id: 'c2n', jour: 2, creneau: CreneauType.nuit),
          creneau(id: 'c1j', jour: 1),
          creneau(id: 'c2j', jour: 2),
        ],
        attributions: const <AttributionSuivi>[],
      );

      final journees = suivi.journees();
      expect(journees.map((JourneeSuivi j) => j.date.day), <int>[1, 2]);
      expect(
        journees.last.creneaux.map((CreneauSuivi c) => c.creneau.creneau),
        <CreneauType>[CreneauType.jour, CreneauType.nuit],
      );
    });

    test('les réponses d\'un créneau sont triées : en attente d\'abord', () {
      final suivi = _suivi(
        creneaux: <CreneauPlanning>[creneau(id: 'c1', jour: 1)],
        attributions: <AttributionSuivi>[
          attributionSuivi(
            id: 'a1',
            creneauId: 'c1',
            userId: 'b',
            nom: 'Bernard L.',
            etat: AttributionEtat.refuse,
          ),
          attributionSuivi(
            id: 'a2',
            creneauId: 'c1',
            userId: 'a',
            nom: 'Aubry I.',
            etat: AttributionEtat.accepte,
          ),
          attributionSuivi(
            id: 'a3',
            creneauId: 'c1',
            userId: 'c',
            nom: 'Camus A.',
          ),
        ],
      );

      expect(
        suivi.journees().single.creneaux.single.attributions.map(
          (AttributionSuivi a) => a.nom,
        ),
        <String>['Camus A.', 'Aubry I.', 'Bernard L.'],
      );
    });

    test('un créneau dont l\'unique attribution est refusée redevient non '
        'pourvu', () {
      final suivi = _suivi(
        creneaux: <CreneauPlanning>[creneau(id: 'c1', jour: 1)],
        attributions: <AttributionSuivi>[
          attributionSuivi(
            id: 'a1',
            creneauId: 'c1',
            userId: 'a',
            nom: 'Aubry I.',
            etat: AttributionEtat.refuse,
          ),
        ],
      );

      final creneauSuivi = suivi.journees().single.creneaux.single;
      expect(creneauSuivi.pourvus, 0);
      expect(creneauSuivi.nonPourvu, isTrue);
      expect(creneauSuivi.couverture, EtatCouverture.aPourvoir);
    });

    test('les filtres se cumulent en union, et « Tous » les lève', () {
      final suivi = _suivi(
        creneaux: <CreneauPlanning>[
          creneau(id: 'attente', jour: 1),
          creneau(id: 'accepte', jour: 2),
          creneau(id: 'refus', jour: 3),
          creneau(id: 'vide', jour: 4),
        ],
        attributions: <AttributionSuivi>[
          attributionSuivi(
            id: 'a1',
            creneauId: 'attente',
            userId: 'a',
            nom: 'A',
          ),
          attributionSuivi(
            id: 'a2',
            creneauId: 'accepte',
            userId: 'b',
            nom: 'B',
            etat: AttributionEtat.accepte,
          ),
          attributionSuivi(
            id: 'a3',
            creneauId: 'refus',
            userId: 'c',
            nom: 'C',
            etat: AttributionEtat.refuse,
          ),
        ],
      );

      final journees = suivi.journees();
      Set<String> retenus(Set<FiltreSuivi> filtres) => <String>{
        for (final journee in journees)
          for (final creneau in journee.creneaux)
            if (creneau.correspond(filtres)) creneau.creneau.id,
      };

      expect(retenus(<FiltreSuivi>{FiltreSuivi.enAttente}), <String>{'attente'});
      expect(
        retenus(<FiltreSuivi>{FiltreSuivi.nonPourvus}),
        // Le créneau refusé n'est plus couvert, celui sans personne non plus.
        <String>{'refus', 'vide'},
      );
      expect(
        retenus(<FiltreSuivi>{FiltreSuivi.enAttente, FiltreSuivi.nonPourvus}),
        <String>{'attente', 'refus', 'vide'},
      );
      expect(retenus(const <FiltreSuivi>{}), hasLength(4));
      expect(retenus(<FiltreSuivi>{FiltreSuivi.tous}), hasLength(4));

      expect(suivi.compte(FiltreSuivi.tous, journees), 4);
      expect(suivi.compte(FiltreSuivi.acceptes, journees), 1);
      expect(suivi.compte(FiltreSuivi.nonPourvus, journees), 2);
    });

    test('les retardataires sont groupés par membre, du plus ancien', () {
      final suivi = _suivi(
        creneaux: <CreneauPlanning>[
          creneau(id: 'c1', jour: 1),
          creneau(id: 'c2', jour: 2),
          creneau(id: 'c3', jour: 3),
        ],
        attributions: <AttributionSuivi>[
          attributionSuivi(
            id: 'a1',
            creneauId: 'c1',
            userId: 'lefebvre',
            nom: 'Marie L.',
            proposeeLe: _maintenant.subtract(const Duration(days: 4)),
          ),
          attributionSuivi(
            id: 'a2',
            creneauId: 'c2',
            userId: 'lefebvre',
            nom: 'Marie L.',
            proposeeLe: _maintenant.subtract(const Duration(days: 5)),
            relances: 1,
            derniereRelance: _maintenant.subtract(const Duration(minutes: 20)),
          ),
          attributionSuivi(
            id: 'a3',
            creneauId: 'c3',
            userId: 'moreau',
            nom: 'Thomas M.',
            proposeeLe: _maintenant.subtract(const Duration(days: 3, hours: 1)),
          ),
        ],
      );

      final retardataires = suivi.retardataires(maintenant: _maintenant);
      expect(retardataires, hasLength(2));
      expect(retardataires.first.nom, 'Marie L.');
      expect(retardataires.first.creneaux, 2);
      expect(
        retardataires.first.depuis,
        _maintenant.subtract(const Duration(days: 5)),
      );
      expect(retardataires.first.derniereRelance, isNotNull);
      expect(retardataires.last.nom, 'Thomas M.');
    });

    test('un brouillon n\'est jamais en retard : proposed_at est nul', () {
      final suivi = _suivi(
        creneaux: <CreneauPlanning>[creneau(id: 'c1', jour: 1)],
        attributions: <AttributionSuivi>[
          attributionSuivi(id: 'a1', creneauId: 'c1', userId: 'a', nom: 'A'),
        ],
      );

      expect(suivi.retardataires(maintenant: _maintenant), isEmpty);
    });

    test('une réponse récente n\'est pas un retard', () {
      final suivi = _suivi(
        creneaux: <CreneauPlanning>[creneau(id: 'c1', jour: 1)],
        attributions: <AttributionSuivi>[
          attributionSuivi(
            id: 'a1',
            creneauId: 'c1',
            userId: 'a',
            nom: 'A',
            proposeeLe: _maintenant.subtract(const Duration(hours: 71)),
          ),
        ],
      );

      expect(suivi.retardataires(maintenant: _maintenant), isEmpty);
    });

    test('le délai de retard est celui de la caserne, pas 72 en dur', () {
      final suivi = _suivi(
        delaiRetardHeures: 24,
        creneaux: <CreneauPlanning>[creneau(id: 'c1', jour: 1)],
        attributions: <AttributionSuivi>[
          attributionSuivi(
            id: 'a1',
            creneauId: 'c1',
            userId: 'a',
            nom: 'A',
            proposeeLe: _maintenant.subtract(const Duration(hours: 25)),
          ),
        ],
      );

      expect(suivi.retardataires(maintenant: _maintenant), hasLength(1));
    });

    test('la progression compte des personnes, pas des cases', () {
      const progression = ProgressionPlanning(
        creneauxTotal: 62,
        creneauxPourvus: 58,
        enAttente: 28,
        acceptees: 42,
        refusees: 6,
        enRetard: 3,
      );

      expect(progression.attendues, 76);
      expect(progression.reponses, 48);
      expect(progression.fraction, closeTo(48 / 76, 0.001));
    });

    test('un planning sans attribution n\'attend rien : la barre est pleine',
        () {
      expect(ProgressionPlanning.vide.fraction, 1);
      expect(ProgressionPlanning.vide.attendues, 0);
    });

    test('cancelled et replaced se lisent comme « annulé »', () {
      expect(
        AttributionSuivi.etatDepuisSql('cancelled'),
        AttributionEtat.annule,
      );
      expect(
        AttributionSuivi.etatDepuisSql('replaced'),
        AttributionEtat.annule,
      );
      expect(
        AttributionSuivi.etatDepuisSql('proposed'),
        AttributionEtat.propose,
      );
    });
  });
}
