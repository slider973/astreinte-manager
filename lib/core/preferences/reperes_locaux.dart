import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les repères d'accueil qui ne s'affichent qu'une fois.
///
/// Ils ne décrivent ni un droit ni une donnée métier : ce sont des marques de
/// passage, locales à l'appareil. Rien ne justifie d'aller les chercher en
/// base — et rien ne justifie de les perdre à chaque ouverture non plus.
enum RepereAccueil {
  /// Le guide de trois écrans, montré après l'acceptation d'une invitation.
  guide('accueil.guide.vu'),

  /// L'aide « Ajouter à l'écran d'accueil ».
  aideInstallation('accueil.installation.vue'),

  /// La proposition d'activer les notifications, dernière étape de l'accueil
  /// (ticket 024). Elle ne revient pas d'elle-même : un refus d'autorisation
  /// est définitif dans le navigateur, et redemander serait insister dans le
  /// vide. La reprise passe par le réglage du profil.
  activationNotifications('accueil.notifications.vue'),

  /// Le membre a terminé au moins une peinture au glissement sur cet
  /// appareil : l'astuce du bloc d'aide n'a plus rien à lui apprendre.
  ///
  /// Le repère se perd s'il change d'appareil ou vide son navigateur, et le
  /// bloc réapparaît. C'est accepté (brief 011 § 7.6) : un rappel de trop
  /// coûte deux lignes, un geste jamais découvert coûte cent vingt touches
  /// par mois.
  peintureDispos('dispos.peinture.faite');

  const RepereAccueil(this.cle);

  /// Clé de stockage. Préfixée par domaine pour ne jamais entrer en collision
  /// avec la session Supabase, qui partage le même `localStorage`.
  final String cle;
}

/// Ce que l'application sait des repères déjà vus.
abstract interface class ReperesLocaux {
  Future<bool> dejaVu(RepereAccueil repere);

  Future<void> marquerVu(RepereAccueil repere);
}

/// Implémentation `shared_preferences` — `localStorage` sur le web.
///
/// Une lecture qui échoue (stockage refusé en navigation privée, quota plein)
/// répond « pas encore vu » : montrer le guide une fois de trop est un petit
/// défaut, le cacher à quelqu'un qui ne l'a jamais vu en est un vrai.
class ReperesLocauxPartages implements ReperesLocaux {
  const ReperesLocauxPartages();

  @override
  Future<bool> dejaVu(RepereAccueil repere) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(repere.cle) ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> marquerVu(RepereAccueil repere) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(repere.cle, true);
    } on Object {
      // Ne rien faire : l'écran a été vu, il le sera peut-être une fois de
      // trop. Ce n'est pas une panne à signaler à un pompier.
    }
  }
}

/// Implémentation en mémoire, pour les tests et pour les plateformes où le
/// stockage n'est pas disponible.
class ReperesLocauxMemoire implements ReperesLocaux {
  ReperesLocauxMemoire([Set<RepereAccueil>? vus])
    : _vus = <RepereAccueil>{...?vus};

  final Set<RepereAccueil> _vus;

  @override
  Future<bool> dejaVu(RepereAccueil repere) async => _vus.contains(repere);

  @override
  Future<void> marquerVu(RepereAccueil repere) async => _vus.add(repere);
}

/// Le dépôt des repères. Surchargé par [ReperesLocauxMemoire] dans les tests.
final Provider<ReperesLocaux> reperesLocauxProvider = Provider<ReperesLocaux>(
  (ref) => const ReperesLocauxPartages(),
);
