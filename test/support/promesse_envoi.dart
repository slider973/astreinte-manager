import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le mot qui promet un envoi. **Sans exception.**
///
/// Il n'y a plus de frontière de mot devant « envoyée » : elle avait été posée
/// pour laisser passer « Renvoyée », le statut d'une adresse déjà invitée — et
/// c'était précisément le libellé qui mentait. Le compte rendu affichait
/// « Renvoyée » au-dessus de « Le courriel n'est pas parti », le garde-fou
/// regardait ailleurs, et la revue du ticket 048 l'a trouvé à sa place. Un
/// garde-fou qui exclut d'avance le mot qui ment ne garde rien.
///
/// Le motif prend donc « envoyée », « envoyées », « renvoyée » et
/// « renvoyées » partout où ils apparaissent. Plus aucun libellé de ces
/// écrans ne les contient : une relance dont le courriel est parti se dit
/// « Relancée » (`AppStrings.resultatRelancee`), ce qui est le même fait dit
/// sans le mot interdit. Seul [AppStrings.invitationsResume] peut encore
/// l'écrire, et seulement quand tous les courriels sont sortis.
final RegExp _promesseDEnvoi = RegExp('envoyée', caseSensitive: false);

/// Refuse à l'écran affiché la moindre promesse d'envoi.
///
/// C'est l'assertion qui manquait à la revue du ticket 048 : vérifier que la
/// phrase attendue est là ne voit pas celle **en trop**. Le compte rendu
/// d'import affichait « 3 invitations envoyées, 0 échec. » posé sur « leur
/// courriel n'est pas parti », et les deux passaient ; le compte rendu du
/// formulaire d'invitation portait la même contradiction, à une adresse près,
/// puis la portait encore par son statut.
///
/// Elle vaut donc pour les trois écrans qui invitent — l'import, le
/// formulaire d'invitation, et celui de l'éditeur, branché au ticket 050 —,
/// et pour toute phrase qu'ils rendent : dès qu'un courriel est resté à quai,
/// plus rien à l'écran n'a le droit de dire « envoyée ». L'écran de l'éditeur
/// n'avait pas été branché au 048, et il a porté la phrase corrigée ailleurs
/// un ticket de plus : un garde-fou ne garde que les écrans qui l'appellent.
///
/// **Ce que « rendent » veut dire.** Les [Text] affichés, et aussi les
/// étiquettes de [Semantics] : le compte rendu pose ses lignes en
/// `Semantics(label:, value:, excludeSemantics: true)`, si bien que ces
/// chaînes-là sont exactement — et seules — ce qu'un lecteur d'écran
/// prononce. Ne lire que `Text.data` laissait la promesse intacte pour qui
/// n'a que la voix.
void aucunEnvoiPromis(WidgetTester tester) {
  for (final phrase in _phrasesAffichees(
    tester,
  ).followedBy(_phrasesPrononcees(tester))) {
    expect(
      _promesseDEnvoi.hasMatch(phrase),
      isFalse,
      reason: '« $phrase » promet un envoi qui n\'a pas eu lieu.',
    );
  }
}

Iterable<String> _phrasesAffichees(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text texte) => texte.data)
    .whereType<String>();

Iterable<String> _phrasesPrononcees(WidgetTester tester) sync* {
  for (final semantique in tester.widgetList<Semantics>(
    find.byType(Semantics),
  )) {
    final proprietes = semantique.properties;
    yield* <String?>[
      proprietes.label ?? proprietes.attributedLabel?.string,
      proprietes.value ?? proprietes.attributedValue?.string,
      proprietes.hint ?? proprietes.attributedHint?.string,
      proprietes.tooltip,
    ].whereType<String>();
  }
}
