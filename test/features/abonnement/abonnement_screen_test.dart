import 'dart:async';

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/features/abonnement/data/abonnement_repository.dart';
import 'package:astreinte_sp/features/abonnement/domain/abonnement.dart';
import 'package:astreinte_sp/features/abonnement/presentation/abonnement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_abonnement.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';

const String _chemin = '/admin/abonnement';

/// Un téléphone haut : trois blocs empilés, et un vrai pouce doit atteindre
/// les deux boutons de formule sans défiler deux fois.
const Size _fenetre = Size(412, 1200);

Future<FauxAbonnementRepository> _ouvrir(
  WidgetTester tester, {
  FauxAbonnementRepository? depot,
  FauxOuvertureExterne? ouverture,
  Appartenance appartenance = appartenanceAdmin,
  String chemin = _chemin,
  bool stabiliser = true,
}) async {
  final effectif = depot ?? FauxAbonnementRepository();
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    abonnement: effectif,
    ouverture: ouverture,
    taille: _fenetre,
    stabiliser: stabiliser,
  );
  await ouvrirRoute(tester, chemin, stabiliser: stabiliser);
  return effectif;
}

Finder _banniere(AppBannerVariante variante) => find.byWidgetPredicate(
  (Widget w) => w is AppBanner && w.variante == variante,
);

void main() {
  group('AbonnementScreen — sans prestataire configuré', () {
    testWidgets('l\'écran s\'ouvre et dit l\'état vrai, sans rien casser', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.byType(AbonnementScreen), findsOneWidget);
      // C'est le cas du projet aujourd'hui : bannière `information`, jamais
      // `erreur` — rien n'est cassé, la caserne tourne.
      expect(_banniere(AppBannerVariante.information), findsOneWidget);
      expect(find.text(AppStrings.abonnementNonConfigureTexte), findsOneWidget);
    });

    testWidgets('la caserne reste en essai, avec sa date de fin', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text(AppStrings.abonnementEtatEssai), findsOneWidget);
      expect(find.textContaining('20 novembre 2026'), findsOneWidget);
    });

    testWidgets('les tarifs restent affichés : c\'est une information', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text(AppStrings.abonnementFormuleMensuelle), findsOneWidget);
      expect(find.text(AppStrings.abonnementFormuleAnnuelle), findsOneWidget);
      expect(find.text('12 €'), findsOneWidget);
      expect(find.text('120 €'), findsOneWidget);
    });

    testWidgets('les boutons sont inertes **et disent pourquoi**', (
      tester,
    ) async {
      final depot = await _ouvrir(tester);

      // `DESIGN.md § Buttons` : un bouton grisé sans explication est un défaut.
      expect(
        find.text(AppStrings.abonnementBientotDisponible),
        findsNWidgets(2),
      );

      await tester.tap(find.text(AppStrings.abonnementSouscrire).first);
      await tester.pumpAndSettle();
      expect(depot.souscriptions, isEmpty);
    });

    testWidgets('aucun bloc de gestion : il n\'y a rien à gérer', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text(AppStrings.abonnementGerer), findsNothing);
      expect(find.text(AppStrings.abonnementSectionGestion), findsNothing);
    });
  });

  group('AbonnementScreen — les états', () {
    testWidgets('abonnée : le statut, la date, et plus de formules', (
      tester,
    ) async {
      await _ouvrir(tester, depot: FauxAbonnementRepository(etat: etatActif));

      expect(find.text(AppStrings.abonnementEtatActif), findsOneWidget);
      expect(find.textContaining('20 décembre 2026'), findsOneWidget);
      // Le bloc des formules disparaît : il n'y a plus rien à souscrire.
      expect(find.text(AppStrings.abonnementSectionFormules), findsNothing);
      expect(find.text(AppStrings.abonnementGerer), findsOneWidget);
      expect(find.text(AppStrings.abonnementGererDetail), findsOneWidget);
    });

    testWidgets('retard de paiement : l\'échéance et la sortie sont nommées', (
      tester,
    ) async {
      await _ouvrir(tester, depot: FauxAbonnementRepository(etat: etatRetard));

      expect(find.text(AppStrings.abonnementEtatRetard), findsOneWidget);
      // Quatorze jours après le 20 novembre : le 4 décembre.
      expect(
        find.text(AppStrings.abonnementRetardEcheance('4 décembre 2026')),
        findsOneWidget,
      );
    });

    testWidgets(
      'retard de paiement : **aucun bouton « S\'abonner »**, seulement le portail',
      (tester) async {
        // Le bloquant : une carte qui expire ne met pas la caserne en « actif ».
        // Lui proposer « S'abonner » l'enverrait vers un **second** abonnement,
        // prélevé en parallèle du premier, pendant que le premier continue ses
        // relances. La carte se change dans le portail, et nulle part ailleurs.
        await _ouvrir(tester, depot: FauxAbonnementRepository(etat: etatRetard));

        expect(find.text(AppStrings.abonnementSouscrire), findsNothing);
        expect(find.text(AppStrings.abonnementSectionFormules), findsNothing);
        expect(find.text(AppStrings.abonnementGerer), findsOneWidget);
      },
    );

    testWidgets('résilié : la souscription redevient possible', (tester) async {
      // Un client qui revient : l'abonnement d'avant est mort chez le
      // prestataire, rien ne se dédouble.
      await _ouvrir(tester, depot: FauxAbonnementRepository(etat: etatResilie));

      expect(find.text(AppStrings.abonnementEtatResilie), findsOneWidget);
      expect(find.text(AppStrings.abonnementSouscrire), findsNWidgets(2));
      expect(find.text(AppStrings.abonnementGerer), findsOneWidget);
    });

    testWidgets('suspendue : « rien n\'a été supprimé » est écrit', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(etat: etatSuspendu),
      );

      expect(find.text(AppStrings.abonnementEtatSuspendu), findsOneWidget);
      // La promesse de `docs/PRD.md § 6.6`, et la seule phrase qui compte pour
      // un chef de centre qui découvre l'écran un mardi soir.
      expect(find.textContaining('Rien n\'a été supprimé'), findsOneWidget);
    });

    testWidgets(
      'essai expiré, pas encore suspendue : on le dit sans paniquer',
      (tester) async {
        await _ouvrir(
          tester,
          depot: FauxAbonnementRepository(etat: etatEssaiExpire),
        );

        // Bannière `attention`, pas `erreur` : la tâche quotidienne n'a pas
        // encore tourné, et ce n'est pas une panne.
        expect(_banniere(AppBannerVariante.attention), findsOneWidget);
        expect(
          find.text(AppStrings.abonnementEssaiExpireTexte),
          findsOneWidget,
        );
        // Le statut reste celui de la base : « Période d'essai ».
        expect(find.text(AppStrings.abonnementEtatEssai), findsOneWidget);
        expect(find.textContaining('Terminée le'), findsOneWidget);
      },
    );
  });

  group('AbonnementScreen — souscrire et gérer', () {
    testWidgets('souscrire ouvre la page de paiement du prestataire', (
      tester,
    ) async {
      final ouverture = FauxOuvertureExterne();
      final depot = await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(etat: etatEssaiConfigure),
        ouverture: ouverture,
      );

      await tester.tap(find.text(AppStrings.abonnementSouscrire).first);
      await tester.pumpAndSettle();

      expect(depot.souscriptions, <FormuleAbonnement>[
        FormuleAbonnement.mensuelle,
      ]);
      expect(ouverture.adresses, <String>['https://checkout.example/session']);
    });

    testWidgets('la formule annuelle est un second bouton, pas un défaut', (
      tester,
    ) async {
      final depot = await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(etat: etatEssaiConfigure),
      );

      await tester.tap(find.text(AppStrings.abonnementSouscrire).last);
      await tester.pumpAndSettle();

      expect(depot.souscriptions, <FormuleAbonnement>[
        FormuleAbonnement.annuelle,
      ]);
    });

    testWidgets('l\'économie annuelle est annoncée, et calculée', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(etat: etatEssaiConfigure),
      );

      expect(find.text(AppStrings.abonnementEconomie('24 €')), findsOneWidget);
    });

    testWidgets('gérer ouvre le portail', (tester) async {
      final ouverture = FauxOuvertureExterne();
      final depot = await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(etat: etatActif),
        ouverture: ouverture,
      );

      await tester.tap(find.text(AppStrings.abonnementGerer));
      await tester.pumpAndSettle();

      expect(depot.portails, 1);
      expect(ouverture.adresses, hasLength(1));
    });

    testWidgets('un onglet bloqué se dit, au lieu de ne rien faire', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(etat: etatActif),
        ouverture: FauxOuvertureExterne(autorise: false),
      );

      await tester.tap(find.text(AppStrings.abonnementGerer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.abonnementOngletBloque), findsWidgets);
    });

    testWidgets('un refus du serveur reste lisible en bannière', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(
          etat: etatEssaiConfigure,
          erreurAction: ErreurAbonnement.prestataire,
        ),
      );

      await tester.tap(find.text(AppStrings.abonnementSouscrire).first);
      await tester.pumpAndSettle();

      // Un `SnackBar` disparaît ; la raison d'un refus doit rester à l'écran.
      expect(_banniere(AppBannerVariante.erreur), findsOneWidget);
      expect(find.text(AppStrings.abonnementEchecPrestataire), findsWidgets);
    });
  });

  group('AbonnementScreen — le retour du prestataire', () {
    testWidgets('?paiement=ok relit, et dit que le statut suit', (
      tester,
    ) async {
      // La caserne est encore en essai : le webhook n'est pas passé. L'écran le
      // dit au lieu de faire tourner un sablier.
      final depot = await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(etat: etatEssaiConfigure),
        chemin: '$_chemin?paiement=ok',
      );

      expect(depot.lectures, greaterThan(1));
      expect(find.text(AppStrings.abonnementPaiementEnAttente), findsOneWidget);
    });

    testWidgets(
      '?paiement=ok sur une caserne déjà active annonce le paiement',
      (tester) async {
        await _ouvrir(
          tester,
          depot: FauxAbonnementRepository(etat: etatActif),
          chemin: '$_chemin?paiement=ok',
        );

        expect(
          find.text(AppStrings.abonnementPaiementEnregistre),
          findsOneWidget,
        );
      },
    );

    testWidgets('?paiement=annule ne dit rien : ce n\'est pas un échec', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(etat: etatEssaiConfigure),
        chemin: '$_chemin?paiement=annule',
      );

      expect(_banniere(AppBannerVariante.erreur), findsNothing);
      expect(find.text(AppStrings.abonnementPaiementEnregistre), findsNothing);
      expect(find.text(AppStrings.abonnementPaiementEnAttente), findsNothing);
    });

    testWidgets('un paramètre inventé n\'a aucune autorité', (tester) async {
      await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(etat: etatEssaiConfigure),
        chemin: '$_chemin?paiement=nimportequoi',
      );

      expect(find.text(AppStrings.abonnementPaiementEnregistre), findsNothing);
      expect(find.text(AppStrings.abonnementEtatEssai), findsOneWidget);
    });
  });

  group('AbonnementScreen — chargement, erreur, droits', () {
    testWidgets('le chargement montre l\'ossature, jamais une roue', (
      tester,
    ) async {
      final depot = _DepotLent();
      await _ouvrir(tester, depot: depot, stabiliser: false);

      expect(find.byType(LoadingSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      depot.liberer();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingSkeleton), findsNothing);

      await demonter(tester);
    });

    testWidgets('une lecture en échec propose de réessayer', (tester) async {
      final depot = await _ouvrir(
        tester,
        depot: FauxAbonnementRepository(
          erreurLecture: ErreurAbonnement.inconnue,
        ),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(AppStrings.abonnementErreurTexte), findsOneWidget);

      depot.erreurLecture = null;
      await tester.tap(find.text(AppStrings.actionReessayer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.abonnementEtatEssai), findsOneWidget);
    });

    testWidgets('un membre ordinaire n\'ouvre pas l\'écran', (tester) async {
      await _ouvrir(tester, appartenance: appartenanceMembre);

      // Le routeur ferme la porte avant l'écran (préfixe `/admin`).
      expect(find.byType(AbonnementScreen), findsNothing);
      expect(emplacementCourant(tester), isNot(contains('abonnement')));
    });
  });
}

/// Un dépôt dont la lecture ne rend la main que sur commande.
///
/// L'ossature reste alors à l'écran le temps qu'on l'y regarde, quel que soit
/// le nombre d'images pompées : depuis que les destinations changent sans
/// transition (ticket 063), la réponse arrive une image plus tôt, et l'attente
/// ne dure plus assez pour qu'on compte dessus.
class _DepotLent extends FauxAbonnementRepository {
  final Completer<void> _verrou = Completer<void>();

  void liberer() => _verrou.complete();

  @override
  Future<EtatAbonnement> lire(String stationId) async {
    await _verrou.future;
    return super.lire(stationId);
  }
}
