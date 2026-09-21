import 'package:astreinte_sp/core/caserne/etat_caserne.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/domain/membres_providers.dart';
import 'package:astreinte_sp/features/superadmin/data/superadmin_repository.dart';
import 'package:astreinte_sp/features/superadmin/domain/caserne_supervisee.dart';
import 'package:astreinte_sp/features/superadmin/domain/superadmin_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_invitations.dart';
import '../../support/faux_superadmin.dart';

/// Un conteneur avec les deux dépôts du contrôleur et **le droit déjà acquis** :
/// le provider de droit passe par la session, qui n'existe pas hors widget.
ProviderContainer _conteneur({
  required FauxSuperAdminRepository editeur,
  FauxMembresRepository? membres,
  bool autorise = true,
}) {
  final conteneur = ProviderContainer(
    // Le type `Override` de Riverpod 3 n'est pas exporté : la liste reste nue,
    // comme dans `test/support/faux_auth.dart`.
    overrides: [
      superAdminRepositoryProvider.overrideWithValue(editeur),
      membresRepositoryProvider.overrideWithValue(
        membres ?? FauxMembresRepository(),
      ),
      estSuperAdminProvider.overrideWith((ref) async => autorise),
    ],
  );
  addTearDown(conteneur.dispose);
  return conteneur;
}

Future<VueSuperAdmin> _vue(ProviderContainer conteneur) =>
    conteneur.read(superAdminControllerProvider.future);

void main() {
  group('SuperAdminController', () {
    test('sans le droit, aucune liste n\'est demandée au serveur', () async {
      final editeur = FauxSuperAdminRepository(autorise: false);
      final conteneur = _conteneur(editeur: editeur, autorise: false);

      final vue = await _vue(conteneur);

      expect(vue.casernes, isEmpty);
      expect(editeur.lectures, 0);
    });

    test('avec le droit, la liste arrive', () async {
      final editeur = FauxSuperAdminRepository();
      final conteneur = _conteneur(editeur: editeur);

      final vue = await _vue(conteneur);

      expect(vue.casernes, hasLength(2));
      expect(editeur.lectures, 1);
    });

    test('la caserne créée prend sa place dans la liste triée', () async {
      final editeur = FauxSuperAdminRepository();
      final conteneur = _conteneur(editeur: editeur);
      await _vue(conteneur);

      final creee = await conteneur
          .read(superAdminControllerProvider.notifier)
          .creerCaserne(nom: 'CIS Aubépine', fuseau: 'Europe/Paris');

      expect(creee, isNotNull);
      final noms = conteneur
          .read(superAdminControllerProvider)
          .requireValue
          .casernes
          .map((CaserneSupervisee c) => c.nom)
          .toList();
      expect(noms.first, 'CIS Aubépine');
      expect(noms, hasLength(3));
    });

    test('une création refusée laisse sa raison lisible', () async {
      final editeur = FauxSuperAdminRepository(
        echecCreation: ErreurSuperAdmin.fuseau,
      );
      final conteneur = _conteneur(editeur: editeur);
      await _vue(conteneur);

      final creee = await conteneur
          .read(superAdminControllerProvider.notifier)
          .creerCaserne(nom: 'CIS Ailleurs', fuseau: 'Mars/Olympus');

      expect(creee, isNull);
      final vue = conteneur.read(superAdminControllerProvider).requireValue;
      expect(vue.echec, AppStrings.superAdminRefusFuseau);
      expect(vue.actionEnCours, isNull);
    });

    // Le point du ticket : l'invitation emprunte le chemin du 006, avec le rôle
    // `admin`, et vise la caserne demandée — pas celle de l'appelant, qui n'en
    // a aucune.
    test('l\'invitation passe par MembresRepository, en rôle admin', () async {
      final membres = FauxMembresRepository();
      final conteneur = _conteneur(
        editeur: FauxSuperAdminRepository(),
        membres: membres,
      );
      await _vue(conteneur);

      final resultat = await conteneur
          .read(superAdminControllerProvider.notifier)
          .inviterAdministrateur(
            stationId: caserneSansAdmin.id,
            email: 'chef@cis-neuve.test',
          );

      expect(resultat.reussi, isTrue);
      expect(membres.rolesEnvoyes, <RoleMembre>[RoleMembre.admin]);
      expect(membres.casernesInvitees, <String>[caserneSansAdmin.id]);
    });

    test('une invitation refusée rend le message du serveur', () async {
      final membres = FauxMembresRepository()
        ..echecInvitation = const EchecInvitation(ErreurInvitation.caserneSuspendue);
      final conteneur = _conteneur(
        editeur: FauxSuperAdminRepository(),
        membres: membres,
      );
      await _vue(conteneur);

      final resultat = await conteneur
          .read(superAdminControllerProvider.notifier)
          .inviterAdministrateur(
            stationId: caserneSansAdmin.id,
            email: 'chef@cis-neuve.test',
          );

      expect(resultat.reussi, isFalse);
      expect(resultat.message, AppStrings.inviteCaserneSuspendue);
    });

    test('la suspension relit la liste et annonce le nom', () async {
      final editeur = FauxSuperAdminRepository();
      final conteneur = _conteneur(editeur: editeur);
      await _vue(conteneur);

      final resultat = await conteneur
          .read(superAdminControllerProvider.notifier)
          .definirSuspension(
            stationId: caserneA.id,
            suspendue: true,
            raison: 'Impayé constaté hors Stripe',
          );

      expect(resultat.reussi, isTrue);
      expect(resultat.message, contains(caserneA.nom));
      expect(editeur.lectures, 2);

      final ligne = conteneur
          .read(superAdminControllerProvider)
          .requireValue
          .casernes
          .firstWhere((CaserneSupervisee c) => c.id == caserneA.id);
      expect(ligne.statut, StatutAbonnement.suspendu);
      expect(ligne.ecriture, isFalse);
    });

    test('la consultation de support porte toujours sa raison', () async {
      final editeur = FauxSuperAdminRepository(
        plannings_: <PlanningSupervise>[planningSupport],
      );
      final conteneur = _conteneur(editeur: editeur);
      await _vue(conteneur);

      final plannings = await conteneur
          .read(superAdminControllerProvider.notifier)
          .consulterPlannings(
            stationId: caserneA.id,
            raison: 'Ticket support 42 : le planning ne se valide pas',
          );

      expect(plannings, hasLength(1));
      expect(editeur.consultations, hasLength(1));
      expect(
        editeur.consultations.single.raison,
        'Ticket support 42 : le planning ne se valide pas',
      );
    });

    test('une consultation refusée ne rend aucun planning', () async {
      final editeur = FauxSuperAdminRepository(
        echecSupport: ErreurSuperAdmin.raison,
      );
      final conteneur = _conteneur(editeur: editeur);
      await _vue(conteneur);

      final plannings = await conteneur
          .read(superAdminControllerProvider.notifier)
          .consulterPlannings(stationId: caserneA.id, raison: 'court');

      expect(plannings, isNull);
      expect(
        conteneur.read(superAdminControllerProvider).requireValue.echec,
        AppStrings.superAdminRefusRaison,
      );
    });

    test('deux gestes ne se chevauchent pas sur une même ligne', () async {
      final editeur = FauxSuperAdminRepository();
      final conteneur = _conteneur(editeur: editeur);
      final vue = await _vue(conteneur);

      expect(vue.enCours(caserneA.id), isFalse);
      expect(vue.actionEnCours, isNull);
    });
  });
}
