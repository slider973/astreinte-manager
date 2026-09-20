import '../session/etat_auth.dart';
import 'app_router.dart';

/// Où l'état d'authentification oblige à aller, ou `null` pour « reste ici ».
///
/// Fonction pure : c'est elle qui est testée, pas le routeur. Les quatre états
/// ont chacun leur écran, et un seul.
///
/// [chemin] est `GoRouterState.matchedLocation`, sans la chaîne de requête :
/// `/connexion/code?email=…` arrive donc comme `/connexion/code`.
String? redirectionAuth({
  required EtatAuth etat,
  required String chemin,
  bool outilsDevAutorises = false,
}) {
  // Le catalogue de composants du ticket 004 reste joignable en build de
  // développement, connecté ou non : c'est un outil, pas un écran du produit.
  if (outilsDevAutorises && chemin.startsWith(AppRoutes.devComponents)) {
    return null;
  }

  final surLaConnexion = chemin.startsWith(AppRoutes.connexion);

  return switch (etat) {
    EtatAuth.chargement => chemin == AppRoutes.demarrage
        ? null
        : AppRoutes.demarrage,
    EtatAuth.deconnecte => surLaConnexion ? null : AppRoutes.connexion,
    EtatAuth.sansCaserne => chemin == AppRoutes.aucuneCaserne
        ? null
        : AppRoutes.aucuneCaserne,
    EtatAuth.connecte =>
      surLaConnexion ||
              chemin == AppRoutes.demarrage ||
              chemin == AppRoutes.aucuneCaserne
          ? AppRoutes.accueil
          : null,
  };
}
