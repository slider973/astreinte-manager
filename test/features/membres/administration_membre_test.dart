import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/membres/domain/administration_membre.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';
import 'package:astreinte_sp/features/membres/domain/membres_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_invitations.dart';

const MembreCaserne _autreAdmin = MembreCaserne(
  id: 'm-2',
  userId: 'u-2',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
  prenom: 'Camille',
  nom: 'Girard',
  email: 'membre3@caserne-a.test',
);

const MembreCaserne _adminDesactive = MembreCaserne(
  id: 'm-3',
  userId: 'u-3',
  role: RoleMembre.admin,
  statut: StatutMembre.desactive,
  prenom: 'Lucas',
  nom: 'Bernard',
  email: 'membre4@caserne-a.test',
);

const ContexteAdministration _seulAdmin = ContexteAdministration(
  adminsActifs: 1,
  userIdCourant: 'u-0',
);

const ContexteAdministration _deuxAdmins = ContexteAdministration(
  adminsActifs: 2,
  userIdCourant: 'u-0',
);

void main() {
  group('Garde-fous', () {
    test('le dernier admin actif ne peut être ni rétrogradé ni désactivé', () {
      for (final action in <ActionMembre>[
        ActionMembre.retrograder,
        ActionMembre.desactiver,
      ]) {
        expect(
          refusPour(
            action: action,
            membre: membreJean,
            contexte: _seulAdmin,
          ),
          RefusAdministration.dernierAdmin,
          reason: action.libelle,
        );
      }
    });

    test('un admin ne se retire pas lui-même, même à plusieurs', () {
      expect(
        refusPour(
          action: ActionMembre.retrograder,
          membre: membreJean,
          contexte: _deuxAdmins,
        ),
        RefusAdministration.soiMeme,
      );
      expect(
        refusPour(
          action: ActionMembre.desactiver,
          membre: membreJean,
          contexte: _deuxAdmins,
        ),
        RefusAdministration.soiMeme,
      );
    });

    test('« dernier admin » gagne sur « soi-même » : c\'est la phrase utile', () {
      expect(
        refusPour(
          action: ActionMembre.retrograder,
          membre: membreJean,
          contexte: _seulAdmin,
        ),
        RefusAdministration.dernierAdmin,
      );
    });

    test('un autre admin actif se rétrograde tant qu\'il en reste un', () {
      expect(
        refusPour(
          action: ActionMembre.retrograder,
          membre: _autreAdmin,
          contexte: _deuxAdmins,
        ),
        isNull,
      );
    });

    test('renommer et promouvoir ne sont jamais refusés', () {
      for (final action in <ActionMembre>[
        ActionMembre.renommer,
        ActionMembre.promouvoir,
        ActionMembre.reactiver,
      ]) {
        expect(
          refusPour(action: action, membre: membreJean, contexte: _seulAdmin),
          isNull,
          reason: action.libelle,
        );
      }
    });

    test('un admin déjà désactivé ne compte pas dans le quorum', () {
      expect(
        refusPour(
          action: ActionMembre.retrograder,
          membre: _adminDesactive,
          contexte: _seulAdmin,
        ),
        isNull,
      );
    });
  });

  group('Actions proposées', () {
    test('un membre actif : renommer, promouvoir, désactiver', () {
      expect(actionsPour(membreMarie), <ActionMembre>[
        ActionMembre.renommer,
        ActionMembre.promouvoir,
        ActionMembre.desactiver,
      ]);
    });

    test('un admin actif : renommer, rétrograder, désactiver', () {
      expect(actionsPour(membreJean), <ActionMembre>[
        ActionMembre.renommer,
        ActionMembre.retrograder,
        ActionMembre.desactiver,
      ]);
    });

    test('on ne propose pas de réactiver quelqu\'un qui est déjà là', () {
      expect(actionsPour(_adminDesactive), contains(ActionMembre.reactiver));
      expect(
        actionsPour(_adminDesactive),
        isNot(contains(ActionMembre.desactiver)),
      );
    });
  });

  group('Recherche', () {
    const emilie = MembreCaserne(
      id: 'm-4',
      userId: 'u-4',
      role: RoleMembre.membre,
      statut: StatutMembre.actif,
      prenom: 'Émilie',
      nom: 'Roux',
      email: 'membre5@caserne-a.test',
      nomAffiche: 'Mimi',
    );

    EtatMembres etat() => const EtatMembres(
      membres: <MembreCaserne>[membreJean, membreMarie, emilie],
    );

    test('sans accent ni casse', () {
      expect(etat().filtres('EMILIE'), <MembreCaserne>[emilie]);
      expect(etat().filtres('émilie'), <MembreCaserne>[emilie]);
      expect(etat().filtres('roux'), <MembreCaserne>[emilie]);
    });

    test('sur le nom affiché et sur l\'adresse', () {
      expect(etat().filtres('mimi'), <MembreCaserne>[emilie]);
      expect(etat().filtres('membre1@'), <MembreCaserne>[membreMarie]);
    });

    test('une recherche vide rend toute la caserne', () {
      expect(etat().filtres('   '), hasLength(3));
    });

    test('une recherche sans résultat rend une liste vide', () {
      expect(etat().filtres('durand'), isEmpty);
    });
  });

  group('Comptes', () {
    test('actifs, désactivés et admins actifs', () {
      const etat = EtatMembres(
        membres: <MembreCaserne>[
          membreJean,
          membreMarie,
          _autreAdmin,
          _adminDesactive,
        ],
      );

      expect(etat.actifs, 3);
      expect(etat.desactives, 1);
      // L'admin désactivé ne compte pas : c'est exactement ce que compte le
      // déclencheur `memberships_guard_admin`.
      expect(etat.adminsActifs, 2);
    });
  });
}
