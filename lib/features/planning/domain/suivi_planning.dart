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
  });

  factory AttributionSuivi.depuisJson(Map<String, dynamic> ligne) {
    final profil = ligne['profiles'];
    return AttributionSuivi(
      id: ligne['id']! as String,
      creneauId: ligne['shift_id']! as String,
      userId: ligne['user_id']! as String,
      nom: _nom(profil is Map<String, dynamic> ? profil : null),
      etat: etatDepuisSql(ligne['status'] as String?),
      proposeeLe: _instant(ligne['proposed_at']),
      repondueLe: _instant(ligne['responded_at']),
      motifRefus: (ligne['decline_reason'] as String?)?.trim(),
      relances: (ligne['reminder_count'] as int?) ?? 0,
      derniereRelance: _instant(ligne['last_reminder_at']),
    );
  }

  /// Les colonnes lues, plus le nom du membre par la clé étrangère
  /// `assignments.user_id`. Jamais `select *`.
  static const String colonnes =
      'id, shift_id, user_id, status, proposed_at, responded_at, '
      'decline_reason, reminder_count, last_reminder_at, '
      'profiles!assignments_user_id_fkey(display_name, first_name, last_name)';

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

  /// Le motif écrit par le membre en refusant. C'est l'information la plus
  /// utile de l'écran : elle dit s'il faut chercher quelqu'un d'autre.
  final String? motifRefus;

  final int relances;
  final DateTime? derniereRelance;

  /// Vrai pour les deux statuts qui occupent une place sur un créneau.
  bool get active =>
      etat == AttributionEtat.propose || etat == AttributionEtat.accepte;

  bool get enAttente => etat == AttributionEtat.propose;

  bool get aUnMotif => (motifRefus ?? '').isNotEmpty;

  /// Vrai quand la réponse se fait attendre au-delà du délai de la caserne.
  /// **`proposeeLe` nul n'est jamais en retard** : un brouillon n'a rien
  /// demandé à personne. Même règle que `v_schedule_progress`.
  bool enRetard({required int delaiHeures, required DateTime maintenant}) {
    final depuis = proposeeLe;
    if (!enAttente || depuis == null) return false;
    return maintenant.difference(depuis).inHours >= delaiHeures;
  }

  /// `assignment_status` : quatre valeurs d'affichage pour cinq valeurs SQL.
  ///
  /// `cancelled` et `replaced` partagent la marque barrée d'« annulé » : les
  /// deux disent « cette attribution ne compte plus », et le ticket 020 leur
  /// donnera leur libellé propre quand il les produira.
  static AttributionEtat etatDepuisSql(String? valeur) => switch (valeur) {
    'proposed' => AttributionEtat.propose,
    'accepted' => AttributionEtat.accepte,
    'declined' => AttributionEtat.refuse,
    _ => AttributionEtat.annule,
  };

  static DateTime? _instant(Object? valeur) =>
      valeur is String ? DateTime.tryParse(valeur)?.toLocal() : null;

  static String _nom(Map<String, dynamic>? profil) {
    if (profil == null) return '';
    final affiche = (profil['display_name'] as String?)?.trim();
    if (affiche != null && affiche.isNotEmpty) return affiche;
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
          other.derniereRelance == derniereRelance;

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
