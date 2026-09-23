import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_spacing.dart';
import 'package:astreinte_sp/core/widgets/legende_etats.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/presentation/widgets/selecteur_mois.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/matrice_screen.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/bandeau_mois.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/barre_commande_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/barre_repartition.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/grille_matrice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';
import '../../support/polices.dart';

/// Le cas de référence du chantier : un 13 pouces, sa barre d'adresse.
const Size _portable = Size(1280, 720);

/// La hauteur que la barre de commande ne doit pas dépasser à 1280 : deux
/// rangées de contrôles et leurs marges (`design/061 § 8 bis`).
const double _plafondBarre = 130;

final DateTime _maintenant = DateTime.now();
final int _joursDuMois = DateTime(
  _maintenant.year,
  _maintenant.month + 1,
  0,
).day;

Future<void> _ouvrirLaMatrice(
  WidgetTester tester, {
  Size taille = _portable,
  bool avecPlanning = false,
  int membresAttribues = 0,
}) async {
  // **Les vraies polices, sinon la mesure ne vaut rien.** La barre de
  // commande est faite de `Wrap` : composée avec la police d'essai, plus
  // large de moitié, elle se replie d'une ligne de plus et rend une hauteur
  // qu'aucun navigateur n'affiche. Tout ce fichier mesure des hauteurs.
  await chargerPolicesDuProduit();
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceAdmin],
    dispos: FauxDisposRepository(
      periodes: <PeriodeSaisie>[
        periodeOuverte(annee: _maintenant.year, mois: _maintenant.month),
      ],
    ),
    matrice: FauxMatriceRepository(
      lignes: <LigneMatrice>[
        ligneMatrice(
          userId: 'u1',
          nom: 'Dubois Jean-Marc',
          jours: moisUniforme('.', jours: _joursDuMois),
          nuits: moisUniforme('.', jours: _joursDuMois),
        ),
      ],
    ),
    planning: avecPlanning
        ? FauxPlanningRepository(
            planning: planningBrouillon,
            creneaux: creneauxDuMois(_joursDuMois),
            attributions: <Attribution>[
              for (var i = 0; i < membresAttribues; i++)
                Attribution(
                  id: 'a$i',
                  creneauId: 'c-${i + 1}-j',
                  userId: 'u$i',
                ),
            ],
          )
        : FauxPlanningRepository(joursDuMoisACreer: _joursDuMois),
    taille: taille,
  );
  await ouvrirRoute(tester, '/admin/planning');
}

double _hauteurBarre(WidgetTester tester) =>
    tester.getSize(find.byType(BarreCommandeMatrice)).height;

void main() {
  group('BarreCommandeMatrice — deux rangées sur grand écran', () {
    testWidgets('sans planning, la barre tient sous le plafond à 1280', (
      tester,
    ) async {
      await _ouvrirLaMatrice(tester);

      expect(tester.takeException(), isNull);
      expect(_hauteurBarre(tester), lessThanOrEqualTo(_plafondBarre));
    });

    testWidgets('la première rangée est une seule ligne de 48 points', (
      tester,
    ) async {
      await _ouvrirLaMatrice(tester);

      // Le mois, la recherche et les trois puces côte à côte : si l'un d'eux
      // passait à la ligne, la rangée ferait deux fois 48.
      final rangee = find
          .descendant(
            of: find.byType(BarreCommandeMatrice),
            matching: find.byType(Wrap),
          )
          .first;
      expect(
        tester.getSize(rangee).height,
        BarreCommandeMatrice.hauteurRangee,
      );

      expect(find.byType(SelecteurMois), findsOneWidget);
      expect(find.text(AppStrings.matriceRechercheLibelle), findsOneWidget);
      expect(find.text(AppStrings.matriceMasquerNonSaisis), findsOneWidget);
      expect(find.text(AppStrings.matriceAfficherCommentaires), findsOneWidget);
    });

    testWidgets('le sélecteur de mois tient sur une ligne, 48 au lieu de 64', (
      tester,
    ) async {
      await _ouvrirLaMatrice(tester);

      final periode = periodeOuverte(
        annee: _maintenant.year,
        mois: _maintenant.month,
      );
      expect(
        find.text(
          AppStrings.moisEtEtat(periode.libelle, periode.ligneEtatBreve),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(SelecteurMois)).height,
        SelecteurMois.hauteurBoutonUneLigne,
      );
    });

    testWidgets('l\'explication de la création tient sur une ligne', (
      tester,
    ) async {
      await _ouvrirLaMatrice(tester);

      final explication = find.text(
        AppStrings.planningCreerDetail(_joursDuMois * 2),
      );
      expect(explication, findsOneWidget);
      // Une seule ligne de texte : c'est ce qui tient la rangée à 48.
      expect(
        tester.getSize(explication).height,
        lessThan(AppSpacing.xl),
      );
      // Et elle garde ses deux faits : combien de créneaux, à quel effectif.
      expect(
        AppStrings.planningCreerDetail(62),
        allOf(contains('62'), contains('effectif requis')),
      );
    });

    testWidgets('la légende est poussée au bord droit, avec l\'indicateur '
        'd\'enregistrement', (tester) async {
      await _ouvrirLaMatrice(tester);

      final barre = tester.getRect(find.byType(BarreCommandeMatrice));
      final legende = tester.getRect(find.byType(LegendeEtats));
      // À moins d'une marge de page du bord droit de la barre.
      expect(barre.right - legende.right, lessThan(80));
    });

    testWidgets('« Publier » vit dans la barre sur grand écran, pas sous la '
        'grille', (tester) async {
      await _ouvrirLaMatrice(tester, avecPlanning: true, membresAttribues: 2);

      final publier = find.widgetWithText(
        PrimaryButton,
        AppStrings.publierAction,
      );
      expect(publier, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BarreCommandeMatrice),
          matching: publier,
        ),
        findsOneWidget,
      );
      expect(find.text(AppStrings.publierDetail(2)), findsOneWidget);
    });

    testWidgets('avec un planning encore à pourvoir, la seconde rangée prend '
        'deux lignes — et c\'est mesuré, pas subi', (tester) async {
      await _ouvrirLaMatrice(tester, avecPlanning: true, membresAttribues: 2);

      // **Le plafond n'est pas tenu dans ce cas, et le dire vaut mieux que
      // de l'arrondir.** La rangée porte alors cinq éléments que le brief du
      // 061c n'avait pas budgétés — l'état du planning, le témoin « Direct »
      // et « Proposer automatiquement », venus des tickets 017 et 018 — soit
      // 418 points dans une rangée qui en a 95 de libres. `Wrap` les passe à
      // la ligne plutôt que de les couper.
      //
      // Ce qui est tenu : la barre coûte toujours **moins** que les quatre
      // étages du 061b et le fil « Publier » qu'elle a remplacés.
      expect(tester.takeException(), isNull);
      expect(_hauteurBarre(tester), lessThan(230 + 70));
      expect(_hauteurBarre(tester), lessThanOrEqualTo(_plafondBarre + 60));
    });
  });

  group('BarreCommandeMatrice — la place rendue à la matrice', () {
    testWidgets('sur un portable en 720, le bandeau complet s\'affiche — même '
        'avec un planning créé', (tester) async {
      await _ouvrirLaMatrice(tester, avecPlanning: true, membresAttribues: 2);

      // **C'est le gain du chantier** : au 061b, le fil « Publier » et les
      // quatre étages de la barre faisaient retomber le bandeau à sa ligne de
      // trois chiffres dès qu'un planning existait.
      expect(tester.takeException(), isNull);
      expect(find.byType(BandeauMois), findsOneWidget);
      expect(find.byType(BarreRepartition), findsOneWidget);
      expect(
        tester.getSize(find.byType(BandeauMois)).height,
        BandeauMois.hauteurComplet,
      );

      // Et la grille garde ses quatre lignes de réserve.
      expect(
        tester.getSize(find.byType(GrilleMatrice)).height,
        greaterThanOrEqualTo(MatriceScreen.placeGrilleUtile),
      );
    });

    testWidgets('sur une fenêtre courte, le bandeau se réduit à sa ligne de '
        'chiffres', (tester) async {
      await _ouvrirLaMatrice(tester, taille: const Size(1280, 460));

      expect(tester.takeException(), isNull);
      expect(find.byType(GrilleMatrice), findsOneWidget);
      expect(
        tester.getSize(find.byType(BandeauMois)).height,
        BandeauMois.hauteurReduit,
      );
    });

    testWidgets('plus courte encore, la matrice garde toute la place : le '
        'bandeau s\'efface', (tester) async {
      // Un navigateur à demi hauteur : de quoi montrer une grille, et rien
      // d'autre. **La matrice est l'écran** — un résumé qui laisserait deux
      // lignes de grille aurait remplacé ce qu'il surplombe.
      await _ouvrirLaMatrice(tester, taille: const Size(1280, 380));

      expect(tester.takeException(), isNull);
      expect(find.byType(GrilleMatrice), findsOneWidget);
      expect(find.byType(BandeauMois), findsNothing);
    });
  });
}
