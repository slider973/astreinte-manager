import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/session/session_utilisateur.dart';
import 'package:astreinte_sp/features/boite/domain/composition_boite.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/features/notifications/domain/centre_providers.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/domain/propositions_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_notifications.dart';
import '../../support/faux_propositions.dart';

void main() {
  group('L\'onglet dans l\'URL', () {
    test('chaque onglet a son mot, et le mot le retrouve', () {
      for (final onglet in OngletBoite.values) {
        expect(OngletBoite.depuisUrl(onglet.valeurUrl), onglet);
      }
    });

    test('un mot inconnu, absent ou vide tombe sur « Tout »', () {
      // « Tout » contient les deux autres : personne n'arrive sur une page qui
      // ne montre pas ce qu'il cherchait.
      expect(OngletBoite.depuisUrl(null), OngletBoite.tout);
      expect(OngletBoite.depuisUrl(''), OngletBoite.tout);
      expect(OngletBoite.depuisUrl('1'), OngletBoite.tout);
      expect(OngletBoite.depuisUrl('rappel'), OngletBoite.tout);
    });

    test('les mots sont des mots, jamais des numéros', () {
      // `?onglet=1` ne dit rien à qui relit son historique : c'est la leçon
      // d'`ongletHerite`, et elle ne se reprend pas.
      for (final onglet in OngletBoite.values) {
        expect(int.tryParse(onglet.valeurUrl), isNull);
      }
    });
  });

  group('« Tout » fusionne les deux sources', () {
    test('par date décroissante, la plus récente en premier', () {
      final elements = fusionner(
        propositions: <Proposition>[
          proposition(
            id: 'p-vieille',
            jour: DateTime(2026, 11, 3),
            proposeeLe: DateTime(2026, 9, 18, 8),
          ),
          proposition(
            id: 'p-fraiche',
            jour: DateTime(2026, 10, 12),
            proposeeLe: DateTime(2026, 9, 20, 9),
          ),
        ],
        rappels: <NotificationInterne>[
          notification(id: 'n-milieu', creeLe: DateTime(2026, 9, 19)),
        ],
      );

      expect(
        elements.map((ElementBoite e) => e.cle).toList(),
        <String>['p-fraiche', 'n-milieu', 'p-vieille'],
      );
    });

    test('une proposition est classée par sa date de proposition', () {
      // Pas par le jour du créneau : la Boîte est un journal d'arrivée, et une
      // proposition reçue ce matin pour mars se lit au-dessus d'un rappel
      // d'hier.
      final elements = fusionner(
        propositions: <Proposition>[
          proposition(
            id: 'p-mars',
            jour: DateTime(2027, 3, 4),
            proposeeLe: DateTime(2026, 9, 20, 9),
          ),
        ],
        rappels: <NotificationInterne>[
          notification(id: 'n-hier', creeLe: DateTime(2026, 9, 19)),
        ],
      );

      expect(elements.first.cle, 'p-mars');
    });

    test('à égalité d\'instant, la question passe devant le fait', () {
      final instant = DateTime(2026, 9, 20, 9);
      final elements = fusionner(
        propositions: <Proposition>[
          proposition(
            id: 'p',
            jour: DateTime(2026, 10, 12),
            proposeeLe: instant,
          ),
        ],
        rappels: <NotificationInterne>[
          notification(id: 'n', creeLe: instant),
        ],
      );

      expect(elements.map((ElementBoite e) => e.cle).toList(), <String>[
        'p',
        'n',
      ]);
    });
  });

  group('Les rappels ne sont pas les propositions', () {
    test('l\'astreinte proposée et sa relance n\'y sont pas', () {
      // Les deux posent la même question que la ligne de proposition, qui,
      // elle, porte la réponse.
      for (final type in <TypeNotification>[
        TypeNotification.astreinteProposee,
        TypeNotification.rappelReponse,
      ]) {
        expect(notification(id: 'n', type: type).estRappel, isFalse);
      }
    });

    test('la réattribution en est un, bien qu\'elle mène aux propositions', () {
      // `assignment_changed` porte le lien `/proposals`
      // (`supabase/functions/README.md § Liens profonds`) : la règle porte sur
      // le **type**, jamais sur la route, sinon une réattribution
      // disparaîtrait du journal.
      for (final type in <TypeNotification>[
        TypeNotification.creneauModifie,
        TypeNotification.creneauAnnule,
      ]) {
        expect(
          notification(id: 'n', type: type).estRappel,
          isTrue,
          reason: type.name,
        );
      }
    });

    test('tous les autres types en sont', () {
      for (final type in TypeNotification.values) {
        if (type.estProposition) continue;
        expect(
          notification(id: 'n', type: type).estRappel,
          isTrue,
          reason: type.name,
        );
      }
    });

    test('le compte de non-lues ne compte que les rappels', () {
      final centre = EtatCentre(
        notifications: <NotificationInterne>[
          notification(id: 'n-1'),
          notification(
            id: 'n-2',
            type: TypeNotification.astreinteProposee,
          ),
          notification(
            id: 'n-3',
            lueLe: DateTime(2026, 9, 20, 12),
          ),
        ],
      );

      // Deux non-lues en base, une seule que la Boîte montre : la pastille ne
      // peut pas rester bloquée sur une ligne qu'aucun écran n'affiche.
      expect(centre.nonLues, 1);
      expect(centre.rappels, hasLength(2));
    });
  });

  group('Une source en panne n\'efface jamais l\'autre', () {
    EtatBoite composer({
      required AsyncValue<EtatPropositions> propositions,
      required AsyncValue<EtatCentre> centre,
    }) => etatBoiteDe(propositions: propositions, centre: centre);

    final unePropositon = EtatPropositions(
      propositions: <Proposition>[
        proposition(id: 'p-1', jour: DateTime(2026, 10, 12)),
      ],
    );
    final unRappel = EtatCentre(
      notifications: <NotificationInterne>[notification(id: 'n-1')],
    );

    test('les deux en chargement : deux squelettes, aucun échec', () {
      final etat = composer(
        propositions: const AsyncValue<EtatPropositions>.loading(),
        centre: const AsyncValue<EtatCentre>.loading(),
      );

      expect(etat.chargePropositions, isTrue);
      expect(etat.chargeRappels, isTrue);
      expect(etat.echecPropositions, isFalse);
      expect(etat.echecRappels, isFalse);
    });

    test('les propositions tombent, les rappels restent', () {
      final etat = composer(
        propositions: AsyncValue<EtatPropositions>.error(
          const FormatException('réseau'),
          StackTrace.current,
        ),
        centre: AsyncValue<EtatCentre>.data(unRappel),
      );

      expect(etat.echecPropositions, isTrue);
      expect(etat.echecRappels, isFalse);
      expect(etat.rappels, hasLength(1));
      expect(etat.tout, hasLength(1));
    });

    test('les rappels tombent, les propositions restent', () {
      final etat = composer(
        propositions: AsyncValue<EtatPropositions>.data(unePropositon),
        centre: AsyncValue<EtatCentre>.error(
          const FormatException('réseau'),
          StackTrace.current,
        ),
      );

      expect(etat.echecRappels, isTrue);
      expect(etat.echecPropositions, isFalse);
      expect(etat.propositions, hasLength(1));
      expect(etat.tout, hasLength(1));
    });

    test('une source sans contenu et sans erreur n\'est pas un échec', () {
      // Les deux contrôleurs rendent un état **vide** avant même d'avoir lu,
      // quand la session ou l'appartenance manque. Ce n'est pas une panne.
      final etat = composer(
        propositions: const AsyncValue<EtatPropositions>.data(
          EtatPropositions(),
        ),
        centre: const AsyncValue<EtatCentre>.data(EtatCentre()),
      );

      expect(etat.echecPropositions, isFalse);
      expect(etat.echecRappels, isFalse);
      expect(etat.chargePropositions, isFalse);
      expect(etat.toutVide, isTrue);
    });
  });

  group('Une relecture en panne n\'efface pas ce qui était juste', () {
    /// Un centre branché sur [depot], lu une fois avec succès.
    ///
    /// Le vrai contrôleur, et non un `AsyncValue` bricolé : c'est lui qui
    /// produit le cas — `AsyncValue.guard` rend une erreur, et Riverpod lui
    /// rattache la valeur précédente. L'API qui compose ce couple à la main
    /// est interne au paquet.
    Future<ProviderContainer> centreLu(
      FauxNotificationsRepository depot,
    ) async {
      final conteneur = ProviderContainer(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(depot),
          sessionProvider.overrideWith(
            (ref) => Stream<SessionUtilisateur?>.value(
              const SessionUtilisateur(userId: 'u-1', email: 'u@test'),
            ),
          ),
        ],
      );
      addTearDown(conteneur.dispose);

      // La session arrive par un flux : le contrôleur ne lit rien tant qu'elle
      // n'est pas là, et l'éprouver avant serait éprouver le vide.
      conteneur.listen(sessionProvider, (_, _) {});
      await conteneur.read(sessionProvider.future);
      conteneur.listen(centreNotificationsProvider, (_, _) {});
      await conteneur.read(centreNotificationsProvider.future);
      expect(depot.lectures, 1);
      return conteneur;
    }

    test(
      'un centre qui n\'a que des propositions et qui tombe est en échec',
      () async {
        // **L'échec se mesure sur la liste affichée**, pas sur la lecture
        // brute. Une dernière lecture réussie qui ne portait que des
        // `assignment_proposed` ne donne aucun rappel : mesuré sur
        // `notifications`, l'onglet aurait dit « Aucun rappel » alors que la
        // relecture venait d'échouer.
        final depot = FauxNotificationsRepository(
          notifications: <NotificationInterne>[
            notification(
              id: 'n-proposee',
              type: TypeNotification.astreinteProposee,
            ),
          ],
        );
        final conteneur = await centreLu(depot);

        depot.erreurLecture = true;
        await conteneur
            .read(centreNotificationsProvider.notifier)
            .rafraichir();

        final apres = conteneur.read(centreNotificationsProvider);
        expect(apres.hasError, isTrue);
        expect(
          apres.value?.notifications,
          hasLength(1),
          reason: 'la lecture précédente est toujours là',
        );

        final etat = etatBoiteDe(
          propositions: const AsyncValue<EtatPropositions>.data(
            EtatPropositions(),
          ),
          centre: apres,
        );
        expect(etat.rappels, isEmpty);
        expect(etat.echecRappels, isTrue);
      },
    );

    test('le centre garde sa liste, et la Boîte ne se croit pas vide', () async {
      // **Le piège du 064a, sous un autre visage**, éprouvé sur le vrai
      // contrôleur : `AsyncValue.guard` rend une erreur, et Riverpod lui
      // rattache la valeur précédente. Tester `hasError` seul — ou passer par
      // un `whenData` — effacerait une liste parfaitement juste.
      final depot = FauxNotificationsRepository(
        notifications: <NotificationInterne>[notification(id: 'n-1')],
      );
      final conteneur = await centreLu(depot);

      depot.erreurLecture = true;
      await conteneur.read(centreNotificationsProvider.notifier).rafraichir();

      final apres = conteneur.read(centreNotificationsProvider);
      expect(apres.hasError, isTrue);
      expect(
        apres.value,
        isNotNull,
        reason: 'Riverpod rattache la valeur précédente à l\'erreur',
      );

      final etat = etatBoiteDe(
        propositions: const AsyncValue<EtatPropositions>.data(
          EtatPropositions(),
        ),
        centre: apres,
      );
      // La liste est là, donc ce n'est pas un échec de section : l'onglet
      // « Rappels » garde ce qui était juste au lieu de se croire vide.
      expect(etat.echecRappels, isFalse);
      expect(etat.rappels, hasLength(1));
    });
  });
}
