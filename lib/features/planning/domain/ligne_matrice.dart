import 'package:flutter/foundation.dart';

import '../../../core/theme/app_status.dart';

/// L'alphabet des cellules de `availability_matrix` (migration 0017).
///
/// Cinq caractères, pas un de plus. La minuscule porte **le même état de
/// disponibilité** que la majuscule : elle dit seulement que la saisie a été
/// faite par un administrateur à la place du membre. C'est ce qui fait
/// survivre la marque de procuration au rechargement.
///
/// Un caractère inconnu se lit « non saisi » : la grille ne plante pas pour
/// un octet qu'elle ne comprend pas (brief § 7.1).
enum CelluleMatrice {
  nonSaisi('.', DisponibiliteEtat.nonSaisi, parAdmin: false),
  disponible('D', DisponibiliteEtat.disponible, parAdmin: false),
  absent('A', DisponibiliteEtat.absent, parAdmin: false),
  disponibleParAdmin('d', DisponibiliteEtat.disponible, parAdmin: true),
  absentParAdmin('a', DisponibiliteEtat.absent, parAdmin: true);

  const CelluleMatrice(this.code, this.etat, {required this.parAdmin});

  /// Le caractère rendu par la base.
  final String code;

  /// L'état de disponibilité, celui que la case peint.
  final DisponibiliteEtat etat;

  /// Vrai quand un administrateur a saisi à la place du membre.
  final bool parAdmin;

  /// Vrai dès que quelque chose a été saisi, par qui que ce soit.
  bool get saisie => etat != DisponibiliteEtat.nonSaisi;

  /// Décode un caractère. Tout ce qui n'est pas l'un des cinq vaut
  /// « non saisi ».
  static CelluleMatrice depuisCode(String code) => switch (code) {
    'D' => CelluleMatrice.disponible,
    'A' => CelluleMatrice.absent,
    'd' => CelluleMatrice.disponibleParAdmin,
    'a' => CelluleMatrice.absentParAdmin,
    _ => CelluleMatrice.nonSaisi,
  };

  /// La cellule que produit une écriture de l'écran : c'est **toujours** une
  /// saisie par procuration, puisque seul un admin écrit ici.
  static CelluleMatrice parAdminPour(DisponibiliteEtat etat) => switch (etat) {
    DisponibiliteEtat.disponible => CelluleMatrice.disponibleParAdmin,
    DisponibiliteEtat.absent => CelluleMatrice.absentParAdmin,
    DisponibiliteEtat.nonSaisi => CelluleMatrice.nonSaisi,
  };

  /// Le cycle de la case, identique à celui du ticket 011 : non saisi →
  /// disponible → absent → non saisi. Un chef qui a vu l'écran d'un pompier
  /// ne réapprend rien.
  static DisponibiliteEtat suivant(DisponibiliteEtat etat) => switch (etat) {
    DisponibiliteEtat.nonSaisi => DisponibiliteEtat.disponible,
    DisponibiliteEtat.disponible => DisponibiliteEtat.absent,
    DisponibiliteEtat.absent => DisponibiliteEtat.nonSaisi,
  };
}

/// Une ligne de `availability_matrix` : un membre actif et son mois.
///
/// **Les deux chaînes sont décodées une seule fois**, à la construction. La
/// grille lit ensuite [cellule] en temps constant : une matrice qui se peint
/// case par case n'a pas à redécouper une chaîne à chaque image (brief § 7.2).
///
/// Les quotas sont typés tels que la base les rend : `null` veut dire
/// **illimité**, jamais zéro, et un reste peut être **négatif** — le PRD § 5.3
/// autorise l'admin à dépasser un plafond. Aucune valeur n'est coercée.
@immutable
class LigneMatrice {
  LigneMatrice({
    required this.userId,
    required this.nomAffiche,
    required String jours,
    required String nuits,
    this.prenom,
    this.nom,
    this.commentaire,
    this.maxAstreintes,
    this.maxWeekends,
    this.astreintes = 0,
    this.unitesWeekend = 0,
    this.astreintesRestantes,
    this.weekendsRestants,
    this.accepteesPrecedentes = 0,
  }) : _jours = _decoder(jours),
       _nuits = _decoder(nuits);

  /// Construit depuis une ligne rendue par la fonction. Quatorze champs,
  /// jamais un quinzième (brief § 7.1).
  factory LigneMatrice.depuisJson(Map<String, dynamic> ligne) => LigneMatrice(
    userId: ligne['user_id']! as String,
    nomAffiche: (ligne['display_name'] as String?) ?? '',
    prenom: ligne['first_name'] as String?,
    nom: ligne['last_name'] as String?,
    commentaire: ligne['comment'] as String?,
    maxAstreintes: ligne['max_shifts'] as int?,
    maxWeekends: ligne['max_weekends'] as int?,
    astreintes: (ligne['shifts_count'] as int?) ?? 0,
    unitesWeekend: (ligne['weekend_units'] as int?) ?? 0,
    astreintesRestantes: ligne['shifts_left'] as int?,
    weekendsRestants: ligne['weekends_left'] as int?,
    accepteesPrecedentes: (ligne['accepted_previous'] as int?) ?? 0,
    jours: (ligne['day_slots'] as String?) ?? '',
    nuits: (ligne['night_slots'] as String?) ?? '',
  );

  final String userId;

  /// `display_name`, ou le nom complet du profil. Texte libre, non borné.
  final String nomAffiche;

  final String? prenom;
  final String? nom;

  /// Le commentaire du mois écrit par le membre au ticket 013. `text` sans
  /// contrainte de longueur en base : on tronque à l'affichage.
  final String? commentaire;

  final int? maxAstreintes;
  final int? maxWeekends;
  final int astreintes;
  final int unitesWeekend;

  /// `null` = pas de plafond. Peut être **négatif**.
  final int? astreintesRestantes;
  final int? weekendsRestants;

  /// Astreintes acceptées sur les trois mois précédents. Pas de colonne à
  /// l'écran : elle vit dans la sémantique et départage les égalités du tri.
  final int accepteesPrecedentes;

  final List<CelluleMatrice> _jours;
  final List<CelluleMatrice> _nuits;

  /// Le nombre de jours du mois, tel que la base l'a encodé : 28, 30 ou 31.
  /// **Jamais supposé** — un mois court a une chaîne courte.
  int get nombreDeJours => _jours.length;

  bool get aUnCommentaire => (commentaire ?? '').trim().isNotEmpty;

  /// Vrai dès qu'une case du mois porte autre chose que « non saisi ».
  bool get aSaisiQuelqueChose =>
      _jours.any((CelluleMatrice c) => c.saisie) ||
      _nuits.any((CelluleMatrice c) => c.saisie);

  /// La cellule du [jour] (1 pour le premier du mois) et du [creneau].
  ///
  /// **La chaîne est indexée à partir de 0 : `jours[jour − 1]`.** Un jour hors
  /// bornes rend « non saisi » plutôt que de lever : une grille ne tombe pas
  /// pour un index.
  CelluleMatrice cellule(int jour, CreneauType creneau) {
    final index = jour - 1;
    final chaine = creneau == CreneauType.jour ? _jours : _nuits;
    if (index < 0 || index >= chaine.length) return CelluleMatrice.nonSaisi;
    return chaine[index];
  }

  /// L'état de disponibilité seul, sans l'auteur.
  DisponibiliteEtat etatDe(int jour, CreneauType creneau) =>
      cellule(jour, creneau).etat;

  /// La même ligne, une cellule remplacée. Sert à l'écriture optimiste : la
  /// grille montre ce qui part, pas ce qu'elle espère relire.
  LigneMatrice avec(int jour, CreneauType creneau, CelluleMatrice cellule) {
    final index = jour - 1;
    if (index < 0 || index >= nombreDeJours) return this;

    final jours = creneau == CreneauType.jour
        ? (<CelluleMatrice>[..._jours]..[index] = cellule)
        : _jours;
    final nuits = creneau == CreneauType.nuit
        ? (<CelluleMatrice>[..._nuits]..[index] = cellule)
        : _nuits;

    return LigneMatrice(
      userId: userId,
      nomAffiche: nomAffiche,
      prenom: prenom,
      nom: nom,
      commentaire: commentaire,
      maxAstreintes: maxAstreintes,
      maxWeekends: maxWeekends,
      astreintes: astreintes,
      unitesWeekend: unitesWeekend,
      astreintesRestantes: astreintesRestantes,
      weekendsRestants: weekendsRestants,
      accepteesPrecedentes: accepteesPrecedentes,
      jours: jours.map((CelluleMatrice c) => c.code).join(),
      nuits: nuits.map((CelluleMatrice c) => c.code).join(),
    );
  }

  /// La même ligne, avec la charge du mois **recomptée sur les attributions
  /// déjà à l'écran**.
  ///
  /// `v_member_load` compte les mêmes choses — astreintes proposées ou
  /// acceptées du mois, unités de weekend distinctes — mais elle les a comptées
  /// au chargement. Attribuer quelqu'un rendrait donc son quota faux jusqu'à la
  /// prochaine lecture, et **un quota faux est exactement ce que cet écran ne
  /// doit pas afficher** : c'est sur lui que le chef décide.
  ///
  /// Le plafond, lui, ne bouge pas : `null` reste illimité, et le reste peut
  /// devenir négatif — l'admin a le droit de dépasser.
  LigneMatrice avecCharge({required int astreintes, required int unitesWeekend}) {
    if (astreintes == this.astreintes && unitesWeekend == this.unitesWeekend) {
      return this;
    }
    return LigneMatrice(
      userId: userId,
      nomAffiche: nomAffiche,
      prenom: prenom,
      nom: nom,
      commentaire: commentaire,
      maxAstreintes: maxAstreintes,
      maxWeekends: maxWeekends,
      astreintes: astreintes,
      unitesWeekend: unitesWeekend,
      astreintesRestantes: maxAstreintes == null
          ? null
          : maxAstreintes! - astreintes,
      weekendsRestants: maxWeekends == null
          ? null
          : maxWeekends! - unitesWeekend,
      accepteesPrecedentes: accepteesPrecedentes,
      jours: _jours.map((CelluleMatrice c) => c.code).join(),
      nuits: _nuits.map((CelluleMatrice c) => c.code).join(),
    );
  }

  static List<CelluleMatrice> _decoder(String chaine) =>
      List<CelluleMatrice>.unmodifiable(<CelluleMatrice>[
        for (var index = 0; index < chaine.length; index++)
          CelluleMatrice.depuisCode(chaine[index]),
      ]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LigneMatrice &&
          other.userId == userId &&
          other.nomAffiche == nomAffiche &&
          other.commentaire == commentaire &&
          other.maxAstreintes == maxAstreintes &&
          other.maxWeekends == maxWeekends &&
          other.astreintes == astreintes &&
          other.unitesWeekend == unitesWeekend &&
          other.astreintesRestantes == astreintesRestantes &&
          other.weekendsRestants == weekendsRestants &&
          other.accepteesPrecedentes == accepteesPrecedentes &&
          listEquals(other._jours, _jours) &&
          listEquals(other._nuits, _nuits);

  @override
  int get hashCode => Object.hash(
    userId,
    nomAffiche,
    commentaire,
    maxAstreintes,
    maxWeekends,
    astreintes,
    unitesWeekend,
    astreintesRestantes,
    weekendsRestants,
    accepteesPrecedentes,
    Object.hashAll(_jours),
    Object.hashAll(_nuits),
  );
}
