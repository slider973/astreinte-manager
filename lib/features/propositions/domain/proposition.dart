import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';

/// Une astreinte proposée à ce membre, et à laquelle il n'a pas répondu.
///
/// C'est une ligne d'`assignments` (`docs/SCHEMA.md § 2.10`) jointe à son
/// créneau (`shifts`) et au planning qui la porte (`schedules`).
///
/// **Ce modèle n'a pas de `toJson()`, et c'est délibéré.** Le déclencheur
/// `assignments_member_transition` (`docs/SCHEMA.md § 4`) compare l'avant et
/// l'après en dehors d'une liste blanche de quatre colonnes : une
/// sérialisation complète, même à valeurs identiques, fait échouer **toute**
/// la requête. La charge utile d'une réponse est construite à la main dans le
/// dépôt, clé par clé (`design/021 § 3`).
@immutable
class Proposition {
  const Proposition({
    required this.id,
    required this.creneauId,
    required this.planningId,
    required this.jour,
    required this.creneau,
    required this.planningEtat,
    this.proposeeLe,
    this.relances = 0,
    this.derniereRelance,
  });

  /// Construit depuis la réponse PostgREST. Aucune colonne inventée.
  ///
  /// Rend `null` quand la ligne n'a pas de créneau lisible : une attribution
  /// dont le `shift` est masqué par la RLS n'est pas une erreur, c'est une
  /// attribution qu'on n'a pas le droit de voir.
  static Proposition? depuisJson(Map<String, dynamic> ligne) {
    final creneau = ligne['shifts'];
    if (creneau is! Map<String, dynamic>) return null;

    final planning = creneau['schedules'];
    final date = creneau['date'];
    final slot = creneau['slot'];
    if (date is! String || slot is! String) return null;

    return Proposition(
      id: ligne['id']! as String,
      creneauId: creneau['id']! as String,
      planningId: creneau['schedule_id']! as String,
      jour: depuisIsoJour(date),
      creneau: CreneauSql.depuisSql(slot),
      planningEtat: planning is Map<String, dynamic>
          ? PlanningSql.depuisSql(planning['status'] as String?)
          : PlanningEtat.publie,
      proposeeLe: _instant(ligne['proposed_at']),
      relances: (ligne['reminder_count'] as int?) ?? 0,
      derniereRelance: _instant(ligne['last_reminder_at']),
    );
  }

  /// Les colonnes lues, créneau et planning compris. Jamais `select *` : une
  /// colonne inutile est une colonne de plus sur le fil, et surtout une
  /// colonne de plus qu'un jour quelqu'un renverrait au serveur.
  static const String colonnes =
      'id, status, proposed_at, reminder_count, last_reminder_at, '
      'shifts!inner(id, date, slot, schedule_id, schedules!inner(id, status))';

  final String id;
  final String creneauId;
  final String planningId;

  /// Le jour du créneau, local à minuit. Jamais un horodatage.
  final DateTime jour;

  final CreneauType creneau;

  /// L'état du planning qui porte ce créneau. `draft` n'arrive jamais ici :
  /// la RLS ne le laisse pas sortir (`docs/SCHEMA.md § 4`). `archived`, lui,
  /// arrive depuis le ticket 044 — d'où [repondable].
  final PlanningEtat planningEtat;

  /// L'instant de la publication. **Jamais nul dans cet écran** : une
  /// attribution sans `proposed_at` est un brouillon, et un brouillon n'a rien
  /// demandé à personne (`docs/WORKFLOWS.md § 3`).
  final DateTime? proposeeLe;

  final int relances;
  final DateTime? derniereRelance;

  /// Vrai quand la base acceptera encore une réponse sur cette attribution.
  ///
  /// `assignments_update_member_response` (`docs/SCHEMA.md § 4`) n'ouvre
  /// l'écriture que sur un planning `published` ou `validated`. Sur un mois
  /// **archivé**, la ligne reste lisible — c'est l'histoire du membre, et
  /// `assignments_select_own_published` la lui rend quel que soit son statut —
  /// mais l'`update` ne toucherait plus aucune ligne. Afficher la carte, c'est
  /// afficher un bouton « Accepter » qui ne fait rien, puis le message « cette
  /// proposition n'est plus là » à chaque appui.
  ///
  /// Une garde du mois de mars ne se prend pas en novembre : ce n'est plus une
  /// question posée, c'est un fait. L'écran des propositions est une liste de
  /// choses à faire (`design/021 § 1`), et il n'y a plus rien à y faire.
  bool get repondable =>
      planningEtat == PlanningEtat.publie ||
      planningEtat == PlanningEtat.valide;

  /// La clé du mois auquel la proposition appartient : `2026-10`.
  String get cleMois =>
      '${jour.year}-${jour.month.toString().padLeft(2, '0')}';

  /// « Octobre 2026 », pour l'en-tête de groupe.
  String get libelleMois => AppStrings.moisNomEtAnnee(jour.month, jour.year);

  /// « octobre », pour une phrase : « Planning d'octobre validé ».
  ///
  /// Le mois du créneau **est** celui du planning : les créneaux sont générés
  /// pour tous les jours de la période, et une période est un mois
  /// (`docs/SCHEMA.md § 2.5`, `§ 2.9`). Aucune requête de plus n'est donc
  /// nécessaire pour nommer le mois validé.
  String get nomMois => AppStrings.moisLongs[jour.month - 1];

  /// L'ordre du calendrier : par date, puis jour avant nuit. C'est le seul
  /// ordre de l'écran (`design/021 § 6.1`).
  int comparer(Proposition autre) {
    final parJour = jour.compareTo(autre.jour);
    if (parJour != 0) return parJour;
    return creneau.index.compareTo(autre.creneau.index);
  }

  static DateTime? _instant(Object? valeur) =>
      valeur is String ? DateTime.tryParse(valeur)?.toLocal() : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Proposition &&
          other.id == id &&
          other.creneauId == creneauId &&
          other.planningId == planningId &&
          other.jour == jour &&
          other.creneau == creneau &&
          other.planningEtat == planningEtat &&
          other.proposeeLe == proposeeLe &&
          other.relances == relances &&
          other.derniereRelance == derniereRelance;

  @override
  int get hashCode => Object.hash(
    id,
    creneauId,
    planningId,
    jour,
    creneau,
    planningEtat,
    proposeeLe,
    relances,
    derniereRelance,
  );
}

/// Un élément de la liste défilante : un en-tête de mois, ou une proposition.
///
/// La liste est **aplatie une fois par état** et rendue par
/// `ListView.builder` : soixante-deux propositions sont légales, et un
/// `Column` dans un `SingleChildScrollView` les construirait toutes à chaque
/// image.
sealed class ElementListe {
  const ElementListe();
}

/// L'en-tête d'un mois : « Octobre 2026 », et combien de lignes suivent.
final class EnteteMois extends ElementListe {
  const EnteteMois({
    required this.cle,
    required this.libelle,
    required this.compte,
    required this.premier,
  });

  /// `2026-10`.
  final String cle;

  /// « Octobre 2026 ».
  final String libelle;

  final int compte;

  /// Le premier en-tête de l'écran n'a pas besoin du grand écart du dessus.
  final bool premier;
}

/// Une ligne de proposition.
final class LigneProposition extends ElementListe {
  const LigneProposition(this.proposition);

  final Proposition proposition;
}

/// Aplatit les propositions en éléments de liste, groupés par mois et triés
/// par date.
List<ElementListe> aplatir(List<Proposition> propositions) {
  if (propositions.isEmpty) return const <ElementListe>[];

  final triees = <Proposition>[...propositions]
    ..sort((Proposition a, Proposition b) => a.comparer(b));

  final elements = <ElementListe>[];
  String? moisCourant;
  var premier = true;

  for (var index = 0; index < triees.length; index++) {
    final proposition = triees[index];
    if (proposition.cleMois != moisCourant) {
      moisCourant = proposition.cleMois;
      var compte = 0;
      for (final autre in triees) {
        if (autre.cleMois == moisCourant) compte++;
      }
      elements.add(
        EnteteMois(
          cle: moisCourant,
          libelle: proposition.libelleMois,
          compte: compte,
          premier: premier,
        ),
      );
      premier = false;
    }
    elements.add(LigneProposition(proposition));
  }

  return List<ElementListe>.unmodifiable(elements);
}
