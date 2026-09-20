import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/data/planning_repository.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/ligne_candidat.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/ligne_creneaux.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/panneau_creneau.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';

const String _chemin = '/admin/planning';

/// Un poste d'administration : la composition de référence, celle où le
/// panneau du créneau vit dans le volet de droite.
const Size _poste = Size(1440, 900);

/// Un téléphone : la matrice n'existe pas, les créneaux sont deux cibles de
/// 48 dp sous le ruban des jours.
const Size _telephone = Size(390, 844);

final DateTime _maintenant = DateTime.now();
final DateTime _moisAffiche = DateTime(_maintenant.year, _maintenant.month);

int get _joursDuMois =>
    DateTime(_moisAffiche.year, _moisAffiche.month + 1, 0).day;

PeriodeSaisie _periode() =>
    periodeOuverte(annee: _moisAffiche.year, mois: _moisAffiche.month);

/// Quatre membres, choisis pour que le tri des candidats soit visible :
///   - Aubry   : disponible, 3 restantes, 0 acceptée sur trois mois ;
///   - Bernard : disponible, 3 restantes, 4 acceptées → derrière Aubry ;
///   - Camus   : disponible, **quota atteint** → grisé, mais attribuable ;
///   - Dupuis  : **absent** le 1er en journée → dans les non disponibles.
List<LigneMatrice> _membres() {
  final reste = '.' * (_joursDuMois - 1);
  return <LigneMatrice>[
    ligneMatrice(
      userId: 'aubry',
      nom: 'Aubry Irène',
      jours: 'D$reste',
      nuits: 'D$reste',
      maxAstreintes: 3,
    ),
    ligneMatrice(
      userId: 'bernard',
      nom: 'Bernard Louis',
      jours: 'D$reste',
      nuits: '.$reste',
      maxAstreintes: 3,
      accepteesPrecedentes: 4,
    ),
    ligneMatrice(
      userId: 'camus',
      nom: 'Camus Awa',
      jours: 'D$reste',
      nuits: '.$reste',
      maxAstreintes: 2,
      astreintes: 2,
    ),
    ligneMatrice(
      userId: 'dupuis',
      nom: 'Dupuis Théo',
      jours: 'A$reste',
      nuits: '.$reste',
      maxAstreintes: 5,
      commentaire: 'Pas plus d\'un weekend.',
    ),
  ];
}

Future<FauxPlanningRepository> _ouvrir(
  WidgetTester tester, {
  FauxPlanningRepository? depot,
  Size taille = _poste,
  Appartenance appartenance = appartenanceAdmin,
}) async {
  final planning =
      depot ??
      FauxPlanningRepository(
        planning: planningBrouillon,
        creneaux: creneauxDuMois(_joursDuMois),
        disponibles: <String>{
          'aubry@c-1-j',
          'bernard@c-1-j',
          'camus@c-1-j',
          'aubry@c-1-n',
        },
      );
  addTearDown(planning.fermer);

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
    matrice: FauxMatriceRepository(lignes: _membres()),
    planning: planning,
    taille: taille,
  );
  await ouvrirRoute(tester, _chemin);
  return planning;
}

/// Le créneau de jour d'aujourd'hui : c'est celui que la vue par jour ouvre.
final String _creneauDuJour = 'c-${_maintenant.day}-j';

/// La case de la ligne des créneaux, ou le bouton de la vue par jour : les
/// deux portent la même clé, parce qu'ils désignent le même créneau.
Finder _creneau(String id) => find.byKey(ValueKey<String>('creneau-$id'));

/// Le contenu de la pastille d'un créneau : « 0/1 ».
String _fraction(WidgetTester tester, String id) {
  final pastille = tester.widget<PastilleCouverture>(
    find.descendant(of: _creneau(id), matching: find.byType(PastilleCouverture)),
  );
  return AppStrings.planningFraction(pastille.pourvus, pastille.requis);
}

/// Amène un widget dans la fenêtre puis le touche.
///
/// Le panneau défile, et sa liste de candidats peut être plus longue que
/// l'écran : toucher sans amener à l'écran manque la cible et ne dit rien.
Future<void> _toucher(WidgetTester tester, Finder quoi) async {
  await tester.ensureVisible(quoi);
  await tester.pumpAndSettle();
  await tester.tap(quoi);
  await tester.pumpAndSettle();
}

/// Sur un téléphone, la barre de commande et le ruban des jours défilent avec
/// le contenu : le bloc des créneaux n'est pas construit tant qu'il n'est pas
/// approché.
Future<void> _descendre(WidgetTester tester, Finder quoi) async {
  for (var essai = 0; essai < 8 && quoi.evaluate().isEmpty; essai++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
  }
}

Future<void> _ouvrirPanneau(WidgetTester tester, String id) async {
  await _toucher(tester, _creneau(id));
}

/// Le nom d'un membre **dans le panneau** : il est aussi dans la colonne
/// figée de la matrice, et les deux ne désignent pas la même chose.
Finder _dansPanneau(Finder quoi) =>
    find.descendant(of: find.byType(PanneauCreneau), matching: quoi);

/// Le bouton d'action de la ligne d'un membre, dans le panneau.
///
/// `find.byType` compare le type **exact** : `TextButton.icon` construit un
/// `_TextButtonWithIcon`, qui n'est pas un `TextButton` à ses yeux. Le prédicat,
/// lui, voit l'héritage.
Finder _actionCandidat(String nom) => find.descendant(
  of: find.ancestor(
    of: _dansPanneau(find.text(nom)),
    matching: find.byType(LigneCandidat),
  ),
  matching: find.byWidgetPredicate((Widget w) => w is TextButton),
);

Finder _boutonAttribuer(String nom) => _actionCandidat(nom);

void main() {
  group('Le planning du mois — sa création', () {
    testWidgets('sans planning, la barre propose de le créer et dit ce que '
        'ça fera', (tester) async {
      await _ouvrir(
        tester,
        depot: FauxPlanningRepository(joursDuMoisACreer: _joursDuMois),
      );

      expect(
        find.text(
          AppStrings.planningCreer(
            AppStrings.moisLongs[_moisAffiche.month - 1],
          ),
        ),
        findsOneWidget,
      );
      // Le nombre de créneaux est celui **du mois affiché**, jamais un 62
      // supposé.
      expect(
        find.text(AppStrings.planningCreerDetail(_joursDuMois * 2)),
        findsOneWidget,
      );
      // Pas de planning, pas de ligne de créneaux : une fraction sur un mois
      // sans créneaux ne voudrait rien dire.
      expect(find.byType(PastilleCouverture), findsNothing);
    });

    testWidgets('la création pose les créneaux avec l\'effectif requis des '
        'réglages', (tester) async {
      final depot = await _ouvrir(
        tester,
        depot: FauxPlanningRepository(
          joursDuMoisACreer: _joursDuMois,
          // L'effectif vient des réglages de la caserne, **copié** à la
          // création : c'est la règle du ticket 010.
          effectifACreer: 2,
        ),
      );

      await tester.tap(
        find.text(
          AppStrings.planningCreer(
            AppStrings.moisLongs[_moisAffiche.month - 1],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(depot.creations, 1);
      expect(_fraction(tester, 'c-1-j'), '0/2');
      expect(
        find.text(
          AppStrings.planningCreeTexte(
            AppStrings.moisLongs[_moisAffiche.month - 1],
            _joursDuMois * 2,
          ),
        ),
        findsOneWidget,
      );
      // Le planning existe : la barre le dit, et n'offre plus de le créer.
      expect(find.text(AppStrings.planningPourvu), findsNothing);
      expect(find.text(AppStrings.planningDirect), findsOneWidget);
    });
  });

  group('La ligne des créneaux', () {
    testWidgets('porte une fraction par colonne, et la sélection se voit',
        (tester) async {
      await _ouvrir(tester);

      expect(_fraction(tester, 'c-1-j'), '0/1');
      expect(_fraction(tester, 'c-2-n'), '0/1');

      final semantique = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(_creneau('c-1-j'))
            .label
            .contains('0 attribué sur 1 requis'),
        isTrue,
      );
      semantique.dispose();
    });

    testWidgets('l\'état suit les attributions : à pourvoir, pourvu, '
        'sur-pourvu', (tester) async {
      await _ouvrir(
        tester,
        depot: FauxPlanningRepository(
          planning: planningBrouillon,
          creneaux: creneauxDuMois(_joursDuMois),
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-2-j', userId: 'aubry'),
            Attribution(id: 'a2', creneauId: 'c-3-j', userId: 'aubry'),
            Attribution(id: 'a3', creneauId: 'c-3-j', userId: 'bernard'),
          ],
        ),
      );

      expect(_fraction(tester, 'c-1-j'), '0/1');
      expect(_fraction(tester, 'c-2-j'), '1/1');
      expect(_fraction(tester, 'c-3-j'), '2/1');
    });
  });

  group('Le panneau des candidats', () {
    testWidgets('liste les disponibles dans l\'ordre du PRD et sépare les '
        'non disponibles', (tester) async {
      await _ouvrir(tester);
      await _ouvrirPanneau(tester, 'c-1-j');

      expect(find.text(AppStrings.planningSectionAttribues(0)), findsOneWidget);
      expect(find.text(AppStrings.planningAucunAttribue), findsOneWidget);
      expect(
        find.text(AppStrings.planningSectionDisponibles(3)),
        findsOneWidget,
      );
      // Un seul non disponible : Dupuis, absent ce créneau-là.
      expect(
        find.text(AppStrings.planningSectionNonDisponibles(1)),
        findsOneWidget,
      );

      // L'ordre : Aubry (3 restantes, 0 acceptée) avant Bernard (3 restantes,
      // 4 acceptées) avant Camus (quota atteint).
      final positions = <String, double>{
        for (final nom in <String>['Aubry Irène', 'Bernard Louis', 'Camus Awa'])
          nom: tester.getTopLeft(_dansPanneau(find.text(nom))).dy,
      };
      expect(positions['Aubry Irène']!, lessThan(positions['Bernard Louis']!));
      expect(positions['Bernard Louis']!, lessThan(positions['Camus Awa']!));

      // La section des non disponibles est fermée : Dupuis n'est pas listé.
      expect(_dansPanneau(find.text('Dupuis Théo')), findsNothing);
    });

    testWidgets('un membre au quota atteint est marqué, et reste attribuable',
        (tester) async {
      final depot = await _ouvrir(tester);
      await _ouvrirPanneau(tester, 'c-1-j');

      expect(find.text(AppStrings.planningQuotaAtteint), findsOneWidget);

      await _toucher(tester, _boutonAttribuer('Camus Awa'));

      // Aucun dialogue : le quota s'est dit en clair avant le geste.
      expect(find.text(AppStrings.planningHorsDispoTitre), findsNothing);
      expect(depot.attributions.single.userId, 'camus');
      expect(_fraction(tester, 'c-1-j'), '1/1');
    });

    testWidgets('attribuer un membre disponible met la couverture à jour',
        (tester) async {
      final depot = await _ouvrir(tester);
      await _ouvrirPanneau(tester, 'c-1-j');

      await _toucher(tester, _boutonAttribuer('Aubry Irène'));

      expect(depot.attributions.single.creneauId, 'c-1-j');
      expect(_fraction(tester, 'c-1-j'), '1/1');
      expect(find.text(AppStrings.planningSectionAttribues(1)), findsOneWidget);
      expect(find.text(AppStrings.planningPourvu), findsWidgets);
    });

    testWidgets('attribuer hors disponibilité demande confirmation et laisse '
        'sa trace', (tester) async {
      final depot = await _ouvrir(tester);
      await _ouvrirPanneau(tester, 'c-1-j');

      await _toucher(
        tester,
        find.text(AppStrings.planningSectionNonDisponibles(1)),
      );
      expect(_dansPanneau(find.text('Dupuis Théo')), findsOneWidget);

      await _toucher(tester, _boutonAttribuer('Dupuis Théo'));

      // Le seul dialogue de l'écran, et il nomme les conséquences.
      expect(find.text(AppStrings.planningHorsDispoTitre), findsOneWidget);
      expect(find.textContaining('s\'est déclaré absent'), findsOneWidget);
      expect(
        find.textContaining('enregistrée à ton nom dans l\'historique'),
        findsOneWidget,
      );

      await tester.tap(find.text(AppStrings.planningHorsDispoValider));
      await tester.pumpAndSettle();

      expect(depot.attributions.single.userId, 'dupuis');
      // La trace que le schéma prévoit : `was_available = false`, posée par la
      // base et non par le client.
      final posee = depot.attributionsPosees.single;
      expect(posee.etaitDisponible, isFalse);
    });

    testWidgets('annuler la confirmation n\'attribue rien', (tester) async {
      final depot = await _ouvrir(tester);
      await _ouvrirPanneau(tester, 'c-1-j');
      await _toucher(
        tester,
        find.text(AppStrings.planningSectionNonDisponibles(1)),
      );
      await _toucher(tester, _boutonAttribuer('Dupuis Théo'));
      await tester.tap(find.text(AppStrings.planningHorsDispoAnnuler));
      await tester.pumpAndSettle();

      expect(depot.attributions, isEmpty);
      expect(_fraction(tester, 'c-1-j'), '0/1');
    });

    testWidgets('retirer une attribution la supprime, et propose d\'annuler',
        (tester) async {
      final depot = await _ouvrir(
        tester,
        depot: FauxPlanningRepository(
          planning: planningBrouillon,
          creneaux: creneauxDuMois(_joursDuMois),
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'aubry'),
          ],
        ),
      );
      await _ouvrirPanneau(tester, 'c-1-j');
      expect(_fraction(tester, 'c-1-j'), '1/1');

      await _toucher(tester, _actionCandidat('Aubry Irène'));

      // **Aucune confirmation** : en brouillon, rien n'est parti.
      expect(depot.retraits, <String>['a1']);
      expect(_fraction(tester, 'c-1-j'), '0/1');
      expect(find.text(AppStrings.planningRetireeTexte), findsOneWidget);

      // La sortie : « Annuler » repose l'attribution.
      await tester.tap(find.text(AppStrings.planningAnnulerRetrait));
      await tester.pumpAndSettle();
      expect(depot.attributions.single.userId, 'aubry');
      expect(_fraction(tester, 'c-1-j'), '1/1');
    });

    testWidgets('une double attribution est refusée proprement',
        (tester) async {
      final depot = await _ouvrir(tester);
      await _ouvrirPanneau(tester, 'c-1-j');

      // L'autre administrateur a été plus rapide : la contrainte d'unicité de
      // la base refuse la seconde écriture.
      depot.erreurEcriture = ErreurPlanning.dejaAttribue;
      await _toucher(tester, _boutonAttribuer('Aubry Irène'));

      expect(find.text(AppStrings.planningDejaAttribue), findsOneWidget);
      // La case revient à sa valeur : l'écran ne garde pas un chiffre que la
      // base ignore.
      expect(_fraction(tester, 'c-1-j'), '0/1');
    });

    testWidgets('modifier l\'effectif requis ne touche que ce créneau',
        (tester) async {
      final depot = await _ouvrir(tester);
      await _ouvrirPanneau(tester, 'c-1-j');

      expect(find.text(AppStrings.planningEffectifDetail), findsOneWidget);

      await _toucher(
        tester,
        find.descendant(
          of: find.byType(PanneauCreneau),
          matching: find.widgetWithIcon(IconButton, Icons.add),
        ),
      );

      expect(depot.effectifs.single, (creneauId: 'c-1-j', effectif: 2));
      expect(_fraction(tester, 'c-1-j'), '0/2');
      expect(_fraction(tester, 'c-1-n'), '0/1');
    });
  });

  group('Le temps réel', () {
    testWidgets('une attribution posée ailleurs arrive sans rien toucher',
        (tester) async {
      final depot = await _ouvrir(tester);
      await _ouvrirPanneau(tester, 'c-1-j');
      expect(_fraction(tester, 'c-1-j'), '0/1');

      depot.posePar(
        creneauId: 'c-1-j',
        userId: 'bernard',
        auteurId: 'aubry',
      );
      await tester.pumpAndSettle();

      expect(_fraction(tester, 'c-1-j'), '1/1');
      // Le panneau reste ouvert, et il dit qui a écrit — le nom vient des
      // lignes de la matrice déjà chargées.
      expect(
        find.text(AppStrings.planningModifieDistant('Aubry Irène')),
        findsOneWidget,
      );
      expect(find.text(AppStrings.planningSectionAttribues(1)), findsOneWidget);
    });

    testWidgets('un retrait distant ne porte qu\'un identifiant, et suffit',
        (tester) async {
      final depot = await _ouvrir(
        tester,
        depot: FauxPlanningRepository(
          planning: planningBrouillon,
          creneaux: creneauxDuMois(_joursDuMois),
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-4-j', userId: 'aubry'),
          ],
        ),
      );
      expect(_fraction(tester, 'c-4-j'), '1/1');

      depot.diffuser(const AttributionSupprimee('a1'));
      await tester.pumpAndSettle();
      expect(_fraction(tester, 'c-4-j'), '0/1');

      // Un identifiant inconnu — une autre caserne, un autre mois — ne casse
      // rien : les suppressions ne sont pas filtrées par la base.
      depot.diffuser(const AttributionSupprimee('jamais-vue'));
      await tester.pumpAndSettle();
      expect(_fraction(tester, 'c-4-j'), '0/1');
    });

    testWidgets('le canal interrompu est dit, pas tu', (tester) async {
      final depot = await _ouvrir(tester);
      expect(find.text(AppStrings.planningDirect), findsOneWidget);

      depot.diffuser(const EtatCanalPlanning(branche: false));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.planningDirectInterrompu), findsOneWidget);
    });
  });

  group('Le téléphone', () {
    testWidgets('les deux créneaux du jour sont des cibles de 48 dp',
        (tester) async {
      await _ouvrir(tester, taille: _telephone);
      // La vue par jour s'ouvre sur **aujourd'hui** : c'est ce jour-là que le
      // chef regarde en premier.
      await _descendre(tester, _creneau(_creneauDuJour));

      final bouton = _creneau(_creneauDuJour);
      expect(bouton, findsOneWidget);
      expect(tester.getSize(bouton).height, greaterThanOrEqualTo(48));
      expect(_fraction(tester, _creneauDuJour), '0/1');
    });

    testWidgets('toucher un créneau ouvre le panneau en feuille',
        (tester) async {
      await _ouvrir(tester, taille: _telephone);
      await _descendre(tester, _creneau(_creneauDuJour));
      await _ouvrirPanneau(tester, _creneauDuJour);

      // Une feuille de bas d'écran, jamais un dialogue, et le panneau entier :
      // rien n'est perdu sur téléphone.
      expect(find.byType(PanneauCreneau), findsOneWidget);
      expect(find.text(AppStrings.planningEffectifRequis), findsOneWidget);
      // Personne n'a saisi ce jour-là : **l'état vide explique et propose une
      // action**, celle que le chef fera ensuite.
      expect(
        find.text(AppStrings.planningAucunDisponibleTitre),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.planningVoirNonDisponibles),
        findsOneWidget,
      );
    });
  });
}
