import 'package:flutter/scheduler.dart';
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
  /// [aLaProchaineImage] n'existe que pour les tests, qui remplacent l'image
  /// par un appel direct ou différé à la main.
  DestinationInitiale({void Function(VoidCallback)? aLaProchaineImage})
    : _aLaProchaineImage = aLaProchaineImage ?? _apresLImageCourante;

  /// Ce qui relâche la destination une fois la redirection retombée.
  ///
  /// `addPostFrameCallback` seul ne suffit pas : il n'exige pas d'image. Un
  /// changement d'état qui ne repeint rien — et la restauration de session en
  /// est un — n'en déclencherait aucune, et la destination resterait gardée
  /// pour toujours. `ensureVisualUpdate` en demande une.
  static void _apresLImageCourante(VoidCallback quoi) {
    final binding = SchedulerBinding.instance
      ..addPostFrameCallback((_) => quoi());
    binding.ensureVisualUpdate();
  }

  final void Function(VoidCallback) _aLaProchaineImage;

  String? _gardee;

  /// Vrai quand la passe courante est déjà passée par la destination : elle a
  /// fait son office, et la rejouer une fois de plus dans la **même** chaîne de
  /// redirection tournerait en rond.
  ///
  /// Le cas n'est pas théorique : les quatre liens publics des notifications
  /// (`/proposals`, `/schedule/…`) n'ont pas d'écran à eux, ils redirigent vers
  /// un autre emplacement. Sans ce drapeau, la redirection y ramènerait
  /// aussitôt, et `go_router` s'arrêterait sur sa limite de redirections.
  bool _atteinte = false;

  bool _oubliProgramme = false;

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

  /// Le routeur repart de l'écran d'attente : la restauration n'est pas
  /// terminée, quoi qu'une passe précédente ait déjà fait de la destination.
  ///
  /// **C'est le correctif du ticket 045.** `go_router` recalcule sa redirection
  /// à chaque notification de `refreshListenable`, et il la recalcule à partir
  /// de l'emplacement que le navigateur affiche — pas de celui qu'une passe
  /// précédente vient de décider, qui n'est rapporté qu'à la fin de l'image.
  /// Le droit de l'éditeur et l'état d'authentification arrivent souvent dans
  /// la même image : deux passes partent alors du même `/demarrage` périmé. La
  /// première menait à la destination, la seconde — mémoire vidée — renvoyait à
  /// l'accueil, et c'est la seconde qui gagne. Une fois sur trois dans Chrome,
  /// pour une destination d'administration comme pour une destination de
  /// membre : le rôle n'y était pour rien.
  void repartDeLAttente() => _atteinte = false;

  /// La destination gardée, si elle diffère de [emplacement] et qu'on n'y est
  /// pas déjà passé dans cette chaîne de redirection.
  ///
  /// **Elle n'est pas consommée ici.** Regarder la mémoire la condamne
  /// seulement à être relâchée à l'image suivante : d'ici là, toutes les passes
  /// de la même image répondent la même chose, et la dernière ne peut plus
  /// défaire ce que la première a décidé.
  String? reprendre(String emplacement) {
    final gardee = _gardee;
    if (gardee == null) return null;
    _programmerOubli();

    if (gardee == emplacement) {
      // Y être déjà rend la reprise inutile — et le dit à la suite de la
      // chaîne.
      _atteinte = true;
      return null;
    }
    return _atteinte ? null : gardee;
  }

  void oublier() {
    _gardee = null;
    _atteinte = false;
    _oubliProgramme = false;
  }

  /// Une destination que la garde de navigation refuse ne revient pas à
  /// l'image suivante : la relâche est programmée dès qu'on l'a regardée.
  void _programmerOubli() {
    if (_oubliProgramme) return;
    _oubliProgramme = true;
    _aLaProchaineImage(oublier);
  }

  /// Vrai si l'emplacement porte une intention : **une adresse interne**,
  /// autre chose que l'accueil nu et qu'une étape traversée.
  static bool vautLeDetour(String emplacement) {
    // Une destination gardée est rejouée telle quelle dans `GoRouter.go` : ce
    // qui entre ici doit donc être un chemin de l'application, et rien
    // d'autre. Une adresse absolue (`https://ailleurs/…`), une adresse de
    // protocole (`javascript:…`) ou un chemin à double barre oblique
    // (`//ailleurs/…`, qui est une autorité) sortiraient de l'application.
    // Depuis le ticket 046, les routes vivent dans le chemin de l'adresse et
    // plus derrière un dièse : ce contrôle est le seul garde-fou qui reste, et
    // il ne dépend d'aucune stratégie d'URL.
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
