import 'package:flutter/foundation.dart';

import '../../../core/theme/app_status.dart';
import 'creneau_planning.dart';

/// Le planning d'un mois : ses créneaux et leurs attributions.
///
/// **Trois index, construits une fois.** La ligne des créneaux lit une
/// couverture par colonne à chaque image ; le panneau lit les attributions
/// d'un créneau ; le temps réel arrive avec un identifiant d'attribution et
/// rien d'autre. Les trois accès sont directs, aucun n'est une recherche
/// linéaire.
///
/// L'index par identifiant n'est pas un confort : **une suppression distante
/// ne diffuse que la clé primaire** (`design/017 § 7.2`, identité de réplique
/// laissée à `default`). Sans cet index, une attribution retirée par l'adjoint
/// serait un identifiant qu'on ne saurait rattacher à aucun créneau.
@immutable
class PlanningMois {
  PlanningMois({
    required this.planning,
    required List<CreneauPlanning> creneaux,
    required List<Attribution> attributions,
  }) : _creneaux = <String, CreneauPlanning>{
         for (final creneau in creneaux) creneau.id: creneau,
       },
       _parJour = <int, String>{
         for (final creneau in creneaux) _cle(creneau.jour, creneau.creneau): creneau.id,
       },
       _attributions = <String, Attribution>{
         for (final attribution in attributions) attribution.id: attribution,
       };

  /// Un mois sans planning : rien n'a encore été créé.
  static PlanningMois vide() => PlanningMois(
    planning: null,
    creneaux: const <CreneauPlanning>[],
    attributions: const <Attribution>[],
  );

  /// `null` tant que le planning du mois n'existe pas.
  final PlanningBrouillon? planning;

  final Map<String, CreneauPlanning> _creneaux;
  final Map<int, String> _parJour;
  final Map<String, Attribution> _attributions;

  /// Vrai quand le planning du mois existe.
  bool get existe => planning != null;

  /// Vrai quand l'écran a le droit d'écrire : le planning existe et il est
  /// encore en brouillon.
  bool get modifiable => planning?.modifiable ?? false;

  Iterable<CreneauPlanning> get creneaux => _creneaux.values;

  /// Le créneau d'une journée, ou `null` si le planning n'existe pas.
  CreneauPlanning? creneau(int jour, CreneauType type) {
    final id = _parJour[_cle(jour, type)];
    return id == null ? null : _creneaux[id];
  }

  CreneauPlanning? creneauParId(String id) => _creneaux[id];

  Attribution? attributionParId(String id) => _attributions[id];

  /// Les attributions actives d'un créneau, dans l'ordre d'arrivée.
  List<Attribution> attributionsDe(String creneauId) => <Attribution>[
    for (final attribution in _attributions.values)
      if (attribution.creneauId == creneauId) attribution,
  ];

  /// L'attribution d'un membre sur un créneau, ou `null`.
  Attribution? attributionDe({
    required String creneauId,
    required String userId,
  }) {
    for (final attribution in _attributions.values) {
      if (attribution.creneauId == creneauId && attribution.userId == userId) {
        return attribution;
      }
    }
    return null;
  }

  int pourvus(String creneauId) {
    var total = 0;
    for (final attribution in _attributions.values) {
      if (attribution.creneauId == creneauId) total++;
    }
    return total;
  }

  /// L'état de couverture d'une journée, ou `null` si le planning n'existe
  /// pas : une ligne de créneaux sans planning ne se dessine pas.
  ({CreneauPlanning creneau, int pourvus, EtatCouverture etat})? couverture(
    int jour,
    CreneauType type,
  ) {
    final cible = creneau(jour, type);
    if (cible == null) return null;
    final n = pourvus(cible.id);
    return (
      creneau: cible,
      pourvus: n,
      etat: EtatCouverture.de(pourvus: n, requis: cible.effectifRequis),
    );
  }

  PlanningMois avecAttribution(Attribution attribution) => _copie(
    attributions: <String, Attribution>{
      ..._attributions,
      attribution.id: attribution,
    },
  );

  PlanningMois sansAttribution(String id) => _copie(
    attributions: <String, Attribution>{..._attributions}..remove(id),
  );

  PlanningMois avecEffectif(String creneauId, int effectif) {
    final cible = _creneaux[creneauId];
    if (cible == null) return this;
    return _copie(
      creneaux: <String, CreneauPlanning>{
        ..._creneaux,
        creneauId: cible.avecEffectif(effectif),
      },
    );
  }

  PlanningMois _copie({
    Map<String, CreneauPlanning>? creneaux,
    Map<String, Attribution>? attributions,
  }) => PlanningMois(
    planning: planning,
    creneaux: (creneaux ?? _creneaux).values.toList(growable: false),
    attributions: (attributions ?? _attributions).values.toList(
      growable: false,
    ),
  );

  /// Une clé par (jour, créneau). Le mois est fixe : le jour suffit.
  static int _cle(int jour, CreneauType type) =>
      jour * 2 + (type == CreneauType.jour ? 0 : 1);
}
