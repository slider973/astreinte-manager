import 'package:astreinte_sp/core/caserne/etat_caserne.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/presentation/widgets/ligne_astreinte.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/presentation/widgets/ligne_proposition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_caserne.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_parametres.dart';
import '../../support/faux_periodes.dart';
import '../../support/faux_propositions.dart';

/// Un écran haut : tout tient sans défiler, la composition reste celle du
/// téléphone.
const Size _telephoneLong = Size(420, 1600);

/// Un mois ouvert dont la date limite est loin : la seule bannière possible
/// est alors celle de l'abonnement.
final PeriodeSaisie _periode = periodeOuverte(
  annee: 2026,
  mois: 10,
  dateLimite: DateTime.now().add(const Duration(days: 40)),
);

Future<void> _ouvrir(
  WidgetTester tester, {
  required String chemin,
  required EtatCaserne caserne,
  Appartenance appartenance = appartenanceMembre,
  bool stabiliser = true,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    caserne: FauxCaserneRepository(caserne),
    // Une date limite **au large** : sans elle, « Mon mois » porterait sa
    // propre bannière « Plus que N jours », et les tests d'échéance d'essai
    // liraient la mauvaise.
    dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode]),
    periodes: FauxPeriodesRepository(periodes: <PeriodeSaisie>[_periode]),
    parametres: FauxParametresRepository(),
    propositions: FauxPropositionsRepository(
      propositions: <Proposition>[
        proposition(
          id: 'a-12',
          creneauId: 'c-12',
          jour: DateTime(2026, 10, 12),
        ),
      ],
    ),
    astreintes: FauxAstreintesRepository(
      astreintes: <Astreinte>[
        astreinte(id: 'g-1', jour: DateTime(2026, 10, 12)),
      ],
    ),
    taille: _telephoneLong,
    stabiliser: stabiliser,
  );
  await ouvrirRoute(tester, chemin, stabiliser: stabiliser);
}

AppBanner _banniere(WidgetTester tester) =>
    tester.widget<AppBanner>(find.byType(AppBanner).first);

void main() {
  group('Caserne suspendue — le bandeau', () {
    testWidgets('l\'accueil l\'annonce avant le premier geste', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        chemin: AppRoutes.accueil,
        caserne: caserneSuspendue,
      );

      final banniere = _banniere(tester);
      expect(banniere.variante, AppBannerVariante.lectureSeule);
      expect(banniere.texte, contains('suspendue'));
      expect(banniere.detail, contains('Rien n\'a été supprimé'));
    });

    testWidgets('la grille reste lisible, et l\'appui dit pourquoi', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        chemin: AppRoutes.calendrier,
        caserne: caserneSuspendue,
      );

      // Les cases sont là : on consulte. C'est le cœur du critère
      // d'acceptation du ticket.
      expect(find.byType(SlotChip), findsWidgets);

      // Et l'appui **répond** au lieu de ne rien faire : un doigt qui
      // n'obtient rien recommence.
      await tester.tap(find.byType(SlotChip).first);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.moisRefusLectureSeule), findsOneWidget);
    });

    testWidgets('« Propositions » : les deux boutons grisés, avec la raison', (
      tester,
    ) async {
      await _ouvrir(tester, chemin: '/proposals', caserne: caserneSuspendue);

      expect(_banniere(tester).variante, AppBannerVariante.lectureSeule);

      // La proposition reste lisible : sa date, son créneau, tout est là.
      expect(find.byType(LigneDeProposition), findsOneWidget);

      final boutons = tester
          .widgetList<PrimaryButton>(find.byType(PrimaryButton))
          .where(
            (PrimaryButton b) =>
                b.libelle == AppStrings.propositionsAccepter ||
                b.libelle == AppStrings.propositionsRefuser,
          )
          .toList();
      expect(boutons, hasLength(2));
      for (final bouton in boutons) {
        expect(bouton.onPressed, isNull);
        expect(
          bouton.raisonDesactivation,
          AppStrings.propositionsLectureSeuleRaison,
        );
      }
    });

    testWidgets('« Périodes » : ouvrir un mois est grisé et dit pourquoi', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        chemin: '/admin/periodes',
        caserne: caserneSuspendue,
        appartenance: appartenanceAdmin,
      );

      expect(_banniere(tester).variante, AppBannerVariante.lectureSeule);

      final ouvrir = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, AppStrings.periodesOuvrirUnMois),
      );
      expect(ouvrir.onPressed, isNull);
      expect(ouvrir.raisonDesactivation, AppStrings.periodeRefusSuspendue);
    });

    testWidgets('« Membres » : inviter est grisé et dit pourquoi', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        chemin: '/admin/membres',
        caserne: caserneSuspendue,
        appartenance: appartenanceAdmin,
      );

      expect(_banniere(tester).variante, AppBannerVariante.lectureSeule);

      final inviter = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, AppStrings.membresInviter),
      );
      expect(inviter.onPressed, isNull);
      expect(inviter.raisonDesactivation, AppStrings.membresSuspendue);
    });

    testWidgets('« Paramètres » : enregistrer est grisé et dit pourquoi', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        chemin: '/admin/parametres',
        caserne: caserneSuspendue,
        appartenance: appartenanceAdmin,
      );

      final enregistrer = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, AppStrings.parametresEnregistrer),
      );
      expect(enregistrer.onPressed, isNull);
      expect(enregistrer.raisonDesactivation, AppStrings.parametresSuspendue);
    });

    testWidgets('l\'admin a une sortie, le membre a une phrase', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        chemin: AppRoutes.accueil,
        caserne: caserneSuspendue,
      );
      expect(_banniere(tester).onAction, isNull);
      expect(_banniere(tester).detail, AppStrings.lectureSeuleMembreDetail);
      await demonter(tester);

      await _ouvrir(
        tester,
        chemin: AppRoutes.accueil,
        caserne: caserneSuspendue,
        appartenance: appartenanceAdmin,
      );
      expect(_banniere(tester).libelleAction, AppStrings.lectureSeuleAction);
    });
  });

  group('Caserne suspendue — la lecture reste entière', () {
    testWidgets('« Mes astreintes » s\'ouvre et montre ses gardes', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        chemin: AppRoutes.astreintes,
        caserne: caserneSuspendue,
      );

      // Aucun écran vide, aucune erreur : la suspension est une lecture seule,
      // jamais une coupure (`docs/PRD.md § 6.6`).
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(LigneDAstreinte), findsWidgets);
    });

    testWidgets('aucun écran de lecture ne porte de bannière d\'erreur', (
      tester,
    ) async {
      for (final chemin in <String>[
        AppRoutes.accueil,
        '/proposals',
        AppRoutes.astreintes,
      ]) {
        await _ouvrir(tester, chemin: chemin, caserne: caserneSuspendue);
        final bannieres = tester.widgetList<AppBanner>(find.byType(AppBanner));
        for (final banniere in bannieres) {
          expect(
            banniere.variante,
            isNot(AppBannerVariante.erreur),
            reason: '$chemin ne doit pas annoncer une panne.',
          );
        }
        await demonter(tester);
      }
    });
  });

  group('Fin d\'essai — le bandeau d\'échéance', () {
    testWidgets('rien à soixante jours', (tester) async {
      await _ouvrir(
        tester,
        chemin: AppRoutes.accueil,
        caserne: caserneEssaiDans(60),
        appartenance: appartenanceAdmin,
      );
      expect(find.byType(AppBanner), findsNothing);
    });

    testWidgets('à J-14, une information ; à J-3, l\'ocre', (tester) async {
      await _ouvrir(
        tester,
        chemin: AppRoutes.accueil,
        caserne: caserneEssaiDans(14),
        appartenance: appartenanceAdmin,
      );
      expect(_banniere(tester).variante, AppBannerVariante.information);
      expect(_banniere(tester).texte, contains('il reste 14 jours'));
      await demonter(tester);

      await _ouvrir(
        tester,
        chemin: AppRoutes.accueil,
        caserne: caserneEssaiDans(3),
        appartenance: appartenanceAdmin,
      );
      expect(_banniere(tester).variante, AppBannerVariante.attention);
      expect(_banniere(tester).texte, contains('il reste 3 jours'));
    });

    testWidgets('un membre ordinaire ne voit rien de tout cela', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        chemin: AppRoutes.accueil,
        caserne: caserneEssaiDans(3),
      );
      expect(find.byType(AppBanner), findsNothing);
    });

    testWidgets('l\'essai qui se termine ne grise aucune case', (tester) async {
      await _ouvrir(
        tester,
        chemin: AppRoutes.calendrier,
        caserne: caserneEssaiDans(3),
        appartenance: appartenanceAdmin,
      );

      await tester.tap(find.byType(SlotChip).first);
      await tester.pumpAndSettle();
      // Aucun refus : la caserne écrit encore, et jusqu'au dernier jour.
      expect(find.text(AppStrings.moisRefusLectureSeule), findsNothing);
    });
  });
}
