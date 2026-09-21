import 'package:astreinte_sp/features/profil/data/calendrier_repository.dart';

/// Un [CalendrierRepository] sans réseau.
///
/// **Il garde son jeton**, il ne se contente pas de compter les appels : une
/// régénération doit rendre autre chose que la lecture précédente, sinon aucun
/// test ne peut vérifier que l'adresse affichée a changé.
class FauxCalendrierRepository implements CalendrierRepository {
  FauxCalendrierRepository({String jeton = jetonInitial}) : _jeton = jeton;

  /// 48 caractères hexadécimaux, comme le vrai (`profiles.ics_token`).
  static const String jetonInitial =
      'aaaabbbbccccddddeeeeffff00001111222233334444555a';

  /// Ce que rend la première régénération.
  static const String jetonRegenere =
      '99998888777766665555444433332222111100009999888b';

  String _jeton;

  /// L'échec rendu par [lireJeton], ou `null` pour réussir.
  EchecAbonnement? echecLecture;

  /// L'échec rendu par [regenererJeton], ou `null` pour réussir.
  EchecAbonnement? echecRegeneration;

  int lectures = 0;
  int regenerations = 0;

  @override
  Future<String> lireJeton() async {
    lectures++;
    final erreur = echecLecture;
    if (erreur != null) throw erreur;
    return _jeton;
  }

  @override
  Future<String> regenererJeton() async {
    regenerations++;
    final erreur = echecRegeneration;
    if (erreur != null) throw erreur;
    _jeton = jetonRegenere;
    return _jeton;
  }
}

/// Un presse-papiers qui garde ce qu'on lui donne.
///
/// Le vrai est un canal de plateforme : il n'existe pas sous `flutter test`, et
/// l'appeler ferait échouer chaque test qui touche au bouton « Copier ».
class FauxPressePapiers {
  FauxPressePapiers({this.accepte = true});

  /// À faux, le navigateur refuse — c'est le cas réel d'un contexte non
  /// sécurisé, et l'écran doit alors dire de copier à la main.
  bool accepte;

  final List<String> copies = <String>[];

  String? get dernier => copies.isEmpty ? null : copies.last;

  Future<bool> call(String texte) async {
    if (!accepte) return false;
    copies.add(texte);
    return true;
  }
}
