import 'package:flutter/foundation.dart';

/// La demande « amène ce jour en vue », de la bande de semaine à la matrice.
///
/// **La matrice garde son défilement** : elle a déjà quatre contrôleurs liés
/// deux à deux, et un second défilement horizontal posé au-dessus d'elle les
/// désynchroniserait. La bande ne défile donc rien elle-même — elle dit quel
/// jour viser, et la grille s'y rend avec le contrôleur qu'elle possède déjà.
///
/// Notifie **à chaque appel**, même pour le jour déjà demandé : viser deux
/// fois le même jour est une façon de revenir dessus après avoir défilé à la
/// main, et un `ValueNotifier` resterait muet.
class DefilementJour extends ChangeNotifier {
  int? _jour;

  /// Le jour visé, en base 1, ou `null` tant que rien n'a été demandé.
  int? get jour => _jour;

  void viser(int jour) {
    _jour = jour;
    notifyListeners();
  }
}
