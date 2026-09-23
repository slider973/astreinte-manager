import 'package:flutter/foundation.dart';

import '../../../core/theme/app_status.dart';
import '../../astreintes/domain/astreinte.dart';
import '../../propositions/domain/proposition.dart';

/// Le nombre de jours que l'accueil regarde devant lui.
///
/// Sept, comme la bande de semaine : les cartes et la bande décrivent **la
/// même fenêtre**, sinon un point orange du vendredi n'aurait pas de carte à
/// laquelle appartenir (`design/064 § 3.1`).
const int joursDeLAccueil = 7;

/// Ce qu'une carte de la rangée dit d'un jour.
enum EtatCarte {
  /// Une astreinte acceptée : la carte est pleine, en `primary`.
  acceptee,

  /// Une proposition en attente de réponse : remplissage `orangeVif`, encre
  /// `onSurface`, et un bouton « Répondre ».
  proposition,

  /// Rien ce jour-là : `surfaceContainerHigh`, « Libre » et la date.
  libre,
}

/// Une carte de la rangée horizontale de l'accueil.
@immutable
class CarteJour {
  const CarteJour({
    required this.jour,
    required this.etat,
    this.creneau,
    this.propositionId,
  });

  /// Le jour, local à minuit.
  final DateTime jour;

  final EtatCarte etat;

  /// Le créneau concerné. `null` sur un jour libre, qui n'en a aucun.
  final CreneauType? creneau;

  /// L'attribution à laquelle « Répondre » renvoie, sur une proposition.
  final String? propositionId;

  /// La clé de reconstruction d'une liste : un jour et un état, jamais un
  /// index — une carte qui change d'état ne doit pas hériter de l'animation
  /// de sa voisine.
  String get cle =>
      '${jour.toIso8601String()}|${etat.name}|${creneau?.name ?? ''}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CarteJour &&
          other.jour == jour &&
          other.etat == etat &&
          other.creneau == creneau &&
          other.propositionId == propositionId;

  @override
  int get hashCode => Object.hash(jour, etat, creneau, propositionId);
}

/// Un jour de la bande de semaine : sa date, et **jusqu'à deux points**.
@immutable
class PointJour {
  const PointJour({
    required this.jour,
    required this.aujourdhui,
    required this.astreinte,
    required this.proposition,
  });

  final DateTime jour;

  /// Le jour courant, en pastille `primaryContainer`.
  final bool aujourdhui;

  /// Un point indigo : une astreinte acceptée ce jour-là.
  final bool astreinte;

  /// Un point orange : une proposition en attente ce jour-là.
  final bool proposition;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PointJour &&
          other.jour == jour &&
          other.aujourdhui == aujourdhui &&
          other.astreinte == astreinte &&
          other.proposition == proposition;

  @override
  int get hashCode => Object.hash(jour, aujourdhui, astreinte, proposition);
}

/// La section « Disponibilités » de l'accueil.
///
/// Trois formes, dont une absence : une période ouverte et incomplète appelle
/// à la saisie, une période ouverte et complète se contente de dire ce qui a
/// été donné, et **quand rien n'est ouvert la section n'existe pas** — il n'y
/// a alors rien à faire, et un bloc qui le dirait serait du bruit permanent
/// (`design/064 § 3.1`).
sealed class AppelDispos {
  const AppelDispos();
}

/// « Saisir mes disponibilités d'octobre » + « Reste 3 jours ».
final class SaisieAFaire extends AppelDispos {
  const SaisieAFaire({
    required this.cleMois,
    required this.nomMois,
    required this.joursRestants,
  });

  /// `2026-10` : ce que le Calendrier attend en `?mois=`.
  final String cleMois;

  /// « octobre », en minuscules, pour la phrase.
  final String nomMois;

  /// Jours entiers avant la date limite. `0` veut dire « dernier jour ».
  final int joursRestants;
}

/// « Octobre saisi : 12 jours, 4 nuits ».
final class SaisieFaite extends AppelDispos {
  const SaisieFaite({
    required this.cleMois,
    required this.libelleMois,
    required this.jours,
    required this.nuits,
  });

  final String cleMois;

  /// « Octobre », avec sa capitale : la phrase commence par lui.
  final String libelleMois;

  final int jours;
  final int nuits;
}

/// Tout ce que l'accueil affiche, composé **à partir des providers que les
/// autres écrans lisent déjà**.
///
/// Aucune requête ne naît ici : les astreintes viennent du contrôleur du
/// ticket 027, les propositions de celui du 021, les périodes et la saisie de
/// ceux du 011. L'accueil est une lecture de plus, pas une lecture nouvelle.
@immutable
class TableauBord {
  const TableauBord({
    required this.cartes,
    required this.astreintesAVenir,
    required this.propositions,
    required this.semaine,
    required this.heures,
    required this.nomCaserne,
    this.dispos,
    this.echecAstreintes = false,
    this.echecPropositions = false,
  });

  /// La rangée horizontale : la prochaine astreinte acceptée d'abord, puis les
  /// sept jours qui viennent.
  final List<CarteJour> cartes;

  /// Le compte de « Mes astreintes · N » — **toutes** les astreintes à venir,
  /// pas seulement celles de la fenêtre de sept jours.
  final int astreintesAVenir;

  /// Les propositions en attente, dans l'ordre du calendrier. L'écran n'en
  /// montre que les trois premières ; le compte, lui, les compte toutes.
  final List<Proposition> propositions;

  /// Les sept jours de la bande à points.
  final List<PointJour> semaine;

  /// Les heures d'affichage de la caserne, telles que l'écran « Astreintes »
  /// les lit (`stations.settings`).
  final HeuresAffichage heures;

  final String nomCaserne;

  /// `null` quand aucune période n'est ouverte : la section n'existe pas.
  final AppelDispos? dispos;

  /// **Une lecture en panne ne devient jamais un état vide.** L'accueil a deux
  /// sources ; quand l'une échoue et que l'autre répond, l'écran s'affiche —
  /// il serait absurde de cacher des propositions parfaitement lues. Mais la
  /// section privée de sa source ne doit pas affirmer « Aucune astreinte à
  /// venir » : elle dit qu'elle n'a pas pu lire, et propose de réessayer.
  final bool echecAstreintes;
  final bool echecPropositions;

  /// Vrai quand la rangée a quelque chose à dire.
  ///
  /// Sept cartes « Libre » ne sont pas une rangée : c'est un état vide déguisé
  /// en contenu, et il coûte 168 points de haut pour ne rien apprendre. Dès
  /// qu'une astreinte est acceptée ou qu'une proposition attend, la rangée
  /// reprend sa place.
  bool get rangeeUtile =>
      astreintesAVenir > 0 ||
      cartes.any((CarteJour carte) => carte.etat != EtatCarte.libre);
}

/// Compose le tableau de bord.
///
/// Fonction pure : c'est elle qui est testée, pas l'écran. [aujourdhui] est
/// injecté pour la même raison qu'ailleurs — un test qui dépendrait de la date
/// du jour échouerait le mois suivant.
TableauBord composerTableauBord({
  required DateTime aujourdhui,
  required MesAstreintes astreintes,
  required List<Proposition> propositions,
  required String nomCaserne,
  AppelDispos? dispos,
  bool echecAstreintes = false,
  bool echecPropositions = false,
}) {
  final minuit = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
  final aVenir = astreintes.aVenir(minuit);

  final enAttente = <Proposition>[
    for (final proposition in propositions)
      if (proposition.repondable && !proposition.jour.isBefore(minuit))
        proposition,
  ]..sort((Proposition a, Proposition b) => a.comparer(b));

  final fenetre = <DateTime>[
    for (var decalage = 0; decalage < joursDeLAccueil; decalage++)
      minuit.add(Duration(days: decalage)),
  ];

  Astreinte? premiereAstreinteDe(DateTime jour) {
    for (final astreinte in aVenir) {
      if (astreinte.jour == jour) return astreinte;
    }
    return null;
  }

  Proposition? premierePropositionDe(DateTime jour) {
    for (final proposition in enAttente) {
      if (proposition.jour == jour) return proposition;
    }
    return null;
  }

  final cartes = <CarteJour>[];

  // **La prochaine astreinte acceptée ouvre la rangée**, où qu'elle tombe :
  // c'est la seule chose que le pompier vient chercher quand il ouvre
  // l'application entre deux activités. Elle peut être hors de la fenêtre de
  // sept jours, et c'est justement quand elle l'est qu'elle a le plus de
  // valeur.
  final prochaine = aVenir.isEmpty ? null : aVenir.first;
  if (prochaine != null) {
    cartes.add(
      CarteJour(
        jour: prochaine.jour,
        etat: EtatCarte.acceptee,
        creneau: prochaine.creneau,
      ),
    );
  }

  for (final jour in fenetre) {
    // Le jour déjà porté par la carte de tête ne revient pas : deux cartes
    // pour la même garde feraient croire à deux gardes.
    if (prochaine != null && prochaine.jour == jour) continue;

    final proposition = premierePropositionDe(jour);
    if (proposition != null) {
      cartes.add(
        CarteJour(
          jour: jour,
          etat: EtatCarte.proposition,
          creneau: proposition.creneau,
          propositionId: proposition.id,
        ),
      );
      continue;
    }

    final astreinte = premiereAstreinteDe(jour);
    cartes.add(
      astreinte == null
          ? CarteJour(jour: jour, etat: EtatCarte.libre)
          : CarteJour(
              jour: jour,
              etat: EtatCarte.acceptee,
              creneau: astreinte.creneau,
            ),
    );
  }

  final semaine = <PointJour>[
    for (final jour in fenetre)
      PointJour(
        jour: jour,
        aujourdhui: jour == minuit,
        astreinte: premiereAstreinteDe(jour) != null,
        proposition: premierePropositionDe(jour) != null,
      ),
  ];

  return TableauBord(
    cartes: List<CarteJour>.unmodifiable(cartes),
    astreintesAVenir: aVenir.length,
    propositions: List<Proposition>.unmodifiable(enAttente),
    semaine: List<PointJour>.unmodifiable(semaine),
    heures: astreintes.heures,
    nomCaserne: nomCaserne,
    dispos: dispos,
    echecAstreintes: echecAstreintes,
    echecPropositions: echecPropositions,
  );
}
