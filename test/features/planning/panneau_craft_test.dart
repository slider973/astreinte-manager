import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/planning/domain/candidat.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/panneau_creneau.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/widgets/helpers.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';
import '../../support/polices.dart';

/// La revue `craft-floor` du panneau des candidats, chantier 061c-2 : ce qui
/// s'y touche a la taille d'un doigt, et ce qui y porte un état l'emprunte à
/// une famille du thème plutôt qu'à un rôle Material choisi au jugé.

LigneMatrice _membre(String nom, {int? maxAstreintes = 8}) => ligneMatrice(
  userId: 'u-$nom',
  nom: nom,
  jours: moisUniforme('D'),
  nuits: moisUniforme('D'),
  maxAstreintes: maxAstreintes,
  maxWeekends: 2,
);

Candidat _candidat(String nom, {DisponibiliteEtat? etat}) => Candidat(
  membre: _membre(nom),
  disponibilite: etat ?? DisponibiliteEtat.disponible,
);

PanneauCandidats _panneau({String? reattribution}) => PanneauCandidats(
  creneau: creneau(id: 'c-1-j', jour: 1),
  jour: DateTime(2026, 10),
  etat: EtatCouverture.pourvu,
  modifiable: true,
  mode: reattribution == null
      ? ModePanneau.construction
      : ModePanneau.reattribution,
  attribues: <Candidat>[_candidat('Aubry Irène')],
  disponibles: <Candidat>[_candidat('Bernard Louis')],
  nonDisponibles: <Candidat>[
    _candidat('Dupuis Théo', etat: DisponibiliteEtat.absent),
  ],
);

Future<void> _monterLePanneau(
  WidgetTester tester, {
  String? reattribution,
}) async {
  await chargerPolicesDuProduit();
  await monter(
    tester,
    // La largeur du volet de droite d'`AppScaffold` : c'est là que le panneau
    // vit sur l'écran qu'il sert.
    SizedBox(
      width: 360,
      child: PanneauCreneau(
        panneau: _panneau(reattribution: reattribution),
        onFermer: () {},
        onAttribuer: (_) {},
        onRetirer: (_) {},
        onEffectif: (_) {},
        messageReattribution: reattribution,
      ),
    ),
    taille: const Size(1440, 900),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PanneauCreneau — revue craft-floor', () {
    testWidgets('tout ce qui s\'y touche fait au moins 44 points', (
      tester,
    ) async {
      await _monterLePanneau(tester);

      verifierCiblesTactiles(
        tester,
        find.byWidgetPredicate((Widget w) => w is TextButton),
      );
      verifierCiblesTactiles(tester, find.byType(IconButton));
      verifierCiblesTactiles(
        tester,
        find.ancestor(
          of: find.text(AppStrings.planningSectionNonDisponibles(1)),
          matching: find.byType(InkWell),
        ),
      );
    });

    testWidgets('le bandeau de réattribution emprunte la famille « publié », '
        'et porte son icône', (tester) async {
      const texte =
          'Planning publié : la personne sera prévenue tout de suite.';
      await _monterLePanneau(tester, reattribution: texte);

      final publie = AppStatusColors.clair.planning(PlanningEtat.publie);

      final bloc = tester.widget<Container>(
        find
            .ancestor(of: find.text(texte), matching: find.byType(Container))
            .first,
      );
      expect((bloc.decoration! as BoxDecoration).color, publie.fond);

      // Jamais la couleur seule : l'icône de la famille accompagne le mot.
      final glyphe = tester.widget<Icon>(find.byIcon(publie.icone).first);
      expect(glyphe.color, publie.encre);
    });

    testWidgets('aucun état du panneau n\'est porté par la couleur seule : '
        'chaque marqueur a son mot', (tester) async {
      await _monterLePanneau(tester);

      // Le membre non disponible porte le libellé de son état, pas seulement
      // le rose de sa famille. La section se déplie d'abord.
      await tester.tap(find.text(AppStrings.planningSectionNonDisponibles(1)));
      await tester.pumpAndSettle();

      expect(
        find.text(
          AppStatusColors.clair.disponibilite(DisponibiliteEtat.absent).libelle,
        ),
        findsWidgets,
      );
    });
  });
}
