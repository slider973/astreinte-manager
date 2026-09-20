import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/invitation/domain/acceptation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les corps de réponse viennent de `supabase/functions/README.md`.
void main() {
  group('AcceptationInvitation', () {
    test('lit la caserne, le rôle et l\'inviteur', () {
      final acceptation = AcceptationInvitation.depuisJson(
        const <String, dynamic>{
          'ok': true,
          'already_accepted': false,
          'membership': <String, dynamic>{'role': 'admin', 'status': 'active'},
          'station': <String, dynamic>{
            'id': 'uuid',
            'name': 'CIS Saint-Martin',
            'slug': 'saint-martin',
          },
          'inviter': <String, dynamic>{
            'first_name': 'Jean',
            'last_name': 'Dupont',
            'email': 'admin@caserne-a.test',
          },
        },
      );

      expect(acceptation.dejaAcceptee, isFalse);
      expect(acceptation.role, RoleMembre.admin);
      expect(acceptation.caserne?.nom, 'CIS Saint-Martin');
      expect(acceptation.inviteur?.libelle, 'Jean Dupont');
    });

    test('un inviteur sans nom est nommé par son adresse', () {
      final acceptation = AcceptationInvitation.depuisJson(
        const <String, dynamic>{
          'already_accepted': true,
          'inviter': <String, dynamic>{
            'first_name': '',
            'last_name': '',
            'email': 'admin@caserne-a.test',
          },
        },
      );

      expect(acceptation.dejaAcceptee, isTrue);
      expect(acceptation.inviteur?.libelle, 'admin@caserne-a.test');
      expect(acceptation.caserne, isNull);
    });
  });

  group('ErreurAcceptation', () {
    test('chaque code du contrat a son écran', () {
      expect(
        ErreurAcceptation.depuisCode('invitation_not_found'),
        ErreurAcceptation.introuvable,
      );
      expect(
        ErreurAcceptation.depuisCode('invitation_expired'),
        ErreurAcceptation.expiree,
      );
      expect(
        ErreurAcceptation.depuisCode('invitation_already_accepted'),
        ErreurAcceptation.dejaAcceptee,
      );
      expect(
        ErreurAcceptation.depuisCode('email_mismatch'),
        ErreurAcceptation.mauvaisCompte,
      );
      expect(
        ErreurAcceptation.depuisCode('station_suspended'),
        ErreurAcceptation.caserneSuspendue,
      );
      expect(
        ErreurAcceptation.depuisCode('profile_missing'),
        ErreurAcceptation.profilManquant,
      );
      expect(
        ErreurAcceptation.depuisCode('autre_chose'),
        ErreurAcceptation.inconnue,
      );
    });

    test('aucune fin de parcours n\'est muette', () {
      for (final erreur in ErreurAcceptation.values) {
        expect(erreur.titre, isNotEmpty);
        final echec = EchecAcceptation(erreur);
        expect(echec.message, isNotEmpty, reason: 'Erreur ${erreur.name}');
      }
    });

    test('seuls le réseau et l\'inconnu se réessaient', () {
      expect(ErreurAcceptation.reseau.reessayable, isTrue);
      expect(ErreurAcceptation.inconnue.reessayable, isTrue);
      expect(ErreurAcceptation.expiree.reessayable, isFalse);
      expect(ErreurAcceptation.mauvaisCompte.reessayable, isFalse);
    });

    test('l\'adresse invitée reste masquée dans la phrase', () {
      const echec = EchecAcceptation(
        ErreurAcceptation.mauvaisCompte,
        adresseInviteeMasquee: 'r****e@exemple.fr',
        adresseCourante: 'autre@exemple.fr',
      );

      expect(echec.message, contains('r****e@exemple.fr'));
      expect(echec.message, contains('autre@exemple.fr'));
      expect(echec.sortie, isNull);
    });

    test('une invitation expirée nomme la caserne à contacter', () {
      const echec = EchecAcceptation(
        ErreurAcceptation.expiree,
        caserne: CaserneInvitation(nom: 'CIS Saint-Martin'),
      );

      expect(echec.titre, AppStrings.invitationExpireeTitre);
      expect(echec.sortie, contains('CIS Saint-Martin'));
    });
  });
}
