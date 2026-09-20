import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/periodes/data/periodes_repository.dart';
import 'package:astreinte_sp/features/periodes/presentation/periodes_screen.dart';
import 'package:astreinte_sp/features/periodes/presentation/widgets/feuille_ouvrir_mois.dart';
import 'package:astreinte_sp/features/periodes/presentation/widgets/feuille_reouverture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_periodes.dart';

const String _cheminPeriodes = '/admin/periodes';

/// Un écran haut : les trois lignes de mois tiennent sans défiler, et la
/// composition reste celle du téléphone (moins de 600 dp de large).
const Size _telephoneLong = Size(420, 1600);

final DateTime _maintenant = DateTime.now();

/// Le premier jour d'un mois relatif au mois courant. `DateTime` normalise
/// les mois hors bornes : décembre + 1 est bien janvier suivant.
DateTime _mois(int decalage) =>
    DateTime(_maintenant.year, _maintenant.month + decalage);

PeriodeSaisie _ouverte(int decalage) {
  final jour = _mois(decalage);
  return periodeOuverte(annee: jour.year, mois: jour.month);
}

PeriodeSaisie _fermee(int decalage) {
  final jour = _mois(decalage);
  return periodeFermeeDepuis(annee: jour.year, mois: jour.month);
}

String _libelle(int decalage) {
  final jour = _mois(decalage);
  return AppStrings.moisNomEtAnnee(jour.month, jour.year);
}

Future<FauxPeriodesRepository> _ouvrirPeriodes(
  WidgetTester tester, {
  required FauxPeriodesRepository depot,
  Appartenance appartenance = appartenanceAdmin,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    periodes: depot,
    taille: _telephoneLong,
  );
  await ouvrirRoute(tester, _cheminPeriodes);
  return depot;
}

void main() {
  group('PeriodesScreen', () {
    testWidgets('liste les mois à venir et les mois écoulés, avec leur état', (
      tester,
    ) async {
      await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_fermee(-1), _ouverte(1)],
          actifs: const <String>{'u1', 'u2', 'u3', 'u4'},
          saisies: <String, Set<String>>{
            _ouverte(1).cle: const <String>{'u1', 'u2', 'u3'},
          },
        ),
      );

      expect(find.byType(PeriodesScreen), findsOneWidget);
      expect(find.text(_libelle(1)), findsOneWidget);
      expect(find.text(_libelle(-1)), findsOneWidget);
      expect(find.text(AppStrings.periodesSectionAVenir), findsOneWidget);
      expect(find.text(AppStrings.periodesSectionEcoules), findsOneWidget);

      // Un état ne se lit jamais à la couleur : le libellé est là.
      expect(find.text(AppStrings.periodeOuverte), findsOneWidget);
      expect(find.text(AppStrings.periodeVerrouillee), findsOneWidget);

      // Le taux, en toutes lettres.
      expect(find.text(AppStrings.periodeTauxSaisie(3, 4)), findsOneWidget);
      expect(find.text(AppStrings.periodeTauxSaisie(0, 4)), findsOneWidget);
      expect(find.text(AppStrings.periodeTauxPourcentage(75)), findsOneWidget);

      // Une action nommée par ligne, et une seule.
      expect(find.text(AppStrings.periodeActionVerrouiller), findsOneWidget);
      expect(find.text(AppStrings.periodeActionRouvrir), findsOneWidget);
    });

    testWidgets('une caserne sans membre actif ne montre pas « 0 % »', (
      tester,
    ) async {
      await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_ouverte(1)],
          actifs: const <String>{},
        ),
      );

      expect(find.text(AppStrings.periodeTauxAucunMembre), findsOneWidget);
      expect(find.text(AppStrings.periodeTauxPourcentage(0)), findsNothing);
    });

    testWidgets('un membre désactivé ne gonfle pas le taux', (tester) async {
      await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_ouverte(1)],
          actifs: const <String>{'u1', 'u2'},
          saisies: <String, Set<String>>{
            _ouverte(1).cle: const <String>{'u1', 'parti'},
          },
        ),
      );

      expect(find.text(AppStrings.periodeTauxSaisie(1, 2)), findsOneWidget);
    });

    testWidgets('verrouiller demande confirmation, puis ferme le mois', (
      tester,
    ) async {
      final depot = await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_ouverte(1)],
        ),
      );

      await tester.tap(find.text(AppStrings.periodeActionVerrouiller));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.periodeVerrouillerTitre(_libelle(1))),
        findsOneWidget,
      );
      expect(depot.verrouillages, isEmpty);

      await tester.tap(find.text(AppStrings.periodeVerrouillerConfirmer));
      await tester.pumpAndSettle();

      expect(depot.verrouillages, hasLength(1));
      expect(find.text(AppStrings.periodeVerrouillee), findsOneWidget);
      expect(find.text(AppStrings.periodeActionRouvrir), findsOneWidget);
      expect(
        find.text(AppStrings.periodeVerrouilleeConfirmation(_libelle(1))),
        findsOneWidget,
      );
    });

    testWidgets('annuler la confirmation ne verrouille rien', (tester) async {
      final depot = await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_ouverte(1)],
        ),
      );

      await tester.tap(find.text(AppStrings.periodeActionVerrouiller));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.actionAnnuler));
      await tester.pumpAndSettle();

      expect(depot.verrouillages, isEmpty);
      expect(find.text(AppStrings.periodeOuverte), findsOneWidget);
    });

    testWidgets('rouvrir repousse la date limite dans le même geste', (
      tester,
    ) async {
      final depot = await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_fermee(-1)],
        ),
      );

      await tester.tap(find.text(AppStrings.periodeActionRouvrir));
      await tester.pumpAndSettle();

      expect(find.byType(FeuilleReouverture), findsOneWidget);
      expect(find.text(AppStrings.periodeRouvrirRegle), findsOneWidget);

      // Pré-rempli sur une valeur future : trois jours.
      final propose = _maintenant.add(
        const Duration(days: FeuilleReouverture.joursProposes),
      );
      expect(
        find.text(
          AppStrings.periodeDateLimiteHeure(
            '${nomJourLong(propose)} ${formaterDateLongue(propose)}',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(AppStrings.periodeRouvrirConfirmer));
      await tester.pumpAndSettle();

      expect(depot.reouvertures, hasLength(1));
      expect(depot.reouvertures.single.limite.isAfter(_maintenant), isTrue);
      expect(find.text(AppStrings.periodeOuverte), findsOneWidget);
      expect(find.text(AppStrings.periodeActionVerrouiller), findsOneWidget);
    });

    testWidgets('un mois fermé avant l\'heure se rouvre sur sa date d\'origine',
        (tester) async {
      // Verrouillé à la main alors que sa date limite était encore devant :
      // rouvrir ne doit pas la raccourcir au passage.
      final limite = DateTime.now().add(const Duration(days: 40));
      final depot = await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[
            PeriodeSaisie(
              id: 'p-tot',
              stationId: stationTest,
              annee: _mois(1).year,
              mois: _mois(1).month,
              statut: PeriodeEtat.verrouillee,
              dateLimite: DateTime(
                limite.year,
                limite.month,
                limite.day,
                23,
                59,
                59,
              ),
              verrouilleeLe: DateTime.now(),
            ),
          ],
        ),
      );

      await tester.tap(find.text(AppStrings.periodeActionRouvrir));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.periodeRouvrirConfirmer));
      await tester.pumpAndSettle();

      expect(depot.reouvertures.single.limite.day, limite.day);
      expect(depot.reouvertures.single.limite.month, limite.month);
    });

    testWidgets('rouvrir sans repousser la date limite est refusé', (
      tester,
    ) async {
      final depot = await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_fermee(-1)],
        ),
      );

      await tester.tap(find.text(AppStrings.periodeActionRouvrir));
      await tester.pumpAndSettle();

      // Trois jours en arrière ramènent la date limite à aujourd'hui, puis
      // dans le passé : le bouton se désactive et dit pourquoi.
      for (var recul = 0; recul < 4; recul++) {
        await tester.tap(
          find.byTooltip(AppStrings.periodeRouvrirJourPlusTot),
        );
        await tester.pumpAndSettle();
      }

      expect(
        find.text(AppStrings.periodeRouvrirRefusDatePassee),
        findsOneWidget,
      );

      await tester.tap(find.text(AppStrings.periodeRouvrirConfirmer));
      await tester.pumpAndSettle();

      // Rien n'est parti : l'écran refuse avant la base.
      expect(depot.reouvertures, isEmpty);
      expect(find.byType(FeuilleReouverture), findsOneWidget);
    });

    testWidgets('le refus de la base est affiché tel qu\'il est dit', (
      tester,
    ) async {
      final depot = await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_ouverte(1)],
          erreurEcriture: ErreurPeriodes.suspendue,
        ),
      );

      await tester.tap(find.text(AppStrings.periodeActionVerrouiller));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.periodeVerrouillerConfirmer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.periodeRefusSuspendue), findsOneWidget);
      expect(find.text(AppStrings.periodeOuverte), findsOneWidget);
      expect(depot.verrouillages, hasLength(1));
    });

    testWidgets('ouvrir un mois propose les mois suivants et marque les déjà '
        'ouverts', (tester) async {
      final depot = await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_ouverte(1)],
        ),
      );

      await tester.tap(find.text(AppStrings.periodesOuvrirUnMois));
      await tester.pumpAndSettle();

      expect(find.byType(FeuilleOuvrirMois), findsOneWidget);
      expect(find.text(AppStrings.periodeCreerDejaOuvert), findsOneWidget);

      await tester.tap(find.text(_libelle(2)));
      await tester.pumpAndSettle();

      expect(depot.creations, hasLength(1));
      expect(depot.creations.single.mois, _mois(2).month);
      expect(
        find.text(AppStrings.periodeCreeeConfirmation(_libelle(2))),
        findsOneWidget,
      );
      expect(find.text(_libelle(2)), findsOneWidget);
    });

    testWidgets('un mois déjà ouvert n\'est pas choisissable deux fois', (
      tester,
    ) async {
      final depot = await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_ouverte(1)],
        ),
      );

      await tester.tap(find.text(AppStrings.periodesOuvrirUnMois));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(FeuilleOuvrirMois),
          matching: find.text(_libelle(1)),
        ),
      );
      await tester.pumpAndSettle();

      expect(depot.creations, isEmpty);
      expect(find.byType(FeuilleOuvrirMois), findsOneWidget);
    });

    testWidgets('sans aucun mois, l\'écran explique et propose d\'en ouvrir un',
        (tester) async {
      await _ouvrirPeriodes(tester, depot: FauxPeriodesRepository());

      expect(find.text(AppStrings.periodesVideTitre), findsOneWidget);
      expect(find.text(AppStrings.periodesOuvrirUnMois), findsOneWidget);
    });

    testWidgets('une lecture en échec propose de réessayer', (tester) async {
      final depot = await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(erreurLecture: true),
      );

      expect(find.text(AppStrings.periodesErreurTexte), findsOneWidget);

      depot
        ..erreurLecture = false
        ..periodes = <PeriodeSaisie>[_ouverte(1)];
      await tester.tap(find.text(AppStrings.actionReessayer));
      await tester.pumpAndSettle();

      expect(find.text(_libelle(1)), findsOneWidget);
    });

    testWidgets('un membre simple n\'y a rien à faire', (tester) async {
      await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_ouverte(1)],
        ),
        appartenance: appartenanceMembre,
      );

      expect(find.text(AppStrings.periodesReserveAdmin), findsOneWidget);
      expect(find.text(AppStrings.periodeActionVerrouiller), findsNothing);
    });

    testWidgets('les autres écrans d\'administration restent à portée', (
      tester,
    ) async {
      await _ouvrirPeriodes(
        tester,
        depot: FauxPeriodesRepository(
          periodes: <PeriodeSaisie>[_ouverte(1)],
        ),
      );

      expect(find.byTooltip(AppStrings.parametresVersMembres), findsOneWidget);
      expect(
        find.byTooltip(AppStrings.parametresDepuisMembres),
        findsOneWidget,
      );
    });
  });
}
