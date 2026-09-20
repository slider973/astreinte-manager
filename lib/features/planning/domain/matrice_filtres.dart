import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import 'ligne_matrice.dart';

/// Les trois ordres d'affichage de la matrice.
enum TriMatrice {
  /// L'ordre rendu par la fonction : par nom affiché. Le défaut.
  nom(AppStrings.matriceTriNom),

  astreintes(AppStrings.matriceTriAstreintes),

  weekends(AppStrings.matriceTriWeekends);

  const TriMatrice(this.libelle);

  final String libelle;
}

/// Ce que l'admin a demandé de voir. **Tout est calculé côté client**, sur les
/// soixante lignes déjà en mémoire : une recherche qui déclencherait une
/// requête serait une régression (brief § 2).
@immutable
class FiltresMatrice {
  const FiltresMatrice({
    this.recherche = '',
    this.masquerNonSaisis = false,
    this.tri = TriMatrice.nom,
    this.commentaires = true,
  });

  final String recherche;
  final bool masquerNonSaisis;
  final TriMatrice tri;

  /// Les commentaires dépliés sous les noms. **Ouverts par défaut** : une
  /// phrase enfouie est une phrase jamais lue (brief § 6.2).
  final bool commentaires;

  /// Vrai dès qu'un filtre masque potentiellement quelqu'un. Le tri et
  /// l'affichage des commentaires n'en sont pas : ils ne retirent personne.
  bool get actif => recherche.trim().isNotEmpty || masquerNonSaisis;

  FiltresMatrice copie({
    String? recherche,
    bool? masquerNonSaisis,
    TriMatrice? tri,
    bool? commentaires,
  }) => FiltresMatrice(
    recherche: recherche ?? this.recherche,
    masquerNonSaisis: masquerNonSaisis ?? this.masquerNonSaisis,
    tri: tri ?? this.tri,
    commentaires: commentaires ?? this.commentaires,
  );

  /// Filtre puis trie. Pur, testable sans widget.
  List<LigneMatrice> appliquer(List<LigneMatrice> lignes) {
    final terme = normaliser(recherche);

    final retenues = <LigneMatrice>[
      for (final ligne in lignes)
        if ((terme.isEmpty || _correspond(ligne, terme)) &&
            (!masquerNonSaisis || ligne.aSaisiQuelqueChose))
          ligne,
    ];

    retenues.sort(_comparer);
    return List<LigneMatrice>.unmodifiable(retenues);
  }

  bool _correspond(LigneMatrice ligne, String terme) =>
      normaliser(ligne.nomAffiche).contains(terme) ||
      normaliser('${ligne.prenom ?? ''} ${ligne.nom ?? ''}').contains(terme);

  int _comparer(LigneMatrice a, LigneMatrice b) => switch (tri) {
    TriMatrice.nom => _parNom(a, b),
    TriMatrice.astreintes => _parReste(
      a,
      b,
      a.astreintesRestantes,
      b.astreintesRestantes,
    ),
    TriMatrice.weekends => _parReste(
      a,
      b,
      a.weekendsRestants,
      b.weekendsRestants,
    ),
  };

  static int _parNom(LigneMatrice a, LigneMatrice b) {
    final ordre = normaliser(a.nomAffiche).compareTo(normaliser(b.nomAffiche));
    return ordre != 0 ? ordre : a.userId.compareTo(b.userId);
  }

  /// **Décroissant, `null` en tête.**
  ///
  /// Un illimité est la plus grande capacité disponible, pas l'absence de
  /// capacité : le ranger en queue mettrait les membres les plus disponibles
  /// hors de vue. Les égalités se départagent par `accepted_previous`
  /// croissant puis par le nom — **exactement** l'ordre des candidats du
  /// PRD § 5.3, que le chef retrouvera au ticket 017.
  static int _parReste(
    LigneMatrice a,
    LigneMatrice b,
    int? resteA,
    int? resteB,
  ) {
    if (resteA != resteB) {
      if (resteA == null) return -1;
      if (resteB == null) return 1;
      if (resteA != resteB) return resteB.compareTo(resteA);
    }
    if (a.accepteesPrecedentes != b.accepteesPrecedentes) {
      return a.accepteesPrecedentes.compareTo(b.accepteesPrecedentes);
    }
    return _parNom(a, b);
  }

  /// Minuscules **et sans accents** : on tape « dupond » et on trouve
  /// « Dupónd ». Aucune dépendance : la table tient en une ligne, et `intl`
  /// n'est pas embarqué.
  static String normaliser(String valeur) {
    final minuscules = valeur.trim().toLowerCase();
    final tampon = StringBuffer();
    for (final unite in minuscules.runes) {
      final caractere = String.fromCharCode(unite);
      tampon.write(_accents[caractere] ?? caractere);
    }
    return tampon.toString();
  }

  static const Map<String, String> _accents = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };
}
