/// L'état d'authentification qui décide de la route affichée.
///
/// Quatre valeurs, et une seule à la fois. Le calcul vit dans
/// `data/auth_providers.dart` ; la conséquence sur la navigation vit dans
/// `core/router/auth_redirection.dart`. Les deux sont testables séparément.
enum EtatAuth {
  /// Session en cours de restauration, ou appartenances en cours de lecture.
  /// Rien n'est encore décidé : on n'envoie personne sur la connexion.
  chargement,

  /// Aucune session : l'écran de connexion.
  deconnecte,

  /// Session valide, mais aucune appartenance active à une caserne.
  sansCaserne,

  /// Session valide et appartenance active : l'app.
  connecte;

  bool get estConnecte => this == connecte;
}
