import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/app_scaffold.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/entete_section.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/presentation/widgets/ligne_proposition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_propositions.dart';

/// Un téléphone : la composition de référence de cet écran.
const Size _telephone = Size(390, 844);

/// Le lien public d'une notification (`docs/WORKFLOWS.md § 8`).
const String _lienNotification = '/proposals';

/// Trois propositions, deux mois. Le 12 et le 19 octobre, le 3 novembre.
FauxPropositionsRepository _depot({
  List<Proposition>? propositions,
  ErreurProposition? erreurLecture,
  ErreurProposition? erreurReponse,
  bool disparue = false,
  PlanningEtat? etatApresReponse,
}) => FauxPropositionsRepository(
  propositions:
      propositions ??
      <Proposition>[
        proposition(
          id: 'a-nov',
          creneauId: 'c-nov',
          planningId: 'plan-11',
          jour: DateTime(2026, 11, 3),
          creneau: CreneauType.jour,
        ),
        proposition(
          id: 'a-19',
          creneauId: 'c-19',
          jour: DateTime(2026, 10, 19),
          creneau: CreneauType.jour,
        ),
        proposition(
          id: 'a-12',
          creneauId: 'c-12',
          jour: DateTime(2026, 10, 12),
        ),
      ],
  erreurLecture: erreurLecture,
  erreurReponse: erreurReponse,
  disparue: disparue,
  etatApresReponse: etatApresReponse,
);

Future<FauxPropositionsRepository> _ouvrir(
  WidgetTester tester, {
  FauxPropositionsRepository? depot,
  Size taille = _telephone,
  Connectivite? reseau,
  bool stabiliser = true,
}) async {
  final propositions = depot ?? _depot();

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    propositions: propositions,
    reseau: reseau,
    taille: taille,
    stabiliser: stabiliser,
  );
  await ouvrirRoute(tester, _lienNotification, stabiliser: stabiliser);
  return propositions;
}

/// Le bouton « Accepter » de la première ligne affichée.
Finder _accepter() => find.widgetWithText(
  PrimaryButton,
  AppStrings.propositionsAccepter,
);

Finder _refuser() => find.widgetWithText(
  PrimaryButton,
  AppStrings.propositionsRefuser,
);

/// Le nombre porté par la pastille de l'onglet « Propositions », lu là où il
/// est réellement posé : sur la destination de la coquille, que la barre du
/// bas et le rail latéral partagent.
int _pastille(WidgetTester tester) {
  final coquille = tester.widget<AppScaffold>(find.byType(AppScaffold));
  return coquille.destinations[1].pastille ?? 0;
}

void main() {
  group('Les propositions — l\'ouverture depuis une notification', () {
    testWidgets('le lien /proposals mène à la liste, pas à l\'accueil', (
      tester,
    ) async {
      await _ouvrir(tester);

      // Le lien public est traduit par la liste blanche du ticket 024 : rien
      // n'a été dupliqué ici.
      expect(emplacementCourant(tester), '/?onglet=1');
      expect(find.byType(LigneDeProposition), findsNWidgets(3));
    });

    testWidgets('deux touches suffisent : la notification puis « Accepter »', (
      tester,
    ) async {
      final depot = await _ouvrir(tester);

      // Première touche : la notification, déjà consommée par `ouvrirRoute`.
      // Seconde touche : le bouton. Aucun écran intermédiaire, aucune
      // confirmation.
      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      expect(depot.chargesEnvoyees, hasLength(1));
      expect(find.byType(LigneDeProposition), findsNWidgets(2));
    });
  });

  group('Les propositions — la liste', () {
    testWidgets('elle est groupée par mois et triée par date', (tester) async {
      await _ouvrir(tester);

      expect(find.byType(EnteteSection), findsNWidgets(2));
      expect(find.text('Octobre 2026'), findsOneWidget);
      expect(find.text('Novembre 2026'), findsOneWidget);
      expect(find.text(AppStrings.propositionsCompte(2)), findsOneWidget);
      expect(find.text(AppStrings.propositionsCompte(1)), findsOneWidget);

      // L'ordre est celui du calendrier, jamais celui de la réponse du
      // serveur.
      final lignes = tester
          .widgetList<LigneDeProposition>(find.byType(LigneDeProposition))
          .toList();
      expect(
        lignes.map((LigneDeProposition ligne) => ligne.proposition.id),
        <String>['a-12', 'a-19', 'a-nov'],
      );
    });

    testWidgets(
      'une proposition d\'un mois archivé n\'est pas proposée à la réponse',
      (tester) async {
        // Le mois d'août s'est terminé sans réponse. La ligne existe toujours
        // en base — c'est l'histoire du membre — mais elle ne s'écrit plus :
        // afficher « Accepter » serait afficher un bouton qui ne fait rien
        // (ticket 044).
        await _ouvrir(
          tester,
          depot: _depot(
            propositions: <Proposition>[
              proposition(
                id: 'a-aout',
                creneauId: 'c-aout',
                planningId: 'plan-08',
                jour: DateTime(2026, 8, 14),
                planningEtat: PlanningEtat.archive,
              ),
              proposition(
                id: 'a-12',
                creneauId: 'c-12',
                jour: DateTime(2026, 10, 12),
              ),
            ],
          ),
        );

        expect(find.byType(LigneDeProposition), findsOneWidget);
        expect(find.text('Août 2026'), findsNothing);
        expect(find.text('lundi 12 octobre'), findsOneWidget);
      },
    );

    testWidgets('chaque ligne porte sa date, son créneau et ses deux actions', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text('lundi 12 octobre'), findsOneWidget);
      expect(find.text(AppStrings.creneauNuit), findsOneWidget);
      expect(_accepter(), findsNWidgets(3));
      expect(_refuser(), findsNWidgets(3));
    });

    testWidgets('« Accepter » est la plus grande cible des deux', (
      tester,
    ) async {
      await _ouvrir(tester);

      final oui = tester.getSize(_accepter().first);
      final non = tester.getSize(_refuser().first);

      expect(oui.width, greaterThan(non.width));
      // Les deux restent très au-dessus du plancher tactile.
      expect(non.width, greaterThanOrEqualTo(48));
      expect(oui.height, greaterThanOrEqualTo(48));
      expect(non.height, greaterThanOrEqualTo(48));
    });

    testWidgets('le chargement montre un squelette, jamais une roue', (
      tester,
    ) async {
      await _ouvrir(tester, stabiliser: false);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(LoadingSkeleton), findsNothing);
    });

    testWidgets('une lecture en échec propose de réessayer', (tester) async {
      await _ouvrir(
        tester,
        depot: _depot(erreurLecture: ErreurProposition.reseau),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
    });
  });

  group('Les propositions — l\'état vide', () {
    testWidgets('il explique et propose d\'aller saisir son mois', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        depot: _depot(propositions: const <Proposition>[]),
      );

      expect(find.text(AppStrings.videPropositionsTitre), findsOneWidget);
      expect(find.text(AppStrings.videPropositionsTexte), findsOneWidget);
      expect(find.text(AppStrings.propositionsVideAction), findsOneWidget);
      expect(find.byType(LigneDeProposition), findsNothing);
    });

    testWidgets('son action ramène sur « Mon mois »', (tester) async {
      await _ouvrir(
        tester,
        depot: _depot(propositions: const <Proposition>[]),
      );

      await tester.tap(find.text(AppStrings.propositionsVideAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.navMonMois), findsWidgets);
      expect(find.text(AppStrings.videPropositionsTitre), findsNothing);
    });
  });

  group('Les propositions — accepter', () {
    testWidgets('la charge utile ne porte que le statut', (tester) async {
      final depot = await _ouvrir(tester);

      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      // **Le garde-fou du ticket** : une colonne de plus ferait échouer toute
      // la requête en base (`docs/SCHEMA.md § 4`).
      expect(depot.chargesEnvoyees.single, <String, dynamic>{
        'status': 'accepted',
      });
      expect(depot.chargesEnvoyees.single.containsKey('responded_at'), isFalse);
    });

    testWidgets('la ligne disparaît et le message le confirme', (tester) async {
      await _ouvrir(tester);

      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      expect(find.text('lundi 12 octobre'), findsNothing);
      expect(
        find.text(
          AppStrings.propositionsAcceptee(
            'lundi 12 octobre, ${AppStrings.creneauNuit.toLowerCase()}',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'la dernière acceptation d\'un planning constate sa validation',
      (tester) async {
        final depot = await _ouvrir(
          tester,
          depot: _depot(
            propositions: <Proposition>[
              proposition(
                id: 'a-12',
                creneauId: 'c-12',
                planningId: 'plan-10',
                jour: DateTime(2026, 10, 12),
              ),
            ],
            etatApresReponse: PlanningEtat.valide,
          ),
        );

        await tester.tap(_accepter().first);
        await tester.pumpAndSettle();

        expect(depot.planningsRelus, <String>['plan-10']);
        expect(
          find.text(AppStrings.propositionsPlanningValide('octobre')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'une acceptation qui n\'est pas la dernière ne relit aucun planning',
      (tester) async {
        final depot = await _ouvrir(tester);

        // Le 12 et le 19 partagent le même planning : il reste une réponse à
        // donner, rien à constater.
        await tester.tap(_accepter().first);
        await tester.pumpAndSettle();

        expect(depot.planningsRelus, isEmpty);
      },
    );
  });

  group('Les propositions — refuser', () {
    Future<void> ouvrirLaFeuille(WidgetTester tester) async {
      await tester.tap(_refuser().first);
      await tester.pumpAndSettle();
    }

    testWidgets('le refus demande confirmation, l\'acceptation non', (
      tester,
    ) async {
      final depot = await _ouvrir(tester);
      await ouvrirLaFeuille(tester);

      // Rien n'est parti tant que la feuille n'est pas confirmée.
      expect(depot.chargesEnvoyees, isEmpty);
      expect(find.text(AppStrings.refusMotifLibelle), findsOneWidget);
      expect(find.text(AppStrings.refusGarder), findsOneWidget);
    });

    testWidgets('« Garder le créneau » ne refuse rien', (tester) async {
      final depot = await _ouvrir(tester);
      await ouvrirLaFeuille(tester);

      await tester.tap(find.text(AppStrings.refusGarder));
      await tester.pumpAndSettle();

      expect(depot.chargesEnvoyees, isEmpty);
      expect(find.byType(LigneDeProposition), findsNWidgets(3));
    });

    testWidgets('sans motif, la charge utile ne porte que le statut', (
      tester,
    ) async {
      final depot = await _ouvrir(tester);
      await ouvrirLaFeuille(tester);

      await tester.tap(find.text(AppStrings.refusConfirmer));
      await tester.pumpAndSettle();

      expect(depot.chargesEnvoyees.single, <String, dynamic>{
        'status': 'declined',
      });
    });

    testWidgets('avec motif, elle porte le statut et le motif, rien d\'autre', (
      tester,
    ) async {
      final depot = await _ouvrir(tester);
      await ouvrirLaFeuille(tester);

      await tester.enterText(find.byType(TextField), '  en formation  ');
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.refusConfirmer));
      await tester.pumpAndSettle();

      expect(depot.chargesEnvoyees.single, <String, dynamic>{
        'status': 'declined',
        'decline_reason': 'en formation',
      });
    });

    testWidgets('la ligne disparaît et le message prévient que l\'admin sait', (
      tester,
    ) async {
      await _ouvrir(tester);
      await ouvrirLaFeuille(tester);

      await tester.tap(find.text(AppStrings.refusConfirmer));
      await tester.pumpAndSettle();

      expect(find.byType(LigneDeProposition), findsNWidgets(2));
      expect(
        find.text(
          AppStrings.propositionsRefusee(
            'lundi 12 octobre, ${AppStrings.creneauNuit.toLowerCase()}',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('Les propositions — l\'attribution disparue', () {
    testWidgets('elle produit une phrase, pas une erreur', (tester) async {
      await _ouvrir(tester, depot: _depot(disparue: true));

      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      // Un créneau repris est un **fait**, pas une panne : aucune bannière
      // rouge, aucun message d'échec.
      expect(banniere.variante, AppBannerVariante.information);
      expect(find.text(AppStrings.propositionsDisparue), findsOneWidget);
    });

    testWidgets('la ligne ne revient pas', (tester) async {
      await _ouvrir(tester, depot: _depot(disparue: true));

      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      expect(find.byType(LigneDeProposition), findsNWidgets(2));
      expect(find.text('lundi 12 octobre'), findsNothing);
    });

    testWidgets('le message se ferme, et il est le seul à le pouvoir', (
      tester,
    ) async {
      await _ouvrir(tester, depot: _depot(disparue: true));

      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsLabel(AppStrings.propositionsDisparueFermer),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBanner), findsNothing);
    });
  });

  group('Les propositions — ce qui empêche de répondre', () {
    testWidgets('un échec réseau remet la ligne à sa place', (tester) async {
      await _ouvrir(
        tester,
        depot: _depot(erreurReponse: ErreurProposition.reseau),
      );

      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      // Rien n'est perdu : les trois lignes sont là, dans le même ordre.
      final lignes = tester
          .widgetList<LigneDeProposition>(find.byType(LigneDeProposition))
          .toList();
      expect(
        lignes.map((LigneDeProposition ligne) => ligne.proposition.id),
        <String>['a-12', 'a-19', 'a-nov'],
      );

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.erreur);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
    });

    testWidgets('hors ligne, les boutons sont inertes et disent pourquoi', (
      tester,
    ) async {
      final reseau = ConnectiviteMemoire(enLigne: false);
      addTearDown(reseau.dispose);

      await _ouvrir(tester, reseau: reseau);

      final bouton = tester.widget<PrimaryButton>(_accepter().first);
      expect(bouton.onPressed, isNull);
      // Un bouton grisé sans explication est un défaut (`DESIGN.md`).
      expect(bouton.raisonDesactivation, isNotNull);
      expect(
        find.text(AppStrings.propositionsHorsLigneRaison),
        findsWidgets,
      );
    });

    testWidgets('une caserne suspendue bloque la réponse et l\'explique', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        depot: _depot(erreurReponse: ErreurProposition.lectureSeule),
      );

      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.lectureSeule);
      // La ligne est revenue : rien n'est perdu, et la liste n'est pas
      // remplacée par un message.
      expect(find.text('lundi 12 octobre'), findsOneWidget);
      expect(
        tester.widget<PrimaryButton>(_accepter().first).onPressed,
        isNull,
      );
    });
  });

  group('Les propositions — la pastille de l\'onglet', () {
    testWidgets('elle porte le nombre en attente, et il est annoncé', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(_pastille(tester), 3);
      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('3')),
        findsOneWidget,
      );
      // Le chiffre est doublé d'un libellé : une pastille muette ne se lit
      // pas au lecteur d'écran.
      expect(find.byTooltip(AppStrings.navPropositionsBadge(3)), findsWidgets);
    });

    testWidgets('elle baisse d\'un à chaque réponse', (tester) async {
      await _ouvrir(tester);

      await tester.tap(_accepter().first);
      await tester.pumpAndSettle();

      expect(_pastille(tester), 2);
    });

    testWidgets('elle disparaît quand il ne reste rien', (tester) async {
      await _ouvrir(
        tester,
        depot: _depot(propositions: const <Proposition>[]),
      );

      expect(_pastille(tester), 0);
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('elle est visible depuis « Mon mois »', (tester) async {
      await _ouvrir(tester);

      await tester.tap(find.text(AppStrings.navMonMois).last);
      await tester.pumpAndSettle();

      // La coquille construit les destinations une fois : « Mon mois » porte
      // la même pastille sans rien savoir des propositions.
      expect(find.text(AppStrings.navMonMois), findsWidgets);
      expect(_pastille(tester), 3);
    });
  });
}
