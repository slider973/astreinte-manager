import 'package:astreinte_sp/core/theme/app_spacing.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/avatar_initiales.dart';
import 'package:astreinte_sp/features/planning/domain/candidat.dart';
import 'package:astreinte_sp/features/planning/domain/cle_cellule.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/domain/matrice_mois.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/entete_ligne_membre.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/geometrie_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/ligne_candidat.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/vue_jour.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/widgets/helpers.dart';
import '../../support/faux_matrice.dart';
import '../../support/polices.dart';

/// Les noms d'usage du seed — les plus longs des dix-huit. `display_name` est
/// libre en base : une autre caserne peut y écrire un nom entier, et c'est le
/// cas que le test suivant mesure.
const List<String> _nomsDuSeed = <String>[
  'Antoine C.',
  'Nicolas F.',
  'Camille G.',
  'Émilie R.',
];

LigneMatrice _ligne(String nom) => ligneMatrice(
  userId: 'u-$nom',
  nom: nom,
  jours: moisUniforme('.'),
  nuits: moisUniforme('.'),
  maxAstreintes: 8,
  maxWeekends: 2,
);

Future<void> _monterLEntete(
  WidgetTester tester,
  String nom, {
  double largeur = 280,
  double echelleTexte = 1,
}) async {
  // **Les vraies polices, sinon la mesure ne vaut rien** : ce fichier mesure
  // ce qui reste au nom une fois le disque posé devant lui.
  await chargerPolicesDuProduit();
  await monter(
    tester,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        EnteteLigneMembre(
          ligne: _ligne(nom),
          largeur: largeur,
          commentaires: false,
          deplie: false,
          onDeplier: () {},
        ),
      ],
    ),
    echelleTexte: echelleTexte,
    taille: const Size(1440, 900),
  );
}

/// Vrai quand le texte a été rogné par son `ellipsis`.
bool _tronque(WidgetTester tester, String texte) {
  final paragraphe = tester.renderObject<RenderParagraph>(find.text(texte));
  return paragraphe.didExceedMaxLines;
}

Candidat _candidat(String nom) =>
    Candidat(membre: _ligne(nom), disponibilite: DisponibiliteEtat.disponible);

void main() {
  group('EnteteLigneMembre — le disque devant le nom', () {
    testWidgets('l\'avatar est là, à 24 points, et la ligne en fait toujours '
        '32', (tester) async {
      await _monterLEntete(tester, 'Antoine C.');

      final avatar = find.byType(AvatarInitiales);
      expect(avatar, findsOneWidget);
      expect(
        tester.getSize(avatar),
        const Size(GeoMatrice.tailleAvatar, GeoMatrice.tailleAvatar),
      );
      expect(
        tester.getSize(find.byType(EnteteLigneMembre)).height,
        GeoMatrice.hauteurLigne,
      );
      // La colonne figée garde sa largeur : l'avatar prend sur le nom, pas
      // sur la grille.
      expect(tester.getSize(find.byType(EnteteLigneMembre)).width, 280);
    });

    testWidgets('l\'avatar est décoratif : le nom reste le seul libellé', (
      tester,
    ) async {
      await _monterLEntete(tester, 'Antoine C.');

      // « AC » n'existe pas pour un lecteur d'écran : la ligne entière est un
      // seul nœud, et il commence par le nom.
      expect(find.bySemanticsLabel(RegExp('^AC')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Antoine C\\.')), findsOneWidget);
    });

    testWidgets('les noms du seed tiennent entiers à 280 comme à 240', (
      tester,
    ) async {
      for (final largeur in <double>[280, 240]) {
        for (final nom in _nomsDuSeed) {
          await _monterLEntete(tester, nom, largeur: largeur);
          expect(
            _tronque(tester, nom),
            isFalse,
            reason: '« $nom » est rogné dans une colonne de $largeur.',
          );
        }
      }
    });

    testWidgets('un nom long est rogné par son ellipsis, jamais débordé', (
      tester,
    ) async {
      // Ce que la colonne ne peut pas montrer, elle le coupe proprement : le
      // nom entier reste dans la sémantique de la ligne, et le panneau du
      // créneau l'écrit en entier.
      await _monterLEntete(tester, 'Vandenberghe-Delacroix Jean-Baptiste');

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(EnteteLigneMembre)).height,
        GeoMatrice.hauteurLigne,
      );
    });

    testWidgets('à grande échelle de texte, les initiales restent dans le '
        'disque', (tester) async {
      await _monterLEntete(tester, 'Antoine C.', echelleTexte: 1.6);

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(AvatarInitiales)),
        const Size(GeoMatrice.tailleAvatar, GeoMatrice.tailleAvatar),
      );
    });
  });

  group('VueJour — pas de disque sur téléphone', () {
    testWidgets('la vue par jour n\'en porte aucun', (tester) async {
      await chargerPolicesDuProduit();
      final lignes = <LigneMatrice>[for (final nom in _nomsDuSeed) _ligne(nom)];

      await monter(
        tester,
        VueJour(
          matrice: MatriceMois(lignes: lignes, nombreDeJours: 31),
          lignes: lignes,
          annee: 2026,
          mois: 10,
          aujourdhui: DateTime(2026, 10, 14),
          commentaires: false,
          erreurs: const <CleCellule>{},
          saisieActive: false,
          onCase: (_) {},
          planning: PlanningMois.vide(),
          creneauSelectionne: null,
          onCreneau: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      // **Décidé au brief** (`design/061 § 8 bis`) : le disque sert à
      // distinguer soixante lignes voisines dans une grille dense. La vue par
      // jour en montre une poignée, en cibles de 48, et chaque point de sa
      // largeur de 390 va au nom et aux cases.
      expect(find.byType(VueJour), findsOneWidget);
      expect(find.byType(AvatarInitiales), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('LigneCandidat — le disque à gauche du bloc de texte', () {
    testWidgets('l\'avatar fait 32 points et la ligne garde sa cible de 48', (
      tester,
    ) async {
      await chargerPolicesDuProduit();
      await monter(
        tester,
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: LigneCandidat(
            candidat: _candidat('Antoine C.'),
            action: ActionCandidat.attribuer,
            onAction: () {},
          ),
        ),
        taille: const Size(420, 900),
      );

      expect(
        tester.getSize(find.byType(AvatarInitiales)),
        const Size(LigneCandidat.tailleAvatar, LigneCandidat.tailleAvatar),
      );
      expect(
        tester.getSize(find.byType(LigneCandidat)).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);

      // Décoratif là aussi : le nœud de la ligne commence par le nom.
      expect(find.bySemanticsLabel('Antoine C.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^AC')), findsNothing);
    });
  });
}
