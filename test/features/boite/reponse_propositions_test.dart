/// **Le parcours de réponse du ticket 021, éprouvé dans la Boîte.**
///
/// Ce fichier est celui de l'écran des propositions, déplacé et non réécrit :
/// l'écran a disparu au chantier 064b, le parcours non. Chaque attente d'alors
/// est encore là — la charge utile à une clé, le refus qui confirme, la ligne
/// qui revient à sa place exacte, la bannière d'information pour un créneau
/// repris, le compte en attente sur l'accueil.
///
/// **Ce qui a changé, et il faut le dire :** répondre coûte une touche de plus.
/// Le brief du 064 (`design/064 § 3.4`, décision 2 du chantier 064b) remplace
/// la ligne à deux boutons par une carte qui ouvre la réponse — une feuille de
/// bas d'écran en `compact`, le volet latéral en `large`. La promesse « deux
/// touches » de `design/021 § 2` devient donc « la notification, la ligne, la
/// réponse ». Le test le dit en toutes lettres plutôt que de faire comme si de
/// rien n'était.
library;

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/entete_section.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/features/boite/presentation/widgets/panneau_reponse.dart';
import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/domain/propositions_providers.dart';
import 'package:astreinte_sp/features/propositions/presentation/widgets/carte_proposition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_propositions.dart';
import '../../support/promesse_envoi.dart';

/// Un téléphone : la composition de référence de cet écran.
const Size _telephone = Size(390, 844);

/// Le lien public d'une notification (`docs/WORKFLOWS.md § 8`).
const String _lienNotification = '/proposals';

/// L'adresse où il mène depuis le chantier 064b.
final String _ongletPropositions = AppRoutes.boiteOnglet(
  OngletBoite.propositions,
);

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
  Appartenance appartenance = appartenanceMembre,
}) async {
  final propositions = depot ?? _depot();

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    propositions: propositions,
    reseau: reseau,
    taille: taille,
    stabiliser: stabiliser,
  );
  await ouvrirRoute(tester, _lienNotification, stabiliser: stabiliser);
  return propositions;
}

/// Ouvre la réponse de la première proposition affichée.
Future<void> _ouvrirReponse(WidgetTester tester) async {
  await tester.tap(find.byType(CarteProposition).first);
  await tester.pumpAndSettle();
}

/// Le bouton « Accepter » de la réponse ouverte.
Finder _accepter() =>
    find.widgetWithText(PrimaryButton, AppStrings.propositionsAccepter);

Finder _refuser() =>
    find.widgetWithText(PrimaryButton, AppStrings.propositionsRefuser);

/// Le nombre de propositions en attente, lu **depuis l'accueil** : c'est là
/// qu'il s'affiche depuis le ticket 064, en tête de la section, et il vient
/// de la liste elle-même — jamais d'une seconde requête.
int _comptePropositions(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(AccueilScreen)),
).read(propositionsEnAttenteProvider);

void main() {
  group('Les propositions — l\'ouverture depuis une notification', () {
    testWidgets('le lien /proposals mène à l\'onglet, pas à l\'accueil', (
      tester,
    ) async {
      await _ouvrir(tester);

      // Le lien public est traduit par la liste blanche du ticket 024 : rien
      // n'a été dupliqué ici, et le lien n'a pas bougé d'un caractère quand
      // l'écran a disparu.
      expect(emplacementCourant(tester), _ongletPropositions);
      expect(find.byType(CarteProposition), findsNWidgets(3));
    });

    testWidgets(
      'trois touches : la notification, la ligne, puis « Accepter »',
      (tester) async {
        final depot = await _ouvrir(tester);

        // Première touche : la notification, déjà consommée par `ouvrirRoute`.
        // Deuxième : la ligne, qui ouvre la réponse. Troisième : le bouton.
        // Aucun écran intermédiaire, aucune confirmation.
        await _ouvrirReponse(tester);
        expect(find.byType(PanneauReponse), findsOneWidget);

        await tester.tap(_accepter());
        await tester.pumpAndSettle();

        expect(depot.chargesEnvoyees, hasLength(1));
        expect(find.byType(CarteProposition), findsNWidgets(2));
        // La feuille se referme d'elle-même : la ligne a quitté la liste.
        expect(find.byType(PanneauReponse), findsNothing);
      },
    );
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
          .widgetList<CarteProposition>(find.byType(CarteProposition))
          .toList();
      expect(
        lignes.map((CarteProposition ligne) => ligne.proposition.id),
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

        expect(find.byType(CarteProposition), findsOneWidget);
        expect(find.text('Août 2026'), findsNothing);
        expect(find.text('lundi 12 octobre'), findsOneWidget);
      },
    );

    testWidgets('chaque ligne porte sa date, son créneau et son ancienneté', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text('lundi 12 octobre'), findsOneWidget);
      expect(find.textContaining(AppStrings.creneauNuit), findsWidgets);
      // Les deux réponses ne sont plus sur la ligne : elles sont derrière un
      // appui, et une seule à la fois.
      expect(_accepter(), findsNothing);
      expect(_refuser(), findsNothing);
    });

    testWidgets('« Accepter » est la plus grande cible des deux', (
      tester,
    ) async {
      await _ouvrir(tester);
      await _ouvrirReponse(tester);

      final oui = tester.getSize(_accepter());
      final non = tester.getSize(_refuser());

      expect(oui.width, greaterThan(non.width));
      // Les deux restent très au-dessus du plancher tactile.
      expect(non.width, greaterThanOrEqualTo(48));
      expect(oui.height, greaterThanOrEqualTo(48));
      expect(non.height, greaterThanOrEqualTo(48));
    });

    testWidgets('la ligne touchée tient le plancher tactile', (tester) async {
      await _ouvrir(tester);

      final taille = tester.getSize(find.byType(CarteProposition).first);
      expect(taille.height, greaterThanOrEqualTo(48));
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
      await _ouvrir(tester, depot: _depot(propositions: const <Proposition>[]));

      expect(find.text(AppStrings.videPropositionsTitre), findsOneWidget);
      expect(find.text(AppStrings.videPropositionsTexte), findsOneWidget);
      expect(find.text(AppStrings.propositionsVideAction), findsOneWidget);
      expect(find.byType(CarteProposition), findsNothing);
    });

    testWidgets('son action ramène sur le Calendrier', (tester) async {
      await _ouvrir(tester, depot: _depot(propositions: const <Proposition>[]));

      await tester.tap(find.text(AppStrings.propositionsVideAction));
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.calendrier);
      expect(find.text(AppStrings.videPropositionsTitre), findsNothing);
    });
  });

  group('Les propositions — accepter', () {
    testWidgets('la charge utile ne porte que le statut', (tester) async {
      final depot = await _ouvrir(tester);
      await _ouvrirReponse(tester);

      await tester.tap(_accepter());
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
      await _ouvrirReponse(tester);

      await tester.tap(_accepter());
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

        await _ouvrirReponse(tester);
        await tester.tap(_accepter());
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
        await _ouvrirReponse(tester);
        await tester.tap(_accepter());
        await tester.pumpAndSettle();

        expect(depot.planningsRelus, isEmpty);
      },
    );
  });

  group('Les propositions — refuser', () {
    Future<void> ouvrirLaFeuille(WidgetTester tester) async {
      await _ouvrirReponse(tester);
      await tester.tap(_refuser());
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
      // La réponse est restée ouverte : on n'a rien perdu en renonçant.
      expect(find.byType(PanneauReponse), findsOneWidget);
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

    // **« Sera prévenu », et rien de plus** (ticket 055). La ligne touchée
    // prouve que `assignment_declined` est en file (migration 0039), pas
    // qu'elle est livrée : [aucunEnvoiPromis] refuse « est prévenu » à
    // l'écran comme dans ce que prononce le lecteur d'écran.
    testWidgets('la ligne disparaît et le message dit que l\'admin sera '
        'prévenu, sans rien affirmer de plus', (tester) async {
      await _ouvrir(tester);
      await ouvrirLaFeuille(tester);

      await tester.tap(find.text(AppStrings.refusConfirmer));
      await tester.pumpAndSettle();

      expect(find.byType(CarteProposition), findsNWidgets(2));
      expect(
        find.text(
          AppStrings.propositionsRefusee(
            'lundi 12 octobre, ${AppStrings.creneauNuit.toLowerCase()}',
          ),
        ),
        findsOneWidget,
      );
      aucunEnvoiPromis(tester);
    });

    testWidgets('un administrateur qui refuse ne se voit rien promettre', (
      tester,
    ) async {
      // Le déclencheur ne le prévient pas de son propre refus, et s'il est
      // seul à administrer la caserne, rien n'est mis en file.
      await _ouvrir(tester, appartenance: appartenanceAdmin);
      await ouvrirLaFeuille(tester);

      await tester.tap(find.text(AppStrings.refusConfirmer));
      await tester.pumpAndSettle();

      expect(
        find.text(
          AppStrings.propositionsRefuseeParAdmin(
            'lundi 12 octobre, ${AppStrings.creneauNuit.toLowerCase()}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('chef de centre'), findsNothing);
      aucunEnvoiPromis(tester);
    });
  });

  group('Les propositions — l\'attribution disparue', () {
    testWidgets('elle produit une phrase, pas une erreur', (tester) async {
      await _ouvrir(tester, depot: _depot(disparue: true));
      await _ouvrirReponse(tester);

      await tester.tap(_accepter());
      await tester.pumpAndSettle();

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      // Un créneau repris est un **fait**, pas une panne : aucune bannière
      // rouge, aucun message d'échec.
      expect(banniere.variante, AppBannerVariante.information);
      expect(find.text(AppStrings.propositionsDisparue), findsOneWidget);
    });

    testWidgets('la ligne ne revient pas', (tester) async {
      await _ouvrir(tester, depot: _depot(disparue: true));
      await _ouvrirReponse(tester);

      await tester.tap(_accepter());
      await tester.pumpAndSettle();

      expect(find.byType(CarteProposition), findsNWidgets(2));
      expect(find.text('lundi 12 octobre'), findsNothing);
    });

    testWidgets('le message se ferme, et il est le seul à le pouvoir', (
      tester,
    ) async {
      await _ouvrir(tester, depot: _depot(disparue: true));
      await _ouvrirReponse(tester);

      await tester.tap(_accepter());
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
      await _ouvrirReponse(tester);

      await tester.tap(_accepter());
      await tester.pumpAndSettle();

      // Rien n'est perdu : les trois lignes sont là, dans le même ordre.
      final lignes = tester
          .widgetList<CarteProposition>(find.byType(CarteProposition))
          .toList();
      expect(
        lignes.map((CarteProposition ligne) => ligne.proposition.id),
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
      await _ouvrirReponse(tester);

      final bouton = tester.widget<PrimaryButton>(_accepter());
      expect(bouton.onPressed, isNull);
      // Un bouton grisé sans explication est un défaut (`DESIGN.md`).
      expect(bouton.raisonDesactivation, isNotNull);
      expect(find.text(AppStrings.propositionsHorsLigneRaison), findsWidgets);
    });

    testWidgets('une caserne suspendue bloque la réponse et l\'explique', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        depot: _depot(erreurReponse: ErreurProposition.lectureSeule),
      );
      await _ouvrirReponse(tester);

      await tester.tap(_accepter());
      await tester.pumpAndSettle();

      final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
      expect(banniere.variante, AppBannerVariante.lectureSeule);
      // La ligne est revenue : rien n'est perdu, et la liste n'est pas
      // remplacée par un message.
      expect(find.text('lundi 12 octobre'), findsOneWidget);

      // Et la réponse rouverte naît inerte, avec sa raison.
      await _ouvrirReponse(tester);
      expect(tester.widget<PrimaryButton>(_accepter()).onPressed, isNull);
    });
  });

  group('Les propositions — le compte en attente', () {
    testWidgets('l\'accueil l\'affiche, et il vient de la liste', (
      tester,
    ) async {
      await _ouvrir(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);

      expect(_comptePropositions(tester), 3);
      // Le compte est écrit à côté du titre de la section : un nombre sans
      // son nom ne dit rien.
      expect(
        find.text(
          AppStrings.accueilSectionCompte(
            AppStrings.accueilPropositionsSection,
            3,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('il baisse d\'un à chaque réponse', (tester) async {
      await _ouvrir(tester);
      await _ouvrirReponse(tester);

      await tester.tap(_accepter());
      await tester.pumpAndSettle();
      await ouvrirRoute(tester, AppRoutes.accueil);

      expect(_comptePropositions(tester), 2);
    });

    testWidgets('il tombe à zéro quand il ne reste rien', (tester) async {
      await _ouvrir(tester, depot: _depot(propositions: const <Proposition>[]));
      await ouvrirRoute(tester, AppRoutes.accueil);

      expect(_comptePropositions(tester), 0);
      expect(
        find.text(AppStrings.accueilVidePropositionsTitre),
        findsOneWidget,
      );
    });
  });
}
