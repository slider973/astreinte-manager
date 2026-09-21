import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

import 'adresse_heritee.dart';

/// Sert les routes dans le **chemin** de l'adresse, pas dans son fragment
/// (ticket 046).
///
/// **Pourquoi ce n'est pas un goût.** Le fournisseur d'authentification renvoie
/// ses jetons dans le fragment — `https://astreintes.example#access_token=…` —
/// et il le fait quelle que soit l'adresse de retour demandée. Tant que
/// `go_router` lisait ce même fragment comme une route, une connexion par lien
/// atterrissait sur une page introuvable : le routeur cherchait une route
/// nommée `access_token=…`. Aucun réglage côté fournisseur ne contourne ça ;
/// la seule sortie est de laisser le fragment au fournisseur et de servir les
/// routes dans le chemin.
///
/// **Ce que ça exige de l'hébergeur.** Toute adresse profonde doit retomber sur
/// `index.html`, sinon un rechargement sur `/admin/planning` rendrait une 404
/// côté serveur. C'est la réécriture de `vercel.json`, rejouée localement par
/// `scripts/servir_web.py`.
///
/// **À appeler avant `runApp`**, et une seule fois : le moteur fige sa
/// stratégie dès la première lecture de la route initiale.
void adopterAdressesSansDiese() {
  usePathUrlStrategy();

  // Les liens partis avant la bascule portent encore un dièse : on les
  // rattrape ici, avant que le routeur existe, en réécrivant l'adresse sans
  // recharger la page. `replaceState` et non `pushState` : l'ancienne forme ne
  // mérite pas une entrée dans l'historique du navigateur.
  final herite = cheminHerite(web.window.location.hash);
  if (herite != null) {
    web.window.history.replaceState(null, '', herite);
  }
}
