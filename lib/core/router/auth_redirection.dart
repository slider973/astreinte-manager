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
/// Deux chemins sortent de la garde quoi qu'il arrive : `/invite/<jeton>` et
/// `/rejoindre/<identifiant>`, les deux entrées d'une même invitation.
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

  // **La seconde entrée de la même invitation** (ticket 051), et la même
  // exemption, pour deux raisons distinctes. En amont : un compte sans caserne
  // y serait renvoyé sur « Aucune caserne » avant d'avoir rien affiché — ou
  // pire, détourné vers un jeton gardé en mémoire, qui n'est pas l'invitation
  // qu'il vient de choisir. En aval : dès que l'appartenance apparaît, l'état
  // passe à [EtatAuth.connecte], et cette branche-là arracherait l'écran vers
  // l'accueil à la seconde où l'acceptation réussit — pas de « Bienvenue »,
  // pas de nom de caserne, pas de profil, pas de guide.
  if (chemin.startsWith(AppRoutes.prefixeRejoindre)) return null;

  // `/install` s'ouvre dans tous les états, pour la même raison qu'une page
  // légale : elle s'adresse à quelqu'un qui n'a pas encore de compte — celui
  // à qui on vient de dicter l'adresse. La renvoyer sur l'écran de connexion
  // ferait de l'aide à l'installation une récompense de la connexion
  // (ticket 032).
  if (chemin == AppRoutes.aideInstallation) return null;

  // Les deux pages légales aussi, et pour une raison qui leur est propre : une
  // politique de confidentialité doit être lisible **sans compte** — par une
  // mairie qui instruit un dossier, par quelqu'un qui vient de recevoir une
  // invitation et veut savoir à quoi il s'engage. Une page qui ne s'ouvre
  // qu'une fois connecté ne remplit pas son office (ticket 034).
  if (_sousLegal(chemin)) return null;

  final surLaConnexion = chemin.startsWith(AppRoutes.connexion);
  final surLEditeur = _sousSuperAdmin(chemin);

  // Tant que le droit de l'éditeur n'est pas connu, la garde **attend** sur son
  // écran plutôt que de trancher : rediriger sur une supposition perdrait
  // l'URL tapée à froid, et l'écran ne peut rien montrer sans droits.
  // `chargement` n'est pas concerné : une session en cours de restauration
  // passe par l'écran d'attente comme pour n'importe quelle autre adresse,
  // sans quoi la destination initiale n'est jamais mémorisée.
  final editeurEnAttente = surLEditeur && estSuperAdmin == null;

  return switch (etat) {
    EtatAuth.chargement =>
      chemin == AppRoutes.demarrage ? null : AppRoutes.demarrage,
    EtatAuth.deconnecte => surLaConnexion ? null : AppRoutes.connexion,
    // Le cas nominal de l'éditeur : connecté, membre d'aucune caserne. Sans
    // cette branche il serait renvoyé sur « Aucune caserne », un écran qui ne
    // propose que la déconnexion.
    EtatAuth.sansCaserne when surLEditeur && estSuperAdmin != false => null,
    EtatAuth.sansCaserne =>
      cheminInvitationEnAttente ??
          (chemin == AppRoutes.aucuneCaserne ? null : AppRoutes.aucuneCaserne),
    EtatAuth.connecte when editeurEnAttente => null,
    EtatAuth.connecte =>
      surLaConnexion ||
              chemin == AppRoutes.demarrage ||
              chemin == AppRoutes.aucuneCaserne ||
              (_sousAdministration(chemin) && !estAdmin) ||
              (surLEditeur && !estSuperAdmin!)
          ? AppRoutes.accueil
          : null,
  };
}

/// Vrai pour `/admin` et tout ce qui est en dessous : les membres, les
/// paramètres, les périodes, et le lien public de suivi du planning.
bool _sousAdministration(String chemin) =>
    chemin == AppRoutes.prefixeAdmin ||
    chemin.startsWith('${AppRoutes.prefixeAdmin}/');

/// Vrai pour `/legal` et les deux documents qui sont en dessous.
bool _sousLegal(String chemin) =>
    chemin == AppRoutes.prefixeLegal ||
    chemin.startsWith('${AppRoutes.prefixeLegal}/');

/// Vrai pour `/superadmin` et tout ce qui viendrait en dessous.
///
/// Ce n'est **pas** un sous-chemin de `/admin` : les deux gardes ne portent pas
/// sur le même droit, et un administrateur de caserne n'est pas l'éditeur du
/// produit.
bool _sousSuperAdmin(String chemin) =>
    chemin == AppRoutes.superAdmin ||
    chemin.startsWith('${AppRoutes.superAdmin}/');
