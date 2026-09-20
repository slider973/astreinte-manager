import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'contexte_plateforme.dart';

/// Les modes d'affichage qui signifient « installée ».
///
/// `standalone` est le mode du manifeste ; `fullscreen` et `minimal-ui`
/// existent sur certains lanceurs Android et comptent tout autant : dans les
/// trois cas, il n'y a plus de barre d'adresse à partager.
const List<String> _modesAutonomes = <String>[
  '(display-mode: standalone)',
  '(display-mode: fullscreen)',
  '(display-mode: minimal-ui)',
];

/// Lit l'agent utilisateur et le mode d'affichage du navigateur.
///
/// Toute la décision est dans [ContextePlateforme.depuisAgent] : ici, on ne
/// fait que tendre les deux faits que seul le navigateur connaît.
ContextePlateforme detecterContextePlateforme() {
  return ContextePlateforme.depuisAgent(
    userAgent: web.window.navigator.userAgent,
    affichageAutonome: _affichageAutonome(),
    autonomeIos: _autonomeIos(),
  );
}

bool _affichageAutonome() {
  for (final requete in _modesAutonomes) {
    try {
      if (web.window.matchMedia(requete).matches) return true;
    } on Object {
      // Un navigateur qui ne connaît pas la requête répond en levant : ce
      // n'est pas une panne, c'est un « non ».
    }
  }
  return false;
}

/// `navigator.standalone`, propriété non standard que seul Safari sur iOS
/// porte. Elle est absente ailleurs : on la lit sans la typer, puis on vérifie
/// que c'est bien un booléen.
bool _autonomeIos() {
  final valeur = (web.window.navigator as JSObject).getProperty<JSAny?>(
    'standalone'.toJS,
  );
  return valeur.isA<JSBoolean>() && (valeur! as JSBoolean).toDart;
}
