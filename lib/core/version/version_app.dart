/// Ce qui identifie la construction qui tourne.
///
/// Ticket 080. Le propriétaire teste la PWA après chaque correctif et ne
/// pouvait pas savoir **ce qu'il avait sous les yeux** : un service worker sert
/// parfois l'ancienne version depuis le cache, et sans repère affiché, un
/// correctif qui marche et un correctif pas encore arrivé sont indiscernables.
///
/// **Pas de version sémantique.** `pubspec.yaml` est resté à `0.1.0+1` pendant
/// 79 livraisons : un numéro que personne ne fait avancer mentirait. Le commit
/// court est exact, automatique et vérifiable — il se compare à `git log` et à
/// la liste des PR.
///
/// Les trois valeurs sont des `const` résolues **à la compilation** par les
/// `--dart-define` de `scripts/build_web.sh`. Aucun paquet, aucune lecture au
/// démarrage, aucun appel asynchrone : un écran peut les afficher sans attendre.
library;

/// L'empreinte courte du commit construit, ou `local` hors dépôt git.
const String appCommit = String.fromEnvironment(
  'APP_COMMIT',
  defaultValue: 'local',
);

/// La date de construction en ISO 8601 (UTC), ou vide si rien n'a été injecté.
///
/// Vide plutôt que `local` : c'est une date, et l'affichage doit pouvoir la
/// taire proprement plutôt que de montrer un mot à la place.
const String appBuildDate = String.fromEnvironment('APP_BUILD_DATE');

/// L'environnement, tel que `env/*.json` le déclare (`dev`, `prod`).
const String appEnv = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'dev',
);

/// Vrai quand la construction n'a pas été datée ni rattachée à un commit.
///
/// C'est le cas d'un `flutter run` ou d'un `flutter test` : le bloc « À propos »
/// s'affiche quand même — il doit être testable — mais sans prétendre identifier
/// une livraison.
bool get constructionLocale => appCommit == 'local';

/// Vrai en production, où l'environnement n'a pas à être affiché : inutile de
/// dire « production » à un pompier qui ouvre son profil.
bool get enProduction => appEnv == 'prod';

/// La date de construction, lisible, ou `null` si elle n'a pas été injectée ou
/// n'est pas analysable.
///
/// Rendre `null` plutôt que lever : une date mal formée ne doit pas empêcher
/// quelqu'un de lire son profil.
DateTime? get dateConstruction {
  if (appBuildDate.isEmpty) return null;
  return DateTime.tryParse(appBuildDate)?.toLocal();
}
