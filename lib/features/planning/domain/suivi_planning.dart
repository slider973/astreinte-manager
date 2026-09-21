import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_status.dart';
import 'creneau_planning.dart';

/// Une attribution vue depuis le suivi : son état, sa date, son motif de refus.
///
/// Elle porte **le nom du membre**, joint à la lecture depuis `profiles` : le
/// suivi est une liste de noms, et aller chercher soixante profils après coup
/// serait une seconde requête pour une donnée que la première pouvait rendre.
@immutable
class AttributionSuivi {
  const AttributionSuivi({
    required this.id,
    required this.creneauId,
    required this.userId,
    required this.nom,
    required this.etat,
    this.proposeeLe,
    this.repondueLe,
    this.motifRefus,
    this.relances = 0,
    this.derniereRelance,
    this.remplaceParId,
  });

  /// [nom] vient de `memberships.display_name`, lu à part : **le nom d'usage
  /// de la caserne n'est pas dans `profiles`** (`docs/SCHEMA.md § 2.3`), et le
  /// canal temps réel ne diffuse de toute façon aucune jointure.
  factory AttributionSuivi.depuisJson(
    Map<String, dynamic> ligne, {
    String nom = '',
  }) {
    return AttributionSuivi(
      id: ligne['id']! as String,
      creneauId: ligne['shift_id']! as String,
      userId: ligne['user_id']! as String,
      nom: nom,
      etat: etatDepuisSql(ligne['status'] as String?),
      proposeeLe: _instant(ligne['proposed_at']),
      repondueLe: _instant(ligne['responded_at']),
      motifRefus: (ligne['decline_reason'] as String?)?.trim(),
      relances: (ligne['reminder_count'] as int?) ?? 0,
      derniereRelance: _instant(ligne['last_reminder_at']),
      remplaceParId: ligne['replaced_by'] as String?,
    );
  }

  /// Les colonnes lues. Jamais `select *` : une colonne inutile est une
  /// colonne de plus sur le fil.
  static const String colonnes =
      'id, shift_id, user_id, status, proposed_at, responded_at, '
      'decline_reason, reminder_count, last_reminder_at, replaced_by';

  /// Les colonnes de `memberships` qui donnent le nom d'usage d'un membre, et
  /// son repli quand il n'en a pas choisi.
  static const String colonnesMembre =
      'user_id, display_name, profiles!inner(first_name, last_name)';

  /// Le nom d'usage d'un membre, depuis une ligne de `memberships`.
  static String nomDeMembre(Map<String, dynamic> ligne) {
    final affiche = (ligne['display_name'] as String?)?.trim();
    if (affiche != null && affiche.isNotEmpty) return affiche;
    final profil = ligne['profiles'];
    return _nom(profil is Map<String, dynamic> ? profil : null);
  }

  final String id;
  final String creneauId;
  final String userId;

  /// Le nom d'usage du membre, tel que la caserne l'affiche.
  final String nom;

  final AttributionEtat etat;

  /// `null` tant que le planning n'est pas publié : c'est le signal
  /// « c'est parti » (`docs/WORKFLOWS.md § 3`).
  final DateTime? proposeeLe;

  final DateTime? repondueLe;

  /// Le motif écrit par le membre en refusant, ou celui écrit par
  /// l'administrateur en annulant (`docs/SCHEMA.md § 2.10`). C'est
  /// l'information la plus utile de l'écran : elle dit s'il faut chercher
  /// quelqu'un d'autre.
  final String? motifRefus;

  final int relances;
  final DateTime? derniereRelance;

  /// L'attribution qui a couvert celle-ci, quand il y en a une
  /// (`assignments.replaced_by`, posé par `reassign_shift`). Elle existe aussi
  /// sur un **refus**, qui reste un refus : c'est le fil qui dit « ce trou-là a
  /// été bouché par cette attribution-là ».
  final String? remplaceParId;

  /// Vrai pour les deux statuts qui occupent une place sur un créneau.
  bool get active =>
      etat == AttributionEtat.propose || etat == AttributionEtat.accepte;

  bool get enAttente => etat == AttributionEtat.propose;

  /// Vrai pour les trois états qui laissent un trou à boucher : un refus, un
  /// remplacement, une annulation. C'est ce qui rend une ligne du suivi
  /// **actionnable** plutôt que seulement lisible.
  bool get close =>
      etat == AttributionEtat.refuse ||
      etat == AttributionEtat.remplace ||
      etat == AttributionEtat.annule;

  bool get aUnMotif => (motifRefus ?? '').isNotEmpty;

  /// La même attribution, avec un autre nom d'affichage.
  ///
  /// **Le canal temps réel ne diffuse aucune jointure** : une ligne reçue par
  /// `postgres_changes` arrive sans nom d'usage, et le contrôleur lui rend
  /// celui qu'il connaît déjà. Cette copie existe pour que ce recollage ne
  /// puisse pas **perdre une colonne** : reconstruire l'objet champ par champ à
  /// l'appel a déjà coûté `replaced_by`, et avec lui le fil de l'historique et
  /// la disparition du bouton d'un créneau réparé.
  AttributionSuivi avecNom(String autre) => AttributionSuivi(
    id: id,
    creneauId: creneauId,
    userId: userId,
    nom: autre,
    etat: etat,
    proposeeLe: proposeeLe,
    repondueLe: repondueLe,
    motifRefus: motifRefus,
    relances: relances,
    derniereRelance: derniereRelance,
    remplaceParId: remplaceParId,
  );

  /// Vrai quand la réponse se fait attendre au-delà du délai de la caserne.
  /// **`proposeeLe` nul n'est jamais en retard** : un brouillon n'a rien
  /// demandé à personne. Même règle que `v_schedule_progress`.
  bool enRetard({required int delaiHeures, required DateTime maintenant}) {
    final depuis = proposeeLe;
    if (!enAttente || depuis == null) return false;
    return maintenant.difference(depuis).inHours >= delaiHeures;
  }

  /// `assignment_status` : cinq valeurs SQL, cinq états d'affichage depuis le
  /// ticket 020, qui est le premier à produire `replaced` et `cancelled`.
  ///
  /// Les deux partagent la marque barrée et l'encre atténuée — ils disent tous
  /// deux « cette attribution ne compte plus » — mais pas l'icône ni le
  /// libellé : « Remplacé » dit que la garde a changé de main, « Annulé » dit
  /// qu'elle n'existe plus. Un statut inconnu se lit comme annulé : le côté sûr
  /// est celui qui ne compte pas dans la couverture.
  static AttributionEtat etatDepuisSql(String? valeur) => switch (valeur) {
    'proposed' => AttributionEtat.propose,
    'accepted' => AttributionEtat.accepte,
    'declined' => AttributionEtat.refuse,
    'replaced' => AttributionEtat.remplace,
    _ => AttributionEtat.annule,
  };

  static DateTime? _instant(Object? valeur) =>
      valeur is String ? DateTime.tryParse(valeur)?.toLocal() : null;

  static String _nom(Map<String, dynamic>? profil) {
    if (profil == null) return '';
    final prenom = (profil['first_name'] as String?)?.trim() ?? '';
    final nom = (profil['last_name'] as String?)?.trim() ?? '';
    return '$prenom $nom'.trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttributionSuivi &&
          other.id == id &&
          other.creneauId == creneauId &&
          other.userId == userId &&
          other.nom == nom &&
          other.etat == etat &&
          other.proposeeLe == proposeeLe &&
          other.repondueLe == repondueLe &&
          other.motifRefus == motifRefus &&
          other.relances == relances &&
          other.derniereRelance == derniereRelance &&
          other.remplaceParId == remplaceParId;

  @override
  int get hashCode => Object.hash(
    id,
    creneauId,
    userId,
    nom,
    etat,
    proposeeLe,
    repondueLe,
    motifRefus,
    relances,
    derniereRelance,
    remplaceParId,
  );
}

/// Ce que `v_schedule_progress` rend, et que **rien ne recompte en Dart**.
///
/// La vue a été livrée au ticket 017 et n'était lue par personne ; c'est ici
/// qu'elle sert. Ses six nombres sont le bloc de progression de l'écran.
@immutable
class ProgressionPlanning {
  const ProgressionPlanning({
    required this.creneauxTotal,
    required this.creneauxPourvus,
    required this.enAttente,
    required this.acceptees,
    required this.refusees,
    required this.enRetard,
  });

  factory ProgressionPlanning.depuisJson(Map<String, dynamic> ligne) =>
      ProgressionPlanning(
        creneauxTotal: (ligne['shifts_total'] as int?) ?? 0,
        creneauxPourvus: (ligne['shifts_filled'] as int?) ?? 0,
        enAttente: (ligne['assignments_pending'] as int?) ?? 0,
        acceptees: (ligne['assignments_accepted'] as int?) ?? 0,
        refusees: (ligne['assignments_declined'] as int?) ?? 0,
        enRetard: (ligne['assignments_late'] as int?) ?? 0,
      );

  static const ProgressionPlanning vide = ProgressionPlanning(
    creneauxTotal: 0,
    creneauxPourvus: 0,
    enAttente: 0,
    acceptees: 0,
    refusees: 0,
    enRetard: 0,
  );

  static const String colonnes =
      'schedule_id, station_id, period_id, status, shifts_total, '
      'shifts_filled, assignments_pending, assignments_accepted, '
      'assignments_declined, assignments_late';

  /// `shifts_filled` compte les attributions **actives**, pas les
  /// acceptations : un créneau dont l'unique attribution est refusée redevient
  /// non pourvu, et c'est exactement ce que le chef doit voir.
  final int creneauxTotal;
  final int creneauxPourvus;

  final int enAttente;
  final int acceptees;
  final int refusees;
  final int enRetard;

  /// Les réponses reçues.
  int get reponses => acceptees + refusees;

  /// Les réponses attendues : **des personnes, pas des cases**.
  int get attendues => enAttente + acceptees + refusees;

  /// De 0 à 1. Un planning sans aucune attribution n'a rien à attendre : la
  /// barre est pleine plutôt que vide, parce qu'il n'y a rien qui manque.
  double get fraction => attendues == 0 ? 1 : reponses / attendues;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressionPlanning &&
          other.creneauxTotal == creneauxTotal &&
          other.creneauxPourvus == creneauxPourvus &&
          other.enAttente == enAttente &&
          other.acceptees == acceptees &&
          other.refusees == refusees &&
          other.enRetard == enRetard;

  @override
  int get hashCode => Object.hash(
    creneauxTotal,
    creneauxPourvus,
    enAttente,
    acceptees,
    refusees,
    enRetard,
  );
}

/// Un pompier qui n'a pas répondu depuis trop longtemps.
@immutable
class Retardataire {
  const Retardataire({
    required this.userId,
    required this.nom,
    required this.creneaux,
    required this.depuis,
    this.derniereRelance,
  });

  final String userId;
  final String nom;

  /// Combien de créneaux attendent sa réponse. C'est ce qui dit l'enjeu, donc
  /// ce qui vient en premier dans la ligne.
  final int creneaux;

  /// La plus ancienne de ses propositions sans réponse.
  final DateTime depuis;

  final DateTime? derniereRelance;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Retardataire &&
          other.userId == userId &&
          other.nom == nom &&
          other.creneaux == creneaux &&
          other.depuis == depuis &&
          other.derniereRelance == derniereRelance;

  @override
  int get hashCode =>
      Object.hash(userId, nom, creneaux, depuis, derniereRelance);
}

/// Les cinq puces de filtre de la liste des créneaux.
///
/// **Des puces, pas des onglets** : le chef veut souvent voir « en attente »
/// *et* « non pourvus » ensemble — ce qui reste à traiter. Un onglet forcerait
/// un choix exclusif (`design/019 § 6.7`).
enum FiltreSuivi {
  tous(AppStrings.suiviFiltreTous),
  enAttente(AppStrings.suiviFiltreAttente),
  acceptes(AppStrings.suiviFiltreAcceptes),
  refuses(AppStrings.suiviFiltreRefuses),
  nonPourvus(AppStrings.suiviFiltreNonPourvus);

  const FiltreSuivi(this.libelle);

  final String libelle;
}

/// Un créneau du suivi : sa couverture et les réponses reçues.
@immutable
class CreneauSuivi {
  const CreneauSuivi({required this.creneau, required this.attributions});

  final CreneauPlanning creneau;

  /// Toutes les attributions du créneau, actives ou non, dans l'ordre de leur
  /// état : en attente, acceptées, refusées, annulées.
  final List<AttributionSuivi> attributions;

  int get pourvus =>
      attributions.where((AttributionSuivi a) => a.active).length;

  EtatCouverture get couverture =>
      EtatCouverture.de(pourvus: pourvus, requis: creneau.effectifRequis);

  bool get nonPourvu => pourvus < creneau.effectifRequis;

  bool contient(AttributionEtat etat) =>
      attributions.any((AttributionSuivi a) => a.etat == etat);

  /// Le nom de celui qui a repris la garde de [attribution], ou `null`.
  ///
  /// Tout est déjà là : les attributions d'un créneau voyagent ensemble, et
  /// `replaced_by` pointe l'une d'entre elles. Sans cette phrase, l'historique
  /// montrerait une sortie sans montrer l'entrée, et le chef recompterait à la
  /// main.
  String? remplacantDe(AttributionSuivi attribution) {
    final cible = attribution.remplaceParId;
    if (cible == null) return null;
    for (final autre in attributions) {
      if (autre.id == cible) return autre.nom.isEmpty ? null : autre.nom;
    }
    return null;
  }

  /// Vrai quand ce créneau porte une décision à prendre : la place manque, ou
  /// un refus — une annulation, un remplacement — n'a **pas encore été
  /// couvert**.
  ///
  /// **C'est la seule condition qui rend une ligne du suivi actionnable.** Un
  /// créneau entièrement accepté et pourvu n'a rien à réparer, même s'il porte
  /// un refus dans son histoire : ce refus-là a déjà trouvé son remplaçant, et
  /// un élément qui a l'air cliquable sans servir est pire qu'un élément
  /// inerte.
  bool get aReparer => nonPourvu || aRemplacer != null;

  /// Vrai quand le créneau porte au moins une attribution close : le geste se
  /// nomme alors « Réattribuer » plutôt que « Pourvoir ».
  bool get porteUnRefus =>
      attributions.any((AttributionSuivi a) => a.close);

  /// L'attribution close de ce créneau qui n'a pas encore été couverte — celle
  /// que la réattribution vient réparer, et à laquelle la base posera le lien.
  ///
  /// **Le même ordre que `reassign_shift` (migration 0020)** : la plus ancienne
  /// réponse d'abord, celles qui n'en ont pas à la fin, puis la proposition la
  /// plus ancienne pour départager. L'écran et la base doivent désigner la
  /// **même** ligne, sinon le bandeau nomme un pompier et le lien en relie un
  /// autre le jour où l'écran cesse de fournir l'identifiant. Ici la liste ne
  /// dépasse jamais quelques entrées : un tri suffit, et il se lit.
  AttributionSuivi? get aRemplacer {
    final candidates =
        attributions
            .where(
              (AttributionSuivi a) => a.close && a.remplaceParId == null,
            )
            .toList(growable: false)
          ..sort(_ordreDuPlusAncienTrou);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// `order by responded_at nulls last, created_at` — le `order by` de la base,
  /// avec `proposeeLe` en second, seule date de création que l'écran connaisse.
  static int _ordreDuPlusAncienTrou(AttributionSuivi a, AttributionSuivi b) {
    final reponseA = a.repondueLe;
    final reponseB = b.repondueLe;
    if (reponseA != null && reponseB != null && reponseA != reponseB) {
      return reponseA.compareTo(reponseB);
    }
    if (reponseA == null && reponseB != null) return 1;
    if (reponseB == null && reponseA != null) return -1;

    final proposeeA = a.proposeeLe;
    final proposeeB = b.proposeeLe;
    if (proposeeA != null && proposeeB != null) {
      return proposeeA.compareTo(proposeeB);
    }
    if (proposeeA == null && proposeeB != null) return 1;
    if (proposeeB == null && proposeeA != null) return -1;
    return a.id.compareTo(b.id);
  }

  /// Vrai quand le créneau répond à au moins l'un des filtres retenus.
  bool correspond(Set<FiltreSuivi> filtres) {
    if (filtres.isEmpty || filtres.contains(FiltreSuivi.tous)) return true;
    for (final filtre in filtres) {
      final retenu = switch (filtre) {
        FiltreSuivi.tous => true,
        FiltreSuivi.enAttente => contient(AttributionEtat.propose),
        FiltreSuivi.acceptes => contient(AttributionEtat.accepte),
        FiltreSuivi.refuses => contient(AttributionEtat.refuse),
        FiltreSuivi.nonPourvus => nonPourvu,
      };
      if (retenu) return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreneauSuivi &&
          other.creneau == creneau &&
          listEquals(other.attributions, attributions);

  @override
  int get hashCode => Object.hash(creneau, Object.hashAll(attributions));
}

/// Une journée du mois et ses deux créneaux.
@immutable
class JourneeSuivi {
  const JourneeSuivi({required this.date, required this.creneaux});

  final DateTime date;
  final List<CreneauSuivi> creneaux;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JourneeSuivi &&
          other.date == date &&
          listEquals(other.creneaux, creneaux);

  @override
  int get hashCode => Object.hash(date, Object.hashAll(creneaux));
}

/// Le suivi d'un planning publié : ses créneaux, ses réponses, son avancement.
@immutable
class SuiviPlanning {
  SuiviPlanning({
    required this.planning,
    required this.progression,
    required List<CreneauPlanning> creneaux,
    required List<AttributionSuivi> attributions,
    required this.annee,
    required this.mois,
    this.delaiRetardHeures = 72,
  }) : _creneaux = <String, CreneauPlanning>{
         for (final creneau in creneaux) creneau.id: creneau,
       },
       _attributions = <String, AttributionSuivi>{
         for (final attribution in attributions) attribution.id: attribution,
       };

  /// Un mois dont le planning n'existe pas encore.
  static SuiviPlanning vide({required int annee, required int mois}) =>
      SuiviPlanning(
        planning: null,
        progression: ProgressionPlanning.vide,
        creneaux: const <CreneauPlanning>[],
        attributions: const <AttributionSuivi>[],
        annee: annee,
        mois: mois,
      );

  /// `null` tant que le planning du mois n'existe pas.
  final PlanningBrouillon? planning;

  final ProgressionPlanning progression;
  final int annee;
  final int mois;

  /// `settings.late_report_hours` de la caserne, **jamais un 72 écrit en dur** :
  /// le sous-titre du bloc des retardataires annonce le délai réel.
  final int delaiRetardHeures;

  final Map<String, CreneauPlanning> _creneaux;
  final Map<String, AttributionSuivi> _attributions;

  bool get existe => planning != null;

  /// Vrai quand il y a quelque chose à suivre : le planning est sorti du
  /// brouillon.
  bool get suivable =>
      planning != null && planning!.etat != PlanningEtat.brouillon;

  PlanningEtat get etat => planning?.etat ?? PlanningEtat.brouillon;

  Iterable<AttributionSuivi> get attributions => _attributions.values;

  AttributionSuivi? attributionParId(String id) => _attributions[id];

  CreneauPlanning? creneauParId(String id) => _creneaux[id];

  /// Les journées du mois, dans l'ordre, avec leurs créneaux et leurs réponses.
  ///
  /// **Construit une fois par état**, pas à chaque image : la liste est
  /// virtualisée et le tri de soixante-deux créneaux n'a aucune raison de se
  /// refaire pendant un défilement.
  List<JourneeSuivi> journees() {
    final parCreneau = <String, List<AttributionSuivi>>{};
    for (final attribution in _attributions.values) {
      (parCreneau[attribution.creneauId] ??= <AttributionSuivi>[]).add(
        attribution,
      );
    }

    final parJour = <int, List<CreneauSuivi>>{};
    for (final creneau in _creneaux.values) {
      final liste = parCreneau[creneau.id] ?? const <AttributionSuivi>[];
      (parJour[creneau.jour] ??= <CreneauSuivi>[]).add(
        CreneauSuivi(
          creneau: creneau,
          attributions: <AttributionSuivi>[...liste]..sort(_ordreDesReponses),
        ),
      );
    }

    final jours = parJour.keys.toList(growable: false)..sort();
    return <JourneeSuivi>[
      for (final jour in jours)
        JourneeSuivi(
          date: DateTime(annee, mois, jour),
          creneaux: parJour[jour]!
            ..sort(
              (CreneauSuivi a, CreneauSuivi b) =>
                  a.creneau.creneau.index.compareTo(b.creneau.creneau.index),
            ),
        ),
    ];
  }

  /// Le compte d'une puce de filtre, calculé sur les créneaux.
  int compte(FiltreSuivi filtre, List<JourneeSuivi> journees) {
    if (filtre == FiltreSuivi.tous) return _creneaux.length;
    var total = 0;
    for (final journee in journees) {
      for (final creneau in journee.creneaux) {
        if (creneau.correspond(<FiltreSuivi>{filtre})) total++;
      }
    }
    return total;
  }

  /// Les pompiers sans réponse au-delà du délai de la caserne, du plus ancien
  /// au plus récent.
  ///
  /// [maintenant] est injecté : un test qui dépend de l'horloge de la machine
  /// échoue une fois par jour, à l'heure où personne ne regarde.
  List<Retardataire> retardataires({DateTime? maintenant}) {
    final instant = maintenant ?? DateTime.now();
    final parMembre = <String, List<AttributionSuivi>>{};

    for (final attribution in _attributions.values) {
      if (!attribution.enRetard(
        delaiHeures: delaiRetardHeures,
        maintenant: instant,
      )) {
        continue;
      }
      (parMembre[attribution.userId] ??= <AttributionSuivi>[]).add(attribution);
    }

    final liste = <Retardataire>[
      for (final entree in parMembre.entries)
        Retardataire(
          userId: entree.key,
          nom: entree.value.first.nom,
          creneaux: entree.value.length,
          depuis: entree.value
              .map((AttributionSuivi a) => a.proposeeLe!)
              .reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b),
          derniereRelance: entree.value
              .map((AttributionSuivi a) => a.derniereRelance)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (DateTime? plus, DateTime candidat) =>
                    plus == null || candidat.isAfter(plus) ? candidat : plus,
              ),
        ),
    ];

    liste.sort(
      (Retardataire a, Retardataire b) => a.depuis.compareTo(b.depuis),
    );
    return liste;
  }

  /// La même donnée, une attribution remplacée — ce que le temps réel apporte.
  SuiviPlanning avecAttribution(AttributionSuivi attribution) => _copie(
    attributions: <String, AttributionSuivi>{
      ..._attributions,
      attribution.id: attribution,
    },
  );

  SuiviPlanning sansAttribution(String id) => _copie(
    attributions: <String, AttributionSuivi>{..._attributions}..remove(id),
  );

  /// Le planning a changé d'état sous nos yeux : c'est la validation
  /// automatique, et c'est le seul moment chorégraphié de l'application.
  SuiviPlanning avecPlanning(PlanningBrouillon entete) => SuiviPlanning(
    planning: entete,
    progression: progression,
    creneaux: _creneaux.values.toList(growable: false),
    attributions: _attributions.values.toList(growable: false),
    annee: annee,
    mois: mois,
    delaiRetardHeures: delaiRetardHeures,
  );

  SuiviPlanning avecProgression(ProgressionPlanning valeur) => SuiviPlanning(
    planning: planning,
    progression: valeur,
    creneaux: _creneaux.values.toList(growable: false),
    attributions: _attributions.values.toList(growable: false),
    annee: annee,
    mois: mois,
    delaiRetardHeures: delaiRetardHeures,
  );

  SuiviPlanning _copie({Map<String, AttributionSuivi>? attributions}) =>
      SuiviPlanning(
        planning: planning,
        progression: progression,
        creneaux: _creneaux.values.toList(growable: false),
        attributions: (attributions ?? _attributions).values.toList(
          growable: false,
        ),
        annee: annee,
        mois: mois,
        delaiRetardHeures: delaiRetardHeures,
      );

  /// En attente d'abord — c'est ce qui reste à faire —, puis accepté, refusé,
  /// annulé ; à état égal, l'ordre alphabétique.
  static int _ordreDesReponses(AttributionSuivi a, AttributionSuivi b) {
    final etats = a.etat.index.compareTo(b.etat.index);
    if (etats != 0) return etats;
    return a.nom.compareTo(b.nom);
  }
}
