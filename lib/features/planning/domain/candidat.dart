import 'package:flutter/foundation.dart';

import '../../../core/theme/app_status.dart';
import 'creneau_planning.dart';
import 'ligne_matrice.dart';
import 'planning_mois.dart';

/// Un membre, vu depuis un créneau : sa disponibilité ce jour-là, ses quotas,
/// et l'attribution qu'il y a déjà, le cas échéant.
///
/// **Rien n'est recalculé ici.** Le quota restant et la charge des trois mois
/// précédents viennent de la ligne de matrice, telle que `availability_matrix`
/// l'a rendue. Le panneau des candidats ne fait pas une requête de plus pour
/// trier douze noms sur des données déjà en mémoire (`design/017 § 2`).
@immutable
class Candidat {
  const Candidat({
    required this.membre,
    required this.disponibilite,
    this.attribution,
  });

  final LigneMatrice membre;

  /// L'état de la case du membre sur **ce** créneau.
  final DisponibiliteEtat disponibilite;

  /// Non nul quand le membre est déjà attribué à ce créneau.
  final Attribution? attribution;

  String get userId => membre.userId;

  bool get estAttribue => attribution != null;

  bool get estDisponible => disponibilite == DisponibiliteEtat.disponible;

  /// `null` veut dire **illimité**, jamais zéro.
  int? get astreintesRestantes => membre.astreintesRestantes;

  /// Le membre a atteint ou dépassé le plafond qu'il a déclaré. Un illimité
  /// n'atteint jamais rien.
  bool get quotaAtteint =>
      astreintesRestantes != null && astreintesRestantes! <= 0;

  /// Le membre est **au-delà** de ce qu'il acceptait.
  bool get quotaDepasse =>
      astreintesRestantes != null && astreintesRestantes! < 0;
}

/// Les candidats d'un créneau, dans l'ordre du PRD § 5.3.
///
/// **Quota d'astreintes restant décroissant, puis astreintes acceptées sur les
/// trois mois précédents croissant, puis nom.** C'est exactement l'ordre du
/// tri « Astreintes restantes » de la matrice (ticket 016) : le chef retrouve
/// le classement qu'il connaît déjà.
///
/// Deux règles que le tri naïf raterait :
/// - **`null` passe en tête** : un illimité est la plus grande capacité
///   disponible, pas l'absence de capacité ;
/// - **un reste négatif passe en queue**, après les zéros : celui qui est déjà
///   au-delà de ce qu'il acceptait est le dernier qu'on dérange.
int comparerCandidats(Candidat a, Candidat b) {
  final resteA = a.astreintesRestantes;
  final resteB = b.astreintesRestantes;

  if (resteA == null && resteB != null) return -1;
  if (resteB == null && resteA != null) return 1;
  if (resteA != null && resteB != null && resteA != resteB) {
    return resteB.compareTo(resteA);
  }

  final charge = a.membre.accepteesPrecedentes.compareTo(
    b.membre.accepteesPrecedentes,
  );
  if (charge != 0) return charge;

  return a.membre.nomAffiche.toLowerCase().compareTo(
    b.membre.nomAffiche.toLowerCase(),
  );
}

/// Ce que le panneau fait quand on touche un nom.
///
/// Même panneau, même tri, mêmes trois listes : ce qui change, c'est la
/// **conséquence**, et elle se dit dans le libellé du bouton comme dans le
/// bandeau de l'en-tête (`design/020 § 5.2`).
enum ModePanneau {
  /// Planning en brouillon : attribuer et retirer, réversible en un geste,
  /// sans confirmation et sans notification.
  construction,

  /// Planning publié ou validé : attribuer **notifie**, retirer **annule** et
  /// laisse une trace. Les deux gestes demandent confirmation.
  reattribution,

  /// Planning archivé, caserne suspendue, membre non administrateur : le
  /// panneau se lit, il ne s'écrit pas.
  lecture,
}

/// Ce que le panneau d'un créneau affiche : le créneau, sa couverture, et ses
/// trois listes.
@immutable
class PanneauCandidats {
  const PanneauCandidats({
    required this.creneau,
    required this.jour,
    required this.etat,
    required this.attribues,
    required this.disponibles,
    required this.nonDisponibles,
    required this.modifiable,
    this.mode = ModePanneau.construction,
  });

  /// Construit les trois listes depuis la matrice et le planning.
  ///
  /// Les trois listes sont **disjointes** : un membre déjà attribué n'apparaît
  /// pas dans les candidats, sans quoi on lui proposerait une place qu'il
  /// occupe et la contrainte d'unicité refuserait l'écriture.
  factory PanneauCandidats.construire({
    required CreneauPlanning creneau,
    required DateTime jour,
    required List<LigneMatrice> membres,
    required PlanningMois planning,
    required bool modifiable,
    ModePanneau mode = ModePanneau.construction,
  }) {
    final attribues = <Candidat>[];
    final disponibles = <Candidat>[];
    final nonDisponibles = <Candidat>[];

    for (final membre in membres) {
      final candidat = Candidat(
        membre: membre,
        disponibilite: membre.etatDe(creneau.jour, creneau.creneau),
        attribution: planning.attributionDe(
          creneauId: creneau.id,
          userId: membre.userId,
        ),
      );

      if (candidat.estAttribue) {
        attribues.add(candidat);
      } else if (candidat.estDisponible) {
        disponibles.add(candidat);
      } else {
        nonDisponibles.add(candidat);
      }
    }

    disponibles.sort(comparerCandidats);
    nonDisponibles.sort(comparerCandidats);
    attribues.sort(comparerCandidats);

    final pourvus = planning.pourvus(creneau.id);
    return PanneauCandidats(
      creneau: creneau,
      jour: jour,
      etat: EtatCouverture.de(
        pourvus: pourvus,
        requis: creneau.effectifRequis,
      ),
      attribues: List<Candidat>.unmodifiable(attribues),
      disponibles: List<Candidat>.unmodifiable(disponibles),
      nonDisponibles: List<Candidat>.unmodifiable(nonDisponibles),
      modifiable: modifiable,
      mode: mode,
    );
  }

  final CreneauPlanning creneau;

  /// La date entière du créneau : le panneau écrit « samedi 4 octobre ».
  final DateTime jour;

  final EtatCouverture etat;

  final List<Candidat> attribues;
  final List<Candidat> disponibles;
  final List<Candidat> nonDisponibles;

  /// Faux quand la caserne est suspendue, le réseau absent, le planning
  /// archivé ou l'appelant non administrateur. **Un contrôle désactivé porte
  /// sa raison** : elle est passée à part, par l'écran.
  final bool modifiable;

  /// Ce que coûte un appui : rien, ou une notification (`design/020 § 5.2`).
  final ModePanneau mode;

  /// Vrai quand attribuer fait sonner un téléphone. Le geste demande alors une
  /// confirmation, parce qu'il est irréversible et qu'il sort de l'application.
  bool get notifie => mode == ModePanneau.reattribution;

  int get pourvus => attribues.length;

  int get requis => creneau.effectifRequis;
}
