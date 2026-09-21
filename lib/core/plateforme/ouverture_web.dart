import 'package:web/web.dart' as web;

/// Ouvre une adresse dans un **nouvel onglet**.
///
/// `noopener` n'est pas une précaution de façade : sans lui, la page ouverte
/// garde une référence vers `window.opener` et peut remplacer l'onglet de
/// l'application par ce qu'elle veut. Ici la destination est le prestataire de
/// paiement, mais l'adresse vient d'une réponse HTTP : on ne lui prête pas plus
/// de pouvoir qu'il n'en faut.
///
/// Rend `false` quand le navigateur a refusé — bloqueur de fenêtres. L'appelant
/// le dit à l'écran plutôt que de laisser un bouton sans effet.
bool ouvrirAdresseExterne(String adresse) {
  try {
    final fenetre = web.window.open(adresse, '_blank', 'noopener,noreferrer');
    return fenetre != null;
  } on Object {
    return false;
  }
}
