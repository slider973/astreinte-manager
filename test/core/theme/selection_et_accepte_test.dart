import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_colors.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/core/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widgets/helpers.dart';

/// Les deux teintes ne doivent jamais se confondre : **l'indigo dit
/// « choisi » et « disponible », le vert dit « accepté, couvert, publié »**
/// (brief 061 § 3). Material 3 sélectionne en `secondary-container` par
/// défaut, c'est-à-dire, depuis le ticket 061, en vert : ce fichier est le
/// garde-fou qui empêche ce défaut de revenir par un composant oublié.
void main() {
  /// La couleur effectivement peinte derrière un segment ou une puce.
  ///
  /// Un segment la porte sur le `Material` de son `TextButton`, une puce sur
  /// l'`Ink` que `RawChip` interpose : les deux sont regardés, parce que
  /// c'est la couleur **peinte** qui compte, pas celle du thème relue.
  Color? fondDe(WidgetTester tester, Finder cible) {
    for (final element
        in find.descendant(of: cible, matching: find.byType(Ink)).evaluate()) {
      final decoration = (element.widget as Ink).decoration;
      if (decoration is ShapeDecoration && decoration.color != null) {
        return decoration.color;
      }
      if (decoration is BoxDecoration && decoration.color != null) {
        return decoration.color;
      }
    }
    for (final element
        in find
            .descendant(of: cible, matching: find.byType(Material))
            .evaluate()) {
      final couleur = (element.widget as Material).color;
      if (couleur != null && couleur != Colors.transparent) return couleur;
    }
    return null;
  }

  /// L'encre réellement appliquée à un texte, une fois toutes les cascades de
  /// style résolues — pas celle que le `TextStyle` du widget déclare.
  Color? encreDe(WidgetTester tester, Finder texte) =>
      tester.renderObject<RenderParagraph>(texte).text.style?.color;

  group('Sélection — la pastille est indigo, jamais verte', () {
    for (final brightness in Brightness.values) {
      final scheme =
          (brightness == Brightness.dark ? AppTheme.sombre : AppTheme.clair)
              .colorScheme;

      testWidgets('${brightness.name} : un segment choisi porte '
          'primary-container', (tester) async {
        await monter(
          tester,
          Center(
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 1, label: Text('Clair')),
                ButtonSegment<int>(value: 2, label: Text('Sombre')),
              ],
              selected: const <int>{2},
              showSelectedIcon: false,
              onSelectionChanged: (_) {},
            ),
          ),
          brightness: brightness,
        );

        final choisi = find.widgetWithText(TextButton, 'Sombre');
        final autre = find.widgetWithText(TextButton, 'Clair');

        expect(
          fondDe(tester, choisi),
          scheme.primaryContainer,
          reason: 'Le segment choisi doit porter la pastille indigo.',
        );
        expect(
          fondDe(tester, choisi),
          isNot(scheme.secondaryContainer),
          reason: 'Le vert dit « accepté », pas « choisi ».',
        );
        expect(fondDe(tester, autre), scheme.surface);

        expect(encreDe(tester, find.text('Sombre')), scheme.onPrimaryContainer);
        expect(encreDe(tester, find.text('Clair')), scheme.onSurface);
      });

      testWidgets('${brightness.name} : une puce choisie porte '
          'primary-container', (tester) async {
        await monter(
          tester,
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FilterChip(
                  label: const Text('Choisie'),
                  selected: true,
                  onSelected: (_) {},
                ),
                FilterChip(label: const Text('Libre'), onSelected: (_) {}),
              ],
            ),
          ),
          brightness: brightness,
        );

        expect(
          fondDe(tester, find.widgetWithText(FilterChip, 'Choisie')),
          scheme.primaryContainer,
        );
        expect(
          fondDe(tester, find.widgetWithText(FilterChip, 'Libre')),
          scheme.surfaceContainer,
        );
        expect(
          encreDe(tester, find.text('Choisie')),
          scheme.onPrimaryContainer,
        );
        expect(encreDe(tester, find.text('Libre')), scheme.onSurface);
      });
    }
  });

  group('Accepté — la famille verte, en clair comme en sombre', () {
    for (final brightness in Brightness.values) {
      final sombre = brightness == Brightness.dark;
      final scheme = (sombre ? AppTheme.sombre : AppTheme.clair).colorScheme;
      final statuts = sombre ? AppStatusColors.sombre : AppStatusColors.clair;

      /// Le fond du seul badge monté.
      Color? fondDuBadge(WidgetTester tester) {
        for (final element
            in find
                .descendant(
                  of: find.byType(StatusBadge),
                  matching: find.byType(DecoratedBox),
                )
                .evaluate()) {
          final decoration = (element.widget as DecoratedBox).decoration;
          if (decoration is BoxDecoration && decoration.color != null) {
            return decoration.color;
          }
        }
        return null;
      }

      testWidgets('${brightness.name} : le badge « Accepté » est vert', (
        tester,
      ) async {
        await monter(
          tester,
          const Center(child: StatusBadge.attribution(AttributionEtat.accepte)),
          brightness: brightness,
        );

        expect(
          fondDuBadge(tester),
          scheme.secondaryContainer,
          reason: 'Accepté appartient à la famille verte.',
        );
        expect(
          fondDuBadge(tester),
          isNot(scheme.primaryContainer),
          reason:
              'L\'indigo dit « disponible » et « choisi », pas « accepté ».',
        );
        expect(
          encreDe(tester, find.text(AppStrings.attributionAccepte)),
          sombre
              ? AppColors.darkEtatAccepteSurFond
              : AppColors.etatAccepteSurFond,
        );
      });

      testWidgets('${brightness.name} : le tampon « Validé » est vert', (
        tester,
      ) async {
        await monter(
          tester,
          const Center(
            child: StatusBadge.planning(PlanningEtat.valide, tampon: true),
          ),
          brightness: brightness,
        );
        await tester.pumpAndSettle();

        expect(fondDuBadge(tester), scheme.secondaryContainer);
        expect(fondDuBadge(tester), isNot(scheme.primaryContainer));
      });

      test(
        '${brightness.name} : tout ce qui est acquis partage un seul vert',
        () {
          final vert = <StatusDescriptor>[
            statuts.attribution(AttributionEtat.accepte),
            statuts.planning(PlanningEtat.valide),
            statuts.planning(PlanningEtat.publie),
            statuts.periode(PeriodeEtat.ouverte),
          ];
          for (final descripteur in vert) {
            expect(
              descripteur.fond,
              scheme.secondaryContainer,
              reason: '« ${descripteur.libelle} » a quitté la famille verte.',
            );
            expect(
              descripteur.encre,
              sombre
                  ? AppColors.darkEtatAccepteSurFond
                  : AppColors.etatAccepteSurFond,
              reason:
                  '« ${descripteur.libelle} » n\'a pas l\'encre du bloc vert.',
            );
          }

          // « Disponible » garde l'indigo : c'est la moitié de la décision.
          expect(
            statuts.disponibilite(DisponibiliteEtat.disponible).fond,
            isNot(scheme.secondaryContainer),
          );
          // « Refusé » reste rose, « proposé » reste orange.
          expect(
            statuts.attribution(AttributionEtat.refuse).fond,
            scheme.errorContainer,
          );
          expect(
            statuts.attribution(AttributionEtat.propose).fond,
            scheme.tertiaryContainer,
          );
        },
      );
    }
  });
}
