/// Hors du web : aucune fenêtre à ouvrir.
///
/// Cette version est compilée pour les builds iOS et Android natifs, qui ne
/// sont produits qu'à la demande d'une caserne (`CLAUDE.md`). Le jour où l'un
/// d'eux doit ouvrir une page de paiement, c'est ici que le paquet natif se
/// branchera — et nulle part ailleurs dans l'application.
bool ouvrirAdresseExterne(String adresse) => false;
