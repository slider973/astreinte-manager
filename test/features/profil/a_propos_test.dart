import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/version/version_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_profil.dart';

/// Ticket 080 : le propriétaire teste la PWA après chaque correctif et ne
/// pouvait pas savoir ce qu'il avait sous les yeux — un service worker sert
/// parfois l'ancienne version depuis le cache.
///
/// Les valeurs viennent de `--dart-define`, donc figées à la compilation : sous
/// `flutter test`, rien n'est injecté et le bloc affiche son repli. C'est
/// précisément ce que ces tests vérifient — le repli ne doit ni mentir ni
/// planter.
Future<void> _ouvrirProfil(WidgetTester tester) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    profils: FauxProfilRepository(),
  );
  await ouvrirProfil(tester);
}

void main() {
  group('Bloc À propos', () {
    testWidgets('le bloc est présent en bas du profil', (tester) async {
      await _ouvrirProfil(tester);
      await defilerJusqua(tester, find.text(AppStrings.aProposTitre));

      expect(find.text(AppStrings.aProposTitre), findsOneWidget);
    });

    testWidgets('sans injection, annonce une version locale sans mentir', (
      tester,
    ) async {
      await _ouvrirProfil(tester);
      await defilerJusqua(tester, find.text(AppStrings.aProposVersionLocale));

      // Le repli : sous `flutter test`, aucun `--dart-define` n'est passé.
      expect(constructionLocale, isTrue);
      expect(find.text(AppStrings.aProposVersionLocale), findsOneWidget);
      // Et surtout : pas de faux numéro présenté comme une livraison.
      expect(find.text(AppStrings.aProposVersion('local')), findsNothing);
    });

    testWidgets('hors production, l\'environnement est affiché', (tester) async {
      await _ouvrirProfil(tester);
      await defilerJusqua(
        tester,
        find.text(AppStrings.aProposEnvironnement(appEnv)),
      );

      // `APP_ENV` vaut `dev` par défaut : un pompier qui voit « dev » comprend
      // pourquoi ses données ne sont pas celles qu'il attendait.
      expect(enProduction, isFalse);
      expect(
        find.text(AppStrings.aProposEnvironnement(appEnv)),
        findsOneWidget,
      );
    });

    testWidgets('le texte est sélectionnable, pour être recopié', (
      tester,
    ) async {
      await _ouvrirProfil(tester);
      await defilerJusqua(tester, find.text(AppStrings.aProposTitre));

      // Son usage réel est d'être copiée dans un message pour dire « j'ai
      // celle-ci ». Sans cela, il faudrait la retranscrire à la main.
      expect(
        find.ancestor(
          of: find.text(AppStrings.aProposVersionLocale),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
    });

    test('une date non analysable ne fait pas tomber l\'écran', () {
      // `appBuildDate` est vide sous test : le getter doit rendre `null`, pas
      // lever. Un profil doit rester lisible même si la date est malformée.
      expect(appBuildDate, isEmpty);
      expect(dateConstruction, isNull);
    });
  });
}
