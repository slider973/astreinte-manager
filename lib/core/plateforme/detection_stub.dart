import 'contexte_plateforme.dart';

/// Hors du web : pas de navigateur, pas d'écran d'accueil à garnir.
///
/// Cette version est compilée pour les builds iOS et Android natifs, qui ne
/// sont produits qu'à la demande d'une caserne (`CLAUDE.md`).
ContextePlateforme detecterContextePlateforme() => ContextePlateforme.natif;
