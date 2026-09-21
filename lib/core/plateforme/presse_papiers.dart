import 'package:flutter/services.dart';

/// Écrit [texte] dans le presse-papiers et dit si ça a marché.
///
/// `Clipboard` est un canal de plateforme du moteur Flutter, pas un paquet :
/// il fonctionne sur le web comme sur les deux plateformes natives, et rien
/// n'a été ajouté à `pubspec.yaml` pour lui (`CLAUDE.md` — aucun plugin sans
/// implémentation web).
///
/// **Le retour n'est pas décoratif.** Sur le web, l'écriture passe par
/// `navigator.clipboard`, que le navigateur refuse hors d'un geste de
/// l'utilisateur ou dans un contexte non sécurisé. Un bouton « Copier » qui
/// annonce une réussite là où rien n'a été copié est pire que pas de bouton du
/// tout : la personne colle une adresse vide dans son agenda et ne comprend
/// pas. L'appelant doit donc afficher le repli — l'adresse reste à l'écran,
/// sélectionnable.
Future<bool> copierDansPressePapiers(String texte) async {
  try {
    await Clipboard.setData(ClipboardData(text: texte));
    return true;
  } on Object {
    return false;
  }
}
