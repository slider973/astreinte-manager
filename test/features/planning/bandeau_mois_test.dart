import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_colors.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/core/widgets/count_stat.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:astreinte_sp/features/planning/domain/resume_mois.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/bandeau_mois.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/barre_repartition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/widgets/helpers.dart';
import '../../support/faux_planning.dart';
import '../../support/polices.dart';

/// Un mois de deux jours : quatre créneaux, assez pour exercer les quatre
/// familles sans écrire soixante-deux lignes.
const int _jours = 2;

PlanningMois _planning({
  List<CreneauPlanning>? creneaux,
  List<Attribution> attributions = const <Attribution>[],
  PlanningEtat etat = PlanningEtat.brouillon,
}) => PlanningMois(
  planning: PlanningBrouillon(id: 'plan-1', etat: etat),
  creneaux: creneaux ?? creneauxDuMois(_jours),
  attributions: attributions,
);

Attribution _attribution(
  String creneauId, {
  String userId = 'u1',
  AttributionEtat etat = AttributionEtat.propose,
}) => Attribution(
  id: 'a-$creneauId-$userId',
  creneauId: creneauId,
  userId: userId,
  etat: etat,
);

/// Le nombre **du compteur**, et non celui de la ligne de légende qui dit le
/// même chiffre trente points plus bas.
Finder _nombre(String valeur) => find.descendant(
  of: find.byType(CountStat),
  matching: find.text(valeur),
);

void main() {
  group('ResumeMois — les comptes du mois', () {
    test('sans planning, tout le mois est non saisi', () {
      final resume = ResumeMois.construire(
        planning: PlanningMois.vide(),
        nombreDeJours: 31,
      );

      expect(resume.nonSaisis, 62);
      expect(resume.couverts, 0);
      expect(resume.manquants, 0);
      expect(resume.enAttente, 0);
      expect(resume.total, 62);
    });

    test('un créneau attribué est couvert, les autres sont à pourvoir', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          attributions: <Attribution>[_attribution('c-1-j')],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.couverts, 1);
      expect(resume.aPourvoir, 3);
      expect(resume.manquants, 3);
      expect(resume.nonSaisis, 0);
      expect(resume.total, _jours * 2);
    });

    test('un effectif requis à zéro n\'est pas un trou', () {
      final resume = ResumeMois.construire(
        planning: _planning(creneaux: creneauxDuMois(_jours, effectifRequis: 0)),
        nombreDeJours: _jours,
      );

      expect(resume.nonSaisis, 4);
      expect(resume.manquants, 0);
    });

    test('un créneau à deux requis n\'est couvert qu\'à deux', () {
      final creneaux = <CreneauPlanning>[
        creneau(id: 'c-1-j', jour: 1, effectifRequis: 2),
        creneau(
          id: 'c-1-n',
          jour: 1,
          creneau: CreneauType.nuit,
          effectifRequis: 2,
        ),
      ];
      final unSeul = ResumeMois.construire(
        planning: _planning(
          creneaux: creneaux,
          attributions: <Attribution>[_attribution('c-1-j')],
        ),
        nombreDeJours: 1,
      );
      expect(unSeul.couverts, 0);
      expect(unSeul.aPourvoir, 2);

      final lesDeux = ResumeMois.construire(
        planning: _planning(
          creneaux: creneaux,
          attributions: <Attribution>[
            _attribution('c-1-j'),
            _attribution('c-1-j', userId: 'u2'),
          ],
        ),
        nombreDeJours: 1,
      );
      expect(lesDeux.couverts, 1);
      expect(lesDeux.aPourvoir, 1);
    });

    test('en brouillon, personne n\'attend de réponse', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          attributions: <Attribution>[
            _attribution('c-1-j'),
            _attribution('c-1-n'),
          ],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.enAttente, 0);
      expect(resume.couverts, 2);
    });

    test('publié, une proposition sans réponse est une réponse en attente', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          etat: PlanningEtat.publie,
          attributions: <Attribution>[
            _attribution('c-1-j'),
            _attribution('c-1-n', etat: AttributionEtat.accepte),
          ],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.enAttente, 1);
      expect(resume.couverts, 2);
    });

    test('publié, deux propositions sans réponse font deux réponses en '
        'attente — et la grille montre les deux mêmes blocs', () {
      // La question est venue d'une inspection : quatre blocs « en attente »
      // dans la grille et « Réponses en attente : 0 » dans le bandeau. Les
      // deux lisent bien le **même** `PlanningMois` ; ce qui les séparait
      // était l'état du planning, et la règle est celle du ticket 061b — en
      // brouillon, une attribution vaut `proposed` sans que personne n'ait
      // été prévenu. Parti, le compte suit.
      final planning = _planning(
        etat: PlanningEtat.publie,
        attributions: <Attribution>[
          _attribution('c-1-j'),
          _attribution('c-2-j'),
        ],
      );

      expect(
        ResumeMois.construire(
          planning: planning,
          nombreDeJours: _jours,
        ).enAttente,
        2,
      );

      // Et le même planning, en brouillon : les mêmes deux blocs à l'écran,
      // zéro réponse attendue. Les deux affirmations sont vraies ensemble.
      expect(
        ResumeMois.construire(
          planning: _planning(
            attributions: <Attribution>[
              _attribution('c-1-j'),
              _attribution('c-2-j'),
            ],
          ),
          nombreDeJours: _jours,
        ).enAttente,
        0,
      );
    });

    test('un refus laisse le créneau à réattribuer, pas à pourvoir', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          etat: PlanningEtat.publie,
          attributions: <Attribution>[
            _attribution('c-1-j', etat: AttributionEtat.refuse),
          ],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.refuses, 1);
      expect(resume.aPourvoir, 3);
      expect(resume.manquants, 4);
      expect(resume.couverts, 0);
    });

    test('les quatre familles couvrent le mois entier, sans recoupement', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          etat: PlanningEtat.publie,
          creneaux: <CreneauPlanning>[
            creneau(id: 'c-1-j', jour: 1),
            creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit),
            creneau(id: 'c-2-j', jour: 2, effectifRequis: 0),
            creneau(
              id: 'c-2-n',
              jour: 2,
              creneau: CreneauType.nuit,
            ),
          ],
          attributions: <Attribution>[
            _attribution('c-1-j', etat: AttributionEtat.accepte),
            _attribution('c-1-n', etat: AttributionEtat.refuse),
          ],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.couverts, 1);
      expect(resume.refuses, 1);
      expect(resume.nonSaisis, 1);
      expect(resume.aPourvoir, 1);
      expect(resume.total, 4);
    });
  });

  group('BandeauMois — ce que le chef lit avant de défiler', () {
    const resume = ResumeMois(
      couverts: 40,
      aPourvoir: 15,
      refuses: 5,
      nonSaisis: 2,
      enAttente: 7,
    );

    testWidgets('trois chiffres et leur libellé, sans titre de mois', (
      tester,
    ) async {
      await monter(
        tester,
        const BandeauMois(resume: resume),
        taille: const Size(1280, 900),
      );

      // **Le mois est écrit une seule fois, dans le sélecteur** de la barre
      // de commande. Le bandeau ne le répète pas : deux fois « Septembre
      // 2026 » à trente points d'écart, c'est une question posée au lecteur.
      expect(find.text(AppStrings.moisNomEtAnnee(10, 2026)), findsNothing);
      expect(find.text(AppStrings.bandeauCouverts), findsOneWidget);
      expect(find.text(AppStrings.bandeauAPourvoir), findsOneWidget);
      expect(find.text(AppStrings.bandeauEnAttente), findsOneWidget);

      expect(find.text('40'), findsWidgets);
      // « À pourvoir » compte les refus avec ce qui manque : 15 + 5.
      expect(find.text('20'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('la ligne d\'attaque est celle du premier nombre, et la '
        'barre la suit', (tester) async {
      await chargerPolicesDuProduit();
      await monter(
        tester,
        const BandeauMois(resume: resume),
        taille: const Size(1280, 900),
      );

      // Le premier nombre, son libellé, la barre et la première ligne de
      // légende partagent une verticale : la place laissée par le titre de
      // mois n'a pas été rendue à un intitulé, elle est rendue aux chiffres.
      // Depuis que le nombre passe au-dessus du libellé, c'est **lui** qui
      // ouvre le bloc — la ligne d'attaque n'a pas bougé d'un point, elle a
      // changé de porteur.
      final gaucheDuNombre = tester.getTopLeft(_nombre('40')).dx;
      final gaucheDuLibelle = tester
          .getTopLeft(find.text(AppStrings.bandeauCouverts))
          .dx;
      final gaucheDeLaBarre = tester
          .getTopLeft(find.byType(BarreRepartition))
          .dx;
      final gaucheDeLaLegende = tester
          .getTopLeft(find.text(AppStrings.bandeauPartCouverts))
          .dx;

      expect(gaucheDuNombre, moreOrLessEquals(gaucheDeLaBarre, epsilon: 1));
      expect(gaucheDuLibelle, moreOrLessEquals(gaucheDeLaBarre, epsilon: 1));
      expect(gaucheDeLaLegende, greaterThan(gaucheDeLaBarre));

      // Et les trois compteurs se partagent toute la largeur du bloc : le
      // troisième commence après les deux tiers.
      final largeur = tester.getSize(find.byType(BarreRepartition)).width;
      final troisieme = tester
          .getTopLeft(find.text(AppStrings.bandeauEnAttente))
          .dx;
      expect(troisieme - gaucheDeLaBarre, greaterThan(largeur * 0.6));
    });

    testWidgets('les trois nombres partagent une ligne, quel que soit le '
        'repli des libellés', (tester) async {
      await chargerPolicesDuProduit();

      for (final taille in <Size>[
        const Size(1280, 900),
        const Size(390, 844),
      ]) {
        final compact = taille.width < 600;
        await monter(
          tester,
          BandeauMois(resume: resume, compact: compact),
          taille: taille,
        );

        // Les trois nombres sur la même ligne — c'est ce qu'on lit d'abord —
        // et chacun **au-dessus** de son libellé.
        final hauts = <double>[
          for (final nombre in <String>['40', '20', '7'])
            tester.getTopLeft(_nombre(nombre)).dy,
        ];
        expect(hauts[1], moreOrLessEquals(hauts.first, epsilon: 0.5));
        expect(hauts[2], moreOrLessEquals(hauts.first, epsilon: 0.5));

        for (final (nombre, libelle) in <(String, String)>[
          ('40', AppStrings.bandeauCouverts),
          ('20', AppStrings.bandeauAPourvoir),
          ('7', AppStrings.bandeauEnAttente),
        ]) {
          expect(
            tester.getTopLeft(_nombre(nombre)).dy,
            lessThan(tester.getTopLeft(find.text(libelle)).dy),
          );
        }
      }

      // Et le repli existe bel et bien sur un téléphone : « Réponses en
      // attente » y tient deux lignes là où « À pourvoir » en tient une.
      // C'est ce repli qui faisait descendre le troisième nombre sous les
      // deux autres.
      expect(
        tester.getSize(find.text(AppStrings.bandeauEnAttente)).height,
        greaterThan(
          tester.getSize(find.text(AppStrings.bandeauAPourvoir)).height,
        ),
      );
    });

    testWidgets('les hauteurs annoncées sont les hauteurs mesurées', (
      tester,
    ) async {
      await chargerPolicesDuProduit();

      // L'écran décide de montrer le bloc à partir de ces deux nombres
      // (`MatriceScreen.placeBandeauComplet`). S'ils dérivaient du rendu, le
      // seuil déciderait à côté et la barre disparaîtrait sans prévenir.
      for (final largeur in <double>[1440, 1280, 1024, 840]) {
        for (final compact in <bool>[false, true]) {
          await monter(
            tester,
            Align(
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  BandeauMois(resume: resume, compact: compact),
                ],
              ),
            ),
            taille: Size(largeur, 900),
          );

          expect(
            tester.getSize(find.byType(BandeauMois)).height,
            compact
                ? BandeauMois.hauteurReduitSansActions
                : BandeauMois.hauteurCompletSansActions,
            reason: 'largeur $largeur, compact $compact',
          );
        }
      }
    });

    testWidgets('la barre a quatre parts proportionnelles, chacune avec sa '
        'ligne de légende', (tester) async {
      await monter(
        tester,
        const BandeauMois(resume: resume),
        taille: const Size(1280, 900),
      );

      final parts = tester
          .widget<BarreRepartition>(find.byType(BarreRepartition))
          .parts;
      expect(parts.map((PartDuMois p) => p.valeur).toList(), <int>[
        40,
        15,
        5,
        2,
      ]);

      // Les teintes vives de la charte, en remplissage seulement.
      expect(parts[0].couleur, AppTheme.clair.colorScheme.secondary);
      expect(parts[1].couleur, AppColors.orangeVif);
      expect(parts[2].couleur, AppColors.roseVif);
      expect(parts[3].couleur, AppColors.etatNonSaisi);

      // La proportion est portée par la largeur peinte : 40 contre 2.
      final flexs = tester
          .widgetList<Expanded>(
            find.descendant(
              of: find.byType(BarreRepartition),
              matching: find.byType(Expanded),
            ),
          )
          .map((Expanded e) => e.flex)
          .toList();
      expect(flexs, <int>[40, 15, 5, 2]);

      // Et chaque part est **peinte** : une part centrée dans la barre plutôt
      // qu'étirée n'aurait aucune hauteur, et la barre serait invisible.
      final peintes = find.descendant(
        of: find.byType(BarreRepartition),
        matching: find.byType(ColoredBox),
      );
      for (var index = 0; index < peintes.evaluate().length; index++) {
        final taille = tester.getSize(peintes.at(index));
        expect(taille.height, BarreRepartition.hauteur);
        expect(taille.width, greaterThan(0));
      }

      // La légende double la couleur d'une icône, d'un libellé et du nombre.
      for (final libelle in <String>[
        AppStrings.bandeauPartCouverts,
        AppStrings.bandeauPartARemplir,
        AppStrings.bandeauPartAReattribuer,
        AppStrings.bandeauPartNonSaisis,
      ]) {
        expect(find.text(libelle), findsOneWidget);
      }
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(find.byIcon(Icons.person_search), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('une part nulle ne prend ni pixel ni ligne de légende', (
      tester,
    ) async {
      await monter(
        tester,
        const BandeauMois(
          resume: ResumeMois(
            couverts: 10,
            aPourvoir: 0,
            refuses: 0,
            nonSaisis: 0,
            enAttente: 0,
          ),
        ),
        taille: const Size(1280, 900),
      );

      expect(find.text(AppStrings.bandeauPartCouverts), findsOneWidget);
      expect(find.text(AppStrings.bandeauPartAReattribuer), findsNothing);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
    });

    testWidgets('en compact, une ligne de trois chiffres et rien d\'autre', (
      tester,
    ) async {
      await monter(
        tester,
        const BandeauMois(resume: resume, compact: true),
      );

      expect(find.text(AppStrings.bandeauCouverts), findsOneWidget);
      expect(find.byType(BarreRepartition), findsNothing);
      expect(find.text(AppStrings.moisNomEtAnnee(10, 2026)), findsNothing);
    });

    testWidgets('sombre : le bandeau tient sans exception', (tester) async {
      await monter(
        tester,
        const BandeauMois(resume: resume),
        taille: const Size(1280, 900),
        brightness: Brightness.dark,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(BarreRepartition), findsOneWidget);
    });
  });
}
