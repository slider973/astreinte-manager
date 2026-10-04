/// Le domaine des échanges d'astreintes (ticket 073) : lecture d'une ligne,
/// vues composées, phrases des refus et des échecs, charge après échange,
/// échéance annoncée, réglages, liens profonds. Tout est pur.
library;

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/features/echanges/data/echanges_repository.dart';
import 'package:astreinte_sp/features/echanges/domain/cause_echange.dart';
import 'package:astreinte_sp/features/echanges/domain/charge_echange.dart';
import 'package:astreinte_sp/features/echanges/domain/demande_echange.dart';
import 'package:astreinte_sp/features/echanges/domain/echange.dart';
import 'package:astreinte_sp/features/echanges/domain/echanges_providers.dart';
import 'package:astreinte_sp/features/echanges/domain/filtre_echanges.dart';
import 'package:astreinte_sp/features/echanges/domain/issue_echange.dart';
import 'package:astreinte_sp/features/notifications/domain/destination_push.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:astreinte_sp/features/parametres/domain/parametres_caserne.dart';
import 'package:astreinte_sp/features/parametres/domain/validation_parametres.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_echanges.dart';

void main() {
  group('Echange.depuisJson', () {
    final ligne = <String, dynamic>{
      'id': 'ech-1',
      'station_id': 'st-1',
      'kind': 'swap',
      'status': 'accepted_by_peer',
      'requester_id': 'u-a',
      'assignment_id': 'att-a',
      'shift_id': 'c-a',
      'target_id': 'u-b',
      'return_assignment_id': 'att-b',
      'return_shift_id': 'c-b',
      'taker_id': 'u-b',
      'auto_approved': false,
      'decided_by': null,
      'reason_code': null,
      'reason': null,
      'expires_at': '2026-10-23T17:00:00Z',
      'accepted_at': '2026-10-05T07:02:00Z',
      'decided_at': null,
      'closed_at': null,
      'created_at': '2026-10-04T19:14:00Z',
      'garde': <String, dynamic>{'date': '2026-10-24', 'slot': 'night'},
      'rendue': <String, dynamic>{'date': '2026-10-27', 'slot': 'day'},
    };

    test('lit les deux gardes, les acteurs et les noms', () {
      final e = Echange.depuisJson(
        ligne,
        noms: const <String, String>{'u-a': 'Antoine C.', 'u-b': 'Chloé C.'},
      )!;
      expect(e.forme, FormeEchange.echange);
      expect(e.statut, StatutEchange.accepteParPair);
      expect(e.garde.jour, DateTime(2026, 10, 24));
      expect(e.garde.creneau, CreneauType.nuit);
      expect(e.garde.attributionId, 'att-a');
      expect(e.gardeRendue!.creneau, CreneauType.jour);
      expect(e.gardeRendue!.attributionId, 'att-b');
      expect(e.demandeurNom, 'Antoine C.');
      expect(e.pairNom, 'Chloé C.');
      expect(e.lecteur('u-a'), LecteurEchange.demandeur);
      expect(e.lecteur('u-b'), LecteurEchange.pair);
      expect(e.lecteur('u-admin'), LecteurEchange.admin);
    });

    test('rend null quand le créneau cédé est illisible', () {
      final sans = Map<String, dynamic>.of(ligne)..['garde'] = null;
      expect(Echange.depuisJson(sans), isNull);
    });

    test('un statut inconnu ne laisse aucun bouton', () {
      expect(StatutEchange.depuisSql('swapped').enCours, isFalse);
    });

    test('les colonnes lues sont celles de docs/SCHEMA.md § 2.19', () {
      for (final colonne in <String>[
        'kind',
        'status',
        'requester_id',
        'assignment_id',
        'target_id',
        'return_assignment_id',
        'taker_id',
        'auto_approved',
        'decided_by',
        'reason_code',
        'reason',
        'expires_at',
        'accepted_at',
        'decided_at',
        'closed_at',
      ]) {
        expect(Echange.colonnes, contains(colonne));
      }
    });
  });

  group('EtatEchanges', () {
    const moi = 'u-chloe';
    final aujourdhui = DateTime(2026, 10, 4);

    test('recues : à moi ou à la caserne, jamais les miennes', () {
      final etat = EtatEchanges(
        moi: moi,
        echanges: <Echange>[
          echange(id: 'a-moi'),
          echange(id: 'caserne', cibleId: null, cibleNom: null),
          echange(
            id: 'la-mienne',
            demandeurId: moi,
            cibleId: null,
            cibleNom: null,
          ),
          echange(id: 'acceptee', statut: StatutEchange.accepteParPair),
        ],
      );
      expect(
        etat.recues.map((Echange e) => e.id),
        unorderedEquals(<String>['a-moi', 'caserne']),
      );
    });

    test('suivies : à valider, puis ouvertes, puis terminées à venir', () {
      final etat = EtatEchanges(
        moi: 'u-antoine',
        echanges: <Echange>[
          echange(id: 'ouverte'),
          echange(
            id: 'refusee',
            statut: StatutEchange.refuse,
            decideLe: DateTime(2026, 10, 3),
          ),
          echange(id: 'a-valider', statut: StatutEchange.accepteParPair),
          echange(
            id: 'passee',
            statut: StatutEchange.expire,
            jour: DateTime(2026, 9),
          ),
        ],
      );
      expect(etat.suivies(aujourdhui).map((Echange e) => e.id), <String>[
        'a-valider',
        'ouverte',
        'refusee',
      ]);
    });

    test('enCoursSur trouve la garde cédée et la garde rendue', () {
      final etat = EtatEchanges(
        moi: moi,
        echanges: <Echange>[
          echange(
            gardeRendue: GardeEchange(
              jour: DateTime(2026, 10, 27),
              creneau: CreneauType.jour,
              attributionId: 'att-b',
            ),
          ),
        ],
      );
      expect(etat.enCoursSur('att-a'), isNotNull);
      expect(etat.enCoursSur('att-b'), isNotNull);
      expect(etat.enCoursSur('att-x'), isNull);
    });

    test('la file de l\'administrateur range par statut', () {
      final etat = EtatEchanges(
        moi: 'u-admin',
        echanges: <Echange>[
          echange(id: 'o'),
          echange(id: 'v', statut: StatutEchange.accepteParPair),
          echange(id: 't', statut: StatutEchange.valide),
        ],
      );
      expect(etat.aValider.single.id, 'v');
      expect(etat.enAttente.single.id, 'o');
      expect(etat.termines.single.id, 't');
    });
  });

  group('Les causes, en français et sans code', () {
    test('une phrase par motif de la liste fermée', () {
      expect(
        causeEchange('peer_weekend_quota_reached', nomPair: 'Chloé C.'),
        AppStrings.echangeCausePlafondWeekends('Chloé C.'),
      );
      expect(
        causeEchange('requester_already_assigned', nomDemandeur: 'Antoine C.'),
        AppStrings.echangeCauseDejaPris('Antoine C.'),
      );
      expect(
        causeEchange('assignment_changed'),
        AppStrings.echangeCauseGardeChangee,
      );
      expect(
        causeEchange('station_suspended'),
        AppStrings.echangeCauseSuspendue,
      );
      expect(causeEchange('inconnu'), AppStrings.echangeCauseAutre);
    });

    test('« pris ailleurs » ne se dit qu\'à l\'administrateur', () {
      expect(
        causeEchange(
          'peer_already_assigned',
          nomPair: 'Chloé C.',
          detail: 'peer_taken_elsewhere',
        ),
        AppStrings.echangeCauseDejaPris('Chloé C.'),
      );
      expect(
        causeEchange(
          'peer_already_assigned',
          nomPair: 'Chloé C.',
          detail: 'peer_taken_elsewhere',
          pourAdmin: true,
        ),
        AppStrings.echangeCauseAilleurs,
      );
    });

    test('les règles de la demande parlent à A quand who = requester', () {
      expect(
        causeEchange('weekend_quota_reached', qui: 'requester'),
        AppStrings.echangeCauseToiPlafondWeekends,
      );
      expect(
        causeEchange('weekend_quota_reached', qui: 'target', nomPair: 'Chloé'),
        AppStrings.echangeCausePlafondWeekends('Chloé'),
      );
    });

    test('aucune phrase ne dit « ailleurs » à un pompier', () {
      for (final code in <String>[
        'peer_already_assigned',
        'requester_already_assigned',
        'already_assigned',
      ]) {
        expect(causeEchange(code, nomPair: 'B'), isNot(contains('ailleurs')));
      }
    });
  });

  group('Les issues des quatre gestes', () {
    const chloe = Collegue(userId: 'u-chloe', nom: 'Chloé C.');

    test('demande : envoyée, à la caserne, personne prévenu', () {
      expect(
        issueDemande(const ResultatEchange(ok: true, notifies: 1), cible: chloe)
            .message,
        AppStrings.echangeEnvoyeeA('Chloé C.'),
      );
      expect(
        issueDemande(const ResultatEchange(ok: true, notifies: 4)).message,
        AppStrings.echangeEnvoyeeCaserne,
      );
      final personne = issueDemande(
        const ResultatEchange(ok: true, notifies: 0),
      );
      expect(personne.ok, isTrue);
      expect(personne.ton, TonIssue.information);
      expect(personne.message, AppStrings.echangeEnvoyeePersonne);
    });

    test('demande refusée : la cause et la sortie', () {
      final issue = issueDemande(
        const ResultatEchange(
          ok: false,
          code: 'weekend_quota_reached',
          qui: 'target',
        ),
        cible: chloe,
      );
      expect(issue.ton, TonIssue.erreur);
      expect(
        issue.message,
        AppStrings.echangeEnvoiRefuse(
          AppStrings.echangeCausePlafondWeekends('Chloé C.'),
        ),
      );
      expect(issue.detail, AppStrings.echangeEnvoiRefuseAide);
    });

    test('réponse : accord, validation automatique, refus', () {
      final e = echange();
      expect(
        issueReponse(
          const ResultatEchange(ok: true, statut: StatutEchange.accepteParPair),
          e,
          accepte: true,
        ).message,
        AppStrings.echangeAccordEnvoye,
      );
      final auto = issueReponse(
        const ResultatEchange(ok: true, statut: StatutEchange.valide),
        e,
        accepte: true,
      );
      expect(auto.valideMaintenant, isTrue);
      expect(auto.message, contains('est à toi'));
      expect(
        issueReponse(
          const ResultatEchange(ok: true, statut: StatutEchange.refuse),
          e,
          accepte: false,
        ).message,
        AppStrings.echangeRefusEnvoye('Antoine C.'),
      );
    });

    test('réponse : une course perdue est une information, jamais un rouge', () {
      final prise = issueReponse(
        const ResultatEchange(
          ok: false,
          code: 'exchange_not_open',
          statut: StatutEchange.accepteParPair,
        ),
        echange(cibleId: null, cibleNom: null),
        accepte: true,
      );
      expect(prise.ton, TonIssue.information);
      expect(prise.retiree, isTrue);
      expect(prise.message, AppStrings.echangeDejaReprise);

      final annulee = issueReponse(
        const ResultatEchange(
          ok: false,
          code: 'exchange_not_open',
          statut: StatutEchange.annule,
        ),
        echange(),
        accepte: true,
      );
      expect(annulee.message, AppStrings.echangeAnnuleeParA('Antoine C.'));
    });

    test('réponse : une règle refuse en erreur, la carte reste', () {
      final regle = issueReponse(
        const ResultatEchange(ok: false, code: 'weekend_quota_reached'),
        echange(),
        accepte: true,
      );
      expect(regle.ton, TonIssue.erreur);
      expect(regle.retiree, isFalse);
      expect(regle.message, AppStrings.echangeTonPlafondWeekends);
    });

    test('annulation trop tard', () {
      expect(
        issueAnnulation(
          const ResultatEchange(
            ok: false,
            code: 'exchange_not_open',
            statut: StatutEchange.valide,
          ),
        ).message,
        AppStrings.echangeAnnulerTropTard,
      );
    });

    test('décision : validé, refusé, sa propre demande, échec', () {
      final e = echange(
        statut: StatutEchange.accepteParPair,
        repreneurId: 'u-chloe',
        repreneurNom: 'Chloé C.',
      );
      expect(
        issueDecision(
          const ResultatEchange(ok: true, statut: StatutEchange.valide),
          e,
          valide: true,
        ).message,
        AppStrings.echangesValide('Antoine C.', 'Chloé C.'),
      );
      expect(
        issueDecision(
          const ResultatEchange(ok: false, code: 'cannot_decide_own_exchange'),
          e,
          valide: true,
        ).message,
        AppStrings.echangesPasSaDecision,
      );
      expect(
        issueDecision(
          const ResultatEchange(
            ok: false,
            code: 'exchange_failed',
            codeMotif: 'peer_already_assigned',
            detail: 'peer_taken_elsewhere',
          ),
          e,
          valide: true,
        ).message,
        AppStrings.echangesEchec(AppStrings.echangeCauseAilleurs),
      );
    });
  });

  group('La charge après l\'échange', () {
    LigneMatrice ligne(String userId, {int n = 3, int w = 1, int? max}) =>
        LigneMatrice.depuisJson(<String, dynamic>{
          'user_id': userId,
          'display_name': userId,
          'max_shifts': max,
          'max_weekends': 2,
          'shifts_count': n,
          'weekend_units': w,
          'day_slots': '.' * 31,
          'night_slots': '${'.' * 23}D${'.' * 7}',
        });

    test('cession : B prend une garde, A libère la sienne', () {
      final e = echange(
        statut: StatutEchange.accepteParPair,
        repreneurId: 'u-chloe',
        repreneurNom: 'Chloé C.',
      );
      final charge = chargeApresEchange(
        e,
        (String cle, String id) => ligne(id, max: 4),
      );
      final b = charge.firstWhere((ChargePersonne p) => p.userId == 'u-chloe');
      final a = charge.firstWhere((ChargePersonne p) => p.userId == 'u-antoine');
      expect(b.astreintes, 4);
      expect(b.depasseAstreintes, isFalse);
      expect(b.disponibilite, DisponibiliteEtat.disponible);
      // Samedi 24 octobre : une unité de weekend de plus, au plus.
      expect(b.unitesWeekend, 2);
      expect(a.libere, isTrue);
      expect(a.astreintes, 2);
    });

    test('un plafond d\'astreintes dépassé est bloquant', () {
      final e = echange(
        statut: StatutEchange.accepteParPair,
        repreneurId: 'u-chloe',
      );
      final charge = chargeApresEchange(
        e,
        (String cle, String id) => ligne(id, n: 4, max: 4),
      );
      expect(
        charge.firstWhere((ChargePersonne p) => p.userId == 'u-chloe')
            .depasseAstreintes,
        isTrue,
      );
    });

    test('échange dans le même mois : chacun garde sa charge', () {
      final e = echange(
        forme: FormeEchange.echange,
        statut: StatutEchange.accepteParPair,
        repreneurId: 'u-chloe',
        gardeRendue: GardeEchange(
          jour: DateTime(2026, 10, 27),
          creneau: CreneauType.jour,
        ),
      );
      final charge = chargeApresEchange(
        e,
        (String cle, String id) => ligne(id, max: 3),
      );
      expect(charge, hasLength(2));
      expect(charge.every((ChargePersonne p) => p.astreintes == 3), isTrue);
      expect(charge.any((ChargePersonne p) => p.depasseAstreintes), isFalse);
    });
  });

  group('Proposer : proposable, échéance, blocages', () {
    final nuit = astreinte(
      id: 'att-a',
      jour: DateTime(2026, 10, 24),
      planningEtat: PlanningEtat.publie,
    );

    test('l\'échéance est le début du créneau moins le réglage', () {
      const reglages = ReglagesEchange.defaut; // 24 h
      expect(
        reglages.echeance(<GardeEchange>[gardeDe(nuit)]),
        DateTime(2026, 10, 23, 19),
      );
    });

    test('une astreinte passée ou archivée n\'est pas proposable', () {
      expect(proposable(nuit, DateTime(2026, 10, 4)), isTrue);
      expect(proposable(nuit, DateTime(2026, 10, 25)), isFalse);
      expect(
        proposable(
          astreinte(
            id: 'x',
            jour: DateTime(2026, 10, 24),
            planningEtat: PlanningEtat.archive,
          ),
          DateTime(2026, 10, 4),
        ),
        isFalse,
      );
    });

    test('la caserne, puis le réseau, puis l\'échéance', () {
      BlocageProposition? b({
        bool enLigne = true,
        bool lectureSeule = false,
        DateTime? maintenant,
      }) => blocageProposition(
        astreinte: nuit,
        reglages: ReglagesEchange.defaut,
        maintenant: maintenant ?? DateTime(2026, 10, 4),
        enLigne: enLigne,
        lectureSeule: lectureSeule,
      );
      expect(b(), isNull);
      expect(
        b(enLigne: false, lectureSeule: true),
        BlocageProposition.lectureSeule,
      );
      expect(b(enLigne: false), BlocageProposition.horsLigne);
      expect(
        b(maintenant: DateTime(2026, 10, 23, 20)),
        BlocageProposition.tropTard,
      );
    });
  });

  group('Les réglages d\'échange de la caserne', () {
    test('absents, ils restent absents à l\'écriture', () {
      final p = ParametresCaserne.depuisJson(const <String, dynamic>{
        'id': 'st',
        'name': 'CIS',
        'settings': <String, dynamic>{'day_start': '07:00'},
      });
      expect(p.echangeAuto, isFalse);
      expect(p.echangeEcheanceHeures, 24);
      expect(p.settingsJson.containsKey('exchange_auto_approve'), isFalse);
      expect(p.settingsJson.containsKey('exchange_deadline_hours'), isFalse);
    });

    test('lus et réécrits même quand on n\'y touche pas', () {
      final p = ParametresCaserne.depuisJson(const <String, dynamic>{
        'id': 'st',
        'name': 'CIS',
        'settings': <String, dynamic>{
          'exchange_auto_approve': true,
          'exchange_deadline_hours': 48,
        },
      });
      final ecrit = p.copyWith(effectifJour: 3).settingsJson;
      expect(ecrit['exchange_auto_approve'], isTrue);
      expect(ecrit['exchange_deadline_hours'], 48);
      expect(p.autresReglages.containsKey('exchange_auto_approve'), isFalse);
    });

    test('l\'échéance est bornée de 1 à 168 heures', () {
      final p = ParametresCaserne.defauts.copyWith(nom: 'CIS');
      expect(
        validerParametres(p.copyWith(echangeEcheanceHeures: 169)),
        contains(ChampParametre.echeanceEchange),
      );
      expect(
        validerParametres(p.copyWith(echangeEcheanceHeures: 168)),
        isNot(contains(ChampParametre.echeanceEchange)),
      );
    });
  });

  group('Liens profonds et notifications', () {
    test('/exchanges mène aux propositions de la Boîte', () {
      expect(
        destinationInterne('/exchanges', admin: false),
        AppRoutes.boiteOnglet(OngletBoite.propositions),
      );
    });

    test('/admin/exchanges : la file pour un admin, rien pour un membre', () {
      expect(
        destinationInterne('/admin/exchanges', admin: true),
        AppRoutes.echangesAdminFiltre(FiltreEchanges.aValider),
      );
      expect(destinationInterne('/admin/exchanges', admin: false), isNull);
    });

    test('une demande reçue est une question, ses issues des rappels', () {
      expect(TypeNotification.echangeDemande.estProposition, isTrue);
      for (final issue in <TypeNotification>[
        TypeNotification.echangeAccepte,
        TypeNotification.echangeValide,
        TypeNotification.echangeRefuse,
        TypeNotification.echangeClos,
      ]) {
        expect(issue.estProposition, isFalse);
      }
    });

    test('le filtre se lit dans l\'adresse, « À valider » par défaut', () {
      expect(FiltreEchanges.depuisUrl('termines'), FiltreEchanges.termines);
      expect(FiltreEchanges.depuisUrl('???'), FiltreEchanges.aValider);
      expect(EtapeDemande.depuisUrl('verifier'), EtapeDemande.verifier);
      expect(EtapeDemande.depuisUrl(null), EtapeDemande.qui);
    });
  });
}
