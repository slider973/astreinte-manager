import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/data/planning_repository.dart';
import 'package:astreinte_sp/features/planning/domain/candidat.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:astreinte_sp/features/planning/domain/suivi_planning.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/ligne_candidat.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/panneau_creneau.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/squelette_panneau.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';
import '../../support/faux_suivi.dart';

const String _chemin = '/admin/suivi';

/// Le poste du chef de centre : c'est là que le panneau vit dans le volet de
/// droite, et c'est là qu'on répare un planning.
const Size _poste = Size(1440, 900);

final DateTime _maintenant = DateTime.now();
final DateTime _moisAffiche = DateTime(_maintenant.year, _maintenant.month);

int get _joursDuMois =>
    DateTime(_moisAffiche.year, _moisAffiche.month + 1, 0).day;

PeriodeSaisie _periode() =>
    periodeOuverte(annee: _moisAffiche.year, mois: _moisAffiche.month);

/// Trois membres : deux disponibles le 1er de jour, un absent.
List<LigneMatrice> _membres() {
  final reste = '.' * (_joursDuMois - 1);
  return <LigneMatrice>[
    ligneMatrice(
      userId: 'girard',
      nom: 'Camille G.',
      jours: 'D$reste',
      nuits: 'D$reste',
      maxAstreintes: 5,
    ),
    ligneMatrice(
      userId: 'bernard',
      nom: 'Lucas B.',
      jours: 'D$reste',
      nuits: '.$reste',
      maxAstreintes: 5,
      accepteesPrecedentes: 3,
    ),
    ligneMatrice(
      userId: 'moreau',
      nom: 'Thomas M.',
      jours: 'A$reste',
      nuits: '.$reste',
      maxAstreintes: 5,
    ),
    ligneMatrice(
      userId: 'lefebvre',
      nom: 'Marie L.',
      jours: '.$reste',
      nuits: 'D$reste',
      maxAstreintes: 5,
    ),
  ];
}

/// Deux créneaux, deux situations :
///   - `c-1-j` : Thomas M. **a refusé**. Rien ne le couvre, le créneau est vide.
///   - `c-1-n` : Marie L. **a accepté**. Rien à réparer.
List<AttributionSuivi> _reponses() => <AttributionSuivi>[
  attributionSuivi(
    id: 'a-refus',
    creneauId: 'c-1-j',
    userId: 'moreau',
    nom: 'Thomas M.',
    etat: AttributionEtat.refuse,
    proposeeLe: _maintenant.subtract(const Duration(days: 4)),
    repondueLe: _maintenant.subtract(const Duration(days: 3)),
    motifRefus: 'en formation',
  ),
  attributionSuivi(
    id: 'a-acceptee',
    creneauId: 'c-1-n',
    userId: 'lefebvre',
    nom: 'Marie L.',
    etat: AttributionEtat.accepte,
    proposeeLe: _maintenant.subtract(const Duration(days: 4)),
    repondueLe: _maintenant.subtract(const Duration(days: 3)),
  ),
];

List<CreneauPlanning> _creneaux() => <CreneauPlanning>[
  creneau(id: 'c-1-j', jour: 1),
  creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit),
];

typedef Poste = ({
  FauxSuiviRepository suivi,
  FauxPlanningRepository planning,
});

Future<Poste> _ouvrir(
  WidgetTester tester, {
  List<AttributionSuivi>? reponses,
  PlanningBrouillon? entete,
  FauxPlanningRepository? depotPlanning,
  Size taille = _poste,
  Appartenance appartenance = appartenanceAdmin,
}) async {
  final suivi = FauxSuiviRepository(
    planning: entete ?? planningPublie(),
    creneaux: _creneaux(),
    attributions: reponses ?? _reponses(),
  );
  addTearDown(suivi.fermer);

  // Le planning que lit le panneau : **les attributions actives seulement**,
  // comme la base les rend (`proposed` et `accepted`).
  final planning =
      depotPlanning ??
      FauxPlanningRepository(
        planning: entete ?? planningPublie(),
        creneaux: _creneaux(),
        attributions: const <Attribution>[
          Attribution(id: 'a-acceptee', creneauId: 'c-1-n', userId: 'lefebvre'),
        ],
        disponibles: <String>{'girard@c-1-j', 'bernard@c-1-j'},
      );
  addTearDown(planning.fermer);

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
    matrice: FauxMatriceRepository(lignes: _membres()),
    planning: planning,
    suivi: suivi,
    taille: taille,
  );
  await ouvrirRoute(tester, _chemin);
  return (suivi: suivi, planning: planning);
}

/// Amène un widget dans la fenêtre puis le touche : le panneau défile, et une
/// cible hors écran ne dit rien de ce qu'on voulait vérifier.
Future<void> _toucher(WidgetTester tester, Finder quoi) async {
  await tester.ensureVisible(quoi);
  await tester.pumpAndSettle();
  await tester.tap(quoi);
  await tester.pumpAndSettle();
}

/// Le nom d'un membre **dans le panneau** : il est aussi dans la liste du
/// suivi, et les deux ne désignent pas la même chose.
Finder _dansPanneau(Finder quoi) =>
    find.descendant(of: find.byType(PanneauCreneau), matching: quoi);

/// Le bouton d'action de la ligne d'un membre, dans le panneau.
///
/// `find.byType` compare le type **exact** : `TextButton.icon` construit un
/// `_TextButtonWithIcon`, qui n'est pas un `TextButton` à ses yeux.
Finder _bouton(String nom) => find.descendant(
  of: find.ancestor(
    of: _dansPanneau(find.text(nom)),
    matching: find.byType(LigneCandidat),
  ),
  matching: find.byWidgetPredicate((Widget w) => w is TextButton),
);

void main() {
  group('Le suivi rend les créneaux réparables', () {
    testWidgets('un créneau refusé porte « Réattribuer »', (tester) async {
      await _ouvrir(tester);

      expect(find.text(AppStrings.reattribuerAction), findsOneWidget);
    });

    testWidgets(
      'un créneau entièrement accepté reste inerte',
      (tester) async {
        await _ouvrir(
          tester,
          reponses: <AttributionSuivi>[
            attributionSuivi(
              id: 'a-acceptee',
              creneauId: 'c-1-j',
              userId: 'lefebvre',
              nom: 'Marie L.',
              etat: AttributionEtat.accepte,
              proposeeLe: _maintenant.subtract(const Duration(days: 4)),
            ),
            attributionSuivi(
              id: 'a-acceptee-2',
              creneauId: 'c-1-n',
              userId: 'girard',
              nom: 'Camille G.',
              etat: AttributionEtat.accepte,
              proposeeLe: _maintenant.subtract(const Duration(days: 4)),
            ),
          ],
        );

        // Ni « Réattribuer » ni « Pourvoir » : il n'y a rien à ouvrir, et un
        // élément qui a l'air cliquable sans servir est pire qu'un élément
        // inerte.
        expect(find.text(AppStrings.reattribuerAction), findsNothing);
        expect(find.text(AppStrings.pourvoirAction), findsNothing);
      },
    );

    testWidgets('un créneau vide porte « Pourvoir », pas « Réattribuer »', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        reponses: <AttributionSuivi>[
          attributionSuivi(
            id: 'a-acceptee',
            creneauId: 'c-1-n',
            userId: 'lefebvre',
            nom: 'Marie L.',
            etat: AttributionEtat.accepte,
            proposeeLe: _maintenant.subtract(const Duration(days: 4)),
          ),
        ],
      );

      expect(find.text(AppStrings.pourvoirAction), findsOneWidget);
      expect(find.text(AppStrings.reattribuerAction), findsNothing);
    });

    testWidgets('un planning en brouillon n\'ouvre rien depuis le suivi', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        entete: const PlanningBrouillon(
          id: 'plan-1',
          etat: PlanningEtat.brouillon,
        ),
      );

      // L'écran montre l'état vide du brouillon : rien n'est parti, il n'y a
      // rien à suivre et rien à réparer.
      expect(find.text(AppStrings.reattribuerAction), findsNothing);
      expect(find.text(AppStrings.suiviBrouillonTitre), findsOneWidget);
    });

    testWidgets('l\'historique dit qui a repris la garde', (tester) async {
      await _ouvrir(
        tester,
        reponses: <AttributionSuivi>[
          attributionSuivi(
            id: 'a-refus',
            creneauId: 'c-1-j',
            userId: 'moreau',
            nom: 'Thomas M.',
            etat: AttributionEtat.refuse,
            proposeeLe: _maintenant.subtract(const Duration(days: 4)),
            motifRefus: 'en formation',
            remplaceParId: 'a-nouvelle',
          ),
          attributionSuivi(
            id: 'a-nouvelle',
            creneauId: 'c-1-j',
            userId: 'girard',
            nom: 'Camille G.',
            proposeeLe: _maintenant.subtract(const Duration(hours: 1)),
          ),
        ],
      );

      // Le refus **reste** affiché, avec son motif, et il dit ce qui l'a
      // couvert : une sortie sans son entrée obligerait le chef à recompter.
      expect(find.text(AppStrings.suiviMotifRefus('en formation')),
          findsOneWidget);
      expect(
        find.text(AppStrings.suiviRemplacePar('Camille G.')),
        findsOneWidget,
      );
    });

    testWidgets('une attribution remplacée porte son libellé propre', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        reponses: <AttributionSuivi>[
          attributionSuivi(
            id: 'a-remplacee',
            creneauId: 'c-1-j',
            userId: 'moreau',
            nom: 'Thomas M.',
            etat: AttributionEtat.remplace,
            proposeeLe: _maintenant.subtract(const Duration(days: 4)),
          ),
        ],
      );

      // « Remplacé », pas « Annulé » : la garde existe toujours, elle a changé
      // de main.
      expect(
        find.textContaining(AppStrings.attributionRemplace.toLowerCase()),
        findsWidgets,
      );
    });
  });

  group('Le panneau des candidats, rouvert sur un planning publié', () {
    testWidgets('il s\'ouvre sur le créneau refusé et dit ce qu\'il coûte', (
      tester,
    ) async {
      await _ouvrir(tester);
      await _toucher(tester, find.text(AppStrings.reattribuerAction));

      expect(find.byType(PanneauCreneau), findsOneWidget);
      // Le bandeau nomme celui qui a refusé **et** la conséquence du geste.
      expect(
        find.text(AppStrings.reattributionBandeauRefus('Thomas M.')),
        findsOneWidget,
      );
      // Le geste ne s'appelle plus « Attribuer » : il notifie.
      expect(
        find.descendant(
          of: find.byType(PanneauCreneau),
          matching: find.text(AppStrings.reattribuerAction),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(PanneauCreneau),
          matching: find.text(AppStrings.planningAttribuer),
        ),
        findsNothing,
      );
    });

    testWidgets('une annulation ne se dit pas comme un refus', (tester) async {
      await _ouvrir(
        tester,
        reponses: <AttributionSuivi>[
          attributionSuivi(
            id: 'a-annulee',
            creneauId: 'c-1-j',
            userId: 'moreau',
            nom: 'Thomas M.',
            etat: AttributionEtat.annule,
            proposeeLe: _maintenant.subtract(const Duration(days: 4)),
            motifRefus: 'manœuvre annulée',
          ),
        ],
      );
      await _toucher(tester, find.text(AppStrings.reattribuerAction));

      // La caserne a retiré la garde ; personne n'a refusé. Le dire autrement
      // mettrait un refus sur le dos de quelqu'un qui n'a rien refusé.
      expect(
        find.text(AppStrings.reattributionBandeauAnnulation('Thomas M.')),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.reattributionBandeauRefus('Thomas M.')),
        findsNothing,
      );
    });

    testWidgets('réattribuer demande confirmation avant de notifier', (
      tester,
    ) async {
      final poste = await _ouvrir(tester);
      await _toucher(tester, find.text(AppStrings.reattribuerAction));
      await _toucher(tester, _bouton('Camille G.'));

      // **Rien n'est parti tant que la confirmation n'est pas donnée** : le
      // geste est irréversible, on ne rappelle pas un push.
      expect(poste.planning.reattributions, isEmpty);
      expect(find.text(AppStrings.reattribuerTitre), findsOneWidget);

      await _toucher(tester, find.text(AppStrings.reattribuerConfirmer));

      expect(poste.planning.reattributions, hasLength(1));
      final demande = poste.planning.reattributions.single;
      expect(demande.creneauId, 'c-1-j');
      expect(demande.userId, 'girard');
      // **Le lien est désigné, pas deviné** : c'est ce refus-là qu'on répare.
      expect(demande.ancienneId, 'a-refus');
    });

    // **Le refus se dit avec ses mots.** Le créneau plein est le cas que la base
    // refuse pour tenir « aucune notification en trop » ; l'écran doit nommer la
    // sortie — augmenter l'effectif requis — et non servir un « ça n'a pas
    // abouti » qui n'apprend rien.
    testWidgets('un créneau déjà pourvu le dit, et dit comment le renforcer', (
      tester,
    ) async {
      final planning = FauxPlanningRepository(
        planning: planningPublie(),
        creneaux: _creneaux(),
        attributions: const <Attribution>[
          Attribution(id: 'a-acceptee', creneauId: 'c-1-n', userId: 'lefebvre'),
        ],
        disponibles: <String>{'girard@c-1-j', 'bernard@c-1-j'},
        erreurEcriture: ErreurPlanning.creneauPourvu,
      );

      await _ouvrir(tester, depotPlanning: planning);
      await _toucher(tester, find.text(AppStrings.reattribuerAction));
      await _toucher(tester, _bouton('Camille G.'));
      await _toucher(tester, find.text(AppStrings.reattribuerConfirmer));

      expect(find.text(AppStrings.reattribuerCreneauPourvu), findsOneWidget);
      expect(find.text(AppStrings.reattribuerErreur), findsNothing);
    });

    testWidgets('renoncer à la confirmation ne notifie personne', (
      tester,
    ) async {
      final poste = await _ouvrir(tester);
      await _toucher(tester, find.text(AppStrings.reattribuerAction));
      await _toucher(tester, _bouton('Camille G.'));
      await _toucher(tester, find.text(AppStrings.reattribuerAnnuler));

      expect(poste.planning.reattributions, isEmpty);
    });

    testWidgets('la réattribution annonce qui a été prévenu', (tester) async {
      final poste = await _ouvrir(tester);
      await _toucher(tester, find.text(AppStrings.reattribuerAction));
      await _toucher(tester, _bouton('Camille G.'));
      await _toucher(tester, find.text(AppStrings.reattribuerConfirmer));

      expect(
        find.text(AppStrings.reattribuerFaite('Camille G.')),
        findsOneWidget,
      );
      expect(poste.suivi.lectures, greaterThan(1));
    });

    testWidgets(
      'un candidat qui s\'est déclaré absent porte son avertissement dans la '
      'MÊME feuille',
      (tester) async {
        await _ouvrir(tester);
        await _toucher(tester, find.text(AppStrings.reattribuerAction));

        // Thomas M. est absent le 1er de jour : il est dans les non
        // disponibles, repliés.
        await _toucher(
          tester,
          find.text(AppStrings.planningSectionNonDisponibles(2)),
        );
        await _toucher(tester, _bouton('Thomas M.'));

        // Une seule feuille porte les deux faits : une confirmation par sujet
        // apprendrait à cliquer « Oui » sans lire.
        expect(find.text(AppStrings.reattribuerTitre), findsOneWidget);
        expect(
          find.text(AppStrings.reattribuerHorsDispo('Thomas M.')),
          findsOneWidget,
        );
      },
    );

    testWidgets('sur un planning publié, « Retirer » devient « Annuler »', (
      tester,
    ) async {
      // Un créneau de nuit qui demande **deux** personnes et n'en a qu'une :
      // il est à pourvoir, donc ouvrable, et il porte un titulaire — les deux
      // conditions pour voir le geste de retrait sur un planning publié.
      final suivi = FauxSuiviRepository(
        planning: planningPublie(),
        creneaux: <CreneauPlanning>[
          creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit,
              effectifRequis: 2),
        ],
        attributions: <AttributionSuivi>[
          attributionSuivi(
            id: 'a-acceptee',
            creneauId: 'c-1-n',
            userId: 'lefebvre',
            nom: 'Marie L.',
            etat: AttributionEtat.accepte,
            proposeeLe: _maintenant.subtract(const Duration(days: 4)),
          ),
        ],
      );
      addTearDown(suivi.fermer);
      final planning = FauxPlanningRepository(
        planning: planningPublie(),
        creneaux: <CreneauPlanning>[
          creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit,
              effectifRequis: 2),
        ],
        attributions: const <Attribution>[
          Attribution(id: 'a-acceptee', creneauId: 'c-1-n', userId: 'lefebvre'),
        ],
      );
      addTearDown(planning.fermer);

      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: <Appartenance>[appartenanceAdmin],
        dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
        matrice: FauxMatriceRepository(lignes: _membres()),
        planning: planning,
        suivi: suivi,
        taille: _poste,
      );
      await ouvrirRoute(tester, _chemin);
      await _toucher(tester, find.text(AppStrings.pourvoirAction));

      // Le libellé dit la conséquence : sur un planning publié, retirer
      // quelqu'un **annule sa garde** et lui laisse une trace.
      expect(
        _dansPanneau(find.text(AppStrings.annulerAstreinteAction)),
        findsOneWidget,
      );
      expect(_dansPanneau(find.text(AppStrings.planningRetirer)), findsNothing);

      await _toucher(tester, _bouton('Marie L.'));

      // Rien n'est parti avant la confirmation, et la feuille porte le champ
      // de motif : « annulée » sans raison est un coup de téléphone de plus.
      expect(planning.annulations, isEmpty);
      expect(find.text(AppStrings.annulerAstreinteTitre), findsOneWidget);
      expect(find.text(AppStrings.annulerMotifLibelle), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).last,
        'manœuvre annulée',
      );
      await _toucher(tester, find.text(AppStrings.annulerConfirmer));

      expect(planning.annulations, hasLength(1));
      expect(planning.annulations.single.attributionId, 'a-acceptee');
      expect(planning.annulations.single.motif, 'manœuvre annulée');
      expect(
        find.text(AppStrings.annulerFaite('Marie L.')),
        findsOneWidget,
      );
    });

    testWidgets('hors ligne, le geste est refusé et il dit pourquoi', (
      tester,
    ) async {
      final suivi = FauxSuiviRepository(
        planning: planningPublie(),
        creneaux: _creneaux(),
        attributions: _reponses(),
      );
      addTearDown(suivi.fermer);
      final planning = FauxPlanningRepository(
        planning: planningPublie(),
        creneaux: _creneaux(),
      );
      addTearDown(planning.fermer);

      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: <Appartenance>[appartenanceAdmin],
        dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
        matrice: FauxMatriceRepository(lignes: _membres()),
        planning: planning,
        suivi: suivi,
        reseau: ConnectiviteMemoire(enLigne: false),
        taille: _poste,
      );
      await ouvrirRoute(tester, _chemin);

      // **Un contrôle désactivé porte sa raison**, à côté de lui.
      expect(find.text(AppStrings.reattribuerHorsLigne), findsWidgets);
    });
  });

  group('Ce que le panneau montre pendant qu\'il se charge', () {
    testWidgets('un squelette à la forme du panneau, jamais une roue', (
      tester,
    ) async {
      final suivi = FauxSuiviRepository(
        planning: planningPublie(),
        creneaux: _creneaux(),
        attributions: _reponses(),
      );
      addTearDown(suivi.fermer);
      final planning = FauxPlanningRepository(
        planning: planningPublie(),
        creneaux: _creneaux(),
      );
      addTearDown(planning.fermer);

      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: <Appartenance>[appartenanceAdmin],
        dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
        // **Aucune ligne de matrice** : le panneau n'a personne à proposer, et
        // `panneauCandidatsProvider` rend `null` — exactement l'état dans
        // lequel il se trouve pendant la lecture.
        matrice: FauxMatriceRepository(),
        planning: planning,
        suivi: suivi,
        taille: _poste,
      );
      await ouvrirRoute(tester, _chemin);

      // **Pas de `pumpAndSettle` ici** : le squelette balaie en continu, et
      // attendre qu'il se taise serait attendre pour toujours. C'est aussi la
      // preuve qu'il s'agit bien d'un squelette animé et non d'un aplat.
      await tester.tap(find.text(AppStrings.reattribuerAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SquelettePanneau), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Le domaine du suivi', () {
    CreneauSuivi creneauAvec(List<AttributionSuivi> attributions) =>
        CreneauSuivi(
          creneau: creneau(id: 'c-1-j', jour: 1),
          attributions: attributions,
        );

    test('un créneau entièrement accepté n\'a rien à réparer', () {
      final c = creneauAvec(<AttributionSuivi>[
        attributionSuivi(
          id: 'a1',
          creneauId: 'c-1-j',
          userId: 'u1',
          nom: 'A',
          etat: AttributionEtat.accepte,
        ),
      ]);
      expect(c.aReparer, isFalse);
      expect(c.aRemplacer, isNull);
    });

    test('un refus rend le créneau réparable et désigne ce qu\'il répare', () {
      final c = creneauAvec(<AttributionSuivi>[
        attributionSuivi(
          id: 'a1',
          creneauId: 'c-1-j',
          userId: 'u1',
          nom: 'A',
          etat: AttributionEtat.refuse,
        ),
      ]);
      expect(c.aReparer, isTrue);
      expect(c.porteUnRefus, isTrue);
      expect(c.aRemplacer?.id, 'a1');
    });

    // **L'écran et la base désignent la même ligne.** La base trie par
    // `responded_at nulls last, created_at` ; l'écran doit faire pareil, sinon
    // le bandeau nomme un pompier et le lien en relie un autre le jour où
    // l'écran cesse de fournir l'identifiant.
    test('le trou désigné est le plus ancien, comme en base', () {
      final c = creneauAvec(<AttributionSuivi>[
        attributionSuivi(
          id: 'recent',
          creneauId: 'c-1-j',
          userId: 'u2',
          nom: 'B',
          etat: AttributionEtat.refuse,
          proposeeLe: DateTime(2026, 10, 2),
          repondueLe: DateTime(2026, 10, 5),
        ),
        attributionSuivi(
          id: 'ancien',
          creneauId: 'c-1-j',
          userId: 'u1',
          nom: 'A',
          etat: AttributionEtat.refuse,
          proposeeLe: DateTime(2026, 10, 3),
          repondueLe: DateTime(2026, 10, 2),
        ),
        // Sans réponse : en queue, comme `nulls last`.
        attributionSuivi(
          id: 'sans-reponse',
          creneauId: 'c-1-j',
          userId: 'u3',
          nom: 'C',
          etat: AttributionEtat.annule,
          proposeeLe: DateTime(2026, 9, 5),
        ),
      ]);

      expect(c.aRemplacer?.id, 'ancien');
    });

    test('un refus déjà couvert ne se répare pas deux fois', () {
      final c = creneauAvec(<AttributionSuivi>[
        attributionSuivi(
          id: 'a1',
          creneauId: 'c-1-j',
          userId: 'u1',
          nom: 'A',
          etat: AttributionEtat.refuse,
          remplaceParId: 'a2',
        ),
        attributionSuivi(
          id: 'a2',
          creneauId: 'c-1-j',
          userId: 'u2',
          nom: 'B',
          etat: AttributionEtat.accepte,
        ),
      ]);
      // Le créneau est pourvu et son refus est **déjà couvert** : plus rien à
      // décider, donc plus rien à ouvrir. Le refus reste dans l'historique, il
      // ne redemande pas d'action.
      expect(c.aRemplacer, isNull);
      expect(c.aReparer, isFalse);
      expect(c.remplacantDe(c.attributions.first), 'B');
    });

    test('une annulation laisse un trou, comme un refus', () {
      final c = creneauAvec(<AttributionSuivi>[
        attributionSuivi(
          id: 'a1',
          creneauId: 'c-1-j',
          userId: 'u1',
          nom: 'A',
          etat: AttributionEtat.annule,
        ),
      ]);
      expect(c.aReparer, isTrue);
      expect(c.porteUnRefus, isTrue);
      expect(c.pourvus, 0);
    });

    test('remplacé et annulé ne comptent pas dans la couverture', () {
      final c = creneauAvec(<AttributionSuivi>[
        attributionSuivi(
          id: 'a1',
          creneauId: 'c-1-j',
          userId: 'u1',
          nom: 'A',
          etat: AttributionEtat.remplace,
        ),
        attributionSuivi(
          id: 'a2',
          creneauId: 'c-1-j',
          userId: 'u2',
          nom: 'B',
          etat: AttributionEtat.annule,
        ),
      ]);
      expect(c.pourvus, 0);
      expect(c.nonPourvu, isTrue);
    });

    // **La régression trouvée en pilotant l'écran.** Une ligne reçue par le
    // canal temps réel arrive sans nom d'usage ; le contrôleur lui rend celui
    // qu'il connaît. Reconstruire l'objet champ par champ a coûté
    // `replaced_by` : le créneau réparé gardait son bouton « Réattribuer », et
    // l'historique perdait « remplacé par… ».
    test('le recollage du nom ne perd aucune colonne', () {
      final recue = attributionSuivi(
        id: 'a1',
        creneauId: 'c-1-j',
        userId: 'u1',
        nom: '',
        etat: AttributionEtat.refuse,
        motifRefus: 'en formation',
        remplaceParId: 'a2',
      );

      final fusionnee = recue.avecNom('Thomas M.');

      expect(fusionnee.nom, 'Thomas M.');
      expect(fusionnee.remplaceParId, 'a2');
      expect(fusionnee.motifRefus, 'en formation');
      expect(fusionnee.etat, AttributionEtat.refuse);
      expect(
        creneauAvec(<AttributionSuivi>[
          fusionnee,
          attributionSuivi(
            id: 'a2',
            creneauId: 'c-1-j',
            userId: 'u2',
            nom: 'Camille G.',
            etat: AttributionEtat.accepte,
          ),
        ]).aReparer,
        isFalse,
        reason: 'le trou est comblé : plus rien à ouvrir',
      );
    });

    test('l\'ordre des réponses met le remplacé avant l\'annulé', () {
      expect(
        AttributionEtat.values,
        <AttributionEtat>[
          AttributionEtat.propose,
          AttributionEtat.accepte,
          AttributionEtat.refuse,
          AttributionEtat.remplace,
          AttributionEtat.annule,
        ],
      );
    });
  });

  group('Le mode du panneau vient du planning', () {
    PanneauCandidats panneauPour(PlanningEtat etat) {
      final mode = switch (etat) {
        PlanningEtat.brouillon => ModePanneau.construction,
        PlanningEtat.publie || PlanningEtat.valide => ModePanneau.reattribution,
        PlanningEtat.archive => ModePanneau.lecture,
      };
      return PanneauCandidats.construire(
        creneau: creneau(id: 'c-1-j', jour: 1),
        jour: DateTime(_moisAffiche.year, _moisAffiche.month),
        membres: _membres(),
        planning: PlanningMois.vide(),
        modifiable: mode != ModePanneau.lecture,
        mode: mode,
      );
    }

    test('un brouillon se construit, un publié se réattribue', () {
      expect(panneauPour(PlanningEtat.brouillon).notifie, isFalse);
      expect(panneauPour(PlanningEtat.publie).notifie, isTrue);
      expect(panneauPour(PlanningEtat.valide).notifie, isTrue);
      expect(panneauPour(PlanningEtat.archive).notifie, isFalse);
      expect(panneauPour(PlanningEtat.archive).modifiable, isFalse);
    });
  });
}
