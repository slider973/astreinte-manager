import 'package:flutter/foundation.dart';

/// **Ce qu'un membre veut vraiment faire dans un mois** — une ligne de
/// `availability_preferences` (`docs/SCHEMA.md § 2.7`).
///
/// C'est la moitié manquante du produit : la grille dit ce que le membre
/// **peut** faire, ceci dit ce qu'il **veut** faire. Cocher tous ses weekends
/// pour laisser le choix à son chef ne l'engage plus à tous les faire.
///
/// `null` signifie **autant que nécessaire**, exactement comme en base. `0`
/// est une valeur légitime et différente : « je suis disponible, mais ne me
/// planifie pas ce mois-ci ».
@immutable
class PreferencesMois {
  const PreferencesMois({
    this.maxAstreintes,
    this.maxWeekends,
    this.commentaire = '',
  });

  /// L'état par défaut d'un membre qui ne s'est jamais prononcé : aucune
  /// limite, aucun mot.
  static const PreferencesMois sansLimite = PreferencesMois();

  /// La borne du commentaire, posée **côté client**.
  ///
  /// La colonne est un `text` sans contrainte. 280 caractères, c'est la
  /// longueur d'une phrase utile — « Pas plus d'un weekend, garde des
  /// enfants. Je peux dépanner en semaine si besoin. » — et c'est ce que la
  /// matrice du ticket 016 pourra montrer dans une cellule sans devenir
  /// illisible.
  static const int commentaireMax = 280;

  /// Le nombre de caractères restants à partir duquel le compteur s'affiche.
  /// Un compteur permanent transforme une phrase libre en épreuve.
  static const int commentaireSeuilCompteur = 40;

  /// Le plus grand plafond d'astreintes proposé par la feuille de choix. Un
  /// mois compte au plus 62 créneaux ; au-delà de vingt astreintes, le choix
  /// n'est plus un choix, c'est une liste.
  static const int plafondAstreintesMax = 20;

  /// Relit une ligne PostgREST. Aucune colonne inventée.
  factory PreferencesMois.depuisJson(Map<String, dynamic> ligne) =>
      PreferencesMois(
        maxAstreintes: ligne['max_shifts'] as int?,
        maxWeekends: ligne['max_weekends'] as int?,
        commentaire: (ligne['comment'] as String?) ?? '',
      );

  /// `max_shifts` : le nombre maximal d'**astreintes**, c'est-à-dire de
  /// créneaux, jours et nuits confondus.
  final int? maxAstreintes;

  /// `max_weekends` : le nombre maximal d'**unités de weekend**, au sens de
  /// `uniteWeekend` — le même calcul que le compteur de la grille, jamais un
  /// second.
  final int? maxWeekends;

  /// `comment`, vide plutôt que nul à l'écran : un champ de texte n'a pas
  /// d'état « nul ». La chaîne vide s'écrit `null` en base.
  final String commentaire;

  bool get sansAucuneLimite => maxAstreintes == null && maxWeekends == null;

  /// Vrai quand le membre n'a rien à dire du tout. **Ce n'est pas une raison
  /// de supprimer la ligne** : « a dit : sans limite » n'est pas « n'a rien
  /// dit ».
  bool get vide => sansAucuneLimite && commentaire.isEmpty;

  PreferencesMois avecAstreintes(int? valeur) => PreferencesMois(
    maxAstreintes: valeur,
    maxWeekends: maxWeekends,
    commentaire: commentaire,
  );

  PreferencesMois avecWeekends(int? valeur) => PreferencesMois(
    maxAstreintes: maxAstreintes,
    maxWeekends: valeur,
    commentaire: commentaire,
  );

  PreferencesMois avecCommentaire(String texte) => PreferencesMois(
    maxAstreintes: maxAstreintes,
    maxWeekends: maxWeekends,
    commentaire: texte.length > commentaireMax
        ? texte.substring(0, commentaireMax)
        : texte,
  );

  /// La ligne prête à partir. La chaîne vide devient `null` : un commentaire
  /// effacé est un commentaire absent, pas un commentaire vide.
  Map<String, dynamic> versJson() => <String, dynamic>{
    'max_shifts': maxAstreintes,
    'max_weekends': maxWeekends,
    'comment': commentaire.isEmpty ? null : commentaire,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PreferencesMois &&
          other.maxAstreintes == maxAstreintes &&
          other.maxWeekends == maxWeekends &&
          other.commentaire == commentaire;

  @override
  int get hashCode => Object.hash(maxAstreintes, maxWeekends, commentaire);

  @override
  String toString() =>
      'PreferencesMois($maxAstreintes astreintes, $maxWeekends weekends, '
      '${commentaire.length} car.)';
}

/// Les préférences **telles que l'écran les porte** : la valeur, plus ce
/// qu'il faut savoir pour l'afficher honnêtement.
@immutable
class EtatPreferences {
  const EtatPreferences({
    this.valeurs = PreferencesMois.sansLimite,
    this.ligneAuChargement = false,
    this.repriseDe,
    this.enErreur = false,
  });

  final PreferencesMois valeurs;

  /// Vrai quand une ligne existait déjà pour ce mois au chargement : le
  /// membre s'est déjà prononcé, la section prend sa forme résumée.
  ///
  /// La reprise du mois précédent **écrit** une ligne mais ne change pas ce
  /// drapeau : la section reste ouverte pour que la reprise soit vue.
  final bool ligneAuChargement;

  /// Le numéro du mois d'où les valeurs ont été reprises, tant que le membre
  /// n'a rien changé. `null` : rien n'a été repris, ou il l'a déjà retouché.
  ///
  /// « La reprise doit être visible et modifiable, jamais silencieuse. »
  final int? repriseDe;

  /// L'écriture de la préférence a échoué : filet 2 dp `error` sur la
  /// section, valeur voulue conservée à l'écran.
  final bool enErreur;

  bool get reprise => repriseDe != null;

  EtatPreferences copyWith({
    PreferencesMois? valeurs,
    bool? ligneAuChargement,
    int? Function()? repriseDe,
    bool? enErreur,
  }) => EtatPreferences(
    valeurs: valeurs ?? this.valeurs,
    ligneAuChargement: ligneAuChargement ?? this.ligneAuChargement,
    repriseDe: repriseDe == null ? this.repriseDe : repriseDe(),
    enErreur: enErreur ?? this.enErreur,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EtatPreferences &&
          other.valeurs == valeurs &&
          other.ligneAuChargement == ligneAuChargement &&
          other.repriseDe == repriseDe &&
          other.enErreur == enErreur;

  @override
  int get hashCode =>
      Object.hash(valeurs, ligneAuChargement, repriseDe, enErreur);
}
