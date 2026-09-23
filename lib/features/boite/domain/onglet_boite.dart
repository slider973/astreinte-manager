import '../../../core/l10n/app_strings.dart';

/// Les trois onglets de la Boîte (`design/064 § 3.4`).
///
/// **L'onglet vit dans l'URL**, jamais dans un cache local : `/boite?onglet=
/// propositions` est l'adresse où mènent « Tout voir » de l'accueil, le lien
/// public `/proposals` et l'ancienne route `/propositions`. Un onglet retenu
/// sur l'appareil aurait fait ouvrir la Boîte ailleurs que là où le lien
/// promettait, et il aurait survécu à une déconnexion — ce que la règle des
/// caches de `CLAUDE.md` interdit.
enum OngletBoite {
  /// Les propositions **et** les rappels, fusionnés par date décroissante.
  tout('tout', AppStrings.boiteOngletTout, AppStrings.boiteOngletToutAnnonce),

  /// Les propositions en attente, groupées par mois.
  propositions(
    'propositions',
    AppStrings.boiteOngletPropositions,
    AppStrings.boiteOngletPropositionsAnnonce,
  ),

  /// Les notifications qui ne sont pas des propositions.
  rappels(
    'rappels',
    AppStrings.boiteOngletRappels,
    AppStrings.boiteOngletRappelsAnnonce,
  );

  const OngletBoite(this.valeurUrl, this.libelle, this.annonce);

  /// Ce qui s'écrit dans `?onglet=`. Un mot, pas un numéro : une adresse
  /// doit se lire, et `?onglet=1` ne dit rien à qui la relit dans un
  /// historique (la leçon d'`ongletHerite`, ticket 064a).
  final String valeurUrl;

  /// Le mot écrit sur l'onglet.
  final String libelle;

  /// Le mot annoncé, qui dit ce que l'onglet contient. « Tout » tout seul ne
  /// dit pas de quoi.
  final String annonce;

  /// L'onglet nommé par [valeur], **« Tout » par défaut**.
  ///
  /// Une valeur inconnue — un lien bricolé, un onglet retiré d'une version
  /// future — n'est pas une erreur : « Tout » contient les deux autres, donc
  /// personne n'arrive sur une page qui ne montre pas ce qu'il cherchait.
  static OngletBoite depuisUrl(String? valeur) {
    for (final onglet in values) {
      if (onglet.valeurUrl == valeur) return onglet;
    }
    return tout;
  }
}
