/// Validation d'adresse e-mail côté saisie.
///
/// Volontairement permissive : elle attrape la faute de frappe évidente
/// (adresse tronquée, espace, domaine sans point) et laisse le serveur
/// trancher le reste. Une expression trop stricte rejette des adresses
/// valides, ce qui coûte plus cher qu'un aller-retour réseau.
final RegExp _formeEmail = RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$');

/// Vrai si [valeur] a la forme d'une adresse e-mail.
bool emailValide(String valeur) => _formeEmail.hasMatch(valeur.trim());

/// Adresse normalisée avant envoi : sans espaces, en minuscules.
///
/// Supabase compare les adresses en minuscules ; normaliser ici évite qu'un
/// « Membre1@Caserne-A.test » saisi au clavier de téléphone crée un écart.
String normaliserEmail(String valeur) => valeur.trim().toLowerCase();
