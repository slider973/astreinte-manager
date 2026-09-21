import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/ouverture_externe.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/features/abonnement/data/abonnement_repository.dart';
import 'package:astreinte_sp/features/abonnement/domain/abonnement.dart';
import 'package:astreinte_sp/features/abonnement/domain/abonnement_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_abonnement.dart';
import '../../support/faux_invitations.dart';

/// Un conteneur minimal : le contrôleur seul, sans écran ni routeur.
ProviderContainer _conteneur({
  required FauxAbonnementRepository depot,
  FauxOuvertureExterne? ouverture,
  Appartenance appartenance = appartenanceAdmin,
}) {
  final conteneur = ProviderContainer(
    overrides: [
      abonnementRepositoryProvider.overrideWithValue(depot),
      ouvertureExterneProvider.overrideWithValue(
        (ouverture ?? FauxOuvertureExterne()).call,
      ),
      appartenanceCouranteProvider.overrideWithValue(appartenance),
      horlogeAbonnementProvider.overrideWithValue(() => maintenantTest),
    ],
  );
  addTearDown(conteneur.dispose);
  return conteneur;
}

void main() {
  group('retourPaiement', () {
    test('ne reconnaît que les deux valeurs du contrat', () {
      expect(retourPaiement('ok'), RetourPaiement.reussi);
      expect(retourPaiement('annule'), RetourPaiement.annule);
    });

    test('tout le reste vaut « pas de retour »', () {
      // Le paramètre vient du dehors : il n'a aucune autorité et ne fait que
      // demander une relecture.
      for (final valeur in <String?>[null, '', 'true', 'OK', 'suspended']) {
        expect(retourPaiement(valeur), isNull, reason: 'valeur : $valeur');
      }
    });
  });

  group('AbonnementController', () {
    test('un membre ordinaire n\'a aucun état d\'abonnement', () async {
      final depot = FauxAbonnementRepository();
      final conteneur = _conteneur(
        depot: depot,
        appartenance: appartenanceMembreSeed,
      );

      expect(await conteneur.read(abonnementControllerProvider.future), isNull);
      expect(depot.lectures, 0);
    });

    test('lit l\'état une fois à l\'ouverture', () async {
      final depot = FauxAbonnementRepository(etat: etatActif);
      final conteneur = _conteneur(depot: depot);

      final vue = await conteneur.read(abonnementControllerProvider.future);

      expect(vue?.etat.abonnement.statut, StatutAbonnement.actif);
      expect(depot.lectures, 1);
    });

    test('souscrire envoie la formule et ouvre l\'adresse rendue', () async {
      final depot = FauxAbonnementRepository(etat: etatEssaiConfigure);
      final ouverture = FauxOuvertureExterne();
      final conteneur = _conteneur(depot: depot, ouverture: ouverture);
      await conteneur.read(abonnementControllerProvider.future);

      final resultat = await conteneur
          .read(abonnementControllerProvider.notifier)
          .souscrire(FormuleAbonnement.annuelle);

      expect(resultat.reussi, isTrue);
      expect(depot.souscriptions, <FormuleAbonnement>[
        FormuleAbonnement.annuelle,
      ]);
      expect(ouverture.adresses.single, depot.adresse);
      // Le bouton revient au repos : sa largeur ne doit pas rester figée sur un
      // indicateur qui tourne pour rien.
      expect(
        conteneur.read(abonnementControllerProvider).value?.enCours,
        isFalse,
      );
    });

    test('un onglet bloqué est un échec annoncé, pas un silence', () async {
      final depot = FauxAbonnementRepository(etat: etatEssaiConfigure);
      final conteneur = _conteneur(
        depot: depot,
        ouverture: FauxOuvertureExterne(autorise: false),
      );
      await conteneur.read(abonnementControllerProvider.future);

      final resultat = await conteneur
          .read(abonnementControllerProvider.notifier)
          .souscrire(FormuleAbonnement.mensuelle);

      expect(resultat.reussi, isFalse);
      expect(resultat.message, AppStrings.abonnementOngletBloque);
      expect(
        conteneur.read(abonnementControllerProvider).value?.echec,
        AppStrings.abonnementOngletBloque,
      );
    });

    test('un refus du serveur garde sa phrase française', () async {
      final depot = FauxAbonnementRepository(
        etat: etatSansStripe,
        erreurAction: ErreurAbonnement.nonConfigure,
      );
      final conteneur = _conteneur(depot: depot);
      await conteneur.read(abonnementControllerProvider.future);

      final resultat = await conteneur
          .read(abonnementControllerProvider.notifier)
          .souscrire(FormuleAbonnement.mensuelle);

      expect(resultat.reussi, isFalse);
      expect(resultat.message, AppStrings.abonnementNonConfigureTexte);
    });

    test('gérer ouvre le portail', () async {
      final depot = FauxAbonnementRepository(etat: etatActif);
      final ouverture = FauxOuvertureExterne();
      final conteneur = _conteneur(depot: depot, ouverture: ouverture);
      await conteneur.read(abonnementControllerProvider.future);

      final resultat = await conteneur
          .read(abonnementControllerProvider.notifier)
          .gerer();

      expect(resultat.reussi, isTrue);
      expect(depot.portails, 1);
      expect(ouverture.adresses, hasLength(1));
    });

    test('un retour annulé ne relit rien et n\'affiche rien', () async {
      final depot = FauxAbonnementRepository(etat: etatEssaiConfigure);
      final conteneur = _conteneur(depot: depot);
      await conteneur.read(abonnementControllerProvider.future);

      await conteneur
          .read(abonnementControllerProvider.notifier)
          .prendreEnCompteRetour(RetourPaiement.annule);

      // Une seule lecture : celle de l'ouverture. Quelqu'un a regardé le prix
      // et fermé l'onglet ; il n'y a rien à vérifier.
      expect(depot.lectures, 1);
      final vue = conteneur.read(abonnementControllerProvider).value;
      expect(vue?.retour, RetourPaiement.annule);
      expect(vue?.statutEnAttente, isFalse);
    });

    test('un retour réussi relit, et **ne croit pas le paramètre**', () async {
      final depot = FauxAbonnementRepository(etat: etatEssaiConfigure);
      final conteneur = _conteneur(depot: depot);
      await conteneur.read(abonnementControllerProvider.future);

      await conteneur
          .read(abonnementControllerProvider.notifier)
          .prendreEnCompteRetour(RetourPaiement.reussi);

      expect(depot.lectures, 2);
      final vue = conteneur.read(abonnementControllerProvider).value;
      // La base dit encore « essai » : le webhook n'est pas passé. L'état
      // affiché reste celui de la base, et l'écran annonce l'attente.
      expect(vue?.etat.abonnement.statut, StatutAbonnement.essai);
      expect(vue?.statutEnAttente, isTrue);
    });

    test('quand le webhook est déjà passé, rien n\'attend', () async {
      final depot = FauxAbonnementRepository(etat: etatActif);
      final conteneur = _conteneur(depot: depot);
      await conteneur.read(abonnementControllerProvider.future);

      await conteneur
          .read(abonnementControllerProvider.notifier)
          .prendreEnCompteRetour(RetourPaiement.reussi);

      final vue = conteneur.read(abonnementControllerProvider).value;
      expect(vue?.statutEnAttente, isFalse);
      expect(vue?.retour, RetourPaiement.reussi);
    });

    test('relire jette le refus précédent', () async {
      final depot = FauxAbonnementRepository(
        etat: etatEssaiConfigure,
        erreurAction: ErreurAbonnement.prestataire,
      );
      final conteneur = _conteneur(depot: depot);
      await conteneur.read(abonnementControllerProvider.future);

      await conteneur
          .read(abonnementControllerProvider.notifier)
          .souscrire(FormuleAbonnement.mensuelle);
      expect(
        conteneur.read(abonnementControllerProvider).value?.echec,
        isNotNull,
      );

      await conteneur.read(abonnementControllerProvider.notifier).relire();

      expect(conteneur.read(abonnementControllerProvider).value?.echec, isNull);
    });

    test('une lecture en échec remonte son échec traduit', () async {
      final depot = FauxAbonnementRepository(
        erreurLecture: ErreurAbonnement.inconnue,
      );
      final conteneur = _conteneur(depot: depot);

      // Le contrôleur est auto-disposé : sans abonné, il disparaît avant même
      // d'avoir pu émettre son échec.
      final abonne = conteneur.listen(
        abonnementControllerProvider,
        (_, _) {},
        onError: (Object _, StackTrace _) {},
      );
      addTearDown(abonne.close);

      // Laisse la lecture aboutir : elle passe par plusieurs micro-tâches.
      for (var tour = 0; tour < 5; tour++) {
        await Future<void>.delayed(Duration.zero);
      }

      final etat = conteneur.read(abonnementControllerProvider);
      expect(etat.hasError, isTrue);
      // La phrase française du dépôt survit jusqu'au provider : l'écran n'a
      // rien à retraduire.
      expect(etat.error, isA<EchecAbonnement>());
      expect(
        (etat.error! as EchecAbonnement).message,
        AppStrings.abonnementEchecGenerique,
      );
    });
  });
}

/// L'appartenance d'un membre ordinaire de la caserne du seed.
const Appartenance appartenanceMembreSeed = Appartenance(
  id: 'm-1',
  stationId: stationTest,
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.membre,
  statut: StatutMembre.actif,
);
