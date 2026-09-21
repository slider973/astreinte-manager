import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le mot qui promet un envoi, précédé d'une frontière de mot.
///
/// La frontière n'est pas un détail : sans elle, « Renvoyée » — le statut
/// d'une adresse déjà invitée, sur le compte rendu du formulaire — contient
/// « envoyée » et ferait échouer le garde-fou pour rien. Elle n'est posée
/// qu'**avant** le mot : le singulier finit par une lettre accentuée, et ce
/// que `\b` en fait dépend du moteur. Le préfixe suffit à écarter
/// « Renvoyée », et « envoyées » est pris par le même motif.
final RegExp _promesseDEnvoi = RegExp(r'\benvoyée', caseSensitive: false);

/// Refuse à l'écran affiché la moindre promesse d'envoi.
///
/// C'est l'assertion qui manquait à la revue du ticket 048 : vérifier que la
/// phrase attendue est là ne voit pas celle **en trop**. Le compte rendu
/// d'import affichait « 3 invitations envoyées, 0 échec. » posé sur « leur
/// courriel n'est pas parti », et les deux passaient ; le compte rendu du
/// formulaire d'invitation portait la même contradiction, à une adresse près.
///
/// Elle vaut donc pour les deux écrans, et pour toute phrase qu'ils rendent :
/// dès qu'un courriel est resté à quai, plus rien à l'écran n'a le droit de
/// dire « envoyée ».
void aucunEnvoiPromis(WidgetTester tester) {
  final phrases = tester
      .widgetList<Text>(find.byType(Text))
      .map((Text texte) => texte.data)
      .whereType<String>();
  for (final phrase in phrases) {
    expect(
      _promesseDEnvoi.hasMatch(phrase),
      isFalse,
      reason: '« $phrase » promet un envoi qui n\'a pas eu lieu.',
    );
  }
}
