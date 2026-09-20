import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/domain/matrice_filtres.dart';
import 'package:astreinte_sp/features/planning/domain/matrice_mois.dart';
import 'package:astreinte_sp/features/planning/domain/matrice_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_dispos.dart';
import '../../support/faux_matrice.dart';

void main() {
  group('Décodage des chaînes de availability_matrix', () {
    test('les cinq caractères de l\'alphabet, et rien d\'autre', () {
      final ligne = ligneMatrice(
        userId: 'u1',
        nom: 'Dubois Jean-Marc',
        //     1234 5
        jours: '.DAda',
        nuits: 'aDA.d',
      );

      expect(ligne.cellule(1, CreneauType.jour), CelluleMatrice.nonSaisi);
      expect(ligne.cellule(2, CreneauType.jour), CelluleMatrice.disponible);
      expect(ligne.cellule(3, CreneauType.jour), CelluleMatrice.absent);
      expect(
        ligne.cellule(4, CreneauType.jour),
        CelluleMatrice.disponibleParAdmin,
      );
      expect(ligne.cellule(5, CreneauType.jour), CelluleMatrice.absentParAdmin);

      // La minuscule porte **le même état** que la majuscule : elle ne dit que
      // l'auteur de la saisie.
      expect(ligne.etatDe(4, CreneauType.jour), DisponibiliteEtat.disponible);
      expect(ligne.etatDe(5, CreneauType.jour), DisponibiliteEtat.absent);
      expect(ligne.cellule(4, CreneauType.jour).parAdmin, isTrue);
      expect(ligne.cellule(2, CreneauType.jour).parAdmin, isFalse);

      // Les deux chaînes sont bien distinctes : jour ≠ nuit.
      expect(ligne.cellule(1, CreneauType.nuit), CelluleMatrice.absentParAdmin);
      expect(ligne.cellule(5, CreneauType.nuit).parAdmin, isTrue);
    });

    test('la chaîne est indexée à partir de 0 : jours[jour − 1]', () {
      final ligne = ligneMatrice(
        userId: 'u1',
        nom: 'A',
        jours: 'D..............................',
        nuits: '..............................A',
      );

      // Le premier jour du mois porte la première lettre, pas la seconde.
      expect(ligne.etatDe(1, CreneauType.jour), DisponibiliteEtat.disponible);
      expect(ligne.etatDe(2, CreneauType.jour), DisponibiliteEtat.nonSaisi);
      // Le dernier jour porte la dernière.
      expect(ligne.etatDe(31, CreneauType.nuit), DisponibiliteEtat.absent);
    });

    test('28, 30 et 31 jours : la longueur vient de la base', () {
      for (final jours in <int>[28, 30, 31]) {
        final ligne = ligneMatrice(
          userId: 'u1',
          nom: 'A',
          jours: moisUniforme('D', jours: jours),
          nuits: moisUniforme('.', jours: jours),
        );

        expect(ligne.nombreDeJours, jours);
        expect(
          ligne.etatDe(jours, CreneauType.jour),
          DisponibiliteEtat.disponible,
        );
        // Un jour hors bornes ne lève pas : il vaut « non saisi ».
        expect(
          ligne.etatDe(jours + 1, CreneauType.jour),
          DisponibiliteEtat.nonSaisi,
        );
        expect(ligne.etatDe(0, CreneauType.jour), DisponibiliteEtat.nonSaisi);
      }
    });

    test('un caractère inconnu se lit « non saisi » sans faire tomber la '
        'grille', () {
      final ligne = ligneMatrice(
        userId: 'u1',
        nom: 'A',
        jours: 'X?D',
        nuits: '  D',
      );

      expect(ligne.etatDe(1, CreneauType.jour), DisponibiliteEtat.nonSaisi);
      expect(ligne.etatDe(2, CreneauType.jour), DisponibiliteEtat.nonSaisi);
      expect(ligne.etatDe(1, CreneauType.nuit), DisponibiliteEtat.nonSaisi);
      expect(ligne.aSaisiQuelqueChose, isTrue);
    });

    test('aSaisiQuelqueChose distingue un mois vide d\'un mois rempli', () {
      final vide = ligneMatrice(
        userId: 'u1',
        nom: 'A',
        jours: moisUniforme('.'),
        nuits: moisUniforme('.'),
      );
      final rempli = ligneMatrice(
        userId: 'u2',
        nom: 'B',
        jours: moisUniforme('.'),
        // Une seule case, posée par un admin : c'est déjà une saisie.
        nuits: '${'.' * 30}a',
      );

      expect(vide.aSaisiQuelqueChose, isFalse);
      expect(rempli.aSaisiQuelqueChose, isTrue);
    });
  });

  group('Quotas', () {
    test('null veut dire illimité, jamais zéro, et le reste peut être '
        'négatif', () {
      final illimite = ligneMatrice(
        userId: 'u1',
        nom: 'A',
        jours: moisUniforme('.'),
        nuits: moisUniforme('.'),
        astreintes: 3,
      );
      final atteint = ligneMatrice(
        userId: 'u2',
        nom: 'B',
        jours: moisUniforme('.'),
        nuits: moisUniforme('.'),
        maxAstreintes: 3,
        astreintes: 3,
      );
      final depasse = ligneMatrice(
        userId: 'u3',
        nom: 'C',
        jours: moisUniforme('.'),
        nuits: moisUniforme('.'),
        maxAstreintes: 3,
        astreintes: 4,
      );

      expect(illimite.maxAstreintes, isNull);
      expect(illimite.astreintesRestantes, isNull);
      expect(illimite.astreintes, 3);

      expect(atteint.astreintesRestantes, 0);
      expect(depasse.astreintesRestantes, -1);
    });
  });

  group('Comptes de disponibles', () {
    test('comptent les majuscules **et** les minuscules', () {
      final matrice = MatriceMois(
        nombreDeJours: 3,
        lignes: <LigneMatrice>[
          ligneMatrice(userId: 'u1', nom: 'A', jours: 'D.A', nuits: '...'),
          ligneMatrice(userId: 'u2', nom: 'B', jours: 'd.D', nuits: 'D..'),
          ligneMatrice(userId: 'u3', nom: 'C', jours: 'A..', nuits: '...'),
        ],
      );

      expect(matrice.disponibles(1, CreneauType.jour), 2);
      expect(matrice.disponibles(2, CreneauType.jour), 0);
      expect(matrice.disponibles(3, CreneauType.jour), 1);
      expect(matrice.disponibles(1, CreneauType.nuit), 1);
    });

    test('une écriture locale invalide le compte', () {
      var matrice = MatriceMois(
        nombreDeJours: 2,
        lignes: <LigneMatrice>[
          ligneMatrice(userId: 'u1', nom: 'A', jours: '..', nuits: '..'),
        ],
      );
      expect(matrice.disponibles(1, CreneauType.jour), 0);

      matrice = matrice.avecCellule(
        userId: 'u1',
        jour: 1,
        creneau: CreneauType.jour,
        cellule: CelluleMatrice.disponibleParAdmin,
      );
      expect(matrice.disponibles(1, CreneauType.jour), 1);
    });

    test('un mois vierge s\'affiche quand même', () {
      final matrice = MatriceMois(
        nombreDeJours: 2,
        lignes: <LigneMatrice>[
          ligneMatrice(userId: 'u1', nom: 'A', jours: '..', nuits: '..'),
        ],
      );

      expect(matrice.vierge, isTrue);
      expect(matrice.aucunMembre, isFalse);
    });
  });

  group('Filtres, recherche et tri', () {
    List<LigneMatrice> lignes() => <LigneMatrice>[
      ligneMatrice(
        userId: 'u1',
        nom: 'Dupónd Éric',
        jours: 'D..',
        nuits: '...',
        maxAstreintes: 4,
        astreintes: 1,
        accepteesPrecedentes: 2,
      ),
      ligneMatrice(
        userId: 'u2',
        nom: 'Martin Alice',
        jours: '...',
        nuits: '...',
        maxAstreintes: 4,
        astreintes: 1,
        accepteesPrecedentes: 5,
      ),
      ligneMatrice(
        userId: 'u3',
        nom: 'Zola Émile',
        jours: 'A..',
        nuits: '...',
        astreintes: 7,
      ),
      ligneMatrice(
        userId: 'u4',
        nom: 'Bernard Luc',
        jours: '..d',
        nuits: '...',
        maxAstreintes: 2,
        astreintes: 3,
      ),
    ];

    test('la recherche est insensible à la casse et aux accents', () {
      for (final terme in <String>['dupond', 'DUPOND', 'Dupónd', ' dupónd ']) {
        final trouvees = FiltresMatrice(recherche: terme).appliquer(lignes());
        expect(trouvees.map((LigneMatrice l) => l.userId), <String>['u1']);
      }
    });

    test('« Masquer ceux qui n\'ont rien saisi » masque les lignes toutes '
        'vides', () {
      final visibles = const FiltresMatrice(
        masquerNonSaisis: true,
      ).appliquer(lignes());

      expect(visibles.map((LigneMatrice l) => l.userId), <String>[
        'u4',
        'u1',
        'u3',
      ]);
    });

    test('tri par astreintes restantes : décroissant, null en tête, égalités '
        'par accepted_previous puis nom', () {
      final triees = const FiltresMatrice(
        tri: TriMatrice.astreintes,
      ).appliquer(lignes());

      expect(triees.map((LigneMatrice l) => l.userId), <String>[
        // Illimité : la plus grande capacité disponible, jamais en queue.
        'u3',
        // 3 restantes, égalité départagée par accepted_previous croissant.
        'u1',
        'u2',
        // -1 : le dépassement passe en dernier, et il reste visible.
        'u4',
      ]);
    });

    test('le tri par nom est l\'ordre par défaut', () {
      final triees = const FiltresMatrice().appliquer(lignes());
      expect(triees.map((LigneMatrice l) => l.userId), <String>[
        'u4',
        'u1',
        'u2',
        'u3',
      ]);
    });

    test('un filtre actif ne change jamais le compte de disponibles', () {
      final matrice = MatriceMois(nombreDeJours: 3, lignes: lignes());
      const filtres = FiltresMatrice(recherche: 'dupond');

      expect(filtres.appliquer(matrice.lignes), hasLength(1));
      // Le compte reste celui de la caserne : deux disponibles le 1er et le 3.
      expect(matrice.disponibles(1, CreneauType.jour), 1);
      expect(matrice.disponibles(3, CreneauType.jour), 1);
      expect(filtres.actif, isTrue);
      expect(const FiltresMatrice(tri: TriMatrice.weekends).actif, isFalse);
    });
  });

  group('Mois par défaut de l\'admin', () {
    test('le mois le plus proche à venir, mois courant inclus', () {
      final periodes = <PeriodeSaisie>[
        periodeVerrouillee(annee: 2026, mois: 8),
        periodeVerrouillee(annee: 2026, mois: 9),
        periodeOuverte(annee: 2026, mois: 10),
        periodeOuverte(annee: 2026, mois: 11),
      ];

      // En septembre, le chef construit… septembre, puis octobre.
      expect(
        periodeParDefautAdmin(periodes, DateTime(2026, 9, 20))?.cle,
        '2026-09',
      );
      expect(
        periodeParDefautAdmin(periodes, DateTime(2026, 10, 2))?.cle,
        '2026-10',
      );
      // Plus rien à venir : le dernier mois écoulé reste consultable.
      expect(
        periodeParDefautAdmin(periodes, DateTime(2027, 3))?.cle,
        '2026-11',
      );
      expect(
        periodeParDefautAdmin(const <PeriodeSaisie>[], DateTime.now()),
        isNull,
      );
    });
  });
}
