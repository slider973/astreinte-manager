import 'package:astreinte_sp/core/theme/app_motion.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/core/widgets/save_indicator.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/core/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Reduce Motion est une **contrainte produit**, pas une option
/// (`PRODUCT.md`, `DESIGN.md § Motion`). Ce fichier vérifie qu'aucun composant
/// ne continue de bouger quand l'utilisateur a demandé le calme.
void main() {
  group('AppMotion', () {
    testWidgets('toutes les durées tombent à zéro', (tester) async {
      late BuildContext contexte;
      await monter(
        tester,
        Builder(
          builder: (context) {
            contexte = context;
            return const SizedBox.shrink();
          },
        ),
        animationsDesactivees: true,
      );

      expect(AppMotion.reduit(contexte), isTrue);
      expect(AppMotion.instantane(contexte), Duration.zero);
      expect(AppMotion.courant(contexte), Duration.zero);
      expect(AppMotion.surface(contexte), Duration.zero);
      expect(AppMotion.page(contexte), Duration.zero);
      expect(
        AppMotion.duree(contexte, const Duration(seconds: 5)),
        Duration.zero,
      );
    });

    testWidgets('les durées nominales sont conservées sinon', (tester) async {
      late BuildContext contexte;
      await monter(
        tester,
        Builder(
          builder: (context) {
            contexte = context;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(AppMotion.reduit(contexte), isFalse);
      expect(AppMotion.instantane(contexte), AppDuration.instantane);
      expect(AppMotion.courant(contexte), AppDuration.courant);
      expect(AppMotion.surface(contexte), AppDuration.surface);
      expect(AppMotion.page(contexte), AppDuration.page);
    });
  });

  group('Aucun composant ne bouge sous Reduce Motion', () {
    testWidgets('LoadingSkeleton perd son balayage', (tester) async {
      await monter(
        tester,
        const LoadingSkeleton(child: SkeletonBloc()),
        animationsDesactivees: true,
      );

      expect(find.byType(ShaderMask), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('SaveIndicator cesse de tourner', (tester) async {
      await monter(
        tester,
        const SaveIndicator(etat: SyncEtat.enregistrement),
        animationsDesactivees: true,
      );

      expect(
        find.descendant(
          of: find.byType(SaveIndicator),
          matching: find.byType(RotationTransition),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('le tampon du StatusBadge ne se joue pas', (tester) async {
      await monter(
        tester,
        const StatusBadge.attribution(AttributionEtat.accepte, tampon: true),
        animationsDesactivees: true,
      );

      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('la case en enregistrement ne pulse pas', (tester) async {
      await monter(
        tester,
        SizedBox(
          height: 48,
          child: SlotChip(
            etat: DisponibiliteEtat.absent,
            creneau: CreneauType.nuit,
            enEnregistrement: true,
            onTap: () {},
            libelleSemantique: 'Samedi 4 octobre, nuit, absent',
          ),
        ),
        animationsDesactivees: true,
      );

      expect(
        find.descendant(
          of: find.byType(SlotChip),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('un écran entier reste immobile', (tester) async {
      await monter(
        tester,
        const Column(
          children: <Widget>[
            StatusBadge.planning(PlanningEtat.valide, tampon: true),
            SaveIndicator(etat: SyncEtat.enregistrement),
            SizedBox(
              height: 120,
              child: LoadingSkeleton(child: SkeletonBloc()),
            ),
          ],
        ),
        animationsDesactivees: true,
      );

      // pumpAndSettle rendrait la main en échec si une boucle tournait encore.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
