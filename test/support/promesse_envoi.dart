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

/// Les adverbes qui se glissent entre l'auxiliaire et le participe sans rien
/// retirer à l'affirmation. La négation (« pas », « jamais », « plus ») n'y est
/// pas : « n'est pas prévenu » ne promet rien.
const String _adverbe =
    '(?:bien|déjà|aussitôt|aussi|immédiatement|directement|correctement'
    '|tous|toutes|tout)';

/// **Le fait affirmé au passé composé** : « est prévenu », « a été notifié »,
/// « sont envoyés », et leurs accords. Ajouté au ticket 055, où l'écran des
/// propositions disait « Ton chef de centre est prévenu » alors que la base
/// n'avait rien mis en file, et la réattribution « `<membre>` est prévenu »
/// alors qu'elle ne le prouvait que pour le sortant.
///
/// Ce que le motif laisse passer, parce que c'est ce que le serveur soutient :
///
/// - **le futur** — « sera prévenu », « seront prévenus » : une demande **en
///   file**, écrite dans la transaction du geste, n'est pas une notification
///   livrée, et le futur dit exactement cela ;
/// - **la négation** — « n'est pas prévenu », « Personne n'a été prévenu » :
///   l'auxiliaire précédé de « n' », ou suivi de « pas » ou « jamais », ne
///   promet rien. C'est le constat le plus honnête qu'un écran puisse faire.
///
/// L'auxiliaire est exigé : « Courriel envoyé le 3 octobre » est une date
/// relue en base (`email_sent_at`, ticket 048), pas une promesse.
final RegExp _faitAffirme = RegExp(
  // `\b` ne connaît que l'ASCII : devant « été » ou « êtes », il ne verrait
  // pas de frontière. D'où `(?<!\p{L})`, la frontière de mot en français.
  //
  // Trois formes, chacune tolérant des adverbes entre ses mots (« a bien été
  // prévenue », « sont déjà notifiés », « a aussitôt prévenu ») :
  //   - être + participe : « est prévenu », « sont notifiés » ;
  //   - avoir + été + participe : « a été prévenu », « ont bien été notifiés » ;
  //   - avoir + participe : « on a prévenu ton chef », « a déjà envoyé ».
  r"(?<![nN]['’])(?<!\p{L})"
  r'(?:(?:est|es|sont|suis|sommes|êtes)'
  '|(?:a|as|ont|avons|avez|ai)(?:\\s+$_adverbe)*\\s+été'
  r'|(?:a|as|ont|avons|avez|ai))'
  '(?:\\s+$_adverbe)*'
  r'\s+(?:prévenu|notifié|envoyé)(?:e|s|es)?(?!\p{L})',
  caseSensitive: false,
  unicode: true,
);

/// **Le compte rendu elliptique d'un envoi** : « Nouveau code envoyé. »,
/// « Chef prévenu. » — le participe seul, en fin de proposition, qu'aucun
/// auxiliaire, futur ou négation ne précède, adverbes compris (« sera bien
/// prévenu. » passe). C'était la phrase de
/// `codeRenvoye` avant le ticket 055 : aucun signal ne dit au client que le
/// courriel est sorti. Les formes à auxiliaire sont l'affaire de
/// [_faitAffirme].
final RegExp _envoiElliptique = RegExp(
  '(?<!(?:été|est|es|sont|suis|sera|seras|seront|serez|pas|jamais|plus)'
  '(?:\\s+(?:$_adverbe|encore))*\\s)'
  r'(?<!\p{L})(?:prévenu|notifié|envoyé)(?:e|s|es)?\s*[.!]\s*$',
  caseSensitive: false,
  unicode: true,
);

/// Vrai si [phrase] affirme qu'un envoi a eu lieu. Les trois motifs
/// ci-dessus, et rien d'autre.
bool promesseDEnvoi(String phrase) =>
    _promesseDEnvoi.hasMatch(phrase) ||
    _faitAffirme.hasMatch(phrase) ||
    _propositions(phrase).any(_envoiElliptique.hasMatch);

/// Une phrase par proposition : « Personne n'a été prévenu. Chef prévenu. »
/// se juge en deux fois, pour que la négation de la première ne couvre pas la
/// seconde.
Iterable<String> _propositions(String phrase) => phrase
    .split(RegExp(r'(?<=[.!?])\s+'))
    .where((String p) => p.trim().isNotEmpty);

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
/// Depuis le ticket 055, elle vaut aussi pour **l'écran des propositions**
/// (le refus, `test/features/boite/reponse_propositions_test.dart`), **la
/// réattribution et l'annulation** du suivi
/// (`test/features/planning/reattribution_test.dart`) et **le code de
/// connexion** (`test/features/auth/code_screen_test.dart`), avec les motifs
/// [_faitAffirme] et [_envoiElliptique] en plus de « envoyée ».
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
      promesseDEnvoi(phrase),
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
