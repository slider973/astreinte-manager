import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'promesse_envoi.dart';

void main() {
  group('promesseDEnvoi', () {
    for (final phrase in <String>[
      'samedi 12 octobre, nuit : refusée. Ton chef de centre est prévenu.',
      'Camille G. est prévenu.',
      'Camille G. est prévenu, Marie L. aussi.',
      'Astreinte annulée. Marie L. est prévenu.',
      'L\'astreinte de Marie L. est annulée et Marie L. en est prévenu.',
      'Nouveau code envoyé. Regarde tes e-mails.',
      'Les membres ont été notifiés.',
      'Tu as été prévenue.',
      '3 invitations envoyées, 0 échec.',
    ]) {
      test('refuse « $phrase »', () => expect(promesseDEnvoi(phrase), isTrue));
    }

    for (final phrase in <String>[
      'samedi 12 octobre, nuit : refusée. Ton chef de centre sera prévenu.',
      'samedi 12 octobre, nuit : refusée.',
      'Camille G. sera prévenu.',
      'Camille G. et Marie L. seront prévenus.',
      'Réattribué : Camille G. reprend le créneau. Marie L. sera prévenu.',
      'Nouveau code demandé. Regarde tes e-mails d\'ici une minute.',
      'Personne d\'autre n\'est prévenu.',
      'Les courriels ne sont pas partis. Personne n\'a été prévenu.',
      'Marie L. n\'a pas encore répondu : il n\'est pas prévenu.',
      'Courriel envoyé le 3 octobre',
    ]) {
      test('laisse passer « $phrase »',
          () => expect(promesseDEnvoi(phrase), isFalse));
    }
  });

  // Les phrases du ticket 055, prises à la source : si l'une redevient une
  // promesse, ce groupe le dit avant même qu'un écran ne l'affiche.
  group('Les phrases des écrans gardés ne promettent rien', () {
    const creneau = 'samedi 12 octobre, nuit';
    for (final phrase in <String>[
      AppStrings.propositionsRefusee(creneau),
      AppStrings.propositionsRefuseeParAdmin(creneau),
      AppStrings.reattribuerFaite('Camille G.'),
      AppStrings.reattribuerFaiteEtAncien('Camille G.', 'Marie L.'),
      AppStrings.reattribuerFaiteSansPreuve('Camille G.'),
      AppStrings.reattribuerFaiteSansPreuve('Camille G.', ancien: 'Marie L.'),
      AppStrings.reattribuerRemplace('Marie L.'),
      AppStrings.annulerFaite('Marie L.'),
      AppStrings.codeRenvoye,
    ]) {
      test('« $phrase »', () => expect(promesseDEnvoi(phrase), isFalse));
    }
  });
}
