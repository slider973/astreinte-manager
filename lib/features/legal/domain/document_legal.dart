import 'package:flutter/foundation.dart';

/// Un document juridique du produit : politique de confidentialité, mentions
/// légales.
///
/// **C'est une donnée, pas un widget.** Quatre pages de texte écrites en dur
/// dans un `Column` seraient impossibles à relire, impossibles à faire relire
/// par quelqu'un qui n'écrit pas de Flutter, et contraires à la règle du projet
/// (« textes centralisés, jamais dans les widgets »). Le rendu est un seul
/// écran qui ne contient **aucune chaîne littérale**.
///
/// Les textes eux-mêmes sont dans `documents_legaux.dart`, et leur source de
/// vérité est `docs/RGPD.md` : ce que la page promet doit être ce que le
/// registre décrit, qui doit être ce que le schéma fait.
@immutable
class DocumentLegal {
  const DocumentLegal({
    required this.titre,
    required this.version,
    required this.chapeau,
    required this.sections,
  });

  /// Le titre de la page, premier élément lu.
  final String titre;

  /// « Version 1 — 21 septembre 2026 ». Un document juridique sans date n'en
  /// est pas un : on doit pouvoir dire lequel s'appliquait le mois dernier.
  final String version;

  /// Une phrase avant le sommaire des sections. Elle dit à qui la page
  /// s'adresse et ce qu'elle va répondre.
  final String chapeau;

  final List<SectionLegale> sections;
}

/// Une section : un titre, des paragraphes, et ce qui reste à décider.
@immutable
class SectionLegale {
  const SectionLegale({
    required this.titre,
    required this.paragraphes,
    this.aCompleter = const <String>[],
  });

  final String titre;

  /// Des phrases entières, pas des fragments à concaténer : une traduction ou
  /// une relecture juridique travaille sur des phrases.
  final List<String> paragraphes;

  /// Ce qui relève d'une **décision du propriétaire** et non du code : raison
  /// sociale, adresse, hébergeur contractuel, contact du responsable de
  /// traitement.
  ///
  /// Ces lignes s'affichent telles quelles, **en évidence**. On n'invente pas
  /// une mention légale plausible : la fausse se croit, la trouée se corrige.
  final List<String> aCompleter;
}
