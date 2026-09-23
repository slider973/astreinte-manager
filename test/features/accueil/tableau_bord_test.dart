import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/accueil/domain/composition_accueil.dart';
import 'package:astreinte_sp/features/accueil/domain/tableau_bord.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/disponibilite_mois.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/presentation/controllers/saisie_controller.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_propositions.dart';

/// Un mercredi, pour que la semaine de sept jours traverse un weekend.
final DateTime _aujourdhui = DateTime(2026, 10, 14, 9);

TableauBord _composer({
  List<Astreinte> astreintes = const <Astreinte>[],
  List<Proposition> propositions = const <Proposition>[],
  AppelDispos? dispos,
}) => composerTableauBord(
  aujourdhui: _aujourdhui,
  astreintes: MesAstreintes(
    astreintes: astreintes,
    luLe: _aujourdhui,
  ),
  propositions: propositions,
  nomCaserne: 'CIS Saint-Martin',
  dispos: dispos,
);

void main() {
  group('La rangée de cartes', () {
    test('sans rien, sept jours libres', () {
      final tableau = _composer();

      expect(tableau.cartes, hasLength(joursDeLAccueil));
      expect(
        tableau.cartes.every((CarteJour c) => c.etat == EtatCarte.libre),
        isTrue,
      );
      expect(tableau.cartes.first.jour, DateTime(2026, 10, 14));
      expect(tableau.cartes.last.jour, DateTime(2026, 10, 20));
    });

    test('la prochaine astreinte acceptée ouvre la rangée, même lointaine', () {
      final tableau = _composer(
        astreintes: <Astreinte>[
          astreinte(id: 'g-1', jour: DateTime(2026, 11, 8)),
        ],
      );

      // Hors de la fenêtre de sept jours, et c'est justement là qu'elle vaut
      // le plus : c'est la seule chose que le pompier vient chercher.
      expect(tableau.cartes.first.etat, EtatCarte.acceptee);
      expect(tableau.cartes.first.jour, DateTime(2026, 11, 8));
      expect(tableau.cartes, hasLength(joursDeLAccueil + 1));
    });

    test('une astreinte du jour ne paraît pas deux fois', () {
      final tableau = _composer(
        astreintes: <Astreinte>[
          astreinte(id: 'g-1', jour: DateTime(2026, 10, 16)),
        ],
      );

      final le16 = tableau.cartes
          .where((CarteJour c) => c.jour == DateTime(2026, 10, 16))
          .toList(growable: false);
      expect(le16, hasLength(1));
      expect(tableau.cartes, hasLength(joursDeLAccueil));
    });

    test('une proposition en attente passe devant un jour libre', () {
      final tableau = _composer(
        propositions: <Proposition>[
          proposition(
            id: 'a-1',
            jour: DateTime(2026, 10, 15),
          ),
        ],
      );

      final le15 = tableau.cartes.firstWhere(
        (CarteJour c) => c.jour == DateTime(2026, 10, 15),
      );
      expect(le15.etat, EtatCarte.proposition);
      expect(le15.creneau, CreneauType.nuit);
      expect(le15.propositionId, 'a-1');
    });

    test('une astreinte passée n\'entre ni dans la rangée ni dans le compte', () {
      final tableau = _composer(
        astreintes: <Astreinte>[
          astreinte(id: 'g-vieux', jour: DateTime(2026, 10)),
        ],
      );

      expect(tableau.astreintesAVenir, 0);
      expect(
        tableau.cartes.every((CarteJour c) => c.etat == EtatCarte.libre),
        isTrue,
      );
    });

    test('le compte annoncé porte toutes les astreintes à venir', () {
      final tableau = _composer(
        astreintes: <Astreinte>[
          astreinte(id: 'g-1', jour: DateTime(2026, 10, 16)),
          astreinte(id: 'g-2', jour: DateTime(2026, 12, 3)),
          astreinte(id: 'g-3', jour: DateTime(2027, 1, 9)),
        ],
      );

      // La rangée n'en montre qu'une partie ; le compte, lui, ne ment pas.
      expect(tableau.astreintesAVenir, 3);
    });
  });

  group('La bande de semaine', () {
    test('sept jours, le premier étant aujourd\'hui', () {
      final tableau = _composer();

      expect(tableau.semaine, hasLength(joursDeLAccueil));
      expect(tableau.semaine.first.aujourdhui, isTrue);
      expect(
        tableau.semaine.skip(1).every((PointJour j) => !j.aujourdhui),
        isTrue,
      );
    });

    test('un jour peut porter les deux points', () {
      final tableau = _composer(
        astreintes: <Astreinte>[
          astreinte(
            id: 'g-1',
            jour: DateTime(2026, 10, 17),
            creneau: CreneauType.jour,
          ),
        ],
        propositions: <Proposition>[
          proposition(
            id: 'a-1',
            jour: DateTime(2026, 10, 17),
          ),
        ],
      );

      final le17 = tableau.semaine.firstWhere(
        (PointJour j) => j.jour == DateTime(2026, 10, 17),
      );
      expect(le17.astreinte, isTrue);
      expect(le17.proposition, isTrue);
    });
  });

  group('Les propositions', () {
    test('une proposition sur un planning archivé n\'est plus une question', () {
      final tableau = _composer(
        propositions: <Proposition>[
          proposition(
            id: 'a-vieux',
            jour: DateTime(2026, 10, 16),
            planningEtat: PlanningEtat.archive,
          ),
        ],
      );

      // La base refuserait la réponse : afficher la ligne, c'est afficher un
      // bouton qui ne fait rien (`Proposition.repondable`).
      expect(tableau.propositions, isEmpty);
    });

    test('elles sont rangées dans l\'ordre du calendrier', () {
      final tableau = _composer(
        propositions: <Proposition>[
          proposition(id: 'a-3', jour: DateTime(2026, 10, 19)),
          proposition(id: 'a-1', jour: DateTime(2026, 10, 15)),
          proposition(id: 'a-2', jour: DateTime(2026, 10, 16)),
        ],
      );

      expect(
        tableau.propositions.map((Proposition p) => p.id).toList(),
        <String>['a-1', 'a-2', 'a-3'],
      );
    });
  });

  group('La section « Disponibilités »', () {
    EtatSaisie saisieDe(PeriodeSaisie periode, int cases) => EtatSaisie(
      periode: periode,
      mois: DisponibiliteMois(
        annee: periode.annee,
        mois: periode.mois,
        valeurs: <CreneauCle, DisponibiliteEtat>{
          for (var index = 0; index < cases; index++)
            CreneauCle(
              DateTime(periode.annee, periode.mois, index ~/ 2 + 1),
              index.isEven ? CreneauType.jour : CreneauType.nuit,
            ): DisponibiliteEtat.disponible,
        },
      ),
    );

    test('aucune période ouverte : la section n\'existe pas', () {
      expect(
        appelDispos(
          periodes: <PeriodeSaisie>[
            periodeVerrouillee(annee: 2026, mois: 9),
          ],
          maintenant: _aujourdhui,
        ),
        isNull,
      );
    });

    test('un mois ouvert et incomplet appelle à saisir', () {
      final periode = periodeOuverte(
        annee: 2026,
        mois: 11,
        dateLimite: DateTime(2026, 10, 17, 23, 59, 59),
      );

      final appel = appelDispos(
        periodes: <PeriodeSaisie>[periode],
        saisie: saisieDe(periode, 4),
        maintenant: _aujourdhui,
      );

      expect(appel, isA<SaisieAFaire>());
      final aFaire = appel! as SaisieAFaire;
      expect(aFaire.nomMois, 'novembre');
      expect(aFaire.cleMois, '2026-11');
      expect(aFaire.joursRestants, 3);
    });

    test('un mois entièrement saisi se contente de le dire', () {
      final periode = periodeOuverte(annee: 2026, mois: 11);
      final appel = appelDispos(
        periodes: <PeriodeSaisie>[periode],
        saisie: saisieDe(periode, periode.nombreDeJours * 2),
        maintenant: _aujourdhui,
      );

      expect(appel, isA<SaisieFaite>());
      final faite = appel! as SaisieFaite;
      expect(faite.libelleMois, 'Novembre 2026');
      expect(faite.jours + faite.nuits, periode.nombreDeJours * 2);
    });

    test('la saisie d\'un autre mois ne décide de rien', () {
      final ouverte = periodeOuverte(annee: 2026, mois: 11);
      final autre = periodeOuverte(annee: 2026, mois: 12);

      // Le Calendrier a été déplacé sur décembre : annoncer « Novembre saisi »
      // à partir des cases de décembre serait un chiffre faux.
      expect(
        appelDispos(
          periodes: <PeriodeSaisie>[ouverte, autre],
          saisie: saisieDe(autre, autre.nombreDeJours * 2),
          maintenant: _aujourdhui,
        ),
        isA<SaisieAFaire>(),
      );
    });
  });

  group('La salutation', () {
    test('« Bonjour » avant 18 h, « Bonsoir » à partir de 18 h', () {
      expect(salutationDe(DateTime(2026, 10, 14, 6)), 'Bonjour,');
      expect(salutationDe(DateTime(2026, 10, 14, 17, 59)), 'Bonjour,');
      expect(salutationDe(DateTime(2026, 10, 14, 18)), 'Bonsoir,');
      expect(salutationDe(DateTime(2026, 10, 14, 23, 30)), 'Bonsoir,');
    });

    test('le prénom est le premier mot du nom d\'usage', () {
      expect(prenomDe('Marie L.'), 'Marie');
      expect(prenomDe('Dubois Jean-Marc'), 'Dubois');
      expect(prenomDe('  '), '');
      expect(prenomDe(null), '');
    });
  });
}
