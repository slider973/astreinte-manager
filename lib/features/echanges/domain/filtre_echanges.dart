/// Les trois filtres de la file de l'administrateur, **dans l'adresse**
/// (`?filtre=a-valider|en-attente|termines`, `design/073 § 8.2`).
enum FiltreEchanges {
  aValider('a-valider'),
  enAttente('en-attente'),
  termines('termines');

  const FiltreEchanges(this.valeurUrl);

  final String valeurUrl;

  /// « À valider » par défaut : c'est le seul où il y a quelque chose à faire.
  static FiltreEchanges depuisUrl(String? valeur) {
    for (final filtre in values) {
      if (filtre.valeurUrl == valeur) return filtre;
    }
    return aValider;
  }
}
