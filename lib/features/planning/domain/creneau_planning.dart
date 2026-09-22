import 'package:flutter/foundation.dart';

import '../../../core/l10n/format_date.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';

/// L'état de couverture d'un créneau, au regard de son effectif requis.
///
/// **Trois états, trois écritures différentes** : `0/1`, `1/1`, `2/1`. La
/// fraction est la marque ; la couleur n'arrive qu'en quatrième
/// (`design/017 § 6.2`).
enum EtatCouverture {
  /// Moins d'attributions que d'effectif requis.
  aPourvoir,

  /// Exactement l'effectif requis. **Un créneau à zéro requis est pourvu**
  /// d'office : « pas d'astreinte ce jour-là » est une décision, pas un trou.
  pourvu,

  /// Plus d'attributions que d'effectif requis. Ce n'est pas une erreur : un
  /// renfort est une décision.
  surPourvu;

  static EtatCouverture de({required int pourvus, required int requis}) {
    if (pourvus < requis) return EtatCouverture.aPourvoir;
    if (pourvus > requis) return EtatCouverture.surPourvu;
    return EtatCouverture.pourvu;
  }
}

/// Un créneau à pourvoir : une ligne de `shifts` (`docs/SCHEMA.md § 2.9`).
///
/// [effectifRequis] est une **copie** des réglages de la caserne, faite à la
/// création du planning et jamais réécrite depuis : changer l'effectif requis
/// de la caserne n'affecte que les plannings créés ensuite (ticket 010).
@immutable
class CreneauPlanning {
  const CreneauPlanning({
    required this.id,
    required this.jour,
    required this.creneau,
    required this.effectifRequis,
  });

  factory CreneauPlanning.depuisJson(Map<String, dynamic> ligne) {
    final date = DateTime.parse(ligne['date']! as String);
    return CreneauPlanning(
      id: ligne['id']! as String,
      jour: date.day,
      creneau: CreneauSql.depuisSql(ligne['slot']! as String),
      effectifRequis: (ligne['required_count'] as int?) ?? 0,
    );
  }

  /// Les colonnes lues. Jamais `select *` : une colonne inutile est une
  /// colonne de plus sur le fil.
  static const String colonnes = 'id, date, slot, required_count';

  final String id;

  /// Le jour du mois, en **base 1**. Le mois vient de la période.
  final int jour;

  final CreneauType creneau;
  final int effectifRequis;

  CreneauPlanning avecEffectif(int effectif) => CreneauPlanning(
    id: id,
    jour: jour,
    creneau: creneau,
    effectifRequis: effectif,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreneauPlanning &&
          other.id == id &&
          other.jour == jour &&
          other.creneau == creneau &&
          other.effectifRequis == effectifRequis;

  @override
  int get hashCode => Object.hash(id, jour, creneau, effectifRequis);
}

/// L'attribution d'un membre à un créneau (`docs/SCHEMA.md § 2.10`).
///
/// En brouillon, elle vaut toujours `proposed` avec `proposed_at` nul : rien
/// n'est parti, rien n'attend de réponse (`docs/WORKFLOWS.md § 3`). L'écran
/// n'écrit donc ni statut ni horodatage.
@immutable
class Attribution {
  const Attribution({
    required this.id,
    required this.creneauId,
    required this.userId,
    this.etat = AttributionEtat.propose,
    this.etaitDisponible = true,
    this.auteurId,
    this.locale = false,
  });

  factory Attribution.depuisJson(Map<String, dynamic> ligne) => Attribution(
    id: ligne['id']! as String,
    creneauId: ligne['shift_id']! as String,
    userId: ligne['user_id']! as String,
    etat: AttributionSql.depuisSql(ligne['status'] as String?),
    etaitDisponible: (ligne['was_available'] as bool?) ?? true,
    auteurId: ligne['created_by'] as String?,
  );

  static const String colonnes =
      'id, shift_id, user_id, status, was_available, created_by';

  final String id;
  final String creneauId;
  final String userId;

  /// L'état de l'attribution, tel que la base le rend.
  ///
  /// **La colonne `status` était déjà lue et jetée** : le dépôt ne charge que
  /// les attributions actives (`proposed` et `accepted`), et en brouillon
  /// elles valent toutes `proposed`. Elle devient nécessaire au bandeau du
  /// mois (ticket 061b), qui compte les réponses en attente une fois le
  /// planning publié. Valeur par défaut `propose` : c'est ce qu'une
  /// attribution posée à l'écran vaut tant que rien n'est parti.
  final AttributionEtat etat;

  /// Faux quand le membre a été attribué hors de ses disponibilités.
  /// **Posé par la base**, jamais par le client : la trace ne se choisit pas
  /// (`assignments_trace_disponibilite`, migration 0018).
  final bool etaitDisponible;

  /// L'administrateur qui a posé l'attribution, tel que la base l'a inscrit.
  final String? auteurId;

  /// Vrai tant que le serveur n'a pas répondu : l'attribution existe à
  /// l'écran, pas encore en base. Elle disparaît si l'écriture échoue.
  final bool locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Attribution &&
          other.id == id &&
          other.creneauId == creneauId &&
          other.userId == userId &&
          other.etat == etat &&
          other.etaitDisponible == etaitDisponible &&
          other.auteurId == auteurId &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    id,
    creneauId,
    userId,
    etat,
    etaitDisponible,
    auteurId,
    locale,
  );
}

/// Le planning d'un mois : sa ligne `schedules`, sans ses créneaux.
@immutable
class PlanningBrouillon {
  const PlanningBrouillon({
    required this.id,
    required this.etat,
    this.publieLe,
    this.valideLe,
  });

  factory PlanningBrouillon.depuisJson(Map<String, dynamic> ligne) =>
      PlanningBrouillon(
        id: ligne['id']! as String,
        etat: PlanningSql.depuisSql(ligne['status'] as String?),
        publieLe: _instant(ligne['published_at']),
        valideLe: _instant(ligne['validated_at']),
      );

  static const String colonnes = 'id, status, published_at, validated_at';

  final String id;
  final PlanningEtat etat;

  /// Les deux horodatages sont **posés par la base** (`schedules_guard_transition`,
  /// migration 0019) : l'écran les lit, il ne les écrit jamais. `publieLe` est
  /// celui de la **première** publication, et il ne bouge plus.
  final DateTime? publieLe;
  final DateTime? valideLe;

  /// Vrai tant que le planning n'est pas publié : c'est la seule situation où
  /// cet écran écrit. Un statut inconnu se lit comme **publié** — le refus est
  /// le côté sûr, comme pour les périodes.
  bool get modifiable => etat == PlanningEtat.brouillon;

  static DateTime? _instant(Object? valeur) =>
      valeur is String ? DateTime.tryParse(valeur)?.toLocal() : null;

}

/// La date ISO d'un créneau, pour l'écriture. Le mois vient de la période :
/// un créneau ne porte que son jour.
String isoCreneau({
  required int annee,
  required int mois,
  required int jour,
}) => isoJour(DateTime(annee, mois, jour));
