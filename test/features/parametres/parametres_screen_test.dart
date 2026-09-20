import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/champ_texte.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';
import 'package:astreinte_sp/features/parametres/data/parametres_repository.dart';
import 'package:astreinte_sp/features/parametres/domain/parametres_caserne.dart';
import 'package:astreinte_sp/features/parametres/presentation/parametres_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_parametres.dart';

const String _chemin = '/admin/parametres';

/// Un téléphone haut : l'écran est un formulaire de six sections, et une
/// fenêtre de 844 dp obligerait à défiler pour tout, y compris pour des
/// contrôles qu'un vrai pouce atteint d'un geste.
const Size _fenetre = Size(412, 1400);

Future<FauxParametresRepository> _ouvrir(
  WidgetTester tester, {
  required FauxParametresRepository depot,
  Appartenance appartenance = appartenanceAdmin,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    parametres: depot,
    taille: _fenetre,
  );
  await ouvrirRoute(tester, _chemin);
  return depot;
}

/// Amène un contrôle sous les yeux : la liste est virtualisée, un widget qui
/// n'est pas construit n'est pas trouvable.
Future<void> _defilerJusqua(WidgetTester tester, Finder cible) async {
  await tester.scrollUntilVisible(
    cible,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ParametresScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Finder _champ(String libelle) => find.descendant(
  of: find.ancestor(of: find.text(libelle), matching: find.byType(ChampTexte)),
  matching: find.byType(TextField),
);

/// Le texte réellement saisi dans un champ. `find.text` ne suffit pas ici :
/// le texte d'invite du nom **est** le nom du seed, et trouverait deux
/// widgets.
String _valeur(WidgetTester tester, String libelle) =>
    tester.widget<TextField>(_champ(libelle)).controller!.text;

Future<void> _enregistrer(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.parametresEnregistrer));
  await tester.pumpAndSettle();
}

void main() {
  group('ParametresScreen', () {
    testWidgets('montre les réglages de la caserne', (tester) async {
      await _ouvrir(tester, depot: FauxParametresRepository());

      expect(find.byType(ParametresScreen), findsOneWidget);
      expect(_valeur(tester, AppStrings.parametresNom), 'CIS Saint-Martin');
      expect(find.text(AppStrings.parametresSectionCaserne), findsOneWidget);
      expect(find.text(AppStrings.parametresSectionCreneaux), findsOneWidget);
      expect(find.text(AppStrings.parametresEffectifJour), findsOneWidget);

      // Rien n'a bougé : l'enregistrement est inerte, et il dit pourquoi.
      expect(
        find.text(AppStrings.parametresAucuneModification),
        findsOneWidget,
      );
    });

    testWidgets('dit la conséquence de l\'effectif et du jour limite', (
      tester,
    ) async {
      await _ouvrir(tester, depot: FauxParametresRepository());

      await _defilerJusqua(
        tester,
        find.text(AppStrings.parametresEffectifConsequence),
      );
      expect(
        find.text(AppStrings.parametresEffectifConsequence),
        findsOneWidget,
      );

      await _defilerJusqua(
        tester,
        find.text(AppStrings.parametresJourLimiteConsequence),
      );
      expect(
        find.text(AppStrings.parametresJourLimiteConsequence),
        findsOneWidget,
      );
    });

    testWidgets('un membre ordinaire n\'ouvre pas les réglages', (tester) async {
      final depot = await _ouvrir(
        tester,
        depot: FauxParametresRepository(),
        appartenance: appartenanceMembre,
      );

      // Depuis le ticket 024, le routeur ferme la porte avant l'écran. La
      // phrase de l'écran (`AppStrings.parametresReserveAdmin`) reste en
      // seconde ligne.
      expect(find.byType(ParametresScreen), findsNothing);
      expect(find.byType(ChampTexte), findsNothing);
      expect(depot.lectures, 0);
    });

    testWidgets('une lecture en échec propose de réessayer', (tester) async {
      final depot = await _ouvrir(
        tester,
        depot: FauxParametresRepository(
          erreurLecture: ErreurParametres.inconnue,
        ),
      );

      expect(find.text(AppStrings.parametresErreurTexte), findsOneWidget);

      depot.erreurLecture = null;
      await tester.tap(find.text(AppStrings.actionReessayer).first);
      await tester.pumpAndSettle();

      expect(_valeur(tester, AppStrings.parametresNom), 'CIS Saint-Martin');
      expect(
        depot.lectures,
        greaterThan(1),
        reason: 'la relecture est bien repartie vers le dépôt',
      );
    });

    testWidgets('augmenter l\'effectif de jour puis enregistrer', (
      tester,
    ) async {
      final depot = await _ouvrir(tester, depot: FauxParametresRepository());

      final plus = find.byTooltip(
        AppStrings.parametresAugmenter(AppStrings.parametresEffectifJour),
      );
      await _defilerJusqua(tester, plus);
      await tester.tap(plus);
      await tester.pumpAndSettle();
      await tester.tap(plus);
      await tester.pumpAndSettle();

      await _enregistrer(tester);

      expect(depot.ecritures.single.effectifJour, 3);
      expect(depot.ecritures.single.effectifNuit, 1);
      expect(find.text(AppStrings.parametresEnregistres), findsOneWidget);
    });

    testWidgets('un nom vide est refusé avant l\'envoi', (tester) async {
      final depot = await _ouvrir(tester, depot: FauxParametresRepository());

      await tester.enterText(_champ(AppStrings.parametresNom), '');
      await tester.pumpAndSettle();
      await _enregistrer(tester);

      expect(depot.ecritures, isEmpty);
      expect(find.text(AppStrings.parametresNomVide), findsOneWidget);
      expect(find.text(AppStrings.parametresACorriger(1)), findsOneWidget);
    });

    testWidgets('une heure mal écrite est refusée avant l\'envoi', (
      tester,
    ) async {
      final depot = await _ouvrir(tester, depot: FauxParametresRepository());

      final debut = _champ(AppStrings.parametresDebutJour);
      await _defilerJusqua(tester, debut);
      await tester.enterText(debut, '2560');
      await tester.pumpAndSettle();
      await _enregistrer(tester);

      expect(depot.ecritures, isEmpty);
      expect(find.text(AppStrings.parametresHeureInvalide), findsOneWidget);
    });

    testWidgets('un refus du serveur reste lisible en bannière', (
      tester,
    ) async {
      final depot = await _ouvrir(
        tester,
        depot: FauxParametresRepository(
          erreurEcriture: ErreurParametres.droits,
        ),
      );

      await tester.enterText(
        _champ(AppStrings.parametresNom),
        'CIS Saint-Martin-en-Vercors',
      );
      await tester.pumpAndSettle();
      await _enregistrer(tester);

      expect(depot.ecritures, hasLength(1));
      // Une fois dans la bannière, une fois dans le bandeau d'annonce.
      expect(find.text(AppStrings.parametresRefusDroits), findsWidgets);
    });

    testWidgets('une surcharge de samedi se pose depuis la feuille', (
      tester,
    ) async {
      final depot = await _ouvrir(tester, depot: FauxParametresRepository());

      final samedi = find.byTooltip(
        AppStrings.parametresSurchargeModifier(JourSemaine.samedi.libelle),
      );
      await _defilerJusqua(tester, samedi);
      await tester.tap(samedi);
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.parametresSurchargeDefautRappel(1, 1)),
        findsOneWidget,
      );

      await tester.tap(find.text(AppStrings.parametresSurchargeFixerJour));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip(
          AppStrings.parametresAugmenter(
            AppStrings.parametresCreneauJourLibelle,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.parametresSurchargeAppliquer));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.parametresSurchargeValeur(2, null)),
        findsOneWidget,
      );

      await _enregistrer(tester);

      expect(
        depot.ecritures.single.settingsJson['required_overrides'],
        <String, dynamic>{
          'sat': <String, dynamic>{'day': 2},
        },
      );
    });

    testWidgets('l\'écran « Membres » y mène, et ramène', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceAdmin],
        membres: FauxMembresRepository(
          membresActifs: const <MembreCaserne>[membreJean],
        ),
        parametres: FauxParametresRepository(),
        taille: _fenetre,
      );
      await ouvrirRoute(tester, '/admin/membres');

      await tester.tap(find.byTooltip(AppStrings.parametresDepuisMembres));
      await tester.pumpAndSettle();
      expect(find.byType(ParametresScreen), findsOneWidget);

      await tester.tap(find.byTooltip(AppStrings.parametresVersMembres));
      await tester.pumpAndSettle();
      expect(find.byType(ParametresScreen), findsNothing);
      expect(find.text('Jean Dupont'), findsOneWidget);
    });

    testWidgets('une date de surcharge impossible est refusée', (tester) async {
      await _ouvrir(tester, depot: FauxParametresRepository());

      final ajouter = find.text(AppStrings.parametresSurchargeAjouterDate);
      await _defilerJusqua(tester, ajouter);
      await tester.tap(ajouter);
      await tester.pumpAndSettle();

      await tester.enterText(
        _champ(AppStrings.parametresSurchargeDate),
        '30022026',
      );
      await tester.tap(find.text(AppStrings.parametresSurchargeFixerNuit));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.parametresSurchargeAppliquer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.parametresDateInvalide), findsOneWidget);

      // Corrigée, elle passe et rejoint la liste des dates.
      await tester.enterText(
        _champ(AppStrings.parametresSurchargeDate),
        '31122026',
      );
      await tester.tap(find.text(AppStrings.parametresSurchargeAppliquer));
      await tester.pumpAndSettle();

      expect(find.text('31/12/2026'), findsOneWidget);
    });
  });
}
