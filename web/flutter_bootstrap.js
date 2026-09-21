// Amorçage du moteur Flutter web — Astreinte SP (ticket 037).
//
// Ce fichier remplace celui que `flutter build web` écrit tout seul. Il en
// reprend le gabarit mot pour mot — les deux jetons de substitution, puis
// l'appel à `_flutter.loader.load` — à deux réglages près. Ces deux réglages
// sont la raison d'être du ticket : **par défaut, le chargeur Flutter va
// chercher deux ressources chez Google à chaque ouverture**.
//
// Attention en relisant ce fichier : `flutter build web` remplace les jetons
// `{{…}}` partout, **y compris dans les commentaires**. Aucun ne doit être cité
// ici autrement qu'à sa place, sous peine de recopier tout `flutter.js` au
// milieu d'une phrase et de produire un fichier qui ne s'exécute pas.
//
//   1. `canvasKitBaseUrl` — sans lui, le moteur de rendu est téléchargé depuis
//      `https://www.gstatic.com/flutter-canvaskit/<révision>/`. Mesuré au
//      ticket 032 : **1 620 Ko**, le premier poste du temps d'ouverture, et une
//      requête vers un CDN américain alors que le registre des données
//      personnelles du produit annonce un hébergement européen (`docs/PRD.md`
//      § 8). Les fichiers sont déjà dans `build/web/canvaskit/` : `flutter
//      build web` les y recopie de toute façon, il ne s'en sert simplement pas.
//
//   2. `fontFallbackBaseUrl` — quand un glyphe manque à toutes les polices
//      chargées (un emoji tapé dans un commentaire, un nom en cyrillique), le
//      moteur télécharge la police Noto correspondante depuis
//      `https://fonts.gstatic.com/s/`. Ça n'arrive pas au démarrage, ça arrive
//      **pendant la navigation**, sur le texte saisi par les utilisateurs —
//      c'est-à-dire au pire moment pour une requête sortante non annoncée.
//      Pointé ici sur `polices-de-repli/`, un répertoire de ce dépôt qui ne
//      contient aucune police : la requête échoue chez nous, le moteur pose un
//      avertissement en console et dessine un caractère de substitution. Le
//      pourquoi est dans `web/polices-de-repli/README.md`.
//
// Le repli **Roboto**, lui, ne se règle pas ici : le moteur le télécharge sans
// condition tant qu'aucune famille nommée `Roboto` n'est déclarée dans
// `pubspec.yaml`. Voir la section `fonts:` de `pubspec.yaml`.
//
// `--no-web-resources-cdn` (voir `scripts/build_web.sh`) fait la même chose que
// le point 1 côté ligne de commande. Les deux sont posés exprès : le réglage
// ci-dessous vaut aussi pour `flutter run -d chrome` et pour un
// `flutter build web` lancé à la main, que personne ne pensera à assortir du
// bon drapeau.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
    fontFallbackBaseUrl: 'polices-de-repli/',
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
