import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/membres/data/membres_repository.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Les corps de réponse viennent de `supabase/functions/README.md`.
void main() {
  group('RapportInvitations', () {
    test('lit un lot mêlant invitée, renvoyée et erreur', () {
      final rapport = RapportInvitations.depuisJson(const <String, dynamic>{
        'ok': false,
        'invited': 2,
        'failed': 1,
        'results': <dynamic>[
          {
            'email': 'recrue@exemple.fr',
            'status': 'invited',
            'invitation_id': 'i-1',
            'role': 'member',
            'email_sent': true,
          },
          {
            'email': 'ancien@exemple.fr',
            'status': 'resent',
            'email_sent': true,
          },
          {
            'email': 'deja@exemple.fr',
            'status': 'error',
            'code': 'already_member',
          },
        ],
      });

      expect(rapport.creees, 2);
      expect(rapport.courrielsPartis, 2);
      expect(rapport.echecs, 1);
      expect(rapport.toutEstPasse, isFalse);
      expect(rapport.adressesEnEchec, <String>['deja@exemple.fr']);
      expect(rapport.resultats[1].statut, StatutResultatInvitation.renvoyee);
      expect(rapport.resultats[2].detail, AppStrings.inviteDejaMembre);
    });

    test('un courriel non parti n\'est pas un échec, mais se dit', () {
      final rapport = RapportInvitations.depuisJson(const <String, dynamic>{
        'results': <dynamic>[
          {
            'email': 'recrue@exemple.fr',
            'status': 'invited',
            'email_sent': false,
          },
        ],
      });

      expect(rapport.echecs, 0);
      expect(rapport.resultats.single.enEchec, isFalse);
      expect(
        rapport.resultats.single.detail,
        AppStrings.resultatCourrielNonParti,
      );
      // L'invitation existe, et personne n'a été prévenu : les deux comptes
      // divergent, et c'est cette divergence qui interdit le mot « envoyée »
      // au compte rendu d'import (ticket 048).
      expect(rapport.creees, 1);
      expect(rapport.courrielsPartis, 0);
      expect(rapport.courrielsNonPartis, 1);
    });

    test('un statut inconnu est traité comme une erreur', () {
      final rapport = RapportInvitations.depuisJson(const <String, dynamic>{
        'results': <dynamic>[
          {'email': 'x@exemple.fr', 'status': 'surprise'},
        ],
      });

      expect(rapport.resultats.single.enEchec, isTrue);
      expect(rapport.resultats.single.detail, AppStrings.inviteErreurServeur);
    });

    test('chaque code de refus a sa phrase', () {
      expect(
        MotifEchecInvitation.depuisCode('invalid_email'),
        MotifEchecInvitation.adresseInvalide,
      );
      expect(
        MotifEchecInvitation.depuisCode('account_failed'),
        MotifEchecInvitation.compteImpossible,
      );
      expect(
        MotifEchecInvitation.depuisCode('conflict'),
        MotifEchecInvitation.conflit,
      );
      // Deux refus globaux qui redescendent par adresse quand l'état change
      // entre le contrôle préalable et la création.
      expect(
        MotifEchecInvitation.depuisCode('station_suspended'),
        MotifEchecInvitation.caserneSuspendue,
      );
      expect(
        MotifEchecInvitation.depuisCode('not_admin'),
        MotifEchecInvitation.nonAdmin,
      );
      for (final motif in MotifEchecInvitation.values) {
        expect(motif.message, isNotEmpty);
      }
    });

    test('les refus de la requête entière sont nommés', () {
      expect(
        ErreurInvitation.depuisCode('not_admin'),
        ErreurInvitation.nonAdmin,
      );
      expect(
        ErreurInvitation.depuisCode('station_suspended'),
        ErreurInvitation.caserneSuspendue,
      );
      expect(
        ErreurInvitation.depuisCode('station_not_found'),
        ErreurInvitation.caserneInconnue,
      );
      expect(
        ErreurInvitation.depuisCode('inattendu'),
        ErreurInvitation.inconnue,
      );
    });
  });

  // Le plafond horaire d'invitations : corps de réponse de
  // `supabase/functions/README.md § Le plafond de débit`.
  group('Refus de débit (ticket 038)', () {
    const faits = <String, dynamic>{
      'scope': 'station',
      'limit': 60,
      'used': 60,
      'remaining': 0,
      'window_minutes': 60,
      'retry_at': '2026-09-21T15:12:00+00:00',
      'retry_after_seconds': 730,
    };
    const phraseServeur =
        'Limite d\'invitations atteinte (60 par heure pour cette caserne). '
        'Réessaie dans 13 minutes.';

    test('n\'est pas un incident serveur', () {
      expect(
        MotifEchecInvitation.depuisCode('rate_limited'),
        MotifEchecInvitation.debitAtteint,
      );
      expect(
        ErreurInvitation.depuisCode('rate_limited'),
        ErreurInvitation.debitAtteint,
      );
      expect(
        MotifEchecInvitation.debitAtteint.message,
        isNot(AppStrings.inviteErreurServeur),
      );
    });

    test('une adresse refusée affiche la phrase du serveur, délai compris', () {
      final rapport = RapportInvitations.depuisJson(const <String, dynamic>{
        'results': <dynamic>[
          {
            'email': 'recrue@exemple.fr',
            'status': 'error',
            'code': 'rate_limited',
            'message': phraseServeur,
            'rate_limit': faits,
          },
        ],
      });

      final resultat = rapport.resultats.single;
      expect(resultat.enEchec, isTrue);
      expect(resultat.detail, phraseServeur);
      expect(resultat.detail, contains('13 minutes'));
    });

    test('les faits sont lus à côté de la phrase', () {
      final rapport = RapportInvitations.depuisJson(const <String, dynamic>{
        'results': <dynamic>[
          {
            'email': 'recrue@exemple.fr',
            'status': 'error',
            'code': 'rate_limited',
            'message': phraseServeur,
            'rate_limit': faits,
          },
        ],
      });

      final plafond = rapport.resultats.single.plafond!;
      expect(plafond.portee, PorteePlafond.caserne);
      expect(plafond.plafond, 60);
      expect(plafond.utilisees, 60);
      expect(plafond.restantes, 0);
      expect(plafond.fenetreMinutes, 60);
      expect(plafond.delaiAvantNouvelEssai, const Duration(seconds: 730));
      expect(
        plafond.reessayerLe,
        DateTime.parse('2026-09-21T15:12:00+00:00').toLocal(),
      );
    });

    test('sans phrase du serveur, les faits disent encore le délai', () {
      final rapport = RapportInvitations.depuisJson(const <String, dynamic>{
        'results': <dynamic>[
          {
            'email': 'recrue@exemple.fr',
            'status': 'error',
            'code': 'rate_limited',
            'rate_limit': faits,
          },
        ],
      });

      expect(rapport.resultats.single.detail, contains('13 minutes'));
    });

    test('sans phrase ni faits, le refus reste un refus, pas une panne', () {
      final rapport = RapportInvitations.depuisJson(const <String, dynamic>{
        'results': <dynamic>[
          {
            'email': 'recrue@exemple.fr',
            'status': 'error',
            'code': 'rate_limited',
          },
        ],
      });

      expect(rapport.resultats.single.detail, AppStrings.inviteDebitAtteint);
    });

    test('un autre motif garde la phrase de l\'écran', () {
      final rapport = RapportInvitations.depuisJson(const <String, dynamic>{
        'results': <dynamic>[
          {
            'email': 'deja@exemple.fr',
            'status': 'error',
            'code': 'already_member',
            'message': 'Cette personne est déjà membre actif de la caserne.',
          },
        ],
      });

      expect(rapport.resultats.single.detail, AppStrings.inviteDejaMembre);
    });

    test('le refus global 429 porte la même phrase', () {
      final echec = EchecInvitation.depuisCorps(<String, dynamic>{
        'code': 'rate_limited',
        'message': phraseServeur,
        ...faits,
      });

      expect(echec.erreur, ErreurInvitation.debitAtteint);
      expect(echec.message, phraseServeur);
      expect(echec.plafond?.plafond, 60);
      expect(echec.plafond?.portee, PorteePlafond.caserne);
    });

    test('un refus global sans phrase compose le délai depuis les faits', () {
      final echec = EchecInvitation.depuisCorps(<String, dynamic>{
        'code': 'rate_limited',
        ...faits,
      });

      expect(echec.message, contains('13 minutes'));
      expect(echec.message, isNot(AppStrings.erreurTexteGenerique));
    });

    test('le super-administrateur est compté par acteur', () {
      final echec = EchecInvitation.depuisCorps(<String, dynamic>{
        'code': 'rate_limited',
        'scope': 'actor',
        'limit': 200,
        'retry_after_seconds': 45,
      });

      expect(echec.plafond?.portee, PorteePlafond.acteur);
      // Arrondi à la minute supérieure : annoncer moins ferait réessayer
      // pour rien.
      expect(echec.message, contains('une minute'));
    });

    test('un autre refus global garde la phrase de l\'écran', () {
      final echec = EchecInvitation.depuisCorps(<String, dynamic>{
        'code': 'station_suspended',
        'message': 'Abonnement suspendu.',
      });

      expect(echec.message, AppStrings.inviteCaserneSuspendue);
    });
  });

  group('Invitation', () {
    test('lit une ligne de invitations sans jamais attendre le jeton', () {
      final invitation = Invitation.depuisJson(const <String, dynamic>{
        'id': 'i-1',
        'email': 'recrue@exemple.fr',
        'role': 'admin',
        'expires_at': '2026-10-04T13:27:19.268869+00:00',
        'created_at': '2026-09-20T13:27:19.268869+00:00',
      });

      expect(invitation.role, RoleMembre.admin);
      expect(invitation.expireLe.isAfter(invitation.creeLe), isTrue);
      expect(
        invitation.expiree(DateTime.parse('2026-10-05T00:00:00Z')),
        isTrue,
      );
      expect(
        invitation.expiree(DateTime.parse('2026-10-01T00:00:00Z')),
        isFalse,
      );
      // Sans les colonnes de la migration 0035 : on ne sait pas, et surtout
      // pas « non envoyé ».
      expect(invitation.envoiCourriel, EnvoiCourriel.inconnu);
    });

    // Ticket 048 : `email_sent_at` et `email_error` se lisent ensemble
    // (`docs/SCHEMA.md § 2.4`).
    test('la trace de l\'envoi dit trois choses, jamais deux', () {
      Invitation lire(Object? envoye, Object? motif) =>
          Invitation.depuisJson(<String, dynamic>{
            'id': 'i-1',
            'email': 'recrue@exemple.fr',
            'role': 'member',
            'expires_at': '2026-10-04T13:27:19Z',
            'created_at': '2026-09-20T13:27:19Z',
            'email_sent_at': envoye,
            'email_error': motif,
          });

      // Un motif sans date : personne n'a été prévenu.
      expect(
        lire(null, 'no email provider configured').envoiCourriel,
        EnvoiCourriel.nonParti,
      );

      // Une date : c'est parti, à cette date.
      final partie = lire('2026-09-20T13:27:20Z', null);
      expect(partie.envoiCourriel, EnvoiCourriel.parti);
      expect(
        partie.courrielEnvoyeLe,
        DateTime.parse('2026-09-20T13:27:20Z').toLocal(),
      );

      // Les deux : un courriel est parti, le dernier renvoi non. La date fait
      // foi — quelqu'un a bien été prévenu.
      expect(
        lire('2026-09-20T13:27:20Z', 'smtp refused').envoiCourriel,
        EnvoiCourriel.parti,
      );

      // Les deux nuls, et une chaîne vide qui ne vaut pas un motif.
      expect(lire(null, null).envoiCourriel, EnvoiCourriel.inconnu);
      expect(lire(null, '  ').envoiCourriel, EnvoiCourriel.inconnu);
    });
  });

  group('MembreCaserne', () {
    test('joint le profil et ne laisse jamais une ligne muette', () {
      final avecNom = MembreCaserne.depuisJson(const <String, dynamic>{
        'id': 'm-1',
        'user_id': 'u-1',
        'role': 'member',
        'status': 'active',
        'display_name': 'Marie L.',
        'profiles': <String, dynamic>{
          'first_name': 'Marie',
          'last_name': 'Lefebvre',
          'email': 'membre1@caserne-a.test',
        },
      });
      expect(avecNom.libelle, 'Marie Lefebvre');

      final sansNom = MembreCaserne.depuisJson(const <String, dynamic>{
        'id': 'm-2',
        'user_id': 'u-2',
        'role': 'member',
        'status': 'active',
        'profiles': <String, dynamic>{
          'first_name': '',
          'last_name': '',
          'email': 'nouveau@caserne-a.test',
        },
      });
      expect(sansNom.libelle, 'nouveau@caserne-a.test');
    });
  });

  // Le défaut du 21 septembre 2026 : les Edge Functions n'étaient pas
  // déployées, et l'écran envoyait vérifier une connexion qui marchait.
  group('Ce que le serveur répond, et ce que l\'écran en dit', () {
    test('une réponse illisible n\'est jamais une panne de réseau', () {
      // Fonction absente : la passerelle répond 404, sans le corps `error`
      // que composent nos fonctions.
      final absente = traduireEchecFonction(
        const FunctionsHttpException(
          status: 404,
          details: <String, dynamic>{'message': 'Function not found'},
        ),
        enLigne: true,
      );

      expect(absente.erreur, ErreurInvitation.serveurIndisponible);
      expect(absente.message, isNot(AppStrings.erreurReseauTexte));
      expect(absente.message, isNot(contains('connexion, puis réessaie')));

      // Un corps qui n'est même pas une table : même verdict.
      expect(
        traduireEchecFonction(
          const FunctionsHttpException(status: 403, details: 'Forbidden'),
          enLigne: true,
        ).erreur,
        ErreurInvitation.serveurIndisponible,
      );

      // Un incident interne, lui, peut passer tout seul : on garde « réessaie
      // dans un instant », qui ne promet toujours pas de cause.
      expect(
        traduireEchecFonction(
          const FunctionsHttpException(status: 502, details: 'Bad gateway'),
          enLigne: true,
        ).erreur,
        ErreurInvitation.inconnue,
      );
    });

    test('le corps typé des fonctions garde la main', () {
      final refus = traduireEchecFonction(
        const FunctionsHttpException(
          status: 403,
          details: <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'station_suspended',
              'message': 'Station suspended',
            },
          },
        ),
        enLigne: true,
      );

      expect(refus.erreur, ErreurInvitation.caserneSuspendue);
    });

    test('sans réponse, on ne parle de connexion que si le navigateur l\'a '
        'affirmé', () {
      // Hors ligne : le « non » du navigateur est sûr, la phrase peut nommer
      // la connexion.
      expect(
        traduireEchecFonction(
          const FunctionsFetchException(details: 'Failed to fetch'),
          enLigne: false,
        ).erreur,
        ErreurInvitation.reseau,
      );

      // En ligne et pourtant rien : c'est ce que voit le navigateur quand il
      // bloque la réponse d'une fonction absente. On ne sait pas, on le dit.
      final muet = traduireEchecFonction(
        const FunctionsFetchException(details: 'Failed to fetch'),
        enLigne: true,
      );
      expect(muet.erreur, ErreurInvitation.sansReponse);
      expect(muet.message, isNot(AppStrings.erreurReseauTexte));
    });
  });
}
