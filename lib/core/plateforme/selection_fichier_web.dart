import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'selection_fichier.dart';

/// Demande un fichier dans un navigateur.
///
/// **Un `input[type=file]` et rien d'autre.** Il est accessible au clavier, il
/// ouvre le sélecteur natif du système — donc « Fichiers » sur iPhone et le
/// gestionnaire de fichiers sur Android —, et il n'ajoute aucune dépendance.
/// L'élément est posé hors du flux, activé, puis retiré : il n'existe que le
/// temps du choix.
///
/// **La taille est lue sur `File.size`, avant la lecture.** Le navigateur la
/// connaît sans ouvrir le fichier ; un refus qui commencerait par charger deux
/// cents mégaoctets en mémoire ferait tomber l'onglet au lieu d'afficher une
/// phrase.
Future<SelectionFichier> demanderFichier({
  required String typesAcceptes,
  required int tailleMaxOctets,
}) async {
  final champ = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = typesAcceptes
    ..multiple = false
    ..style.display = 'none';

  final attente = Completer<SelectionFichier>();

  void terminer(SelectionFichier resultat) {
    if (!attente.isCompleted) attente.complete(resultat);
  }

  // `change` quand un fichier est choisi ; `cancel` quand la fenêtre est
  // refermée sans rien prendre. Le second n'existe que depuis Chrome 113,
  // Safari 16.4 et Firefox 109 : sur un navigateur plus ancien, la promesse
  // reste simplement en attente jusqu'à ce que la personne réessaie, ce qui
  // est exactement ce qu'elle voit — un bouton qui n'a rien fait. Aucun repli
  // par `focus` : il se déclenche à tort dès qu'on change d'onglet, et
  // annoncer « annulé » pendant que le sélecteur est ouvert serait pire.
  champ.onchange = ((web.Event _) {
    final fichier = champ.files?.item(0);
    if (fichier == null) {
      terminer(const SelectionAnnulee());
      return;
    }
    if (fichier.size > tailleMaxOctets) {
      terminer(
        FichierTropGros(octets: fichier.size, limite: tailleMaxOctets),
      );
      return;
    }
    unawaited(
      _lire(fichier)
          .then(
            (Uint8List octets) =>
                terminer(FichierChoisi(nom: fichier.name, octets: octets)),
          )
          .catchError((Object _) => terminer(const SelectionIndisponible())),
    );
  }).toJS;

  champ.oncancel = ((web.Event _) => terminer(const SelectionAnnulee())).toJS;

  web.document.body?.appendChild(champ);
  try {
    champ.click();
    return await attente.future;
  } on Object {
    return const SelectionIndisponible();
  } finally {
    champ.remove();
  }
}

/// Le contenu brut du fichier. `arrayBuffer()` plutôt que `FileReader` : une
/// promesse au lieu de trois écouteurs d'événements, pour le même résultat.
Future<Uint8List> _lire(web.File fichier) async {
  final tampon = await fichier.arrayBuffer().toDart;
  return tampon.toDart.asUint8List();
}
