/// Le contrôleur des échanges et le coordinateur de fraîcheur (tickets 070 et
/// 073) : relecture après chaque geste, rien publié sous un geste en vol,
/// `Donnee.echanges` relue par le coordinateur.
library;

import 'dart:async';

import 'package:astreinte_sp/core/caserne/caserne_providers.dart';
import 'package:astreinte_sp/core/fraicheur/fraicheur.dart';
import 'package:astreinte_sp/core/fraicheur/relecture.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/appartenances_locales.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/session/session_utilisateur.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreintes_providers.dart';
import 'package:astreinte_sp/features/echanges/data/echanges_repository.dart';
import 'package:astreinte_sp/features/echanges/domain/echange.dart';
import 'package:astreinte_sp/features/echanges/domain/echanges_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_caserne.dart';
import '../../support/faux_echanges.dart';

/// Un geste que le test laisse en vol.
class _GesteRetenu extends FauxEchangesRepository {
  _GesteRetenu({super.echanges});

  final Completer<void> retour = Completer<void>();

  @override
  Future<ResultatEchange> annuler({required String echangeId}) async {
    await retour.future;
    return super.annuler(echangeId: echangeId);
  }
}

ProviderContainer _conteneur(
  FauxEchangesRepository depot, {
  FauxAstreintesRepository? astreintes,
  DateTime Function()? horloge,
}) {
  final conteneur = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(
        (ref) => Stream<SessionUtilisateur?>.value(sessionMembre),
      ),
      membershipRepositoryProvider.overrideWithValue(
        FauxMembershipRepository(
          appartenances: const <Appartenance>[appartenanceMembre],
        ),
      ),
      appartenancesLocalesProvider.overrideWithValue(
        AppartenancesLocalesMemoire(),
      ),
      caserneRepositoryProvider.overrideWithValue(FauxCaserneRepository()),
      echangesRepositoryProvider.overrideWithValue(depot),
      astreintesRepositoryProvider.overrideWithValue(
        astreintes ?? FauxAstreintesRepository(),
      ),
      cacheAstreintesProvider.overrideWithValue(CacheAstreintesMemoire()),
      horlogeRafraichissementProvider.overrideWithValue(
        horloge ?? () => DateTime(2026, 10, 4, 10),
      ),
    ],
  );
  addTearDown(conteneur.dispose);
  conteneur
    ..listen(sessionProvider, (_, _) {})
    ..listen(appartenancesProvider, (_, _) {})
    ..listen(echangesControllerProvider, (_, _) {});
  return conteneur;
}

Future<EtatEchanges> _lu(ProviderContainer c) async {
  await c.read(sessionProvider.future);
  await c.read(appartenancesProvider.future);
  return c.read(echangesControllerProvider.future);
}

void main() {
  test('la première lecture rend la liste de la caserne', () async {
    final depot = FauxEchangesRepository(echanges: <Echange>[echange()]);
    final etat = await _lu(_conteneur(depot));
    expect(etat.echanges, hasLength(1));
    expect(etat.moi, sessionMembre.userId);
    expect(depot.lectures, 1);
  });

  test('un geste relit la liste, réussi ou non', () async {
    final depot = FauxEchangesRepository(echanges: <Echange>[echange()]);
    final c = _conteneur(depot);
    await _lu(c);
    depot.apres = (_, _) => depot.definir(<Echange>[
      echange(statut: StatutEchange.annule, decideLe: DateTime(2026, 10, 4)),
    ]);

    final issue = await c
        .read(echangesControllerProvider.notifier)
        .annuler(echange());
    expect(issue.ok, isTrue);
    expect(depot.lectures, 2);
    expect(
      c.read(echangesControllerProvider).value!.echanges.single.statut,
      StatutEchange.annule,
    );

    depot.prochaineReponse = const ResultatEchange(
      ok: false,
      code: 'exchange_not_open',
      statut: StatutEchange.expire,
    );
    final refus = await c
        .read(echangesControllerProvider.notifier)
        .repondre(echange(), accepte: true);
    expect(refus.ok, isFalse);
    expect(depot.lectures, 3);
  });

  test('une panne de réseau ne relit pas et le dit', () async {
    final depot = FauxEchangesRepository();
    final c = _conteneur(depot);
    await _lu(c);
    depot.prochainePanne = ErreurEchange.reseau;
    final issue = await c
        .read(echangesControllerProvider.notifier)
        .annuler(echange());
    expect(issue.ok, isFalse);
    expect(issue.message, ErreurEchange.reseau.message);
    expect(depot.lectures, 1);
  });

  test('rien n\'est publié sous un geste en vol', () async {
    final depot = _GesteRetenu(echanges: <Echange>[echange()]);
    final c = _conteneur(depot);
    await _lu(c);

    final geste = c
        .read(echangesControllerProvider.notifier)
        .annuler(echange());
    await Future<void>.delayed(Duration.zero);
    expect(
      c.read(echangesControllerProvider.notifier).ecritureEnAttente,
      isTrue,
    );
    final relecture = await c
        .read(echangesControllerProvider.notifier)
        .rafraichir();
    expect(relecture, Relecture.retenue);

    depot.retour.complete();
    await geste;
    expect(
      c.read(echangesControllerProvider.notifier).ecritureEnAttente,
      isFalse,
    );
  });

  test('le coordinateur relit Donnee.echanges sur un événement', () async {
    final depot = FauxEchangesRepository();
    final c = _conteneur(depot);
    await _lu(c);
    expect(depot.lectures, 1);

    depot.definir(<Echange>[echange()]);
    await c.read(fraicheurProvider).maintenant(const <Donnee>{Donnee.echanges});
    expect(depot.lectures, 2);
    expect(c.read(echangesRecusProvider), isEmpty);
    expect(c.read(echangesControllerProvider).value!.echanges, hasLength(1));
  });

  test('une validation relit « Mes astreintes »', () async {
    final depot = FauxEchangesRepository(echanges: <Echange>[echange()]);
    final astreintes = FauxAstreintesRepository();
    final c = _conteneur(depot, astreintes: astreintes);
    c.listen(astreintesControllerProvider, (_, _) {});
    await _lu(c);
    await c.read(astreintesControllerProvider.future);
    final avant = astreintes.lectures;

    depot.prochaineReponse = const ResultatEchange(
      ok: true,
      statut: StatutEchange.valide,
      autoValide: true,
    );
    await c
        .read(echangesControllerProvider.notifier)
        .repondre(echange(), accepte: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(astreintes.lectures, greaterThan(avant));
  });
}
