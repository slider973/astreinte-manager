import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/legal/domain/document_legal.dart';
import 'package:astreinte_sp/features/legal/domain/documents_legaux.dart';
import 'package:astreinte_sp/features/legal/presentation/document_legal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';

/// Les deux documents, pour les tests qui valent pour l'un comme pour l'autre.
const List<DocumentLegal> _documents = <DocumentLegal>[
  DocumentsLegaux.confidentialite,
  DocumentsLegaux.mentions,
];

/// Tous les paragraphes d'un document, à plat.
List<String> _paragraphes(DocumentLegal document) => <String>[
  document.chapeau,
  for (final section in document.sections) ...section.paragraphes,
];

void main() {
  group('Pages légales — contenu', () {
    test('les deux documents sont datés et non vides', () {
      for (final document in _documents) {
        expect(document.titre.trim(), isNotEmpty);
        expect(document.version.trim(), isNotEmpty);
        expect(document.sections, isNotEmpty);
        for (final section in document.sections) {
          expect(
            section.paragraphes,
            isNotEmpty,
            reason: '« ${section.titre} » n\'a aucun paragraphe',
          );
        }
      }
    });

    // Un document juridique de remplissage se reconnaît à ses phrases sans
    // sujet. Ce test n'en juge pas la qualité — il attrape l'oubli manifeste :
    // un « Lorem ipsum », un gabarit non rempli, une phrase tronquée.
    test('aucun paragraphe de remplissage', () {
      for (final document in _documents) {
        for (final paragraphe in _paragraphes(document)) {
          expect(paragraphe.length, greaterThan(40));
          expect(paragraphe.trim().endsWith('.'), isTrue);
          expect(paragraphe.toLowerCase(), isNot(contains('lorem')));
          expect(paragraphe, isNot(contains('TODO')));
          expect(paragraphe, isNot(contains('XXX')));
        }
      }
    });

    // **Rien n'est inventé.** Ce qui relève d'une décision du propriétaire —
    // raison sociale, adresse, hébergeur contractuel — passe par `aCompleter`,
    // qui est visible à l'écran. Une mention légale fausse se croit.
    test('les mentions légales portent leurs marques à compléter', () {
      final marques = <String>[
        for (final section in DocumentsLegaux.mentions.sections)
          ...section.aCompleter,
      ];
      expect(marques, isNotEmpty);
      expect(
        marques.any((String m) => m.contains('Raison sociale')),
        isTrue,
        reason: 'la raison sociale ne doit jamais être inventée',
      );
    });

    test('la politique de confidentialité décrit le produit réel', () {
      final texte = _paragraphes(DocumentsLegaux.confidentialite).join(' ');

      // Les quatre faits que le schéma impose et que la page doit dire.
      expect(texte, contains('Membre supprimé'));
      expect(texte, contains('Exporter mes données'));
      expect(texte, contains('Firebase'));
      expect(texte, contains('CNIL'));
      // Ce que le produit ne fait pas, et qu'il faut dire aussi.
      expect(texte, contains('aucune donnée de localisation'));
    });
  });

  group('Pages légales — écran', () {
    testWidgets('la politique de confidentialité se rend en entier', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: DocumentLegalScreen.confidentialite()),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(DocumentsLegaux.confidentialite.titre),
        findsWidgets,
      );
      expect(find.text(DocumentsLegaux.confidentialite.version), findsOneWidget);
      // Le premier titre de section, sans défilement : la page commence par le
      // sujet, pas par un sommaire.
      expect(
        find.text(DocumentsLegaux.confidentialite.sections.first.titre),
        findsOneWidget,
      );
    });

    testWidgets('les marques à compléter sont visibles, pas cachées', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: DocumentLegalScreen.mentions()),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.legalACompleterTitre), findsWidgets);
      expect(
        find.text(DocumentsLegaux.mentions.sections.first.aCompleter.first),
        findsOneWidget,
      );
    });
  });

  group('Pages légales — routes', () {
    testWidgets('« Confidentialité » s\'ouvre depuis le profil', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );

      await tester.tap(find.text(AppStrings.navProfil));
      await tester.pumpAndSettle();
      await defilerJusqua(
        tester,
        find.text(AppStrings.legalConfidentialiteLien),
      );
      await tester.tap(find.text(AppStrings.legalConfidentialiteLien));
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.confidentialite);
      expect(find.byType(DocumentLegalScreen), findsOneWidget);
    });

    // **Sans compte.** C'est la raison d'être de la route : une mairie, un
    // candidat à l'invitation ou quelqu'un qui a reçu un courriel doit pouvoir
    // la lire. Le pied de l'écran de connexion y mène.
    testWidgets('elle s\'ouvre aussi depuis l\'écran de connexion', (
      tester,
    ) async {
      await monterApp(tester);

      await defilerJusqua(
        tester,
        find.text(AppStrings.legalConfidentialiteLien),
      );
      await tester.tap(find.text(AppStrings.legalConfidentialiteLien));
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.confidentialite);
      expect(
        find.text(DocumentsLegaux.confidentialite.sections.first.titre),
        findsOneWidget,
      );
    });

    testWidgets('chaque document renvoie vers l\'autre', (tester) async {
      await monterApp(tester);

      await defilerJusqua(tester, find.text(AppStrings.legalMentionsLien));
      await tester.tap(find.text(AppStrings.legalMentionsLien));
      await tester.pumpAndSettle();
      expect(emplacementCourant(tester), AppRoutes.mentions);

      await defilerJusqua(
        tester,
        find.text(AppStrings.legalConfidentialiteLien),
      );
      await tester.tap(find.text(AppStrings.legalConfidentialiteLien));
      await tester.pumpAndSettle();
      expect(emplacementCourant(tester), AppRoutes.confidentialite);
    });
  });
}
