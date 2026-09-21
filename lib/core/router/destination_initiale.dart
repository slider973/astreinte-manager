import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';

/// La destination demandée au lancement, gardée le temps que la session se
/// restaure.
///
/// **Le défaut que cette classe corrige** (ticket 039, relevé au ticket 011) :
/// ouvrir l'application sur une URL précise — `/availability/2026-10`,
/// `/?onglet=0&mois=2026-10` — la perd, parce que la restauration de session
/// renvoie d'abord sur `/demarrage` et réécrit l'URL. Le retour du navigateur
/// en cours de session marchait déjà ; seul le démarrage à froid était touché.
///
/// C'est exactement le chemin d'une notification touchée alors que
/// l'application est fermée (`docs/WORKFLOWS.md § 8`), donc le corriger fait
/// partie du ticket 024 : livrer l'ouverture depuis une notification sans ça
/// serait livrer une fonctionnalité qui ramène à l'accueil une fois sur deux.
///
/// Une seule destination est gardée, la **première** : celle que
/// l'utilisateur a demandée. Les redirections suivantes sont des conséquences,
/// pas des intentions.
class DestinationInitiale {
  String? _gardee;

  /// Les emplacements qui ne sont jamais une destination : ce sont les étapes
  /// qu'on traverse. Y revenir après la connexion serait une boucle.
  static const List<String> _prefixesTechniques = <String>[
    AppRoutes.demarrage,
    AppRoutes.connexion,
    AppRoutes.configuration,
    AppRoutes.aucuneCaserne,
    AppRoutes.prefixeBienvenue,
    // Le lien d'invitation a déjà sa propre mémoire
    // (`core/session/jeton_invitation.dart`), qui survit à la connexion.
    AppRoutes.prefixeInvitation,
  ];

  /// Garde [emplacement] s'il vaut la peine d'y revenir. Renvoie vrai s'il a
  /// été gardé.
  bool memoriser(String emplacement) {
    if (_gardee != null) return false;
    if (!vautLeDetour(emplacement)) return false;
    _gardee = emplacement;
    return true;
  }

  /// La destination gardée, une fois et une seule, si elle diffère de
  /// [emplacement] — y être déjà rend la reprise inutile.
  String? reprendre(String emplacement) {
    final gardee = _gardee;
    if (gardee == null) return null;
    _gardee = null;
    return gardee == emplacement ? null : gardee;
  }

  void oublier() => _gardee = null;

  /// Une destination gardée est **consommée même si l'appelant ne la rejoue
  /// pas** : c'est [reprendre] qui vide la mémoire, et une destination que la
  /// garde de navigation refuse ne doit pas revenir au tour suivant.

  /// Vrai si l'emplacement porte une intention : **une adresse interne**,
  /// autre chose que l'accueil nu et qu'une étape traversée.
  static bool vautLeDetour(String emplacement) {
    // Une destination gardée est rejouée telle quelle dans `GoRouter.go` : ce
    // qui entre ici doit donc être un chemin de l'application, et rien
    // d'autre. Une adresse absolue (`https://ailleurs/…`), une adresse de
    // protocole (`javascript:…`) ou un chemin à double barre oblique
    // (`//ailleurs/…`, qui est une autorité) sortiraient de l'application.
    // La stratégie d'URL en vigueur — le dièse de `go_router` — contient
    // aujourd'hui les dégâts ; le ticket 032 peut la changer, et le contrôle
    // ne doit pas dépendre de ce choix.
    if (!emplacement.startsWith('/')) return false;
    if (emplacement.startsWith('//')) return false;
    // Certains navigateurs lisent `/\ailleurs` comme `//ailleurs`.
    if (emplacement.contains(r'\')) return false;

    final uri = Uri.tryParse(emplacement);
    if (uri == null) return false;
    if (uri.hasScheme || uri.hasAuthority) return false;

    final chemin = uri.path;
    if (chemin.isEmpty) return false;

    for (final brut in _prefixesTechniques) {
      // `prefixeInvitation` porte déjà sa barre finale, les autres non : on
      // normalise plutôt que d'en faire un cas particulier.
      final prefixe = brut.endsWith('/')
          ? brut.substring(0, brut.length - 1)
          : brut;
      if (chemin == prefixe || chemin.startsWith('$prefixe/')) return false;
    }

    // L'accueil nu est la destination par défaut : la garder ne dit rien.
    // L'accueil avec un onglet ou un mois, lui, est une destination.
    if (chemin == AppRoutes.accueil && uri.query.isEmpty) return false;

    return true;
  }
}

/// La destination initiale du lancement courant. Un objet par application :
/// il porte un état, et le routeur est construit une seule fois.
final Provider<DestinationInitiale> destinationInitialeProvider =
    Provider<DestinationInitiale>((ref) => DestinationInitiale());
