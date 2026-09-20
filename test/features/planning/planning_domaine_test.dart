import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/planning/domain/candidat.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';

/// Un mois de 31 jours, tout « non saisi » sauf ce qu'on précise.
LigneMatrice _membre(
  String id,
  String nom, {
  String? jours,
  int? maxAstreintes,
  int astreintes = 0,
  int accepteesPrecedentes = 0,
}) => ligneMatrice(
  userId: id,
  nom: nom,
  jours: jours ?? moisUniforme('.'),
  nuits: moisUniforme('.'),
  maxAstreintes: maxAstreintes,
  astreintes: astreintes,
  accepteesPrecedentes: accepteesPrecedentes,
);

void main() {
  group('EtatCouverture — la fraction dit l\'état', () {
    test('à pourvoir, pourvu, sur-pourvu', () {
      expect(
        EtatCouverture.de(pourvus: 0, requis: 1),
        EtatCouverture.aPourvoir,
      );
      expect(
        EtatCouverture.de(pourvus: 1, requis: 2),
        EtatCouverture.aPourvoir,
      );
      expect(EtatCouverture.de(pourvus: 1, requis: 1), EtatCouverture.pourvu);
      expect(
        EtatCouverture.de(pourvus: 3, requis: 1),
        EtatCouverture.surPourvu,
      );
    });

    test('un créneau qui ne demande personne est pourvu d\'office', () {
      // `check (required_count >= 0)` : zéro est une valeur, pas une absence.
      // « Pas d'astreinte ce jour-là » n'est pas un trou dans le planning.
      expect(EtatCouverture.de(pourvus: 0, requis: 0), EtatCouverture.pourvu);
      expect(
        EtatCouverture.de(pourvus: 1, requis: 0),
        EtatCouverture.surPourvu,
      );
    });
  });

  group('PlanningMois', () {
    PlanningMois planning() => PlanningMois(
      planning: planningBrouillon,
      creneaux: creneauxDuMois(31),
      attributions: const <Attribution>[
        Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'u1'),
        Attribution(id: 'a2', creneauId: 'c-1-j', userId: 'u2'),
      ],
    );

    test('indexe les créneaux par jour et par créneau', () {
      final mois = planning();
      expect(mois.creneau(1, CreneauType.jour)?.id, 'c-1-j');
      expect(mois.creneau(1, CreneauType.nuit)?.id, 'c-1-n');
      expect(mois.creneau(31, CreneauType.nuit)?.id, 'c-31-n');
      // Un jour hors du mois ne lève pas : il n'existe pas, voilà tout.
      expect(mois.creneau(32, CreneauType.jour), isNull);
    });

    test('un mois sans planning n\'existe pas et n\'est pas modifiable', () {
      final vide = PlanningMois.vide();
      expect(vide.existe, isFalse);
      expect(vide.modifiable, isFalse);
      expect(vide.creneau(1, CreneauType.jour), isNull);
      expect(vide.couverture(1, CreneauType.jour), isNull);
    });

    test('compte les attributions et rend la couverture', () {
      final mois = planning();
      expect(mois.pourvus('c-1-j'), 2);
      expect(mois.pourvus('c-1-n'), 0);

      final couverture = mois.couverture(1, CreneauType.jour);
      expect(couverture!.pourvus, 2);
      expect(couverture.etat, EtatCouverture.surPourvu);
      expect(mois.couverture(1, CreneauType.nuit)!.etat,
          EtatCouverture.aPourvoir);
    });

    test('retrouve une attribution par son identifiant — ce que le temps '
        'réel donne d\'une suppression', () {
      // Une suppression ne diffuse que la clé primaire : sans cet index, un
      // retrait fait par l'adjoint serait un identifiant orphelin.
      final mois = planning();
      expect(mois.attributionParId('a1')?.creneauId, 'c-1-j');
      expect(mois.attributionParId('inconnue'), isNull);

      final apres = mois.sansAttribution('a1');
      expect(apres.pourvus('c-1-j'), 1);
      expect(mois.pourvus('c-1-j'), 2, reason: 'l\'original ne bouge pas');
    });

    test('ajoute, remplace et retire une attribution', () {
      final mois = planning().avecAttribution(
        const Attribution(id: 'a3', creneauId: 'c-2-j', userId: 'u3'),
      );
      expect(mois.pourvus('c-2-j'), 1);

      // Le même identifiant remplace, il ne double pas : c'est ce qui rend
      // l'écho du canal inoffensif.
      final rejoue = mois.avecAttribution(
        const Attribution(id: 'a3', creneauId: 'c-2-j', userId: 'u3'),
      );
      expect(rejoue.pourvus('c-2-j'), 1);
      expect(rejoue.attributionDe(creneauId: 'c-2-j', userId: 'u3'), isNotNull);
      expect(rejoue.attributionDe(creneauId: 'c-2-j', userId: 'u9'), isNull);
    });

    test('change l\'effectif d\'un seul créneau', () {
      final mois = planning().avecEffectif('c-1-n', 3);
      expect(mois.creneauParId('c-1-n')!.effectifRequis, 3);
      expect(mois.creneauParId('c-1-j')!.effectifRequis, 1);
      expect(mois.couverture(1, CreneauType.nuit)!.etat,
          EtatCouverture.aPourvoir);
    });
  });

  group('Le tri des candidats — docs/PRD.md § 5.3', () {
    Candidat candidat(
      String id, {
      int? maxAstreintes,
      int astreintes = 0,
      int accepteesPrecedentes = 0,
      String nom = 'Zzz',
    }) => Candidat(
      membre: _membre(
        id,
        nom,
        maxAstreintes: maxAstreintes,
        astreintes: astreintes,
        accepteesPrecedentes: accepteesPrecedentes,
      ),
      disponibilite: DisponibiliteEtat.disponible,
    );

    List<String> trier(List<Candidat> candidats) =>
        (<Candidat>[...candidats]..sort(comparerCandidats))
            .map((Candidat c) => c.userId)
            .toList();

    test('quota restant décroissant', () {
      expect(
        trier(<Candidat>[
          candidat('peu', maxAstreintes: 3, astreintes: 2),
          candidat('beaucoup', maxAstreintes: 6, astreintes: 1),
          candidat('moyen', maxAstreintes: 4, astreintes: 1),
        ]),
        <String>['beaucoup', 'moyen', 'peu'],
      );
    });

    test('un illimité passe en tête, un dépassement en queue', () {
      // `null` n'est pas zéro : c'est la plus grande capacité disponible. Et
      // celui qui est déjà au-delà de ce qu'il acceptait est le dernier qu'on
      // dérange.
      expect(
        trier(<Candidat>[
          candidat('zero', maxAstreintes: 2, astreintes: 2),
          candidat('negatif', maxAstreintes: 2, astreintes: 3),
          candidat('illimite'),
          candidat('deux', maxAstreintes: 4, astreintes: 2),
        ]),
        <String>['illimite', 'deux', 'zero', 'negatif'],
      );
    });

    test('à quota égal, la charge des trois derniers mois départage, '
        'croissante', () {
      expect(
        trier(<Candidat>[
          candidat('charge', maxAstreintes: 3, accepteesPrecedentes: 5),
          candidat('repose', maxAstreintes: 3),
          candidat('moyen', maxAstreintes: 3, accepteesPrecedentes: 2),
        ]),
        <String>['repose', 'moyen', 'charge'],
      );
    });

    test('à égalité parfaite, le nom, insensible à la casse', () {
      expect(
        trier(<Candidat>[
          candidat('b', nom: 'bernard'),
          candidat('a', nom: 'Arnaud'),
        ]),
        <String>['a', 'b'],
      );
    });

    test('quota atteint et quota dépassé', () {
      expect(candidat('x', maxAstreintes: 3, astreintes: 3).quotaAtteint,
          isTrue);
      expect(candidat('x', maxAstreintes: 3, astreintes: 4).quotaDepasse,
          isTrue);
      expect(candidat('x', maxAstreintes: 3, astreintes: 2).quotaAtteint,
          isFalse);
      // Un illimité n'atteint jamais rien.
      expect(candidat('x').quotaAtteint, isFalse);
    });
  });

  group('PanneauCandidats', () {
    // Trois membres sur le créneau du 1er, en journée : un disponible, un
    // absent, un qui n'a rien saisi.
    List<LigneMatrice> membres() => <LigneMatrice>[
      _membre('dispo', 'Dubois', jours: 'D${'.' * 30}', maxAstreintes: 3),
      _membre('absent', 'Martin', jours: 'A${'.' * 30}', maxAstreintes: 3),
      _membre('muet', 'Nguyen', maxAstreintes: 3),
    ];

    PanneauCandidats construire({List<Attribution>? attributions}) =>
        PanneauCandidats.construire(
          creneau: creneau(id: 'c-1-j', jour: 1),
          jour: DateTime(2026, 10),
          membres: membres(),
          planning: PlanningMois(
            planning: planningBrouillon,
            creneaux: creneauxDuMois(31),
            attributions: attributions ?? const <Attribution>[],
          ),
          modifiable: true,
        );

    test('trois listes disjointes : attribués, disponibles, non '
        'disponibles', () {
      final panneau = construire();
      expect(panneau.attribues, isEmpty);
      expect(
        panneau.disponibles.map((Candidat c) => c.userId),
        <String>['dispo'],
      );
      // Absent **et** non saisi : les deux sont attribuables, et les deux
      // gardent leur état, que le produit refuse de confondre.
      expect(
        panneau.nonDisponibles.map((Candidat c) => c.userId).toSet(),
        <String>{'absent', 'muet'},
      );
      expect(panneau.etat, EtatCouverture.aPourvoir);
      expect(panneau.pourvus, 0);
      expect(panneau.requis, 1);
    });

    test('un membre attribué quitte les candidats', () {
      // Sinon on lui proposerait une place qu'il occupe, et la contrainte
      // d'unicité refuserait l'écriture.
      final panneau = construire(
        attributions: const <Attribution>[
          Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'dispo'),
        ],
      );
      expect(panneau.attribues.map((Candidat c) => c.userId), <String>['dispo']);
      expect(panneau.disponibles, isEmpty);
      expect(panneau.etat, EtatCouverture.pourvu);
      expect(panneau.attribues.single.attribution!.id, 'a1');
    });

    test('les attributions d\'un autre créneau ne comptent pas', () {
      final panneau = construire(
        attributions: const <Attribution>[
          Attribution(id: 'a1', creneauId: 'c-1-n', userId: 'dispo'),
        ],
      );
      expect(panneau.attribues, isEmpty);
      expect(panneau.pourvus, 0);
    });
  });
}
