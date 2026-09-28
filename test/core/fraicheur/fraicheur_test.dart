// Ticket 070 — les briques du coordinateur des relectures, sans écran.

import 'dart:async';

import 'package:astreinte_sp/core/caserne/caserne_providers.dart';
import 'package:astreinte_sp/core/fraicheur/fraicheur.dart';
import 'package:astreinte_sp/core/fraicheur/relecture.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/appartenances_locales.dart';
import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/session/session_utilisateur.dart';
import 'package:astreinte_sp/features/dispos/presentation/controllers/saisie_controller.dart';
import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/domain/propositions_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_caserne.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_propositions.dart';

/// Une réponse que le test laisse en vol aussi longtemps qu'il le veut.
class _ReponseRetenue extends FauxPropositionsRepository {
  _ReponseRetenue({super.propositions});

  final Completer<void> retour = Completer<void>();

  @override
  Future<ResultatReponse> repondre({
    required String attributionId,
    required bool accepte,
    String? motif,
  }) async {
    await retour.future;
    return super.repondre(
      attributionId: attributionId,
      accepte: accepte,
      motif: motif,
    );
  }
}

/// Une liste dont la première lecture ne répond jamais : le trou noir du
/// réseau rural.
class _ListeMuette extends FauxPropositionsRepository {
  bool muette = true;

  @override
  Future<List<Proposition>> lister({
    required String userId,
    required String stationId,
  }) {
    if (muette) {
      lectures++;
      return Completer<List<Proposition>>().future;
    }
    return super.lister(userId: userId, stationId: stationId);
  }
}

ProviderContainer _conteneur({
  FauxMembershipRepository? memberships,
  FauxCaserneRepository? caserne,
  FauxPropositionsRepository? propositions,
  DateTime Function()? horloge,
}) {
  final conteneur = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(
        (ref) => Stream<SessionUtilisateur?>.value(sessionMembre),
      ),
      membershipRepositoryProvider.overrideWithValue(
        memberships ??
            FauxMembershipRepository(
              appartenances: const <Appartenance>[appartenanceMembre],
            ),
      ),
      appartenancesLocalesProvider.overrideWithValue(
        AppartenancesLocalesMemoire(),
      ),
      caserneRepositoryProvider.overrideWithValue(
        caserne ?? FauxCaserneRepository(),
      ),
      propositionsRepositoryProvider.overrideWithValue(
        propositions ?? FauxPropositionsRepository(),
      ),
      horlogeRafraichissementProvider.overrideWithValue(
        horloge ?? () => DateTime(2026, 9, 21, 10),
      ),
    ],
  );
  addTearDown(conteneur.dispose);
  conteneur
    ..listen(sessionProvider, (_, _) {})
    ..listen(appartenancesProvider, (_, _) {})
    ..listen(etatCaserneProvider, (_, _) {});
  return conteneur;
}

Future<void> _attendre(ProviderContainer conteneur) async {
  await conteneur.read(sessionProvider.future);
  await conteneur.read(appartenancesProvider.future);
  await conteneur.read(etatCaserneProvider.future);
}

void main() {
  group('L\'état de caserne relu', () {
    test('ne publie que ce qui change', () async {
      final caserne = FauxCaserneRepository();
      final conteneur = _conteneur(caserne: caserne);
      await _attendre(conteneur);
      var publications = 0;
      conteneur.listen(etatCaserneProvider, (_, _) => publications++);

      final inchangee = await conteneur
          .read(etatCaserneProvider.notifier)
          .relire();
      expect(inchangee, Relecture.inchangee);
      expect(publications, 0);

      caserne.etat = caserneSuspendue;
      final publiee = await conteneur
          .read(etatCaserneProvider.notifier)
          .relire();
      expect(publiee, Relecture.publiee);
      expect(conteneur.read(lectureSeuleCaserneProvider), isTrue);
    });

    test('une lecture qui échoue garde l\'état connu', () async {
      final caserne = FauxCaserneRepository(caserneSuspendue);
      final conteneur = _conteneur(caserne: caserne);
      await _attendre(conteneur);

      caserne.injoignable = true;
      final issue = await conteneur.read(etatCaserneProvider.notifier).relire();

      expect(issue, Relecture.echouee);
      expect(conteneur.read(lectureSeuleCaserneProvider), isTrue);
    });

    test('retient la publication quand la condition refuse', () async {
      final caserne = FauxCaserneRepository();
      final conteneur = _conteneur(caserne: caserne);
      await _attendre(conteneur);

      caserne.etat = caserneSuspendue;
      final issue = await conteneur
          .read(etatCaserneProvider.notifier)
          .relire(publierSi: () => false);

      expect(issue, Relecture.retenue);
      expect(conteneur.read(lectureSeuleCaserneProvider), isFalse);
    });

    test(
      'un refus ne dit « suspendue » que si station_access le dit',
      () async {
        final caserne = FauxCaserneRepository();
        final conteneur = _conteneur(caserne: caserne);
        await _attendre(conteneur);
        final notifier = conteneur.read(etatCaserneProvider.notifier);

        expect(await notifier.suspendueApresRefus(), isFalse);
        caserne.etat = caserneSuspendue;
        expect(await notifier.suspendueApresRefus(), isTrue);
      },
    );
  });

  group('Les appartenances relues', () {
    test('un rôle donné en base est publié, sans seconde requête', () async {
      final memberships = FauxMembershipRepository(
        appartenances: const <Appartenance>[appartenanceMembre],
      );
      final conteneur = _conteneur(memberships: memberships);
      await _attendre(conteneur);
      expect(conteneur.read(appartenanceCouranteProvider)?.estAdmin, isFalse);

      memberships.appartenances = const <Appartenance>[
        Appartenance(
          id: 'm-1',
          stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
          nomCaserne: 'CIS Saint-Martin',
          role: RoleMembre.admin,
          statut: StatutMembre.actif,
          nomAffiche: 'Marie L.',
        ),
      ];
      final lecturesAvant = memberships.lectures;
      final ref = conteneur.read(_refProvider);
      final issue = await relireAppartenances(ref);
      await conteneur.read(appartenancesProvider.future);

      expect(issue, Relecture.publiee);
      expect(conteneur.read(appartenanceCouranteProvider)?.estAdmin, isTrue);
      expect(memberships.lectures, lecturesAvant + 1);
    });

    test('une panne de réseau ne change rien', () async {
      final memberships = FauxMembershipRepository(
        appartenances: const <Appartenance>[appartenanceAdmin],
      );
      final conteneur = _conteneur(memberships: memberships);
      await _attendre(conteneur);

      memberships.erreur = AuthErreur.reseau;
      final issue = await relireAppartenances(conteneur.read(_refProvider));

      expect(issue, Relecture.echouee);
      // Toujours admin : un tunnel ne rétrograde pas un rôle confirmé.
      expect(conteneur.read(appartenanceCouranteProvider)?.estAdmin, isTrue);
    });

    test('une liste identique ne republie rien', () async {
      final conteneur = _conteneur();
      await _attendre(conteneur);
      var publications = 0;
      conteneur.listen(appartenanceCouranteProvider, (_, _) => publications++);

      final issue = await relireAppartenances(conteneur.read(_refProvider));

      expect(issue, Relecture.inchangee);
      expect(publications, 0);
    });
  });

  group('Le coordinateur', () {
    test('une relecture des propositions attend la fin d\'une réponse en '
        'vol', () async {
      final depot = _ReponseRetenue(
        propositions: <Proposition>[
          proposition(id: 'a-1', jour: DateTime(2026, 9, 28)),
          proposition(id: 'a-2', creneauId: 'c-2', jour: DateTime(2026, 9, 29)),
        ],
      );
      final conteneur = _conteneur(propositions: depot);
      await _attendre(conteneur);
      conteneur.listen(propositionsControllerProvider, (_, _) {});
      final premiere = await conteneur.read(
        propositionsControllerProvider.future,
      );
      final fraicheur = conteneur.read(fraicheurProvider);

      // La réponse part : la ligne quitte l'écran tout de suite.
      final reponse = conteneur
          .read(propositionsControllerProvider.notifier)
          .repondre(premiere.propositions.first, accepte: true);
      expect(
        conteneur.read(propositionsControllerProvider).value!.propositions,
        hasLength(1),
      );

      // Un événement demande une relecture pendant le vol : elle est
      // retenue, et la ligne retirée ne revient pas.
      await fraicheur.maintenant(const <Donnee>{Donnee.propositions});
      expect(fraicheur.retenue(Donnee.propositions), isTrue);
      expect(
        conteneur.read(propositionsControllerProvider).value!.propositions,
        hasLength(1),
      );

      // La réponse revient : la relecture retenue repart d'elle-même.
      final lecturesAvant = depot.lectures;
      depot.retour.complete();
      await reponse;
      await pumpEventQueue();

      expect(fraicheur.retenue(Donnee.propositions), isFalse);
      expect(depot.lectures, greaterThan(lecturesAvant));
      expect(
        conteneur.read(propositionsControllerProvider).value!.propositions,
        hasLength(1),
      );
    });

    test('la caserne retenue sous une réponse repart à son retour, sans '
        'faire naître la saisie', () async {
      final caserne = FauxCaserneRepository();
      final depot = _ReponseRetenue(
        propositions: <Proposition>[
          proposition(id: 'a-1', jour: DateTime(2026, 9, 28)),
        ],
      );
      final conteneur = _conteneur(caserne: caserne, propositions: depot);
      await _attendre(conteneur);
      conteneur.listen(propositionsControllerProvider, (_, _) {});
      final premiere = await conteneur.read(
        propositionsControllerProvider.future,
      );
      final fraicheur = conteneur.read(fraicheurProvider);

      final reponse = conteneur
          .read(propositionsControllerProvider.notifier)
          .repondre(premiere.propositions.first, accepte: true);
      caserne.etat = caserneSuspendue;
      await fraicheur.maintenant(const <Donnee>{Donnee.caserne});

      // Publier maintenant reconstruirait les propositions sous la réponse.
      expect(fraicheur.retenue(Donnee.caserne), isTrue);
      expect(conteneur.read(lectureSeuleCaserneProvider), isFalse);
      // Un compte qui n'a jamais ouvert son mois n'a pas de saisie : la
      // reprise ne l'écoute pas, donc ne la crée pas.
      expect(conteneur.exists(saisieControllerProvider), isFalse);

      depot.retour.complete();
      await reponse;
      await pumpEventQueue();

      expect(fraicheur.retenue(Donnee.caserne), isFalse);
      expect(conteneur.read(lectureSeuleCaserneProvider), isTrue);
      expect(conteneur.exists(saisieControllerProvider), isFalse);
    });

    test('une première lecture qui ne répond jamais ne bloque pas la '
        'donnée', () async {
      final depot = _ListeMuette();
      final conteneur = _conteneur(propositions: depot);
      await _attendre(conteneur);
      conteneur.listen(propositionsControllerProvider, (_, _) {});
      final fraicheur = conteneur.read(fraicheurProvider)
        ..attentePremiereLecture = const Duration(milliseconds: 50);

      // L'attente rend la main, bornée, au lieu de garder la relecture « en
      // cours » pour toujours.
      await fraicheur
          .auRetour(const <Donnee>{Donnee.propositions})
          .timeout(const Duration(seconds: 2));

      // Le moment suivant ne l'attend plus : il relit vraiment.
      depot.muette = false;
      final lectures = depot.lectures;
      await fraicheur
          .maintenant(const <Donnee>{Donnee.propositions})
          .timeout(const Duration(seconds: 2));
      expect(depot.lectures, lectures + 1);
    });

    test('pas de rafale, sauf pour un événement', () async {
      var maintenant = DateTime(2026, 9, 21, 10);
      final depot = FauxPropositionsRepository();
      final conteneur = _conteneur(
        propositions: depot,
        horloge: () => maintenant,
      );
      await _attendre(conteneur);
      conteneur.listen(propositionsControllerProvider, (_, _) {});
      await conteneur.read(propositionsControllerProvider.future);
      final fraicheur = conteneur.read(fraicheurProvider);
      final lectures = depot.lectures;

      // La première lecture vient d'avoir lieu : l'ouverture ne relit pas.
      await fraicheur.auRetour(const <Donnee>{Donnee.propositions});
      expect(depot.lectures, lectures);

      // Un événement, lui, relit tout de suite.
      await fraicheur.maintenant(const <Donnee>{Donnee.propositions});
      expect(depot.lectures, lectures + 1);

      // Après le délai minimal, un retour relit.
      maintenant = maintenant.add(Fraicheur.intervalleMinimal);
      await fraicheur.auRetour(const <Donnee>{Donnee.propositions});
      expect(depot.lectures, lectures + 2);
    });
  });
}

/// Un `Ref` pour appeler [relireAppartenances] comme le coordinateur le fait.
final Provider<Ref> _refProvider = Provider<Ref>((ref) => ref);
