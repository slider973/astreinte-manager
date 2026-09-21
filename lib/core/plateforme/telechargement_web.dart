import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'telechargement.dart';

/// Remet un fichier à la personne, dans un navigateur.
///
/// **Deux chemins, et le choix entre les deux est le sujet de ce fichier.**
///
/// 1. **La feuille de partage du système** (`navigator.share` avec un fichier),
///    quand le navigateur l'accepte. C'est le geste attendu sur un iPhone où la
///    PWA est installée : `Enregistrer dans Fichiers`, ou un envoi à soi-même.
///    L'attribut `download` d'une ancre y reste inégal — selon la version
///    d'iOS, il ouvre une vue blanche, télécharge sans le dire, ou ne fait
///    rien. Un bouton qui ne fait rien est le pire résultat possible pour un
///    export RGPD, parce que la personne ne peut pas savoir s'il a marché.
/// 2. **L'ancre `download`**, partout ailleurs : sur Chrome (ordinateur comme
///    Android) et sur les navigateurs de bureau, c'est le chemin le plus court,
///    il ne demande aucun geste supplémentaire et il nomme le fichier.
///
/// Le partage n'est tenté **que** quand le système le propose pour un fichier
/// (`canShare({files})`) : Chrome sur ordinateur répond non, et retombe donc
/// sur l'ancre sans qu'on ait à le reconnaître à son agent utilisateur.
///
/// L'URL d'objet est libérée dans tous les cas : sans `revokeObjectURL`, le
/// contenu du fichier — donc l'export complet d'une personne — reste en mémoire
/// de l'onglet jusqu'à sa fermeture.
Future<ResultatTelechargement> telechargerFichier({
  required String nomFichier,
  required String contenu,
  String typeMime = 'application/json',
}) async {
  final fichier = _fichier(nomFichier, contenu, typeMime);

  final partage = await _partager(fichier);
  if (partage != null) return partage;

  return _ancre(fichier, nomFichier);
}

/// Un fichier en mémoire, portant son nom : `navigator.share` l'exige, et
/// l'ancre s'en sert pour le suffixe.
web.File _fichier(String nomFichier, String contenu, String typeMime) {
  return web.File(
    <JSAny>[contenu.toJS].toJS,
    nomFichier,
    web.FilePropertyBag(type: typeMime),
  );
}

/// Tente la feuille de partage. Rend `null` quand ce chemin n'est pas celui de
/// cette plateforme — l'appelant passe alors à l'ancre.
Future<ResultatTelechargement?> _partager(web.File fichier) async {
  final donnees = web.ShareData(files: <web.File>[fichier].toJS);

  try {
    if (!web.window.navigator.canShare(donnees)) return null;
  } on Object {
    // Un navigateur qui ne connaît pas `canShare` lève au lieu de répondre.
    // Ce n'est pas une panne, c'est un « non ».
    return null;
  }

  try {
    await web.window.navigator.share(donnees).toDart;
    return ResultatTelechargement.partage;
  } on Object catch (cause) {
    // `AbortError` : la feuille a été refermée. C'est un choix, pas un échec —
    // et il ne doit surtout pas retomber sur l'ancre, qui enregistrerait le
    // fichier que la personne vient de refuser.
    return _estAbandon(cause)
        ? ResultatTelechargement.annule
        : ResultatTelechargement.impossible;
  }
}

/// Le chemin ordinaire : une ancre `download`, un clic, puis le ménage.
ResultatTelechargement _ancre(web.File fichier, String nomFichier) {
  String? adresse;
  try {
    adresse = web.URL.createObjectURL(fichier);
    final lien = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = adresse
      ..download = nomFichier
      // Hors du flux et invisible : l'ancre n'existe que le temps du clic,
      // elle ne doit ni décaler la mise en page ni recevoir le focus.
      ..style.display = 'none';

    web.document.body?.appendChild(lien);
    lien.click();
    lien.remove();
    return ResultatTelechargement.enregistre;
  } on Object {
    return ResultatTelechargement.impossible;
  } finally {
    if (adresse != null) {
      // Après le clic, jamais avant : Safari lit l'URL au moment du clic, et
      // la libérer dans la même instruction rendrait le fichier vide. Le tour
      // de boucle suivant suffit.
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 1),
          () => web.URL.revokeObjectURL(adresse!),
        ),
      );
    }
  }
}

/// Vrai quand l'erreur rendue par `share` est un abandon de la personne.
///
/// **La forme textuelle est lue plutôt que le type**, et c'est un choix. Ce qui
/// remonte ici est un objet JavaScript, pas une exception Dart : selon le
/// navigateur et le compilateur — `dart2js` ou `dart2wasm` —, il arrive en
/// `DOMException` ou en objet d'erreur ordinaire, et le tester avec `is`
/// donnerait un résultat qui dépend de la plateforme (c'est exactement ce que
/// l'analyseur refuse, `invalid_runtime_check_with_js_interop_types`).
///
/// `DOMException.prototype.toString` est normalisé en `<name>: <message>` : le
/// nom est donc toujours en tête, dans tous les navigateurs, et il n'est pas
/// traduit.
bool _estAbandon(Object cause) => cause.toString().startsWith('AbortError');
