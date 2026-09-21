import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/router/auth_redirection.dart';
import 'package:astreinte_sp/core/session/etat_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redirectionAuth', () {
    test('en chargement, tout mène à l\'écran de démarrage', () {
      for (final chemin in <String>[
        AppRoutes.accueil,
        AppRoutes.connexion,
        AppRoutes.code,
        AppRoutes.aucuneCaserne,
      ]) {
        expect(
          redirectionAuth(etat: EtatAuth.chargement, chemin: chemin),
          AppRoutes.demarrage,
          reason: 'depuis $chemin',
        );
      }
      expect(
        redirectionAuth(etat: EtatAuth.chargement, chemin: AppRoutes.demarrage),
        isNull,
      );
    });

    test('déconnecté, tout mène à la connexion', () {
      expect(
        redirectionAuth(etat: EtatAuth.deconnecte, chemin: AppRoutes.accueil),
        AppRoutes.connexion,
      );
      expect(
        redirectionAuth(
          etat: EtatAuth.deconnecte,
          chemin: AppRoutes.aucuneCaserne,
        ),
        AppRoutes.connexion,
      );
    });

    test('déconnecté, les deux étapes de connexion restent accessibles', () {
      expect(
        redirectionAuth(etat: EtatAuth.deconnecte, chemin: AppRoutes.connexion),
        isNull,
      );
      expect(
        redirectionAuth(etat: EtatAuth.deconnecte, chemin: AppRoutes.code),
        isNull,
      );
    });

    test('connecté sans caserne, tout mène à l\'écran d\'invitation', () {
      expect(
        redirectionAuth(etat: EtatAuth.sansCaserne, chemin: AppRoutes.accueil),
        AppRoutes.aucuneCaserne,
      );
      expect(
        redirectionAuth(etat: EtatAuth.sansCaserne, chemin: AppRoutes.code),
        AppRoutes.aucuneCaserne,
      );
      expect(
        redirectionAuth(
          etat: EtatAuth.sansCaserne,
          chemin: AppRoutes.aucuneCaserne,
        ),
        isNull,
      );
    });

    test('connecté avec caserne, les écrans d\'avant-connexion renvoient à '
        'l\'accueil', () {
      for (final chemin in <String>[
        AppRoutes.connexion,
        AppRoutes.code,
        AppRoutes.demarrage,
        AppRoutes.aucuneCaserne,
      ]) {
        expect(
          redirectionAuth(etat: EtatAuth.connecte, chemin: chemin),
          AppRoutes.accueil,
          reason: 'depuis $chemin',
        );
      }
    });

    test('connecté avec caserne, l\'accueil ne redirige pas', () {
      expect(
        redirectionAuth(etat: EtatAuth.connecte, chemin: AppRoutes.accueil),
        isNull,
      );
    });

    test('le catalogue de composants reste joignable en développement', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.deconnecte,
          chemin: AppRoutes.devComponents,
          outilsDevAutorises: true,
        ),
        isNull,
      );
      expect(
        redirectionAuth(
          etat: EtatAuth.deconnecte,
          chemin: AppRoutes.devComponents,
        ),
        AppRoutes.connexion,
      );
    });
  });

  group('redirectionAuth et le lien d\'invitation', () {
    const lien = '/invite/a1b2c3';

    test('le lien s\'ouvre dans tous les états, session inconnue comprise', () {
      for (final etat in EtatAuth.values) {
        expect(
          redirectionAuth(etat: etat, chemin: lien),
          isNull,
          reason:
              'Le jeton n\'existe que dans l\'URL : la perdre perd '
              'l\'invitation (état $etat).',
        );
      }
    });

    test('connecté sans caserne, on revient à l\'invitation en cours', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.sansCaserne,
          chemin: AppRoutes.aucuneCaserne,
          cheminInvitationEnAttente: lien,
        ),
        lien,
      );
    });

    test('sans invitation en attente, rien ne change', () {
      expect(
        redirectionAuth(etat: EtatAuth.sansCaserne, chemin: AppRoutes.accueil),
        AppRoutes.aucuneCaserne,
      );
    });

    test(
      'l\'accueil du nouveau membre n\'est ouvert qu\'une fois connecté',
      () {
        expect(
          redirectionAuth(etat: EtatAuth.connecte, chemin: AppRoutes.guide),
          isNull,
        );
        expect(
          redirectionAuth(etat: EtatAuth.deconnecte, chemin: AppRoutes.guide),
          AppRoutes.connexion,
        );
      },
    );

    test('l\'écran des membres suit les mêmes règles que l\'accueil', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.connecte,
          chemin: AppRoutes.membres,
          estAdmin: true,
        ),
        isNull,
      );
      expect(
        redirectionAuth(etat: EtatAuth.deconnecte, chemin: AppRoutes.membres),
        AppRoutes.connexion,
      );
    });
  });

  group('redirectionAuth et les écrans d\'administration', () {
    const ecrans = <String>[
      AppRoutes.prefixeAdmin,
      AppRoutes.membres,
      '${AppRoutes.membres}/${AppRoutes.inviterChemin}',
      AppRoutes.parametres,
      AppRoutes.periodes,
      '/admin/schedule/2026-10',
    ];

    test('un membre y est renvoyé à l\'accueil', () {
      for (final chemin in ecrans) {
        expect(
          redirectionAuth(etat: EtatAuth.connecte, chemin: chemin),
          AppRoutes.accueil,
          reason: chemin,
        );
      }
    });

    test('un admin les ouvre', () {
      for (final chemin in ecrans) {
        expect(
          redirectionAuth(
            etat: EtatAuth.connecte,
            chemin: chemin,
            estAdmin: true,
          ),
          isNull,
          reason: chemin,
        );
      }
    });

    test('un chemin qui commence par « admin » sans en être n\'est pas '
        'concerné', () {
      expect(
        redirectionAuth(etat: EtatAuth.connecte, chemin: '/administratif'),
        isNull,
      );
    });
  });

  group('La garde de /superadmin (ticket 031)', () {
    test('un administrateur de caserne y est renvoyé à l\'accueil', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.connecte,
          chemin: AppRoutes.superAdmin,
          estAdmin: true,
          estSuperAdmin: false,
        ),
        AppRoutes.accueil,
      );
    });

    test('un simple membre aussi', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.connecte,
          chemin: AppRoutes.superAdmin,
          estSuperAdmin: false,
        ),
        AppRoutes.accueil,
      );
    });

    test('l\'éditeur y entre', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.connecte,
          chemin: AppRoutes.superAdmin,
          estSuperAdmin: true,
        ),
        isNull,
      );
    });

    // Le cas nominal : la personne qui édite le produit n'est membre d'aucune
    // caserne. Sans cette branche, elle atterrirait sur « Aucune caserne », un
    // écran qui ne propose que la déconnexion.
    test('l\'éditeur sans caserne y entre quand même', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.sansCaserne,
          chemin: AppRoutes.superAdmin,
          estSuperAdmin: true,
        ),
        isNull,
      );
    });

    test('un compte sans caserne qui n\'est pas l\'éditeur reste dehors', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.sansCaserne,
          chemin: AppRoutes.superAdmin,
          estSuperAdmin: false,
        ),
        AppRoutes.aucuneCaserne,
      );
      expect(
        redirectionAuth(
          etat: EtatAuth.sansCaserne,
          chemin: AppRoutes.accueil,
          estSuperAdmin: false,
        ),
        AppRoutes.aucuneCaserne,
      );
    });

    // `chargement` n'est **pas** une attente de l'éditeur : une session en
    // cours de restauration passe par l'écran d'attente comme pour n'importe
    // quelle adresse. Sans ça, `destinationInitiale` ne mémorise jamais l'URL
    // tapée à froid — et c'est ce chemin-là qui avait bouclé dans Chrome.
    test('en chargement, /superadmin passe par l\'écran d\'attente', () {
      for (final droit in <bool?>[null, true, false]) {
        expect(
          redirectionAuth(
            etat: EtatAuth.chargement,
            chemin: AppRoutes.superAdmin,
            estSuperAdmin: droit,
          ),
          AppRoutes.demarrage,
          reason: 'droit = $droit',
        );
      }
    });

    test('déconnecté, /superadmin mène à la connexion comme le reste', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.deconnecte,
          chemin: AppRoutes.superAdmin,
          estSuperAdmin: true,
        ),
        AppRoutes.connexion,
      );
    });

    // `null` veut dire « pas encore su » : la garde attend plutôt que de
    // rediriger sur une supposition, sinon une URL tapée à froid est perdue.
    test('tant que le droit est inconnu, la garde ne tranche pas', () {
      expect(
        redirectionAuth(etat: EtatAuth.connecte, chemin: AppRoutes.superAdmin),
        isNull,
      );
    });

    test('l\'écran de l\'éditeur n\'est pas sous la garde des admins', () {
      // `/superadmin` ne commence pas par `/admin` : les deux gardes portent
      // sur deux droits différents, et il ne faut pas qu'un administrateur de
      // caserne hérite de l'une par l'autre.
      expect(AppRoutes.superAdmin.startsWith(AppRoutes.prefixeAdmin), isFalse);
    });

    test('un chemin qui commence par « superadmin » sans en être n\'est pas '
        'concerné', () {
      expect(
        redirectionAuth(
          etat: EtatAuth.connecte,
          chemin: '/superadministration',
          estSuperAdmin: false,
        ),
        isNull,
      );
    });
  });
}
