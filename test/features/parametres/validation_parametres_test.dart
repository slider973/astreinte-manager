import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/features/parametres/domain/parametres_caserne.dart';
import 'package:astreinte_sp/features/parametres/domain/validation_parametres.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_parametres.dart';

/// Les bornes vérifiées ici sont **exactement** celles de la contrainte SQL
/// `stations_settings_valide` (migration `0011`,
/// `supabase/tests/station_settings_test.sql`). Les deux listes de cas se
/// répondent volontairement : si l'une change sans l'autre, l'écran promet ce
/// que la base refuse.
void main() {
  group('validerParametres', () {
    test('les réglages du seed passent', () {
      expect(validerParametres(parametresSeed), isEmpty);
    });

    test('un nom vide ou blanc est refusé', () {
      expect(
        validerParametres(
          parametresSeed.copyWith(nom: '   '),
        )[ChampParametre.nom],
        AppStrings.parametresNomVide,
      );
    });

    test('un nom de plus de 80 caractères est refusé', () {
      expect(
        validerParametres(
          parametresSeed.copyWith(nom: 'x' * 81),
        )[ChampParametre.nom],
        AppStrings.parametresNomLong,
      );
      expect(
        validerParametres(parametresSeed.copyWith(nom: 'x' * 80)),
        isEmpty,
      );
    });

    test('un fuseau hors de la liste est refusé', () {
      expect(
        validerParametres(
          parametresSeed.copyWith(fuseau: 'Europe/Pariss'),
        )[ChampParametre.fuseau],
        AppStrings.parametresFuseauInconnu,
      );
    });

    test('une heure mal écrite est refusée', () {
      for (final heure in <String>['7:00', '25:00', '07:60', '0700', '']) {
        expect(
          validerParametres(
            parametresSeed.copyWith(debutJour: heure),
          )[ChampParametre.debutJour],
          AppStrings.parametresHeureInvalide,
          reason: heure,
        );
      }
    });

    test('un jour qui commence et finit à la même heure est refusé', () {
      final erreurs = validerParametres(
        parametresSeed.copyWith(finJour: '07:00'),
      );
      expect(
        erreurs[ChampParametre.finJour],
        AppStrings.parametresHeuresIdentiques,
      );
    });

    test('un effectif hors de 0 à 50 est refusé', () {
      expect(
        validerParametres(
          parametresSeed.copyWith(effectifJour: 51),
        )[ChampParametre.effectifJour],
        AppStrings.parametresEffectifBorne,
      );
      expect(
        validerParametres(
          parametresSeed.copyWith(effectifNuit: -1),
        )[ChampParametre.effectifNuit],
        AppStrings.parametresEffectifBorne,
      );
      expect(
        validerParametres(parametresSeed.copyWith(effectifJour: 0)),
        isEmpty,
      );
    });

    test('le jour limite va du 1 au 28', () {
      expect(
        validerParametres(parametresSeed.copyWith(jourLimite: 28)),
        isEmpty,
      );
      for (final jour in <int>[0, 29, 31]) {
        expect(
          validerParametres(
            parametresSeed.copyWith(jourLimite: jour),
          )[ChampParametre.jourLimite],
          AppStrings.parametresJourLimiteBorne,
          reason: '$jour',
        );
      }
    });

    test('un délai de relance va de 1 à 336 heures', () {
      expect(
        validerParametres(
          parametresSeed.copyWith(relancePushHeures: 0),
        )[ChampParametre.relancePush],
        AppStrings.parametresDelaiBorne,
      );
      expect(
        validerParametres(
          parametresSeed.copyWith(rapportRetardHeures: 400),
        )[ChampParametre.rapportRetard],
        AppStrings.parametresDelaiBorne,
      );
      expect(
        validerParametres(parametresSeed.copyWith(relanceEmailHeures: 336)),
        isEmpty,
      );
    });

    test('une surcharge vide est refusée', () {
      final avecVide = parametresSeed.copyWith(
        surcharges: const <SurchargeEffectif>[SurchargeEffectif(cle: 'sat')],
      );
      expect(
        validerParametres(avecVide)[ChampParametre.surcharges],
        AppStrings.parametresSurchargeIncomplete,
      );
    });

    test('une clé de surcharge inconnue est refusée', () {
      final avecCleFausse = parametresSeed.copyWith(
        surcharges: const <SurchargeEffectif>[
          SurchargeEffectif(cle: 'samedi', effectifJour: 2),
        ],
      );
      expect(
        validerParametres(avecCleFausse)[ChampParametre.surcharges],
        AppStrings.parametresDateInvalide,
      );
    });

    test('des surcharges légitimes passent', () {
      final avecSurcharges = parametresSeed.copyWith(
        surcharges: const <SurchargeEffectif>[
          SurchargeEffectif(cle: 'sat', effectifJour: 2),
          SurchargeEffectif(cle: '2026-12-31', effectifNuit: 3),
        ],
      );
      expect(validerParametres(avecSurcharges), isEmpty);
    });
  });

  group('cleSurchargeValide', () {
    test('les sept jours de semaine', () {
      for (final jour in JourSemaine.values) {
        expect(cleSurchargeValide(jour.cle), isTrue, reason: jour.cle);
      }
    });

    test('une date réelle, et seulement une date réelle', () {
      expect(cleSurchargeValide('2026-12-31'), isTrue);
      expect(cleSurchargeValide('2026-02-30'), isFalse);
      expect(cleSurchargeValide('31/12/2026'), isFalse);
      expect(cleSurchargeValide('2026-1-5'), isFalse);
    });
  });

  group('lireDateCourte', () {
    test('lit une date française', () {
      expect(lireDateCourte('31/12/2026'), DateTime(2026, 12, 31));
    });

    test('refuse une date qui n\'existe pas', () {
      expect(lireDateCourte('30/02/2026'), isNull);
      expect(lireDateCourte('32/01/2026'), isNull);
      expect(lireDateCourte('01/13/2026'), isNull);
      expect(lireDateCourte('1/1/2026'), isNull);
      expect(lireDateCourte(''), isNull);
    });
  });

  group('ParametresCaserne', () {
    test('lit la ligne PostgREST, surcharges comprises', () {
      final parametres = ParametresCaserne.depuisJson(const <String, dynamic>{
        'id': 'station-1',
        'name': 'CIS Val-de-Loue',
        'timezone': 'Indian/Reunion',
        'settings': <String, dynamic>{
          'day_start': '08:00',
          'day_end': '20:00',
          'required_day': 2,
          'required_night': 3,
          'availability_deadline_day': 10,
          'response_reminder_hours': 12,
          'response_email_hours': 24,
          'late_report_hours': 48,
          'required_overrides': <String, dynamic>{
            '2026-12-31': <String, dynamic>{'night': 4},
            'sat': <String, dynamic>{'day': 2, 'night': 3},
          },
        },
      });

      expect(parametres.nom, 'CIS Val-de-Loue');
      expect(parametres.fuseau, 'Indian/Reunion');
      expect(parametres.effectifNuit, 3);
      expect(parametres.jourLimite, 10);
      // Les jours de semaine d'abord, les dates ensuite.
      expect(
        parametres.surcharges.map((SurchargeEffectif s) => s.cle),
        const <String>['sat', '2026-12-31'],
      );
      expect(parametres.surchargeDe(JourSemaine.samedi)?.effectifJour, 2);
      expect(parametres.surchargesDatees.single.effectifNuit, 4);
    });

    test('une clé absente reprend le défaut plutôt que de casser l\'écran', () {
      final parametres = ParametresCaserne.depuisJson(const <String, dynamic>{
        'id': 'station-1',
        'name': 'CIS Saint-Martin',
        'settings': <String, dynamic>{'required_day': 4},
      });

      expect(parametres.effectifJour, 4);
      expect(parametres.debutJour, ParametresCaserne.defauts.debutJour);
      expect(parametres.jourLimite, ParametresCaserne.defauts.jourLimite);
      expect(parametres.fuseau, 'Europe/Paris');
    });

    test('le document écrit ne porte les surcharges que s\'il y en a', () {
      expect(
        parametresSeed.settingsJson.containsKey('required_overrides'),
        isFalse,
      );

      final avec = parametresSeed.avecSurcharge(
        const SurchargeEffectif(cle: 'sat', effectifJour: 2),
      );
      expect(avec.settingsJson['required_overrides'], const <String, dynamic>{
        'sat': <String, dynamic>{'day': 2},
      });
    });

    test('une surcharge vidée est retirée du document', () {
      final avec = parametresSeed.avecSurcharge(
        const SurchargeEffectif(cle: 'sat', effectifJour: 2),
      );
      final sans = avec.avecSurcharge(const SurchargeEffectif(cle: 'sat'));

      expect(sans.surcharges, isEmpty);
      expect(sans.settingsJson.containsKey('required_overrides'), isFalse);
    });

    test(
      'deux documents identiques sont égaux — c\'est ce qui dit « modifié »',
      () {
        expect(parametresSeed.copyWith(effectifJour: 1), parametresSeed);
        expect(
          parametresSeed.copyWith(effectifJour: 2) == parametresSeed,
          isFalse,
        );
        expect(
          parametresSeed.avecSurcharge(
                const SurchargeEffectif(cle: 'sat', effectifJour: 2),
              ) ==
              parametresSeed,
          isFalse,
        );
      },
    );

    test('les clés que l\'écran ne connaît pas font l\'aller-retour', () {
      final parametres = ParametresCaserne.depuisJson(<String, dynamic>{
        'id': 'station-1',
        'name': 'CIS Saint-Martin',
        'settings': <String, dynamic>{
          ...parametresSeed.settingsJson,
          // Le plafond horaire d'invitations (ticket 038) : réglé en base,
          // jamais montré par cet écran.
          'invitation_hourly_limit': 120,
          'cle_inconnue': 'valeur',
        },
      });

      expect(parametres.autresReglages, <String, dynamic>{
        'invitation_hourly_limit': 120,
        'cle_inconnue': 'valeur',
      });
      expect(parametres.settingsJson['invitation_hourly_limit'], 120);
      expect(parametres.settingsJson['cle_inconnue'], 'valeur');

      // Modifier un champ de l'écran n'en efface aucune.
      final modifie = parametres.copyWith(effectifJour: 4);
      expect(modifie.settingsJson['invitation_hourly_limit'], 120);
      expect(modifie.settingsJson['required_day'], 4);
    });

    test('une clé inconnue ne peut pas écraser un réglage de l\'écran', () {
      final parametres = ParametresCaserne.depuisJson(const <String, dynamic>{
        'id': 'station-1',
        'name': 'CIS Saint-Martin',
        'settings': <String, dynamic>{'required_day': 2, 'day_start': '06:00'},
      });

      expect(parametres.autresReglages, isEmpty);
      expect(parametres.settingsJson['required_day'], 2);
      expect(parametres.settingsJson['day_start'], '06:00');
    });

    test('deux documents ne diffèrent pas que par ce qu\'ils montrent', () {
      final avec = ParametresCaserne.depuisJson(<String, dynamic>{
        'id': parametresSeed.stationId,
        'name': parametresSeed.nom,
        'settings': <String, dynamic>{
          ...parametresSeed.settingsJson,
          'invitation_hourly_limit': 120,
        },
      });

      expect(avec == parametresSeed, isFalse);
      expect(avec.copyWith(), avec);
    });

    test('l\'aller-retour JSON conserve tout', () {
      final origine = ParametresCaserne.depuisJson(<String, dynamic>{
        'id': parametresSeed.stationId,
        'name': parametresSeed.nom,
        'timezone': parametresSeed.fuseau,
        'settings': <String, dynamic>{
          ...parametresSeed.settingsJson,
          'invitation_hourly_limit': 120,
        },
      }).copyWith(effectifJour: 3, jourLimite: 20).avecSurcharge(
        const SurchargeEffectif(cle: 'sun', effectifNuit: 2),
      );

      final relu = ParametresCaserne.depuisJson(<String, dynamic>{
        'id': origine.stationId,
        'name': origine.nom,
        'timezone': origine.fuseau,
        'settings': origine.settingsJson,
      });

      expect(relu, origine);
    });
  });
}
