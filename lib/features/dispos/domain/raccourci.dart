import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_status.dart';
import 'creneau_cle.dart';
import 'disponibilite_mois.dart';
import 'periode_saisie.dart';

/// **Ce qu'un raccourci vise** : un ensemble de jours du mois.
///
/// Les cinq portées sont **calendaires**, jamais comptables. « Les weekends »
/// dit samedi et dimanche, et rien d'autre — pas les fériés en semaine, même
/// si `docs/PRD.md § 6.3` les compte comme des weekends au quota. Le critère
/// d'acceptation du ticket est explicite (« coche **exactement** les samedis
/// et dimanches nuit »), et un membre qui lit « les weekends » et récupère le
/// 14 juillet aurait raison de se sentir trahi. Les fériés restent visibles
/// dans la grille, étoilés et nommés, à une touche.
///
/// La conséquence tient en une phrase : **les portées `weekends` et `semaine`
/// partagent le mois sans recouvrement ni trou**, et leur union est
/// `moisEntier`.
enum PorteeRaccourci {
  /// Samedis et dimanches du mois.
  weekends(AppStrings.raccourciWeekends, AppStrings.raccourciWeekendsDetail),

  /// Du lundi au vendredi, **fériés compris** : ce sont des jours de semaine.
  semaine(AppStrings.raccourciSemaine, AppStrings.raccourciSemaineDetail),

  /// Tous les jours du mois.
  moisEntier(AppStrings.raccourciMois, AppStrings.raccourciMoisDetail),

  /// Reprend le mois précédent, **aligné sur les jours de semaine**.
  copieMoisPrecedent(
    AppStrings.raccourciCopie,
    AppStrings.raccourciCopieDetail,
  ),

  /// Remet tout le mois à « non saisi ».
  effacer(AppStrings.raccourciEffacer, AppStrings.raccourciEffacerDetail);

  const PorteeRaccourci(this.libelle, this.detail);

  /// Le libellé du bouton : « Les weekends ».
  final String libelle;

  /// La phrase qui dit exactement ce que la portée couvre, affichée en tête
  /// de la feuille de choix.
  final String detail;

  /// Vrai quand la portée **écrase du travail déjà fait** : le ticket exige
  /// une confirmation pour ces deux-là, et pour elles seules.
  bool get ecrase =>
      this == PorteeRaccourci.effacer ||
      this == PorteeRaccourci.copieMoisPrecedent;

  /// Vrai quand la portée a besoin de lire un autre mois avant d'agir.
  bool get litLeMoisPrecedent => this == PorteeRaccourci.copieMoisPrecedent;
}

/// **Le créneau qu'un raccourci vise.** Chaque portée les propose tous les
/// trois : c'est ce couple portée × créneau qui produit les six raccourcis
/// nommés par le ticket — « toutes les nuits en semaine » est
/// `semaine` × `nuit`.
enum CibleCreneau {
  jour(AppStrings.raccourciCibleJour),
  nuit(AppStrings.raccourciCibleNuit),
  lesDeux(AppStrings.raccourciCibleLesDeux);

  const CibleCreneau(this.libelle);

  final String libelle;

  List<CreneauType> get creneaux => switch (this) {
    CibleCreneau.jour => const <CreneauType>[CreneauType.jour],
    CibleCreneau.nuit => const <CreneauType>[CreneauType.nuit],
    CibleCreneau.lesDeux => const <CreneauType>[
      CreneauType.jour,
      CreneauType.nuit,
    ],
  };
}

/// Un raccourci qui vient d'être appliqué, et ce qu'il a coûté.
///
/// C'est ce que la ligne de résultat affiche — « 22 cases mises à jour » —
/// et c'est ce qui justifie le bouton « Annuler » à côté.
@immutable
class RaccourciApplique {
  const RaccourciApplique({
    required this.portee,
    required this.cible,
    required this.cases,
  });

  final PorteeRaccourci portee;
  final CibleCreneau cible;

  /// Le nombre de cases que le raccourci a réellement changées.
  final int cases;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RaccourciApplique &&
          other.portee == portee &&
          other.cible == cible &&
          other.cases == cases;

  @override
  int get hashCode => Object.hash(portee, cible, cases);
}

/// Les jours du mois que [portee] couvre, dans l'ordre.
List<DateTime> joursDeLaPortee(PeriodeSaisie periode, PorteeRaccourci portee) =>
    <DateTime>[
      for (final jour in periode.jours)
        if (_couvert(jour, portee)) jour,
    ];

bool _couvert(DateTime jour, PorteeRaccourci portee) => switch (portee) {
  PorteeRaccourci.weekends =>
    jour.weekday == DateTime.saturday || jour.weekday == DateTime.sunday,
  PorteeRaccourci.semaine =>
    jour.weekday != DateTime.saturday && jour.weekday != DateTime.sunday,
  _ => true,
};

/// **Le décalage qui aligne le mois précédent sur le mois courant, en jours
/// de semaine.**
///
/// Un mois ne commence presque jamais le même jour que le précédent : copier
/// le 1er sur le 1er mettrait les weekends au milieu de la semaine, et c'est
/// exactement ce que le critère d'acceptation interdit.
///
/// Le décalage `a` vérifie, pour tout index de jour `i` du mois précédent :
/// `(premierPrecedent + i)` et `(premierCourant + i + a)` **tombent le même
/// jour de la semaine**. Il y en a une infinité, espacés de sept ; on prend
/// celui de plus petite valeur absolue, donc dans `[-3, 3]` — la copie reste
/// à sa place dans le mois au lieu de glisser d'une semaine entière.
///
/// Conséquence assumée : jusqu'à trois jours d'un bord n'ont pas de source et
/// repartent à « non saisi ». Copier, c'est reproduire le mois précédent, pas
/// le superposer à ce qui est déjà là.
int decalageAlignement(DateTime premierPrecedent, DateTime premierCourant) {
  final brut = (premierPrecedent.weekday - premierCourant.weekday) % 7;
  return brut > 3 ? brut - 7 : brut;
}

/// Le jour du mois précédent qui alimente le [jour] du mois courant, ou
/// `null` s'il n'y en a pas.
DateTime? sourceAlignee({
  required DateTime jour,
  required DateTime premierPrecedent,
  required DateTime premierCourant,
}) {
  final decalage = decalageAlignement(premierPrecedent, premierCourant);
  final index = jour.day - 1 - decalage;
  final joursDuPrecedent = DateTime(
    premierPrecedent.year,
    premierPrecedent.month + 1,
    0,
  ).day;
  if (index < 0 || index >= joursDuPrecedent) return null;
  return DateTime(
    premierPrecedent.year,
    premierPrecedent.month,
    index + 1,
  );
}

/// **Ce qu'un raccourci change, et rien de plus.**
///
/// Rend les seules cases dont la valeur diffère de celle affichée : c'est à
/// la fois le lot d'écriture, le compte annoncé (« 22 cases mises à jour ») et
/// l'exactitude de l'annulation. Réappliquer deux fois le même raccourci rend
/// une carte vide la seconde fois, et rien ne part sur le réseau.
///
/// [moisPrecedent] n'est lu que par [PorteeRaccourci.copieMoisPrecedent] ;
/// l'absence de clé y vaut « non saisi », comme partout ailleurs.
Map<CreneauCle, DisponibiliteEtat> modificationsRaccourci({
  required PeriodeSaisie periode,
  required PorteeRaccourci portee,
  required CibleCreneau cible,
  required DisponibiliteMois courant,
  Map<CreneauCle, DisponibiliteEtat> moisPrecedent =
      const <CreneauCle, DisponibiliteEtat>{},
}) {
  final premierCourant = periode.premierJour;
  final premierPrecedent = DateTime(periode.annee, periode.mois - 1);
  final creneaux = cible.creneaux;

  final modifications = <CreneauCle, DisponibiliteEtat>{};
  for (final jour in joursDeLaPortee(periode, portee)) {
    for (final creneau in creneaux) {
      final cle = CreneauCle(jour, creneau);
      final voulu = switch (portee) {
        PorteeRaccourci.effacer => DisponibiliteEtat.nonSaisi,
        PorteeRaccourci.copieMoisPrecedent => _valeurCopiee(
          cle: cle,
          premierPrecedent: premierPrecedent,
          premierCourant: premierCourant,
          moisPrecedent: moisPrecedent,
        ),
        _ => DisponibiliteEtat.disponible,
      };
      if (courant.etat(cle) != voulu) modifications[cle] = voulu;
    }
  }
  return modifications;
}

DisponibiliteEtat _valeurCopiee({
  required CreneauCle cle,
  required DateTime premierPrecedent,
  required DateTime premierCourant,
  required Map<CreneauCle, DisponibiliteEtat> moisPrecedent,
}) {
  final source = sourceAlignee(
    jour: cle.date,
    premierPrecedent: premierPrecedent,
    premierCourant: premierCourant,
  );
  if (source == null) return DisponibiliteEtat.nonSaisi;
  return moisPrecedent[CreneauCle(source, cle.creneau)] ??
      DisponibiliteEtat.nonSaisi;
}

/// Le nombre de cases **déjà saisies** que [portee] × [cible] va écraser.
///
/// C'est le chiffre de la confirmation : « 22 saisies seront effacées ». Il
/// compte les cases qui portent une valeur aujourd'hui, pas celles qui
/// changeront — une case « non saisi » qui le reste ne coûte rien à personne.
int saisiesEcrasees({
  required PeriodeSaisie periode,
  required PorteeRaccourci portee,
  required CibleCreneau cible,
  required DisponibiliteMois courant,
}) {
  var compte = 0;
  for (final jour in joursDeLaPortee(periode, portee)) {
    for (final creneau in cible.creneaux) {
      if (courant.etat(CreneauCle(jour, creneau)) !=
          DisponibiliteEtat.nonSaisi) {
        compte++;
      }
    }
  }
  return compte;
}
