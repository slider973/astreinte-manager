/// Les adresses de l'ancienne stratégie d'URL, celle du dièse.
///
/// Jusqu'au ticket 046, l'application servait ses routes derrière un dièse
/// (`https://…/#/invite/xyz`). Des courriels partis avant la bascule portent
/// encore cette forme : un lien d'invitation, un lien de notification. Sans
/// rien, ils ouvriraient l'accueil et perdraient la destination — un jeton
/// d'invitation abandonné, sans message, sans rattrapage.
///
/// La fonction est pure : elle se teste sans navigateur.
library;

/// Le chemin d'application caché derrière un ancien dièse, ou `null` s'il n'y
/// en a pas.
///
/// Renvoie `null` pour tout ce qui n'est **pas** une route de l'application :
///
/// - un fragment vide, ou une ancre ordinaire (`#contenu`) ;
/// - les jetons du fournisseur d'authentification (`#access_token=…`), qui
///   arrivent exactement au même endroit et que `supabase_flutter` consomme
///   lui-même — c'est tout l'objet du ticket 046 ;
/// - une adresse qui sortirait de l'application : adresse absolue
///   (`#https://ailleurs/…`), adresse de protocole (`#javascript:…`), chemin à
///   double barre oblique (`#//ailleurs`, qui est une autorité). La valeur
///   renvoyée est réinjectée dans la barre d'adresse : elle doit être interne,
///   et le vérifier ici est moins coûteux que de le regretter.
/// - l'accueil nu (`#/`), qui n'apprend rien.
String? cheminHerite(String fragment) {
  final chemin = fragment.startsWith('#') ? fragment.substring(1) : fragment;

  if (!chemin.startsWith('/')) return null;
  if (chemin == '/') return null;
  if (chemin.startsWith('//')) return null;
  // Certains navigateurs lisent `/\ailleurs` comme `//ailleurs`.
  if (chemin.contains(r'\')) return null;

  final uri = Uri.tryParse(chemin);
  if (uri == null) return null;
  if (uri.hasScheme || uri.hasAuthority) return null;
  if (uri.path.isEmpty) return null;

  return chemin;
}
