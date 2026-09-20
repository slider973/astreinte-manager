import 'package:astreinte_sp/core/l10n/jours_feries.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/disponibilite_mois.dart';
import 'package:astreinte_sp/features/dispos/domain/raccourci.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_dispos.dart';

DisponibiliteMois moisVide(int annee, int mois) =>
    DisponibiliteMois.vide(annee: annee, mois: mois);

DisponibiliteMois moisAvec(
  int annee,
  int mois,
  Map<CreneauCle, DisponibiliteEtat> valeurs,
) => DisponibiliteMois(annee: annee, mois: mois, valeurs: valeurs);

void main() {
  group('« Tous les weekends, nuit »', () {
    test('coche exactement les samedis et dimanches nuit', () {
      final periode = periodeOuverte(annee: 2026, mois: 10);

      final modifications = modificationsRaccourci(
        periode: periode,
        portee: PorteeRaccourci.weekends,
        cible: CibleCreneau.nuit,
        courant: moisVide(2026, 10),
      );

      // Octobre 2026 : 4 samedis (3, 10, 17, 24, 31 → 5) et 4 dimanches.
      final attendues = <CreneauCle>{
        for (final jour in periode.jours)
          if (jour.weekday == DateTime.saturday ||
              jour.weekday == DateTime.sunday)
            CreneauCle(jour, CreneauType.nuit),
      };

      expect(modifications.keys.toSet(), attendues);
      expect(
        modifications.values.every(
          (etat) => etat == DisponibiliteEtat.disponible,
        ),
        isTrue,
      );
      // Aucune case « jour », aucun jour de semaine.
      expect(
        modifications.keys.every(
          (cle) =>
              cle.creneau == CreneauType.nuit &&
              (cle.date.weekday == DateTime.saturday ||
                  cle.date.weekday == DateTime.sunday),
        ),
        isTrue,
      );
    });

    test(
      'n\'inclut pas un jour férié tombant en semaine — décision du ticket',
      () {
        // Mai 2026 : 1er mai (vendredi), 8 mai (vendredi), Ascension le 14 mai
        // (jeudi), lundi de Pentecôte le 25 mai. Quatre fériés en semaine.
        final periode = periodeOuverte(annee: 2026, mois: 5);
        final feriesEnSemaine = <DateTime>[
          for (final jour in periode.jours)
            if (estJourFerie(jour) &&
                jour.weekday != DateTime.saturday &&
                jour.weekday != DateTime.sunday)
              jour,
        ];
        expect(
          feriesEnSemaine,
          isNotEmpty,
          reason: 'le mois de test doit contenir un férié en semaine',
        );

        final weekends = modificationsRaccourci(
          periode: periode,
          portee: PorteeRaccourci.weekends,
          cible: CibleCreneau.lesDeux,
          courant: moisVide(2026, 5),
        );
        for (final ferie in feriesEnSemaine) {
          expect(
            weekends.containsKey(CreneauCle(ferie, CreneauType.jour)),
            isFalse,
            reason: '« Les weekends » est calendaire, pas comptable',
          );
        }

        // Et la portée « semaine » les reprend : les deux portées partagent
        // le mois sans trou ni recouvrement.
        final semaine = modificationsRaccourci(
          periode: periode,
          portee: PorteeRaccourci.semaine,
          cible: CibleCreneau.lesDeux,
          courant: moisVide(2026, 5),
        );
        for (final ferie in feriesEnSemaine) {
          expect(
            semaine.containsKey(CreneauCle(ferie, CreneauType.jour)),
            isTrue,
          );
        }

        final mois = modificationsRaccourci(
          periode: periode,
          portee: PorteeRaccourci.moisEntier,
          cible: CibleCreneau.lesDeux,
          courant: moisVide(2026, 5),
        );
        expect(
          weekends.length + semaine.length,
          mois.length,
          reason: 'weekends ∪ semaine = tout le mois, sans recouvrement',
        );
      },
    );
  });

  group('Les portées', () {
    test('« la semaine » couvre du lundi au vendredi', () {
      final periode = periodeOuverte(annee: 2026, mois: 10);
      final jours = joursDeLaPortee(periode, PorteeRaccourci.semaine);

      expect(jours, isNotEmpty);
      expect(jours.every((jour) => jour.weekday <= DateTime.friday), isTrue);
    });

    test('« tout le mois » couvre les 31 jours d\'octobre, deux créneaux', () {
      final modifications = modificationsRaccourci(
        periode: periodeOuverte(annee: 2026, mois: 10),
        portee: PorteeRaccourci.moisEntier,
        cible: CibleCreneau.lesDeux,
        courant: moisVide(2026, 10),
      );

      expect(modifications.length, 62);
    });

    test('« tout effacer » ne rend que les cases réellement saisies', () {
      final periode = periodeOuverte(annee: 2026, mois: 10);
      final courant = moisAvec(2026, 10, <CreneauCle, DisponibiliteEtat>{
        CreneauCle(DateTime(2026, 10, 4), CreneauType.jour):
            DisponibiliteEtat.disponible,
        CreneauCle(DateTime(2026, 10, 5), CreneauType.nuit):
            DisponibiliteEtat.absent,
      });

      final modifications = modificationsRaccourci(
        periode: periode,
        portee: PorteeRaccourci.effacer,
        cible: CibleCreneau.lesDeux,
        courant: courant,
      );

      expect(modifications.length, 2);
      expect(
        modifications.values.every((e) => e == DisponibiliteEtat.nonSaisi),
        isTrue,
      );
    });

    test('un raccourci déjà appliqué ne change plus rien', () {
      final periode = periodeOuverte(annee: 2026, mois: 10);
      final premier = modificationsRaccourci(
        periode: periode,
        portee: PorteeRaccourci.weekends,
        cible: CibleCreneau.nuit,
        courant: moisVide(2026, 10),
      );

      final second = modificationsRaccourci(
        periode: periode,
        portee: PorteeRaccourci.weekends,
        cible: CibleCreneau.nuit,
        courant: moisAvec(2026, 10, premier),
      );

      expect(second, isEmpty);
    });
  });

  group('« Copier le mois précédent »', () {
    test('aligne sur les jours de semaine, pas sur les numéros', () {
      // Novembre 2026 (1er = dimanche) copié depuis octobre 2026 (1er =
      // jeudi) : deux mois qui ne commencent pas le même jour.
      final octobre = DateTime(2026, 10);
      final novembre = DateTime(2026, 11);
      expect(octobre.weekday, isNot(novembre.weekday));

      for (var numero = 1; numero <= 30; numero++) {
        final jour = DateTime(2026, 11, numero);
        final source = sourceAlignee(
          jour: jour,
          premierPrecedent: octobre,
          premierCourant: novembre,
        );
        if (source == null) continue;
        expect(
          source.weekday,
          jour.weekday,
          reason: 'un samedi doit rester un samedi',
        );
        expect(source.month, 10);
      }
    });

    test('le décalage reste dans [-3, 3] pour tous les mois de 2026-2028', () {
      for (var annee = 2026; annee <= 2028; annee++) {
        for (var mois = 1; mois <= 12; mois++) {
          final courant = DateTime(annee, mois);
          final precedent = DateTime(annee, mois - 1);
          final decalage = decalageAlignement(precedent, courant);
          expect(decalage, inInclusiveRange(-3, 3));
          // La propriété qui compte : le décalage conserve le jour de semaine.
          expect(
            DateTime(annee, mois, 1 + decalage.abs() + 7).weekday,
            DateTime(
              precedent.year,
              precedent.month,
              1 + decalage.abs() + 7 - decalage,
            ).weekday,
          );
        }
      }
    });

    test('reporte les nuits de weekend sur les weekends du mois suivant', () {
      // Octobre 2026 : toutes les nuits de samedi et dimanche.
      final octobre = periodeOuverte(annee: 2026, mois: 10);
      final saisiesOctobre = modificationsRaccourci(
        periode: octobre,
        portee: PorteeRaccourci.weekends,
        cible: CibleCreneau.nuit,
        courant: moisVide(2026, 10),
      );

      final novembre = periodeOuverte(annee: 2026, mois: 11);
      final copie = modificationsRaccourci(
        periode: novembre,
        portee: PorteeRaccourci.copieMoisPrecedent,
        cible: CibleCreneau.nuit,
        courant: moisVide(2026, 11),
        moisPrecedent: saisiesOctobre,
      );

      // Tout ce qui est posé tombe un samedi ou un dimanche, et en nuit.
      expect(copie, isNotEmpty);
      for (final entree in copie.entries) {
        expect(entree.value, DisponibiliteEtat.disponible);
        expect(entree.key.creneau, CreneauType.nuit);
        expect(
          entree.key.date.weekday,
          anyOf(DateTime.saturday, DateTime.sunday),
          reason: 'la copie ne doit jamais déplacer un weekend en semaine',
        );
      }
    });

    test('efface les cases du mois courant que la source ne couvre pas', () {
      final novembre = periodeOuverte(annee: 2026, mois: 11);
      final courant = moisAvec(2026, 11, <CreneauCle, DisponibiliteEtat>{
        CreneauCle(DateTime(2026, 11, 2), CreneauType.jour):
            DisponibiliteEtat.disponible,
      });

      final copie = modificationsRaccourci(
        periode: novembre,
        portee: PorteeRaccourci.copieMoisPrecedent,
        cible: CibleCreneau.jour,
        courant: courant,
      );

      expect(
        copie[CreneauCle(DateTime(2026, 11, 2), CreneauType.jour)],
        DisponibiliteEtat.nonSaisi,
        reason: 'copier un mois vide vide le mois : c\'est une reproduction',
      );
    });

    test('le nombre de saisies écrasées est celui de la portée visée', () {
      final periode = periodeOuverte(annee: 2026, mois: 10);
      final courant = moisAvec(2026, 10, <CreneauCle, DisponibiliteEtat>{
        // Un samedi : dans la portée « weekends ».
        CreneauCle(DateTime(2026, 10, 3), CreneauType.nuit):
            DisponibiliteEtat.disponible,
        // Un lundi : hors de cette portée.
        CreneauCle(DateTime(2026, 10, 5), CreneauType.nuit):
            DisponibiliteEtat.disponible,
      });

      expect(
        saisiesEcrasees(
          periode: periode,
          portee: PorteeRaccourci.weekends,
          cible: CibleCreneau.nuit,
          courant: courant,
        ),
        1,
      );
      expect(
        saisiesEcrasees(
          periode: periode,
          portee: PorteeRaccourci.effacer,
          cible: CibleCreneau.lesDeux,
          courant: courant,
        ),
        2,
      );
    });
  });
}
