import 'package:flutter/foundation.dart';

import '../../../core/theme/app_status.dart';
import 'creneau_planning.dart';
import 'ligne_matrice.dart';
import 'planning_mois.dart';

/// Un créneau que personne ne couvre entièrement, au moment de publier.
@immutable
class CreneauNonPourvu {
  const CreneauNonPourvu({
    required this.date,
    required this.creneau,
    required this.pourvus,
    required this.requis,
  });

  /// La date complète, pas seulement le jour : le récapitulatif écrit
  /// « sam. 11 nuit », et le nom du jour demande le mois.
  final DateTime date;

  final CreneauType creneau;
  final int pourvus;
  final int requis;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreneauNonPourvu &&
          other.date == date &&
          other.creneau == creneau &&
          other.pourvus == pourvus &&
          other.requis == requis;

  @override
  int get hashCode => Object.hash(date, creneau, pourvus, requis);
}

/// Un membre au-delà de l'un de ses deux plafonds.
///
/// Les deux sont portés séparément parce qu'ils se dépassent séparément :
/// quatre astreintes de semaine ne coûtent aucun weekend, et deux weekends
/// complets ne font que quatre astreintes.
@immutable
class MembreHorsQuota {
  const MembreHorsQuota({
    required this.userId,
    required this.nom,
    required this.astreintes,
    required this.unitesWeekend,
    this.maxAstreintes,
    this.maxWeekends,
  });

  final String userId;
  final String nom;
  final int astreintes;
  final int unitesWeekend;
  final int? maxAstreintes;
  final int? maxWeekends;

  /// Vrai quand c'est le plafond d'astreintes qui saute.
  bool get astreintesDepassees =>
      maxAstreintes != null && astreintes > maxAstreintes!;

  /// Vrai quand c'est le plafond de weekends qui saute.
  bool get weekendsDepasses =>
      maxWeekends != null && unitesWeekend > maxWeekends!;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MembreHorsQuota &&
          other.userId == userId &&
          other.nom == nom &&
          other.astreintes == astreintes &&
          other.unitesWeekend == unitesWeekend &&
          other.maxAstreintes == maxAstreintes &&
          other.maxWeekends == maxWeekends;

  @override
  int get hashCode => Object.hash(
    userId,
    nom,
    astreintes,
    unitesWeekend,
    maxAstreintes,
    maxWeekends,
  );
}

/// Un membre attribué hors de ses disponibilités, et les créneaux concernés.
///
/// L'information vient de `assignments.was_available`, **posé par la base** à
/// l'insertion (migration 0018) : le client ne la recalcule pas, il la lit.
@immutable
class MembreHorsDispo {
  const MembreHorsDispo({
    required this.userId,
    required this.nom,
    required this.creneaux,
  });

  final String userId;
  final String nom;
  final List<CreneauNonPourvu> creneaux;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MembreHorsDispo &&
          other.userId == userId &&
          other.nom == nom &&
          listEquals(other.creneaux, creneaux);

  @override
  int get hashCode => Object.hash(userId, nom, Object.hashAll(creneaux));
}

/// Le bordereau d'expédition d'une publication.
///
/// **Fonction pure, zéro requête** : tout est construit depuis le planning et
/// les lignes de matrice **déjà chargées** par l'écran. C'est le même parti que
/// les quotas de la ligne membre au ticket 017 — les recompter coûte zéro
/// requête et donne exactement les mêmes nombres que la base, qui les compte de
/// la même façon.
///
/// Il **avertit et ne bloque jamais** : trois trous et deux quotas dépassés
/// n'empêchent pas de publier (`docs/PRD.md § 7.4`, « l'app avertit, l'admin
/// décide »). Un chef qui publie un mois incomplet sait ce qu'il fait.
@immutable
class RecapitulatifPublication {
  const RecapitulatifPublication({
    required this.creneaux,
    required this.attributions,
    required this.membres,
    required this.nonPourvus,
    required this.horsQuota,
    required this.horsDispo,
  });

  /// Construit le bordereau depuis ce qui est à l'écran.
  ///
  /// [lignes] sont les lignes de la matrice **avec la charge du mois** telle
  /// qu'elle est affichée (`lignesAvecChargeProvider`) : le quota qu'on
  /// contrôle ici est exactement celui que le chef vient de lire.
  factory RecapitulatifPublication.construire({
    required PlanningMois planning,
    required List<LigneMatrice> lignes,
    required int annee,
    required int mois,
  }) {
    final nomsParId = <String, LigneMatrice>{
      for (final ligne in lignes) ligne.userId: ligne,
    };

    final nonPourvus = <CreneauNonPourvu>[];
    final horsDispoParMembre = <String, List<CreneauNonPourvu>>{};
    final membres = <String>{};
    var attributions = 0;

    // Un seul parcours des créneaux, dans l'ordre du mois : la liste rendue est
    // celle que le chef lira, sans tri supplémentaire.
    final tries = <CreneauPlanning>[...planning.creneaux]..sort(ordreDuMois);

    for (final creneau in tries) {
      final posees = planning.attributionsDe(creneau.id);
      attributions += posees.length;

      if (posees.length < creneau.effectifRequis) {
        nonPourvus.add(
          CreneauNonPourvu(
            date: DateTime(annee, mois, creneau.jour),
            creneau: creneau.creneau,
            pourvus: posees.length,
            requis: creneau.effectifRequis,
          ),
        );
      }

      for (final attribution in posees) {
        membres.add(attribution.userId);
        if (attribution.etaitDisponible) continue;
        (horsDispoParMembre[attribution.userId] ??= <CreneauNonPourvu>[]).add(
          CreneauNonPourvu(
            date: DateTime(annee, mois, creneau.jour),
            creneau: creneau.creneau,
            pourvus: posees.length,
            requis: creneau.effectifRequis,
          ),
        );
      }
    }

    // **Le quota se lit sur les lignes, pas sur les attributions** : un membre
    // sans plafond n'est jamais hors quota, et un reste négatif est une décision
    // de l'admin, pas une anomalie de comptage.
    final horsQuota = <MembreHorsQuota>[
      for (final ligne in lignes)
        if (_depasse(ligne))
          MembreHorsQuota(
            userId: ligne.userId,
            nom: ligne.nomAffiche,
            astreintes: ligne.astreintes,
            unitesWeekend: ligne.unitesWeekend,
            maxAstreintes: ligne.maxAstreintes,
            maxWeekends: ligne.maxWeekends,
          ),
    ];

    final horsDispo = <MembreHorsDispo>[
      for (final entree in horsDispoParMembre.entries)
        MembreHorsDispo(
          userId: entree.key,
          nom: nomsParId[entree.key]?.nomAffiche ?? '',
          creneaux: entree.value,
        ),
    ]..sort((MembreHorsDispo a, MembreHorsDispo b) => a.nom.compareTo(b.nom));

    return RecapitulatifPublication(
      creneaux: tries.length,
      attributions: attributions,
      membres: membres.length,
      nonPourvus: nonPourvus,
      horsQuota: horsQuota,
      horsDispo: horsDispo,
    );
  }

  /// Créneaux du planning.
  final int creneaux;

  /// Attributions actives, tous membres confondus.
  final int attributions;

  /// **Membres distincts** : le nombre de téléphones qui vont sonner.
  final int membres;

  final List<CreneauNonPourvu> nonPourvus;
  final List<MembreHorsQuota> horsQuota;
  final List<MembreHorsDispo> horsDispo;

  /// Vrai quand il n'y a rien à signaler. Le dire est aussi utile que de
  /// signaler : un récapitulatif silencieux ferait douter qu'il ait regardé.
  bool get sansReserve =>
      nonPourvus.isEmpty && horsQuota.isEmpty && horsDispo.isEmpty;

  static bool _depasse(LigneMatrice ligne) =>
      (ligne.maxAstreintes != null && ligne.astreintes > ligne.maxAstreintes!) ||
      (ligne.maxWeekends != null && ligne.unitesWeekend > ligne.maxWeekends!);
}

/// L'ordre du mois : le jour croissant, puis le créneau de jour avant celui de
/// nuit, comme partout ailleurs dans le produit.
///
/// C'est **l'ordre chronologique** dont parle le ticket 018, et il est ici plutôt
/// que dupliqué là-bas : le bordereau de publication et le remplissage
/// automatique parcourent le même mois, ils n'ont pas à le parcourir
/// différemment.
int ordreDuMois(CreneauPlanning a, CreneauPlanning b) {
  final jours = a.jour.compareTo(b.jour);
  if (jours != 0) return jours;
  return a.creneau.index.compareTo(b.creneau.index);
}
