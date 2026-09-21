import 'package:flutter/foundation.dart';

import '../../../core/theme/app_status.dart';
import '../../dispos/domain/disponibilite_mois.dart';
import 'candidat.dart';
import 'creneau_planning.dart';
import 'ligne_matrice.dart';
import 'planning_mois.dart';
import 'recapitulatif_publication.dart';

/// Un créneau, un pompier : une ligne du plan de remplissage.
@immutable
class ChoixAutomatique {
  const ChoixAutomatique({
    required this.creneauId,
    required this.userId,
    required this.date,
    required this.creneau,
  });

  final String creneauId;
  final String userId;

  /// La date entière, pour écrire « sam. 11 nuit » dans le récapitulatif.
  final DateTime date;
  final CreneauType creneau;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChoixAutomatique &&
          other.creneauId == creneauId &&
          other.userId == userId &&
          other.date == date &&
          other.creneau == creneau;

  @override
  int get hashCode => Object.hash(creneauId, userId, date, creneau);
}

/// Le remplissage que la machine propose, et ce qu'il laisse derrière lui.
///
/// **Fonction pure, zéro requête**, comme le bordereau de publication du ticket
/// 019 : tout est calculé sur la matrice et le planning **déjà chargés** par
/// l'écran. Le chef valide donc exactement ce qui partira — un plan recalculé
/// au moment d'appliquer serait un second plan, et le récapitulatif n'engagerait
/// plus rien (`design/018 § 4`).
///
/// L'heuristique, et rien de plus (`docs/PRD.md § 6.4`) : **pour chaque créneau
/// non pourvu, dans l'ordre du mois, le premier candidat du tri du ticket 017**
/// — quota d'astreintes restant décroissant, puis astreintes acceptées sur les
/// trois mois précédents croissant, puis charge du mois en construction, puis
/// nom. Pas d'optimisation globale, pas de second passage, pas de rattrapage.
///
/// Trois choses qu'elle ne fait jamais :
/// - **toucher une attribution déjà posée** : les membres déjà attribués à un
///   créneau ne sont même pas candidats sur lui, et un créneau déjà pourvu
///   n'ouvre aucune place ;
/// - **dépasser un plafond** : ni celui des astreintes, ni celui des weekends.
///   Le premier est dans le tri, le second exclut — un pompier qui a fait son
///   compte de weekends reste proposable un mardi ;
/// - **désigner quelqu'un qui n'a pas dit oui** : ni un absent, ni un membre
///   qui n'a rien saisi. L'administrateur garde ce droit, à la main, avec
///   l'avertissement du ticket 017 ; la machine ne l'a pas.
@immutable
class PropositionAutomatique {
  const PropositionAutomatique({
    required this.choix,
    required this.creneauxRemplis,
    required this.decouverts,
    required this.membresMobilises,
  });

  /// Calcule le plan depuis ce qui est à l'écran.
  ///
  /// [lignes] sont les lignes de la matrice **avec la charge du mois** telle
  /// qu'elle est affichée (`lignesAvecChargeProvider`) : le quota sur lequel la
  /// machine décide est exactement celui que le chef vient de lire.
  factory PropositionAutomatique.construire({
    required PlanningMois planning,
    required List<LigneMatrice> lignes,
    required int annee,
    required int mois,
  }) {
    if (!planning.existe || lignes.isEmpty) {
      return const PropositionAutomatique(
        choix: <ChoixAutomatique>[],
        creneauxRemplis: 0,
        decouverts: <CreneauNonPourvu>[],
        membresMobilises: 0,
      );
    }

    // La charge de chaque membre, **tenue à jour au fil du remplissage**. Elle
    // part de ce que la base a compté et suit chaque choix : sans cela, un
    // pompier à trois astreintes de plafond en recevrait soixante-deux, son
    // reste n'ayant jamais bougé entre deux créneaux.
    final astreintes = <String, int>{};
    final unites = <String, Set<DateTime>>{};

    for (final creneau in planning.creneaux) {
      final unite = uniteWeekend(DateTime(annee, mois, creneau.jour));
      for (final attribution in planning.attributionsDe(creneau.id)) {
        astreintes[attribution.userId] =
            (astreintes[attribution.userId] ?? 0) + 1;
        if (unite != null) {
          (unites[attribution.userId] ??= <DateTime>{}).add(unite);
        }
      }
    }

    final choix = <ChoixAutomatique>[];
    final decouverts = <CreneauNonPourvu>[];
    final mobilises = <String>{};
    var remplis = 0;
    var compteur = 0;

    // L'ordre chronologique, jour puis nuit : c'est celui du ticket, et c'est
    // lui qui rend le résultat reproductible quand deux créneaux se disputent
    // le dernier quota de quelqu'un.
    final tries = <CreneauPlanning>[...planning.creneaux]..sort(ordreDuMois);

    // Le planning **simulé** : chaque choix y est posé tout de suite, pour que
    // le suivant voie la place prise et le quota consommé.
    var courant = planning;

    for (final creneau in tries) {
      final jour = DateTime(annee, mois, creneau.jour);
      final unite = uniteWeekend(jour);
      final avant = courant.pourvus(creneau.id);
      var pourvus = avant;

      while (pourvus < creneau.effectifRequis) {
        final membres = <LigneMatrice>[
          for (final ligne in lignes)
            ligne.avecCharge(
              astreintes: astreintes[ligne.userId] ?? 0,
              unitesWeekend: unites[ligne.userId]?.length ?? 0,
            ),
        ];

        // **Le tri du ticket 017, appelé et non recopié.** `disponibles` ne
        // contient que les membres qui se sont déclarés disponibles sur ce
        // créneau et qui n'y sont pas déjà attribués : l'absent, le non-saisi
        // et le déjà-placé sont écartés par la construction même du panneau.
        final panneau = PanneauCandidats.construire(
          creneau: creneau,
          jour: jour,
          membres: membres,
          planning: courant,
          modifiable: true,
        );

        final elu = _premierEligible(
          panneau.disponibles,
          unite: unite,
          unites: unites,
        );
        if (elu == null) break;

        courant = courant.avecAttribution(
          Attribution(
            id: 'auto:${compteur++}',
            creneauId: creneau.id,
            userId: elu.userId,
            locale: true,
          ),
        );
        astreintes[elu.userId] = (astreintes[elu.userId] ?? 0) + 1;
        if (unite != null) {
          (unites[elu.userId] ??= <DateTime>{}).add(unite);
        }
        mobilises.add(elu.userId);
        choix.add(
          ChoixAutomatique(
            creneauId: creneau.id,
            userId: elu.userId,
            date: jour,
            creneau: creneau.creneau,
          ),
        );
        pourvus++;
      }

      if (pourvus >= creneau.effectifRequis) {
        // Un créneau qui était déjà pourvu ne compte pas comme rempli : le
        // chiffre annoncé est **ce que l'appui change**, pas l'état du mois.
        if (avant < creneau.effectifRequis) remplis++;
      } else {
        decouverts.add(
          CreneauNonPourvu(
            date: jour,
            creneau: creneau.creneau,
            pourvus: pourvus,
            requis: creneau.effectifRequis,
          ),
        );
      }
    }

    return PropositionAutomatique(
      choix: List<ChoixAutomatique>.unmodifiable(choix),
      creneauxRemplis: remplis,
      decouverts: List<CreneauNonPourvu>.unmodifiable(decouverts),
      membresMobilises: mobilises.length,
    );
  }

  /// Le plan, **dans l'ordre du mois**. Cet ordre part tel quel au serveur :
  /// c'est lui qui décide qui prend la dernière place d'un quota.
  final List<ChoixAutomatique> choix;

  /// Créneaux que ce remplissage ferait passer de « à pourvoir » à « pourvu ».
  final int creneauxRemplis;

  /// Créneaux qui resteraient à découvert **faute de candidat**. Ce sont eux que
  /// le récapitulatif nomme : le chef saura où chercher à la main.
  final List<CreneauNonPourvu> decouverts;

  /// Pompiers distincts désignés au moins une fois.
  final int membresMobilises;

  /// Attributions que le plan poserait.
  int get attributions => choix.length;

  int get creneauxDecouverts => decouverts.length;

  /// Vrai quand il n'y a rien à proposer : le mois est complet, ou personne
  /// n'est disponible nulle part. Le bouton ne s'affiche pas dans le premier
  /// cas ; le récapitulatif le dit dans le second.
  bool get vide => choix.isEmpty;

  /// Le corps de requête d'`auto-propose`, tel quel.
  List<Map<String, String>> get picks => <Map<String, String>>[
    for (final ligne in choix)
      <String, String>{'shift_id': ligne.creneauId, 'user_id': ligne.userId},
  ];

  /// Le premier candidat que rien n'exclut, dans l'ordre déjà trié.
  ///
  /// Le tri a classé ; ici on **filtre**, et seulement sur les deux plafonds.
  /// Un candidat au quota atteint n'est pas écarté du panneau — l'admin peut
  /// l'y choisir en connaissance de cause (`docs/PRD.md § 7.4`) —, il est
  /// écarté de la **machine**, qui n'a pas ce droit.
  static Candidat? _premierEligible(
    List<Candidat> disponibles, {
    required DateTime? unite,
    required Map<String, Set<DateTime>> unites,
  }) {
    for (final candidat in disponibles) {
      if (candidat.quotaAtteint) continue;
      if (unite != null && _weekendPlein(candidat, unite, unites)) continue;
      return candidat;
    }
    return null;
  }

  /// Vrai quand ce créneau coûterait au membre une unité de weekend qu'il n'a
  /// plus.
  ///
  /// **Un weekend déjà entamé ne coûte rien de plus** : le samedi et le dimanche
  /// d'un même weekend font une unité, et quatre créneaux de ce weekend en font
  /// toujours une (`uniteWeekend`, ticket 011, dont la parité avec la fonction
  /// SQL `unite_weekend` est testée des deux côtés).
  static bool _weekendPlein(
    Candidat candidat,
    DateTime unite,
    Map<String, Set<DateTime>> unites,
  ) {
    final reste = candidat.membre.weekendsRestants;
    if (reste == null) return false;
    if (unites[candidat.userId]?.contains(unite) ?? false) return false;
    return reste <= 0;
  }
}
