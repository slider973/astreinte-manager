import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ouverture_stub.dart' if (dart.library.js_interop) 'ouverture_web.dart';

/// Envoie le navigateur vers une adresse **hors de l'application** : la page de
/// paiement du prestataire, son portail de gestion (ticket 029).
///
/// Une fonction, pas un paquet. `url_launcher` ferait la même chose en tirant
/// une implémentation par plateforme pour un `window.open` de trois lignes ; le
/// canal principal du produit est la PWA (`CLAUDE.md`), et le reste du projet
/// résout déjà ce genre de besoin par import conditionnel
/// (`plateforme/detection_web.dart`).
///
/// Rend `false` quand l'ouverture a été refusée — typiquement un bloqueur de
/// fenêtres. L'écran le dit alors et propose l'adresse : un onglet bloqué en
/// silence laisserait un chef de centre devant un bouton qui ne fait rien.
typedef OuvrirExterne = bool Function(String adresse);

/// Surchargé par un faux dans les tests : aucun test n'ouvre d'onglet.
final Provider<OuvrirExterne> ouvertureExterneProvider =
    Provider<OuvrirExterne>((ref) => ouvrirAdresseExterne);
