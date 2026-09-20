import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/router/auth_redirection.dart';
import 'package:astreinte_sp/features/auth/domain/etat_auth.dart';
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
        redirectionAuth(
          etat: EtatAuth.chargement,
          chemin: AppRoutes.demarrage,
        ),
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
}
