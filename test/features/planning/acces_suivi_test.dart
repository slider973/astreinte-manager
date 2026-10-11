import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';
import '../../support/faux_suivi.dart';

/// Ticket 079 : depuis la matrice, rien ne menait au suivi du planning.
///
/// Les deux seuls chemins étaient un lien de notification et la redirection
/// après publication — deux événements, jamais une navigation délibérée. Une
/// fois le planning publié et la notification balayée, l'écran devenait
/// injoignable, et la réattribution avec lui puisqu'elle n'existe que là.
///
/// Le libellé `AppStrings.suiviVersSuivi` était déclaré depuis le ticket 019
/// et utilisé nulle part : la trace du lien oublié.
const String _chemin = '/admin/planning';

/// Un poste d'administration : c'est de là que le chef suit son planning.
const Size _poste = Size(1440, 900);

final DateTime _maintenant = DateTime.now();
final DateTime _moisAffiche = DateTime(_maintenant.year, _maintenant.month);

PeriodeSaisie _periode() =>
    periodeOuverte(annee: _moisAffiche.year, mois: _moisAffiche.month);

List<LigneMatrice> _membres() => <LigneMatrice>[
  ligneMatrice(userId: 'u1', nom: 'Alpha', jours: '', nuits: ''),
  ligneMatrice(userId: 'u2', nom: 'Bravo', jours: '', nuits: ''),
];

/// Deux créneaux, et autant d'attributions que le test en demande.
List<CreneauPlanning> _creneaux() => const <CreneauPlanning>[
  CreneauPlanning(
    id: 'c1',
    jour: 1,
    creneau: CreneauType.jour,
    effectifRequis: 1,
  ),
  CreneauPlanning(
    id: 'c2',
    jour: 2,
    creneau: CreneauType.jour,
    effectifRequis: 1,
  ),
];

Future<FauxPlanningRepository> _ouvrir(
  WidgetTester tester, {
  required PlanningBrouillon? planning,
  List<Attribution> attributions = const <Attribution>[],
  Appartenance appartenance = appartenanceAdmin,
}) async {
  final depot = FauxPlanningRepository(
    planning: planning,
    creneaux: _creneaux(),
    attributions: attributions,
  );
  final suivi = FauxSuiviRepository();
  addTearDown(depot.fermer);
  addTearDown(suivi.fermer);

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
    matrice: FauxMatriceRepository(lignes: _membres()),
    planning: depot,
    suivi: suivi,
    taille: _poste,
  );
  await ouvrirRoute(tester, _chemin);
  return depot;
}

Finder get _lienSuivi => find.byTooltip(AppStrings.suiviVersSuivi);

void main() {
  group('Accès au suivi depuis la matrice', () {
    testWidgets('un planning publié offre le lien vers son suivi', (
      tester,
    ) async {
      await _ouvrir(tester, planning: planningPublie());

      expect(
        _lienSuivi,
        findsOneWidget,
        reason: 'sans ce lien, le suivi reste injoignable après publication',
      );
    });

    testWidgets('un brouillon ne l\'offre pas : personne n\'a été sollicité', (
      tester,
    ) async {
      await _ouvrir(tester, planning: planningBrouillon);

      expect(_lienSuivi, findsNothing);
    });

    testWidgets('sans planning du tout, rien à suivre', (tester) async {
      await _ouvrir(tester, planning: null);

      expect(_lienSuivi, findsNothing);
    });

    testWidgets('les refus à traiter sont comptés sur le lien', (tester) async {
      await _ouvrir(
        tester,
        planning: planningPublie(),
        attributions: <Attribution>[
          const Attribution(
            id: 'a1',
            creneauId: 'c1',
            userId: 'u1',
            etat: AttributionEtat.refuse,
          ),
          const Attribution(
            id: 'a2',
            creneauId: 'c2',
            userId: 'u2',
            etat: AttributionEtat.accepte,
          ),
        ],
      );

      // Le compte est écrit, pas seulement coloré : contexte d'usage binding —
      // extérieur, gants, coup d'œil rapide.
      expect(_lienSuivi, findsOneWidget);
      expect(
        find.descendant(of: _lienSuivi, matching: find.text('1')),
        findsOneWidget,
        reason: 'un refus en attente doit se voir sans entrer dans l\'écran',
      );
    });

    testWidgets('aucun refus, aucune pastille', (tester) async {
      await _ouvrir(
        tester,
        planning: planningPublie(),
        attributions: <Attribution>[
          const Attribution(
            id: 'a1',
            creneauId: 'c1',
            userId: 'u1',
            etat: AttributionEtat.accepte,
          ),
        ],
      );

      expect(_lienSuivi, findsOneWidget);
      expect(find.descendant(of: _lienSuivi, matching: find.byType(Badge)),
          findsNothing);
    });

    testWidgets('un membre simple ne voit pas ce lien', (tester) async {
      await _ouvrir(
        tester,
        planning: planningPublie(),
        appartenance: appartenanceMembre,
      );

      expect(_lienSuivi, findsNothing);
    });
  });
}
