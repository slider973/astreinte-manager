import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_spacing.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
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
import 'package:astreinte_sp/features/planning/presentation/widgets/vue_jour.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/zone_planning.dart';
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
  int moisOuverts = 1,
  PlanningEtat etatPlanning = PlanningEtat.brouillon,
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
        for (var i = 0; i < moisOuverts; i++)
          periodeOuverte(
            annee: _maintenant.year,
            mois: _maintenant.month + i,
          ),
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
            planning: PlanningBrouillon(id: 'plan-1', etat: etatPlanning),
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

    testWidgets('la première rangée est une seule ligne de 48 points, à un '
        'comme à deux mois ouverts', (tester) async {
      await _ouvrirLaMatrice(tester, moisOuverts: 2);

      // Le mois, la recherche et le tri côte à côte : si l'un d'eux passait
      // à la ligne, la rangée ferait deux fois 48.
      final rangee = find
          .descendant(
            of: find.byType(BarreCommandeMatrice),
            matching: find.byType(Wrap),
          )
          .first;
      expect(
        tester.getSize(rangee).height,
        lessThanOrEqualTo(BarreCommandeMatrice.hauteurRangee),
      );
      expect(_hauteurBarre(tester), lessThanOrEqualTo(_plafondBarre));

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

    testWidgets('« Publier » vit dans le bandeau, pas dans la barre ni sous '
        'la grille', (tester) async {
      await _ouvrirLaMatrice(tester, avecPlanning: true, membresAttribues: 2);

      final publier = find.widgetWithText(
        PrimaryButton,
        AppStrings.publierAction,
      );
      expect(publier, findsOneWidget);
      // Le bandeau compte ce que ce bouton change : c'est là que la décision
      // se prend (chantier 061c).
      expect(
        find.descendant(of: find.byType(ZonePlanning), matching: publier),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BarreCommandeMatrice),
          matching: publier,
        ),
        findsNothing,
      );
      expect(find.text(AppStrings.publierDetail(2)), findsOneWidget);
    });

    testWidgets('avec un planning, la barre garde ses deux rangées', (
      tester,
    ) async {
      await _ouvrirLaMatrice(tester, avecPlanning: true, membresAttribues: 2);

      expect(tester.takeException(), isNull);
      expect(_hauteurBarre(tester), lessThanOrEqualTo(_plafondBarre));
      // Et le bandeau qui accueille les actions reste sous son plafond — 150
      // au 061c-1, 172 depuis que la légende des blocs d'attribution s'y
      // adosse : la barre de commande la facturait 56 points, le bandeau 22
      // (`DESIGN.md § Écarts, 061c-2`).
      expect(
        tester.getSize(find.byType(BandeauMois)).height,
        lessThanOrEqualTo(172),
      );
      expect(
        tester.getSize(find.byType(BandeauMois)).height,
        lessThanOrEqualTo(BandeauMois.hauteurCompletAvecLegende),
      );
    });

    for (final fenetre in <Size>[_portable, const Size(1000, 700)]) {
      testWidgets('à ${fenetre.width.toInt()} de large avec deux mois '
          'ouverts, les deux libellés sont entiers dans la fenêtre', (
        tester,
      ) async {
        await _ouvrirLaMatrice(tester, moisOuverts: 2, taille: fenetre);

        final vue = Offset.zero & fenetre;
        for (var i = 0; i < 2; i++) {
          final periode = periodeOuverte(
            annee: _maintenant.year,
            mois: _maintenant.month + i,
          );
          final libelle = find.text(
            AppStrings.moisEtEtat(periode.libelle, periode.ligneEtatBreve),
          );
          expect(libelle, findsOneWidget, reason: 'mois $i');
          final rect = tester.getRect(libelle);
          // **Jamais rogné, jamais caché derrière un défilement.** Le
          // sélecteur n'est borné que s'il dépasse la barre à lui seul ;
          // sinon ce sont la recherche et le tri qui descendent d'une
          // rangée. Borné à la place restante, il rognait « Octobre 2026 »
          // dès 1000 points de large — vu à l'écran.
          expect(
            vue.contains(rect.topLeft) && vue.contains(rect.bottomRight),
            isTrue,
            reason: 'mois $i, rect $rect hors de $vue',
          );
        }
      });
    }
  });

  group('Les gestes du planning suivent la matrice, pas la classe de '
      'fenêtre', () {
    testWidgets('sur une tablette portrait, la barre reprend les actions et '
        'le fil « Publier » revient sous la vue par jour', (tester) async {
      // 768 de large : ni `compact`, ni deux volets. La matrice n'y est pas,
      // le bandeau qui porte la zone du planning non plus — et sans cette
      // règle, l'admin n'avait plus aucun geste de planning.
      await _ouvrirLaMatrice(
        tester,
        taille: const Size(768, 1024),
        avecPlanning: true,
        membresAttribues: 2,
      );

      expect(find.byType(VueJour), findsOneWidget);
      expect(find.byType(ZonePlanning), findsNothing);
      expect(
        find.widgetWithText(PrimaryButton, AppStrings.publierAction),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PrimaryButton, AppStrings.proposerAction),
        findsOneWidget,
      );
    });

    testWidgets('sans planning, la tablette portrait garde « Créer le '
        'planning »', (tester) async {
      await _ouvrirLaMatrice(tester, taille: const Size(768, 1024));

      expect(
        find.widgetWithText(
          PrimaryButton,
          AppStrings.planningCreer(
            AppStrings.moisLongs[_maintenant.month - 1],
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('à 1280 avec une échelle de texte de 1,8, « Publier » reste '
        'atteignable', (tester) async {
      // L'échelle doit exister **avant** le montage : elle décide de la
      // composition, pas de la taille des glyphes.
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _ouvrirLaMatrice(
        tester,
        avecPlanning: true,
        membresAttribues: 2,
      );

      expect(find.byType(VueJour), findsOneWidget);
      expect(find.byType(ZonePlanning), findsNothing);
      expect(
        find.widgetWithText(PrimaryButton, AppStrings.publierAction),
        findsOneWidget,
      );
    });

    testWidgets('un planning publié ne promet plus de prévenir personne', (
      tester,
    ) async {
      await _ouvrirLaMatrice(
        tester,
        avecPlanning: true,
        membresAttribues: 2,
        etatPlanning: PlanningEtat.publie,
      );

      // Le bouton n'existe plus — un planning publié ne se republie pas — et
      // son explication s'en va avec lui : « 2 pompiers seront prévenus »
      // sans le geste qui les prévient est une promesse en l'air.
      expect(
        find.widgetWithText(PrimaryButton, AppStrings.publierAction),
        findsNothing,
      );
      expect(find.text(AppStrings.publierDetail(2)), findsNothing);
      // L'état, lui, se lit toujours.
      expect(find.byType(ZonePlanning), findsOneWidget);
      expect(find.text(AppStrings.planningPublie), findsOneWidget);
    });

    testWidgets('l\'explication tombe sous « Publier », pas sous « Proposer »',
        (tester) async {
      await _ouvrirLaMatrice(
        tester,
        avecPlanning: true,
        membresAttribues: 2,
      );

      final publier = find.widgetWithText(
        PrimaryButton,
        AppStrings.publierAction,
      );
      final explication = find.text(AppStrings.publierDetail(2));
      expect(publier, findsOneWidget);
      expect(explication, findsOneWidget);
      expect(
        tester.getRect(explication).left,
        moreOrLessEquals(tester.getRect(publier).left, epsilon: 0.5),
      );
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
        lessThanOrEqualTo(BandeauMois.hauteurCompletAvecLegende),
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
