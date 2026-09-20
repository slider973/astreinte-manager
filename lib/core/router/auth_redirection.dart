import '../session/etat_auth.dart';
import 'app_router.dart';

/// Où l'état d'authentification oblige à aller, ou `null` pour « reste ici ».
///
/// Fonction pure : c'est elle qui est testée, pas le routeur. Les quatre états
/// ont chacun leur écran, et un seul.
///
/// [chemin] est `GoRouterState.matchedLocation`, sans la chaîne de requête :
/// `/connexion/code?email=…` arrive donc comme `/connexion/code`.
///
/// [cheminInvitationEnAttente] est le lien d'invitation en cours de parcours,
/// gardé en mémoire par `core/session/jeton_invitation.dart`. Il change une
/// seule chose : un compte qui vient de se connecter sans caserne retourne à
/// son invitation au lieu d'être envoyé sur « aucune caserne ».
String? redirectionAuth({
  required EtatAuth etat,
  required String chemin,
  bool outilsDevAutorises = false,
  String? cheminInvitationEnAttente,
}) {
  // Le catalogue de composants du ticket 004 reste joignable en build de
  // développement, connecté ou non : c'est un outil, pas un écran du produit.
  if (outilsDevAutorises && chemin.startsWith(AppRoutes.devComponents)) {
    return null;
  }

  // Le lien d'invitation s'ouvre dans **tous** les états, y compris pendant la
  // restauration de session : rediriger vers l'écran de démarrage perdrait le
  // jeton, qui n'existe que dans l'URL reçue par courriel.
  if (chemin.startsWith(AppRoutes.prefixeInvitation)) return null;

  final surLaConnexion = chemin.startsWith(AppRoutes.connexion);

  return switch (etat) {
    EtatAuth.chargement =>
      chemin == AppRoutes.demarrage ? null : AppRoutes.demarrage,
    EtatAuth.deconnecte => surLaConnexion ? null : AppRoutes.connexion,
    EtatAuth.sansCaserne =>
      cheminInvitationEnAttente ??
          (chemin == AppRoutes.aucuneCaserne ? null : AppRoutes.aucuneCaserne),
    EtatAuth.connecte =>
      surLaConnexion ||
              chemin == AppRoutes.demarrage ||
              chemin == AppRoutes.aucuneCaserne
          ? AppRoutes.accueil
          : null,
  };
}
