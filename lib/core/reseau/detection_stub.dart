import 'connectivite.dart';

/// Hors du web : aucun navigateur à interroger.
///
/// Les builds iOS et Android natifs ne sont produits qu'à la demande d'une
/// caserne (`CLAUDE.md`) et aucun plugin de connectivité n'est ajouté pour
/// eux. L'application s'y comporte comme si le réseau était là : c'est
/// exactement ce que faisait l'écran avant ce module, et l'échec d'une
/// requête reste traité comme un échec réseau.
Connectivite detecterConnectivite() => ConnectiviteMemoire();
