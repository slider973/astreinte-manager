import 'dart:math' as math;

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_spacing.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/matrice_screen.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/bande_semaine.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/bandeau_mois.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/barre_repartition.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/geometrie_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/grille_matrice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/widgets/helpers.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';
import '../../support/polices.dart';

const Size _poste = Size(1440, 900);

final DateTime _maintenant = DateTime.now();
final int _joursDuMois = DateTime(
  _maintenant.year,
  _maintenant.month + 1,
  0,
).day;

/// Le fond peint d'une pastille : `Material` porte la couleur, et c'est lui
/// qui dit si le jour est courant, du weekend, ou ordinaire.
Color? _fond(WidgetTester tester, int jour) {
  final materiau = tester.widget<Material>(
    find
        .descendant(
          of: find.byType(BandeSemaine),
          matching: find.ancestor(
            of: find.text('$jour'),
            matching: find.byType(Material),
          ),
        )
        .first,
  );
  return materiau.color;
}

/// Le liseré d'une pastille : `Material` porte la forme, et c'est elle qui
/// dit si le jour est celui que la matrice montre.
BorderSide _lisere(WidgetTester tester, int jour) {
  final materiau = tester.widget<Material>(
    find
        .descendant(
          of: find.byType(BandeSemaine),
          matching: find.ancestor(
            of: find.text('$jour'),
            matching: find.byType(Material),
          ),
        )
        .first,
  );
  return (materiau.shape! as RoundedRectangleBorder).side;
}

/// Le décalage horizontal de la grille, celui que la bande commande.
double _decalage(WidgetTester tester) {
  final positions = tester
      .stateList<ScrollableState>(
        find.descendant(
          of: find.byType(GrilleMatrice),
          matching: find.byType(Scrollable),
        ),
      )
      .where(
        (ScrollableState etat) =>
            etat.position.axis == Axis.horizontal &&
            etat.position.hasContentDimensions,
      );
  return positions.first.position.pixels;
}

double _maximum(WidgetTester tester) {
  final positions = tester
      .stateList<ScrollableState>(
        find.descendant(
          of: find.byType(GrilleMatrice),
          matching: find.byType(Scrollable),
        ),
      )
      .where(
        (ScrollableState etat) =>
            etat.position.axis == Axis.horizontal &&
            etat.position.hasContentDimensions,
      );
  return positions.first.position.maxScrollExtent;
}

Future<void> _ouvrirLaMatrice(
  WidgetTester tester, {
  Size taille = _poste,
}) async {
  // **Les vraies polices, sinon la mesure ne vaut rien.** La barre de
  // commande est une `Wrap` : composée avec la police d'essai, plus large de
  // moitié, elle se replie d'une ligne de plus et rend une hauteur qu'aucun
  // navigateur n'affiche. Tout ce fichier mesure des seuils de hauteur.
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
    taille: taille,
  );
  await ouvrirRoute(tester, '/admin/planning');
}

void main() {
  group('BandeSemaine — le mois en une ligne', () {
    testWidgets('un jour par pastille, le jour courant en indigo', (
      tester,
    ) async {
      await monter(
        tester,
        BandeSemaine(
          annee: 2026,
          mois: 10,
          nombreDeJours: 31,
          aujourdhui: DateTime(2026, 10, 14),
          onJour: (_) {},
        ),
        taille: _poste,
      );

      final scheme = AppTheme.clair.colorScheme;
      // Le 14 octobre 2026 est un mercredi : jour courant, pastille indigo.
      expect(_fond(tester, 14), scheme.primaryContainer);
      // Le 17 est un samedi : un cran de surface, et le jour en gras.
      expect(_fond(tester, 17), scheme.surfaceContainer);
      // Le 15, un jeudi ordinaire : rien du tout.
      expect(_fond(tester, 15), Colors.transparent);

      // L'abréviation du jour accompagne le numéro : jamais un chiffre nu.
      expect(
        find.descendant(
          of: find.byType(BandeSemaine),
          matching: find.text(AppStrings.grilleJoursCourts[2]),
        ),
        findsWidgets,
      );
    });

    testWidgets('chaque pastille est une cible d\'au moins 44 points', (
      tester,
    ) async {
      await monter(
        tester,
        BandeSemaine(
          annee: 2026,
          mois: 10,
          nombreDeJours: 31,
          aujourdhui: DateTime(2026, 10, 14),
          onJour: (_) {},
        ),
        taille: _poste,
      );

      verifierCiblesTactiles(
        tester,
        find.descendant(
          of: find.byType(BandeSemaine),
          matching: find.byType(InkWell),
        ),
      );
    });

    testWidgets('toucher un jour remonte son numéro', (tester) async {
      var vise = 0;
      await monter(
        tester,
        BandeSemaine(
          annee: 2026,
          mois: 10,
          nombreDeJours: 31,
          aujourdhui: DateTime(2026, 10, 14),
          onJour: (int jour) => vise = jour,
        ),
        taille: _poste,
      );

      await tester.tap(
        find
            .descendant(
              of: find.byType(BandeSemaine),
              matching: find.text('9'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(vise, 9);
    });

    testWidgets('le jour visé porte un liseré et s\'annonce sélectionné', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        BandeSemaine(
          annee: 2026,
          mois: 10,
          nombreDeJours: 31,
          aujourdhui: DateTime(2026, 10, 14),
          jourVise: 14,
          onJour: (_) {},
        ),
        taille: _poste,
      );

      // **Le liseré s'ajoute au remplissage** : le 14 est à la fois
      // aujourd'hui et le jour visé, et il le montre deux fois plutôt que de
      // choisir.
      final scheme = AppTheme.clair.colorScheme;
      expect(_fond(tester, 14), scheme.primaryContainer);
      expect(_lisere(tester, 14).width, AppStroke.etat);
      expect(_lisere(tester, 14).color, scheme.outline);
      // Le voisin n'a rien : un liseré à la fois.
      expect(_lisere(tester, 15).style, BorderStyle.none);

      // Et l'état ne tient pas qu'au trait : il est aussi dit.
      final libelle = <String>[
        dateAvecJourSemaine(DateTime(2026, 10, 14)),
        AppStrings.jourAujourdhui,
      ].join(', ');
      expect(
        tester.getSemantics(find.bySemanticsLabel(libelle)),
        containsSemantics(label: libelle, isButton: true, isSelected: true),
      );
      handle.dispose();
    });

    testWidgets('le jour courant s\'annonce, et chaque pastille dit où elle '
        'mène', (tester) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        BandeSemaine(
          annee: 2026,
          mois: 10,
          nombreDeJours: 31,
          aujourdhui: DateTime(2026, 10, 14),
          onJour: (_) {},
        ),
        taille: _poste,
      );

      final libelle = <String>[
        dateAvecJourSemaine(DateTime(2026, 10, 14)),
        AppStrings.jourAujourdhui,
      ].join(', ');
      expect(find.bySemanticsLabel(libelle), findsOneWidget);
      handle.dispose();
    });
  });

  group('BandeSemaine — dans l\'écran de l\'admin', () {
    testWidgets('toucher un jour amène sa colonne dans la matrice', (
      tester,
    ) async {
      await _ouvrirLaMatrice(tester);

      expect(find.byType(BandeSemaine), findsOneWidget);
      expect(_decalage(tester), 0);

      await tester.tap(
        find
            .descendant(
              of: find.byType(BandeSemaine),
              matching: find.text('12'),
            )
            .first,
      );
      await tester.pumpAndSettle();

      // La matrice s'est rendue au 12, avec **son** défilement : la bande
      // n'en ouvre pas un second.
      expect(
        _decalage(tester),
        math.min(11 * GeoMatrice.largeurJour, _maximum(tester)),
      );
    });

    testWidgets('après un clic, la pastille marque le jour que la matrice '
        'montre — et l\'oublie quand on défile ailleurs', (tester) async {
      final handle = tester.ensureSemantics();
      await _ouvrirLaMatrice(tester);

      // Rien n'est visé tant que rien n'a été demandé.
      expect(_lisere(tester, 12).style, BorderStyle.none);

      await tester.tap(
        find
            .descendant(
              of: find.byType(BandeSemaine),
              matching: find.text('12'),
            )
            .first,
      );
      await tester.pumpAndSettle();

      // La grille a bougé, et la bande le dit : liseré **et** `selected`.
      expect(_decalage(tester), greaterThan(0));
      expect(_lisere(tester, 12).width, AppStroke.etat);
      expect(
        tester.getSemantics(
          find.descendant(
            of: find.byType(BandeSemaine),
            matching: find.bySemanticsLabel(
              dateAvecJourSemaine(
                DateTime(_maintenant.year, _maintenant.month, 12),
              ),
            ),
          ),
        ),
        containsSemantics(isButton: true, isSelected: true),
      );

      // Un défilement à la main qui emmène la grille loin du 12 défait la
      // marque : elle dit « la matrice est posée là », pas « tu as cliqué
      // ici ».
      await tester.drag(
        find.byType(GrilleMatrice),
        const Offset(-800, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(_lisere(tester, 12).style, BorderStyle.none);

      handle.dispose();
    });

    testWidgets('sur un portable en 720, la barre du mois et sa légende se '
        'voient quand même', (tester) async {
      await _ouvrirLaMatrice(tester, taille: const Size(1280, 720));

      // **Le cas de référence du chantier** : un 13 pouces, sa barre
      // d'adresse, 341 points de place sous la barre de commande. Le bloc
      // resserré y tient — la barre de répartition et sa légende sont un
      // livrable, pas un bonus de grand écran.
      expect(tester.takeException(), isNull);
      expect(find.byType(BandeauMois), findsOneWidget);
      expect(find.byType(BarreRepartition), findsOneWidget);
      expect(find.byType(BandeSemaine), findsOneWidget);
      expect(find.byType(GrilleMatrice), findsOneWidget);

      // La légende est lisible, pas seulement présente : ses quatre lignes
      // tiennent côte à côte, et chacune porte son mot.
      expect(find.text(AppStrings.bandeauPartNonSaisis), findsOneWidget);
      final legende = tester.getSize(
        find.byType(BarreRepartition),
      );
      expect(legende.height, lessThan(BandeauMois.hauteurComplet));

      // Et la grille garde ses quatre lignes de réserve.
      expect(
        tester.getSize(find.byType(GrilleMatrice)).height,
        greaterThanOrEqualTo(MatriceScreen.placeGrilleUtile),
      );
    });

    testWidgets('sur une fenêtre courte, la matrice garde la place : le '
        'bandeau et la bande s\'effacent', (tester) async {
      // Un navigateur à demi hauteur : 181 points sous la barre de commande,
      // de quoi montrer une grille et rien d'autre.
      await _ouvrirLaMatrice(tester, taille: const Size(1280, 560));

      // La grille est entière, sans débordement : c'est elle l'écran.
      expect(tester.takeException(), isNull);
      expect(find.byType(GrilleMatrice), findsOneWidget);
      expect(find.byType(BandeSemaine), findsNothing);
      expect(find.byType(BandeauMois), findsNothing);
    });

    testWidgets('viser deux fois le même jour reste possible après un '
        'défilement à la main', (tester) async {
      await _ouvrirLaMatrice(tester);

      await tester.tap(
        find
            .descendant(
              of: find.byType(BandeSemaine),
              matching: find.text('12'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final premier = _decalage(tester);
      expect(premier, greaterThan(0));

      await tester.drag(
        find.byType(GrilleMatrice),
        const Offset(200, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .descendant(
              of: find.byType(BandeSemaine),
              matching: find.text('12'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(_decalage(tester), premier);
    });
  });
}
