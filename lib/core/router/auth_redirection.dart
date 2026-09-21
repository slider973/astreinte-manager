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
///
/// [estAdmin] ferme les écrans d'administration à qui n'administre pas la
/// caserne. Les **données** sont déjà protégées par les politiques RLS
/// (`docs/SCHEMA.md § 4`), mais sans cette garde l'interface s'ouvre quand
/// même : un membre arrivant sur `/admin/membres` verrait des listes vides et
/// un formulaire d'invitation qui échoue à l'envoi. Une porte fermée vaut
/// mieux qu'une porte ouverte sur une pièce vide.
///
/// [estSuperAdmin] garde `/superadmin` par la **même** mécanique, avec deux
/// différences imposées par ce qu'est l'éditeur du produit :
///
/// - il n'est membre d'aucune caserne, donc il arrive en
///   [EtatAuth.sansCaserne], que la règle générale envoie sur « Aucune
///   caserne ». Son écran, et lui seul, reste joignable depuis cet état ;
/// - son statut ne vit pas dans la session : il vient d'un appel. `null` veut
///   dire **pas encore su**, et la garde ne tranche alors pas. Rediriger sur
///   un statut non résolu perdrait l'URL tapée à froid ; laisser l'écran
///   s'ouvrir ne montre rien, puisque toutes ses données viennent de fonctions
///   qui refusent (migration `0025`).
String? redirectionAuth({
  required EtatAuth etat,
  required String chemin,
  bool outilsDevAutorises = false,
  bool estAdmin = false,
  bool? estSuperAdmin,
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
  final surLEditeur = _sousSuperAdmin(chemin);

  // L'écran de l'éditeur est fermé à tout le monde d'autre, quel que soit
  // l'état — y compris à un compte parfaitement rattaché à sa caserne. Le
  // statut inconnu (`null`) ne tranche pas : voir la documentation ci-dessus.
  if (surLEditeur && estSuperAdmin == false) {
    return etat == EtatAuth.connecte ? AppRoutes.accueil : null;
  }

  return switch (etat) {
    EtatAuth.chargement =>
      chemin == AppRoutes.demarrage ? null : AppRoutes.demarrage,
    EtatAuth.deconnecte => surLaConnexion ? null : AppRoutes.connexion,
    // Le cas nominal de l'éditeur : connecté, membre d'aucune caserne. Sans
    // cette branche il serait renvoyé sur « Aucune caserne », un écran qui ne
    // propose que la déconnexion.
    EtatAuth.sansCaserne when surLEditeur && estSuperAdmin == true => null,
    EtatAuth.sansCaserne =>
      cheminInvitationEnAttente ??
          (chemin == AppRoutes.aucuneCaserne ? null : AppRoutes.aucuneCaserne),
    EtatAuth.connecte =>
      surLaConnexion ||
              chemin == AppRoutes.demarrage ||
              chemin == AppRoutes.aucuneCaserne ||
              (_sousAdministration(chemin) && !estAdmin)
          ? AppRoutes.accueil
          : null,
  };
}

/// Vrai pour `/admin` et tout ce qui est en dessous : les membres, les
/// paramètres, les périodes, et le lien public de suivi du planning.
bool _sousAdministration(String chemin) =>
    chemin == AppRoutes.prefixeAdmin ||
    chemin.startsWith('${AppRoutes.prefixeAdmin}/');

/// Vrai pour `/superadmin` et tout ce qui viendrait en dessous.
///
/// Ce n'est **pas** un sous-chemin de `/admin` : les deux gardes ne portent pas
/// sur le même droit, et un administrateur de caserne n'est pas l'éditeur du
/// produit.
bool _sousSuperAdmin(String chemin) =>
    chemin == AppRoutes.superAdmin ||
    chemin.startsWith('${AppRoutes.superAdmin}/');
