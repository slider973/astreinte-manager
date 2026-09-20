import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('StatusBadge — les six familles', () {
    for (final brightness in Brightness.values) {
      final statuts = brightness == Brightness.dark
          ? AppStatusColors.sombre
          : AppStatusColors.clair;

      testWidgets(
        '${brightness.name} : chaque état affiche son libellé et son icône',
        (tester) async {
          await monter(
            tester,
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final etat in DisponibiliteEtat.values)
                    StatusBadge.disponibilite(etat),
                  for (final type in CreneauType.values)
                    StatusBadge.creneau(type),
                  for (final etat in AttributionEtat.values)
                    StatusBadge.attribution(etat),
                  for (final etat in PlanningEtat.values)
                    StatusBadge.planning(etat),
                  for (final etat in PeriodeEtat.values)
                    StatusBadge.periode(etat),
                  for (final etat in SyncEtat.values) StatusBadge.sync(etat),
                ],
              ),
            ),
            brightness: brightness,
          );

          expect(tester.takeException(), isNull);
          for (final descripteur in statuts.tous) {
            expect(
              find.text(descripteur.libelle),
              findsWidgets,
              reason: 'Libellé manquant : « ${descripteur.libelle} ».',
            );
            expect(
              find.byIcon(descripteur.icone),
              findsWidgets,
              reason: 'Icône manquante pour « ${descripteur.libelle} ».',
            );
          }
        },
      );
    }
  });

  group('StatusBadge — variantes', () {
    testWidgets('la taille compacte se rend', (tester) async {
      await monter(
        tester,
        const StatusBadge.attribution(
          AttributionEtat.accepte,
          taille: StatusBadgeTaille.compacte,
        ),
      );

      expect(find.text(AppStrings.attributionAccepte), findsOneWidget);
    });

    testWidgets('un libellé de remplacement remplace celui du descripteur', (
      tester,
    ) async {
      await monter(
        tester,
        const StatusBadge.attribution(
          AttributionEtat.propose,
          libelle: AppStrings.attributionProposeMembre,
        ),
      );

      expect(find.text(AppStrings.attributionProposeMembre), findsOneWidget);
      expect(find.text(AppStrings.attributionPropose), findsNothing);
    });

    testWidgets('un libellé vide est refusé', (tester) async {
      await monter(
        tester,
        const StatusBadge.planning(PlanningEtat.publie, libelle: ''),
      );

      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('un libellé long est tronqué, pas débordé', (tester) async {
      await monter(
        tester,
        const SizedBox(
          width: 120,
          child: StatusBadge.attribution(
            AttributionEtat.propose,
            libelle: 'Marie-Christine de Villeneuve-Latour attend ta réponse',
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final texte = tester.widget<Text>(find.byType(Text));
      expect(texte.overflow, TextOverflow.ellipsis);
      expect(texte.maxLines, 1);
    });

    testWidgets('le tampon se pose une fois puis s\'arrête', (tester) async {
      await monter(
        tester,
        const StatusBadge.planning(PlanningEtat.valide, tampon: true),
      );

      await tester.pump(const Duration(milliseconds: 90));
      expect(find.byType(Transform), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.planningValide), findsOneWidget);
    });

    testWidgets('sous Reduce Motion, le tampon n\'anime pas', (tester) async {
      await monter(
        tester,
        const StatusBadge.planning(PlanningEtat.valide, tampon: true),
        animationsDesactivees: true,
      );

      expect(find.text(AppStrings.planningValide), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('StatusBadge — accessibilité', () {
    testWidgets('le libellé est annoncé', (tester) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        const StatusBadge.disponibilite(DisponibiliteEtat.absent),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel(AppStrings.etatAbsent)).label,
        AppStrings.etatAbsent,
      );

      handle.dispose();
    });

    testWidgets('tient une échelle de texte de 2.0', (tester) async {
      await monter(
        tester,
        const StatusBadge.periode(PeriodeEtat.verrouillee),
        echelleTexte: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
