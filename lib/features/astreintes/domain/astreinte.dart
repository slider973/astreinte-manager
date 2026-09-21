import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';

/// Vrai quand la base rend les attributions de **toute** la caserne sur un
/// planning dans cet état, et pas seulement celles du lecteur.
///
/// Deux états, deux politiques, une seule règle écrite ici :
///
/// - `validated` — `assignments_select_station_validated` ouvre le mois figé ;
/// - `archived` — `assignments_select_station_archived` (migration `0031`)
///   ouvre les attributions `accepted` du mois écoulé. C'est la décision du
///   ticket 044 : un planning archivé se lit comme le tableau de garde du mois
///   passé, punaisé au mur.
///
/// Sur un planning `published`, la base ne rend que les attributions du
/// lecteur : l'écran ne montre que ses propres créneaux, et dit pourquoi.
bool caserneEntiereLisible(PlanningEtat etat) =>
    etat == PlanningEtat.valide || etat == PlanningEtat.archive;

/// Les heures d'affichage d'une caserne (`stations.settings`,
/// `docs/SCHEMA.md § 2.1`).
///
/// **Affichage uniquement** : rien n'est découpé par ces heures, aucun créneau
/// n'en dépend. Elles répondent pourtant à la seule question que la date ne
/// couvre pas — « à quelle heure je prends ». La nuit est l'intervalle
/// complémentaire du jour : `day_end → day_start`.
@immutable
class HeuresAffichage {
  const HeuresAffichage({required this.debutJour, required this.finJour});

  /// Les valeurs par défaut de la colonne `settings` (migration `0001`).
  /// Servent quand la caserne n'a pas pu être lue : afficher 07:00 – 19:00 est
  /// l'hypothèse la plus probable, et elle est marquée comme telle par le fait
  /// qu'elle vient d'ici.
  static const HeuresAffichage defaut = HeuresAffichage(
    debutJour: '07:00',
    finJour: '19:00',
  );

  /// « 07:00 ».
  final String debutJour;

  /// « 19:00 ».
  final String finJour;

  /// « 07:00 → 19:00 » en journée, « 19:00 → 07:00 » la nuit.
  String intervalle(CreneauType creneau) => creneau == CreneauType.jour
      ? AppStrings.astreintesIntervalle(debutJour, finJour)
      : AppStrings.astreintesIntervalle(finJour, debutJour);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeuresAffichage &&
          other.debutJour == debutJour &&
          other.finJour == finJour;

  @override
  int get hashCode => Object.hash(debutJour, finJour);
}

/// Une astreinte **acceptée** par ce membre.
///
/// C'est une ligne d'`assignments` (`docs/SCHEMA.md § 2.10`) jointe à son
/// créneau (`shifts`) et au planning qui la porte (`schedules`).
///
/// **Elle n'expose pas de `toJson()`**, comme [Proposition] au ticket 021 et
/// pour la même raison : `assignments_member_transition` compare l'avant et
/// l'après en dehors d'une liste blanche de quatre colonnes. Cet écran
/// n'écrit d'ailleurs rien du tout. Ce qu'elle expose est un [versCache], dont
/// le nom dit où il va et où il ne va pas.
@immutable
class Astreinte {
  const Astreinte({
    required this.id,
    required this.creneauId,
    required this.planningId,
    required this.jour,
    required this.creneau,
    required this.planningEtat,
    this.equipiers = const <String>[],
  });

  /// Construit depuis la réponse PostgREST. Aucune colonne inventée.
  ///
  /// Rend `null` quand la ligne n'a pas de créneau lisible : une attribution
  /// dont le `shift` est masqué par la RLS n'est pas une erreur, c'est une
  /// attribution qu'on n'a pas le droit de voir.
  static Astreinte? depuisJson(
    Map<String, dynamic> ligne, {
    List<String> equipiers = const <String>[],
  }) {
    final creneau = ligne['shifts'];
    if (creneau is! Map<String, dynamic>) return null;

    final date = creneau['date'];
    final slot = creneau['slot'];
    if (date is! String || slot is! String) return null;

    final planning = creneau['schedules'];

    return Astreinte(
      id: ligne['id']! as String,
      creneauId: creneau['id']! as String,
      planningId: creneau['schedule_id']! as String,
      jour: depuisIsoJour(date),
      creneau: CreneauSql.depuisSql(slot),
      planningEtat: planning is Map<String, dynamic>
          ? PlanningSql.depuisSql(planning['status'] as String?)
          : PlanningEtat.publie,
      equipiers: equipiers,
    );
  }

  /// Les colonnes lues, créneau et planning compris. Jamais `select *`.
  static const String colonnes =
      'id, shift_id, status, '
      'shifts!inner(id, date, slot, schedule_id, schedules!inner(id, status))';

  final String id;
  final String creneauId;
  final String planningId;

  /// Le jour du créneau, local à minuit. Jamais un horodatage.
  final DateTime jour;

  final CreneauType creneau;

  /// L'état du planning qui porte ce créneau. **Jamais `brouillon`** : la RLS
  /// ne laisse sortir que `published`, `validated` et — depuis le ticket 044 —
  /// `archived` (`supabase/migrations/0031`, politiques
  /// `shifts_select_member_published` et `assignments_select_own_published`).
  ///
  /// `archive` arrive bel et bien jusqu'ici : l'écran remonte un an
  /// d'historique, et tout mois révolu est archivé le 1er du mois suivant.
  final PlanningEtat planningEtat;

  /// Les autres membres acceptés sur ce créneau, par nom d'usage.
  ///
  /// **Vide tant que le planning est seulement publié**, et c'est la base qui
  /// le décide : `assignments_select_station_validated` n'ouvre les
  /// attributions des autres que sur un planning `validated`, et
  /// `assignments_select_station_archived` les gardes tenues d'un mois
  /// archivé. L'écran n'affiche donc pas une liste vide, il affiche la phrase
  /// qui explique l'attente.
  final List<String> equipiers;

  /// Vrai quand les autres noms sont **connaissables**. Ce n'est pas la même
  /// chose que « il y a des équipiers » : sur un planning validé, une liste
  /// vide veut dire « tu es seul », ce qui est une information.
  ///
  /// **Archivé compte comme validé** (ticket 044) : sur un mois écoulé, la
  /// base rend les attributions `accepted` de toute la caserne. Écrire « en
  /// attente de la validation » sur une garde tenue il y a huit mois serait
  /// annoncer une décision qui n'arrivera jamais.
  bool get equipiersConnus => caserneEntiereLisible(planningEtat);

  /// La clé du mois : `2026-10`.
  String get cleMois =>
      '${jour.year}-${jour.month.toString().padLeft(2, '0')}';

  /// « Octobre 2026 », pour l'en-tête de groupe.
  String get libelleMois => AppStrings.moisNomEtAnnee(jour.month, jour.year);

  /// Vrai quand le jour du créneau est **strictement** antérieur à
  /// aujourd'hui.
  ///
  /// La frontière est le jour, pas l'instant : une astreinte de nuit du jour
  /// même reste « à venir » toute la journée, elle ne bascule pas dans les
  /// passées à 8 h du matin (`design/027 § 7.2`).
  bool passee(DateTime aujourdhui) {
    final minuit = DateTime(
      aujourdhui.year,
      aujourdhui.month,
      aujourdhui.day,
    );
    return jour.isBefore(minuit);
  }

  /// La même astreinte, avec ses équipiers. Le seul `copyWith` du modèle, et
  /// il n'a qu'un appelant : le dépôt, qui lit les noms dans une seconde
  /// requête.
  Astreinte avecEquipiers(List<String> noms) => Astreinte(
    id: id,
    creneauId: creneauId,
    planningId: planningId,
    jour: jour,
    creneau: creneau,
    planningEtat: planningEtat,
    equipiers: noms,
  );

  /// L'ordre du calendrier : par date, puis jour avant nuit.
  int comparer(Astreinte autre) {
    final parJour = jour.compareTo(autre.jour);
    if (parJour != 0) return parJour;
    return creneau.index.compareTo(autre.creneau.index);
  }

  /// Le document rangé dans le cache local. **Jamais envoyé à la base** : les
  /// clés sont courtes parce qu'elles sont relues par cette classe seule, et
  /// les noms y sont déjà résolus parce que hors ligne il n'y a pas de table
  /// de correspondance à consulter (`design/027 § 8.2`).
  Map<String, dynamic> versCache() => <String, dynamic>{
    'id': id,
    'c': creneauId,
    'p': planningId,
    'd': isoJour(jour),
    's': creneau.valeurSql,
    'e': planningEtat.valeurSql,
    if (equipiers.isNotEmpty) 'm': equipiers,
  };

  /// Relit une entrée du cache. Rend `null` sur un document illisible : un
  /// cache abîmé vaut un cache vide.
  static Astreinte? depuisCache(Object? entree) {
    if (entree is! Map<String, dynamic>) return null;
    final id = entree['id'];
    final creneauId = entree['c'];
    final planningId = entree['p'];
    final date = entree['d'];
    final slot = entree['s'];
    if (id is! String ||
        creneauId is! String ||
        planningId is! String ||
        date is! String ||
        (slot != 'day' && slot != 'night')) {
      return null;
    }
    final jour = DateTime.tryParse(date);
    if (jour == null) return null;

    final membres = entree['m'];
    return Astreinte(
      id: id,
      creneauId: creneauId,
      planningId: planningId,
      jour: DateTime(jour.year, jour.month, jour.day),
      creneau: CreneauSql.depuisSql(slot as String),
      planningEtat: PlanningSql.depuisSql(entree['e'] as String?),
      equipiers: membres is List
          ? <String>[
              for (final nom in membres)
                if (nom is String) nom,
            ]
          : const <String>[],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Astreinte &&
          other.id == id &&
          other.creneauId == creneauId &&
          other.planningId == planningId &&
          other.jour == jour &&
          other.creneau == creneau &&
          other.planningEtat == planningEtat &&
          listEquals(other.equipiers, equipiers);

  @override
  int get hashCode => Object.hash(
    id,
    creneauId,
    planningId,
    jour,
    creneau,
    planningEtat,
    Object.hashAll(equipiers),
  );
}

/// Tout ce que l'écran affiche, et tout ce que le cache garde.
///
/// [luLe] est l'horodatage de la **dernière lecture réussie du serveur**. Il
/// est nul tant qu'il n'y en a jamais eu : c'est ce qui distingue « je n'ai
/// rien » de « je n'ai rien lu ».
@immutable
class MesAstreintes {
  const MesAstreintes({
    this.astreintes = const <Astreinte>[],
    this.heures = HeuresAffichage.defaut,
    this.luLe,
  });

  final List<Astreinte> astreintes;
  final HeuresAffichage heures;
  final DateTime? luLe;

  /// Vrai quand rien n'a jamais été lu : ni du serveur, ni du cache.
  bool get jamaisLu => luLe == null;

  /// Les astreintes à venir, dans l'ordre du calendrier.
  List<Astreinte> aVenir(DateTime aujourdhui) => <Astreinte>[
    for (final astreinte in astreintes)
      if (!astreinte.passee(aujourdhui)) astreinte,
  ]..sort((Astreinte a, Astreinte b) => a.comparer(b));

  /// Les astreintes passées, **la plus récente d'abord**. On ne remonte pas le
  /// temps depuis son entrée dans la caserne : on regarde en arrière depuis
  /// aujourd'hui (`design/027 § 7.2`).
  List<Astreinte> passees(DateTime aujourdhui) => <Astreinte>[
    for (final astreinte in astreintes)
      if (astreinte.passee(aujourdhui)) astreinte,
  ]..sort((Astreinte a, Astreinte b) => b.comparer(a));

  /// Les astreintes du mois affiché par le calendrier, rangées par jour.
  Map<int, List<Astreinte>> parJourDuMois(int annee, int mois) {
    final parJour = <int, List<Astreinte>>{};
    for (final astreinte in astreintes) {
      if (astreinte.jour.year != annee || astreinte.jour.month != mois) {
        continue;
      }
      (parJour[astreinte.jour.day] ??= <Astreinte>[]).add(astreinte);
    }
    for (final jour in parJour.values) {
      jour.sort((Astreinte a, Astreinte b) => a.comparer(b));
    }
    return parJour;
  }

  /// Le mois sur lequel le calendrier s'ouvre : **celui de la prochaine
  /// astreinte**, et le mois courant à défaut.
  ///
  /// Le mois courant est souvent vide — un planning se construit un mois à
  /// l'avance — et ouvrir sur une grille sans aucune marque demande de
  /// comprendre qu'il faut appuyer sur une flèche. Vu dans Chrome
  /// (`design/027 § 11`).
  DateTime moisDouverture(DateTime aujourdhui) {
    final prochaines = aVenir(aujourdhui);
    if (prochaines.isEmpty) {
      return DateTime(aujourdhui.year, aujourdhui.month);
    }
    final jour = prochaines.first.jour;
    return DateTime(jour.year, jour.month);
  }

  /// Les mois que le calendrier peut atteindre : du premier mois porteur
  /// d'une astreinte au dernier, et **toujours** le mois courant. Une flèche
  /// qui ne mène nulle part est désactivée, pas cachée.
  (DateTime, DateTime) etendue(DateTime aujourdhui) {
    var premier = DateTime(aujourdhui.year, aujourdhui.month);
    var dernier = premier;
    for (final astreinte in astreintes) {
      final mois = DateTime(astreinte.jour.year, astreinte.jour.month);
      if (mois.isBefore(premier)) premier = mois;
      if (mois.isAfter(dernier)) dernier = mois;
    }
    return (premier, dernier);
  }

  MesAstreintes copie({
    List<Astreinte>? astreintes,
    HeuresAffichage? heures,
    DateTime? luLe,
  }) => MesAstreintes(
    astreintes: astreintes ?? this.astreintes,
    heures: heures ?? this.heures,
    luLe: luLe ?? this.luLe,
  );
}

/// Un élément de la liste défilante.
///
/// La liste est **aplatie une fois par état** et rendue par
/// `ListView.builder` : l'historique n'est jamais supprimé
/// (`docs/PRD.md § 7.6`), donc les passées se comptent en centaines après deux
/// ans d'usage.
sealed class ElementAstreintes {
  const ElementAstreintes();
}

/// L'en-tête d'un mois : « Octobre 2026 », et combien de lignes suivent.
final class EnteteMoisAstreintes extends ElementAstreintes {
  const EnteteMoisAstreintes({
    required this.cle,
    required this.libelle,
    required this.compte,
    required this.premier,
  });

  final String cle;
  final String libelle;
  final int compte;

  /// Le premier en-tête de l'écran n'a pas besoin du grand écart du dessus.
  final bool premier;
}

/// Une ligne d'astreinte.
final class LigneAstreinte extends ElementAstreintes {
  const LigneAstreinte(this.astreinte, {this.passee = false});

  final Astreinte astreinte;

  /// Les passées sont atténuées : ce sont des faits, pas des rendez-vous.
  final bool passee;
}

/// Le repli des passées : une ligne, un compte, un chevron.
final class ReplisPassees extends ElementAstreintes {
  const ReplisPassees({required this.compte, required this.ouvert});

  final int compte;
  final bool ouvert;
}

/// Aplatit les astreintes en éléments de liste : les à venir groupées par mois
/// croissant, puis le repli, puis — s'il est ouvert — les passées groupées par
/// mois décroissant.
List<ElementAstreintes> aplatirAstreintes({
  required MesAstreintes donnees,
  required DateTime aujourdhui,
  required bool passeesOuvertes,
}) {
  final elements = <ElementAstreintes>[];

  final aVenir = donnees.aVenir(aujourdhui);
  _grouper(elements, aVenir, passee: false);

  final passees = donnees.passees(aujourdhui);
  if (passees.isEmpty) return List<ElementAstreintes>.unmodifiable(elements);

  // Le repli **n'existe pas** quand il n'y a rien derrière : un accordéon vide
  // est un piège.
  elements.add(
    ReplisPassees(compte: passees.length, ouvert: passeesOuvertes),
  );
  // L'en-tête du premier mois passé n'apparaît qu'une fois le repli ouvert :
  // annoncer une section qui n'est pas là serait un mensonge de mise en page.
  if (passeesOuvertes) _grouper(elements, passees, passee: true);

  return List<ElementAstreintes>.unmodifiable(elements);
}

void _grouper(
  List<ElementAstreintes> elements,
  List<Astreinte> astreintes, {
  required bool passee,
}) {
  if (astreintes.isEmpty) return;

  final comptes = <String, int>{};
  for (final astreinte in astreintes) {
    comptes[astreinte.cleMois] = (comptes[astreinte.cleMois] ?? 0) + 1;
  }

  String? moisCourant;
  var premier = elements.isEmpty;
  for (final astreinte in astreintes) {
    if (astreinte.cleMois != moisCourant) {
      moisCourant = astreinte.cleMois;
      elements.add(
        EnteteMoisAstreintes(
          cle: moisCourant,
          libelle: astreinte.libelleMois,
          compte: comptes[moisCourant] ?? 0,
          premier: premier,
        ),
      );
      premier = false;
    }
    elements.add(LigneAstreinte(astreinte, passee: passee));
  }
}
