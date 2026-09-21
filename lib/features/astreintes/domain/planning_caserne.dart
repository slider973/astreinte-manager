import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';
import 'astreinte.dart';

/// Un mois que le sélecteur peut atteindre : **un planning**, pas une case de
/// calendrier.
///
/// Le sélecteur marche de planning en planning et non de mois en mois : si
/// octobre et décembre ont un planning mais pas novembre, « › » depuis octobre
/// mène à décembre. Un mois sans planning n'est pas une destination, il n'y a
/// rien à y voir (`design/023 § 5`).
@immutable
class MoisPlanning {
  const MoisPlanning({
    required this.planningId,
    required this.annee,
    required this.mois,
    required this.etat,
  });

  /// Les colonnes lues. `periods` est lisible par tout membre
  /// (`docs/SCHEMA.md § 4`), et c'est elle qui porte l'année et le mois.
  static const String colonnes = 'id, status, periods!inner(year, month)';

  /// Les deux seuls états qui donnent quelque chose à lire à un membre.
  ///
  /// **Ce n'est pas une redite de la RLS** : `schedules_select_member_published`
  /// laisse passer `archived`, mais `shifts_select_member_published` ne rend
  /// les créneaux que sur `published` ou `validated`. Un mois archivé
  /// n'afficherait donc rien du tout. Et un administrateur, lui, voit aussi ses
  /// brouillons — qui n'ont rien à faire ici.
  static const List<String> etatsLisibles = <String>['published', 'validated'];

  /// Construit depuis la réponse PostgREST. Rend `null` sur une ligne sans
  /// période lisible plutôt que de lever : une ligne qu'on ne comprend pas est
  /// un mois qu'on n'atteint pas, pas un écran cassé.
  static MoisPlanning? depuisJson(Map<String, dynamic> ligne) {
    final periode = ligne['periods'];
    if (periode is! Map<String, dynamic>) return null;

    final annee = periode['year'];
    final mois = periode['month'];
    final id = ligne['id'];
    if (annee is! int || mois is! int || id is! String) return null;

    return MoisPlanning(
      planningId: id,
      annee: annee,
      mois: mois,
      etat: PlanningSql.depuisSql(ligne['status'] as String?),
    );
  }

  final String planningId;
  final int annee;
  final int mois;
  final PlanningEtat etat;

  /// Le premier du mois, local à minuit.
  DateTime get premierJour => DateTime(annee, mois);

  /// La clé du mois : `2026-10`. Sert de clé de cache et d'identité.
  String get cle => '$annee-${mois.toString().padLeft(2, '0')}';

  /// « Octobre 2026 ».
  String get libelle => AppStrings.moisNomEtAnnee(mois, annee);

  /// Vrai quand la caserne entière est lisible. C'est **la** distinction de cet
  /// écran, et c'est la base qui la porte : `assignments_select_station_validated`
  /// n'ouvre les attributions des autres que sur un planning `validated`
  /// (`docs/SCHEMA.md § 4`).
  bool get complet => etat == PlanningEtat.valide;

  /// L'ordre du calendrier.
  int comparer(MoisPlanning autre) {
    final parAnnee = annee.compareTo(autre.annee);
    return parAnnee != 0 ? parAnnee : mois.compareTo(autre.mois);
  }

  /// Vrai quand ce mois est antérieur à celui d'[aujourdhui].
  bool passe(DateTime aujourdhui) =>
      annee < aujourdhui.year ||
      (annee == aujourdhui.year && mois < aujourdhui.month);

  /// Vrai quand ce mois **est** celui d'[aujourdhui].
  bool courant(DateTime aujourdhui) =>
      annee == aujourdhui.year && mois == aujourdhui.month;

  Map<String, dynamic> versCache() => <String, dynamic>{
    'p': planningId,
    'a': annee,
    'm': mois,
    'e': etat.valeurSql,
  };

  static MoisPlanning? depuisCache(Object? entree) {
    if (entree is! Map<String, dynamic>) return null;
    final planningId = entree['p'];
    final annee = entree['a'];
    final mois = entree['m'];
    if (planningId is! String ||
        annee is! int ||
        mois is! int ||
        mois < 1 ||
        mois > 12) {
      return null;
    }
    return MoisPlanning(
      planningId: planningId,
      annee: annee,
      mois: mois,
      etat: PlanningSql.depuisSql(entree['e'] as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoisPlanning &&
          other.planningId == planningId &&
          other.annee == annee &&
          other.mois == mois &&
          other.etat == etat;

  @override
  int get hashCode => Object.hash(planningId, annee, mois, etat);
}

/// Le mois sur lequel l'écran s'ouvre : **le mois courant s'il a un planning,
/// sinon le premier à venir, sinon le plus récent passé**.
///
/// Un pompier qui ouvre l'écran le 28 octobre pense à novembre, pas à
/// septembre (`design/023 § 5`).
MoisPlanning? moisDouverturePlanning(
  List<MoisPlanning> mois,
  DateTime aujourdhui,
) {
  if (mois.isEmpty) return null;

  final tries = <MoisPlanning>[...mois]
    ..sort((MoisPlanning a, MoisPlanning b) => a.comparer(b));

  for (final candidat in tries) {
    if (candidat.courant(aujourdhui)) return candidat;
  }
  for (final candidat in tries) {
    if (!candidat.passe(aujourdhui)) return candidat;
  }
  return tries.last;
}

/// Un créneau du planning de la caserne : qui est d'astreinte, ce soir-là.
@immutable
class CreneauCaserne {
  const CreneauCaserne({
    required this.id,
    required this.creneau,
    required this.requis,
    this.noms = const <String>[],
    this.moi = false,
    this.anonymes = 0,
  });

  /// Les colonnes lues sur `shifts`. Jamais `select *`.
  static const String colonnes = 'id, date, slot, required_count';

  final String id;
  final CreneauType creneau;

  /// L'effectif demandé par la caserne sur ce créneau (`shifts.required_count`).
  ///
  /// Sert à ne **pas** écrire « Personne n'est d'astreinte » sur un créneau
  /// dont la caserne ne veut personne : ce serait annoncer un trou là où il n'y
  /// a pas de besoin.
  final int requis;

  /// Les autres membres acceptés, par nom d'usage, dans l'ordre alphabétique.
  /// Il n'y a pas d'autre ordre juste entre deux personnes d'un même créneau.
  final List<String> noms;

  /// Vrai quand le lecteur est lui-même sur ce créneau. Il n'apparaît pas dans
  /// [noms] : l'écran le nomme « toi », en tête, et le marque.
  final bool moi;

  /// Les membres acceptés dont le nom n'a pas pu être lu — quelqu'un qui a
  /// quitté la caserne. Comptés, jamais affichés : un UUID à l'écran n'est pas
  /// une information (`design/023 § 7.2`).
  final int anonymes;

  /// Combien de personnes sont d'astreinte, lecteur compris.
  int get effectif => noms.length + anonymes + (moi ? 1 : 0);

  /// Vrai quand personne n'est d'astreinte sur ce créneau.
  bool get personne => effectif == 0;

  /// Vrai quand il n'y a **rien** à montrer : personne, et personne n'est
  /// demandé. Un tel créneau ne s'affiche pas.
  bool get muet => personne && requis == 0;

  Map<String, dynamic> versCache() => <String, dynamic>{
    'i': id,
    's': creneau.valeurSql,
    'r': requis,
    if (noms.isNotEmpty) 'n': noms,
    if (moi) 'moi': true,
    if (anonymes > 0) 'x': anonymes,
  };

  static CreneauCaserne? depuisCache(Object? entree) {
    if (entree is! Map<String, dynamic>) return null;
    final id = entree['i'];
    final slot = entree['s'];
    if (id is! String || (slot != 'day' && slot != 'night')) return null;

    final noms = entree['n'];
    return CreneauCaserne(
      id: id,
      creneau: CreneauSql.depuisSql(slot as String),
      requis: entree['r'] is int ? entree['r']! as int : 1,
      noms: noms is List
          ? <String>[
              for (final nom in noms)
                if (nom is String) nom,
            ]
          : const <String>[],
      moi: entree['moi'] == true,
      anonymes: entree['x'] is int ? entree['x']! as int : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreneauCaserne &&
          other.id == id &&
          other.creneau == creneau &&
          other.requis == requis &&
          other.moi == moi &&
          other.anonymes == anonymes &&
          listEquals(other.noms, noms);

  @override
  int get hashCode =>
      Object.hash(id, creneau, requis, moi, anonymes, Object.hashAll(noms));
}

/// Une journée du registre : sa date et ses créneaux, jour avant nuit.
@immutable
class JourneeCaserne {
  const JourneeCaserne({required this.date, required this.creneaux});

  /// Local à minuit. Jamais un horodatage.
  final DateTime date;

  final List<CreneauCaserne> creneaux;

  bool get porteMoi => creneaux.any((CreneauCaserne c) => c.moi);

  bool get weekend =>
      date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

  Map<String, dynamic> versCache() => <String, dynamic>{
    'd': isoJour(date),
    'c': <Map<String, dynamic>>[
      for (final creneau in creneaux) creneau.versCache(),
    ],
  };

  static JourneeCaserne? depuisCache(Object? entree) {
    if (entree is! Map<String, dynamic>) return null;
    final date = entree['d'];
    if (date is! String) return null;
    final jour = DateTime.tryParse(date);
    if (jour == null) return null;

    final creneaux = entree['c'];
    return JourneeCaserne(
      date: DateTime(jour.year, jour.month, jour.day),
      creneaux: <CreneauCaserne>[
        if (creneaux is List)
          for (final creneau in creneaux)
            if (CreneauCaserne.depuisCache(creneau)
                case final CreneauCaserne lu)
              lu,
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JourneeCaserne &&
          other.date == date &&
          listEquals(other.creneaux, creneaux);

  @override
  int get hashCode => Object.hash(date, Object.hashAll(creneaux));
}

/// Le planning d'un mois, tel que ce membre a le droit de le lire.
@immutable
class PlanningCaserne {
  const PlanningCaserne({
    required this.mois,
    this.journees = const <JourneeCaserne>[],
    this.heures = HeuresAffichage.defaut,
    this.luLe,
  });

  final MoisPlanning mois;

  /// Les journées à afficher, déjà filtrées par [assemblerJournees].
  final List<JourneeCaserne> journees;

  final HeuresAffichage heures;

  /// L'horodatage de la dernière lecture réussie du serveur. Nul tant qu'il n'y
  /// en a jamais eu : c'est ce qui distingue « je n'ai rien » de « je n'ai rien
  /// lu ».
  final DateTime? luLe;

  /// Vrai quand toute la caserne est lisible. Porté par la base
  /// (`docs/SCHEMA.md § 4`), jamais décidé ici.
  bool get complet => mois.complet;

  /// Vrai quand il n'y a aucune journée à montrer. Sur un planning seulement
  /// publié, cela veut dire « je n'ai pas d'astreinte ce mois-ci » — **pas**
  /// « le planning est vide », et c'est le bloc d'attente qui fait la
  /// différence.
  bool get vide => journees.isEmpty;

  PlanningCaserne copie({DateTime? luLe}) => PlanningCaserne(
    mois: mois,
    journees: journees,
    heures: heures,
    luLe: luLe ?? this.luLe,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanningCaserne &&
          other.mois == mois &&
          other.heures == heures &&
          other.luLe == luLe &&
          listEquals(other.journees, journees);

  @override
  int get hashCode =>
      Object.hash(mois, heures, luLe, Object.hashAll(journees));
}

/// Assemble les journées affichables d'un mois.
///
/// **C'est ici qu'est écrite la seule différence de forme entre les deux états
/// du planning** (`design/023 § 3`) :
///
/// - planning **validé** — la base rend tout : on affiche toutes les journées
///   qui portent au moins un créneau demandé. Un créneau sans personne est un
///   trou réel, et c'est une information ;
/// - planning **publié** — la base ne rend que les attributions du lecteur : on
///   n'affiche que les journées où il est attribué. Écrire « Personne n'est
///   d'astreinte » sur les vingt-neuf autres serait un mensonge de mise en
///   page, puisque quelqu'un y est sûrement et qu'on n'a pas le droit de
///   savoir qui.
List<JourneeCaserne> assemblerJournees({
  required PlanningEtat etat,
  required Map<DateTime, List<CreneauCaserne>> parJour,
}) {
  final complet = etat == PlanningEtat.valide;
  final journees = <JourneeCaserne>[];

  for (final entree in parJour.entries) {
    final creneaux = <CreneauCaserne>[
      for (final creneau in entree.value)
        if (!creneau.muet) creneau,
    ]..sort(
      (CreneauCaserne a, CreneauCaserne b) =>
          a.creneau.index.compareTo(b.creneau.index),
    );
    if (creneaux.isEmpty) continue;

    final journee = JourneeCaserne(date: entree.key, creneaux: creneaux);
    if (!complet && !journee.porteMoi) continue;
    journees.add(journee);
  }

  journees.sort((JourneeCaserne a, JourneeCaserne b) => a.date.compareTo(b.date));
  return List<JourneeCaserne>.unmodifiable(journees);
}
