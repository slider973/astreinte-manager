/// Textes de l'application, centralisés et en français.
///
/// Aucune chaîne visible ne doit être écrite en dur dans un widget. Si le
/// projet passe à des fichiers ARB, cette classe sera remplacée par les
/// accesseurs générés sans changer les appelants.
abstract final class AppStrings {
  static const String appTitle = 'Astreinte SP';

  // Écran Hello (ticket 001)
  static const String helloTitle = 'Bonjour';
  static const String helloSubtitle =
      'Le socle Flutter est en place. Cet écran lit la configuration '
      'fournie à la compilation.';
  static const String appEnvLabel = 'Environnement';
  static const String supabaseUrlLabel = 'URL Supabase';
  static const String valueUndefined = 'Non définie';
}
