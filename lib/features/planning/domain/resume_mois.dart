import 'package:flutter/foundation.dart';

import '../../../core/theme/app_status.dart';
import 'planning_mois.dart';

/// Où en est le mois, en quatre comptes de créneaux et un d'attributions.
///
/// **Aucune lecture de plus.** Tout se calcule sur ce que l'écran de l'admin
/// a déjà en mémoire : les créneaux et leurs attributions du planning
/// (tickets 017 et 019). Un bandeau qui redemanderait à la base ce que la
/// matrice vient de lire paierait une requête pour trois nombres, et ces
/// nombres auraient un âge différent de la grille qu'ils surplombent.
///
/// **L'unité est le créneau**, pas le poste : chacun des `jours × 2` créneaux
/// du mois tombe dans une case et une seule, et c'est ce qui permet à la
/// barre de répartition et aux chiffres de dire la même chose. Avec un
/// effectif requis de 1 — le réglage par défaut d'une caserne — « créneaux à
/// pourvoir » et « postes manquants » sont le même nombre ; au-delà, c'est le
/// créneau qui est compté, parce que c'est lui qu'on ouvre pour le remplir.
@immutable
class ResumeMois {
  const ResumeMois({
    required this.couverts,
    required this.aPourvoir,
    required this.refuses,
    required this.nonSaisis,
    required this.enAttente,
  });

  /// Compte le mois à partir du planning déjà lu.
  ///
  /// [nombreDeJours] vient de la période : sans planning, le mois n'a aucun
  /// créneau et **tout** est non saisi — ce qui est exactement ce qu'il faut
  /// montrer avant que le chef n'ait créé son planning.
  factory ResumeMois.construire({
    required PlanningMois planning,
    required int nombreDeJours,
  }) {
    final total = nombreDeJours * 2;
    if (!planning.existe) {
      return ResumeMois(
        couverts: 0,
        aPourvoir: 0,
        refuses: 0,
        nonSaisis: total,
        enAttente: 0,
      );
    }

    var couverts = 0;
    var aPourvoir = 0;
    var refuses = 0;
    var nonSaisis = 0;
    var enAttente = 0;

    // Les réponses ne s'attendent qu'une fois le planning parti : en
    // brouillon, une attribution vaut `proposed` sans que personne n'ait été
    // prévenu (`docs/WORKFLOWS.md § 3`). Compter ces soixante-deux-là serait
    // annoncer soixante-deux pompiers qui ne doivent rien.
    final partie = planning.planning?.etat != PlanningEtat.brouillon;

    for (var jour = 1; jour <= nombreDeJours; jour++) {
      for (final type in CreneauType.values) {
        final creneau = planning.creneau(jour, type);
        if (creneau == null || creneau.effectifRequis == 0) {
          // Un créneau sans effectif requis n'est pas un trou : « pas
          // d'astreinte ce jour-là » est une décision, pas un manque.
          nonSaisis++;
          continue;
        }

        final attributions = planning.attributionsDe(creneau.id);
        var actives = 0;
        var refusees = 0;
        for (final attribution in attributions) {
          switch (attribution.etat) {
            case AttributionEtat.propose:
              actives++;
              if (partie) enAttente++;
            case AttributionEtat.accepte:
              actives++;
            case AttributionEtat.refuse:
            case AttributionEtat.remplace:
            case AttributionEtat.annule:
              refusees++;
          }
        }

        if (actives >= creneau.effectifRequis) {
          couverts++;
        } else if (refusees > 0) {
          refuses++;
        } else {
          aPourvoir++;
        }
      }
    }

    return ResumeMois(
      couverts: couverts,
      aPourvoir: aPourvoir,
      refuses: refuses,
      nonSaisis: nonSaisis,
      enAttente: enAttente,
    );
  }

  /// Créneaux dont l'effectif requis est atteint : attribués, acceptés, ou
  /// les deux.
  final int couverts;

  /// Créneaux auxquels il manque du monde, sans refus connu.
  final int aPourvoir;

  /// Créneaux auxquels il manque du monde **après un refus** : ceux-là se
  /// réattribuent, ils ne se remplissent pas de zéro.
  final int refuses;

  /// Créneaux sans effectif requis, et mois dont le planning n'existe pas
  /// encore.
  final int nonSaisis;

  /// Attributions parties et sans réponse. Zéro tant que le planning est en
  /// brouillon.
  final int enAttente;

  /// Tous les créneaux du mois : la somme des quatre familles.
  int get total => couverts + aPourvoir + refuses + nonSaisis;

  /// Ce qui manque de monde, refus compris. C'est le chiffre « À pourvoir »
  /// du bandeau : le chef y lit son reste à faire, d'où qu'il vienne.
  int get manquants => aPourvoir + refuses;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResumeMois &&
          other.couverts == couverts &&
          other.aPourvoir == aPourvoir &&
          other.refuses == refuses &&
          other.nonSaisis == nonSaisis &&
          other.enAttente == enAttente;

  @override
  int get hashCode =>
      Object.hash(couverts, aPourvoir, refuses, nonSaisis, enAttente);
}
