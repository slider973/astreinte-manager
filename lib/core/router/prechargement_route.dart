import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/abonnement/domain/abonnement_providers.dart';
import '../../features/astreintes/domain/astreintes_providers.dart';
import '../../features/membres/domain/membres_providers.dart';
import '../../features/notifications/domain/centre_providers.dart';
import '../../features/parametres/domain/parametres_providers.dart';
import '../../features/periodes/domain/periodes_providers.dart';
import '../../features/planning/domain/matrice_providers.dart';
import '../../features/planning/domain/planning_providers.dart';
import '../../features/planning/domain/suivi_providers.dart';
import '../../features/propositions/domain/propositions_providers.dart';
import 'app_router.dart';

/// Les données qu'un écran demande dès sa première image, par chemin.
///
/// Pure et testable : c'est la table que [PrechargementRoutes] déroule.
/// Un chemin absent de la liste ne précharge rien — c'est le cas des écrans
/// qui n'interrogent pas la base, et de ceux dont les données sont déjà
/// retenues par un autre lecteur.
List<ProviderSubscription<Object?> Function(Ref ref)> donneesDEcran(
  String chemin,
) =>
    switch (chemin) {
      // **L'écran le plus ouvert du produit** (ticket 064). Rien n'abonnait
      // ces deux contrôleurs avant que le tableau de bord ne se construise :
      // ses deux lectures partaient donc une image trop tard, sur la route où
      // ça se voit le plus — celle qu'on ouvre en lançant l'application.
      AppRoutes.accueil => <ProviderSubscription<Object?> Function(Ref)>[
        (Ref ref) => ref.listen(astreintesControllerProvider, (_, _) {}),
        (Ref ref) => ref.listen(propositionsControllerProvider, (_, _) {}),
      ],
      // La matrice lit le mois **et** le planning du mois : les deux requêtes
      // partent ensemble, comme quand l'écran les demande lui-même.
      AppRoutes.planningAdmin => <ProviderSubscription<Object?> Function(Ref)>[
        (Ref ref) => ref.listen(matriceControllerProvider, (_, _) {}),
        (Ref ref) => ref.listen(planningControllerProvider, (_, _) {}),
      ],
      AppRoutes.suivi => <ProviderSubscription<Object?> Function(Ref)>[
        (Ref ref) => ref.listen(suiviControllerProvider, (_, _) {}),
        (Ref ref) => ref.listen(planningControllerProvider, (_, _) {}),
      ],
      AppRoutes.membres => <ProviderSubscription<Object?> Function(Ref)>[
        (Ref ref) => ref.listen(membresControllerProvider, (_, _) {}),
      ],
      AppRoutes.periodes => <ProviderSubscription<Object?> Function(Ref)>[
        (Ref ref) => ref.listen(periodesControllerProvider, (_, _) {}),
      ],
      AppRoutes.parametres => <ProviderSubscription<Object?> Function(Ref)>[
        (Ref ref) => ref.listen(parametresControllerProvider, (_, _) {}),
      ],
      AppRoutes.abonnement => <ProviderSubscription<Object?> Function(Ref)>[
        (Ref ref) => ref.listen(abonnementControllerProvider, (_, _) {}),
      ],
      // La Boîte (chantier 064b) : les rappels **et** les propositions, ses
      // deux sources. `/notifications` et `/propositions` n'existent plus que
      // comme renvois. Les deux lectures sont celles que les deux écrans
      // d'avant faisaient chacun de leur côté : le compte de requêtes d'une
      // ouverture de Boîte ne bouge pas, il change seulement d'écran.
      AppRoutes.boite => <ProviderSubscription<Object?> Function(Ref)>[
        (Ref ref) => ref.listen(centreNotificationsProvider, (_, _) {}),
        (Ref ref) => ref.listen(propositionsControllerProvider, (_, _) {}),
      ],
      _ => const <ProviderSubscription<Object?> Function(Ref)>[],
    };

/// Réveille les données de l'écran visé **au moment où la route change**,
/// sans attendre que sa première image soit construite.
///
/// Pourquoi ce détour plutôt que de laisser l'écran demander ses données comme
/// il le fait déjà : sur le web, la file de micro-tâches ne se vide qu'à la fin
/// de la tâche du navigateur. Un provider lu pour la première fois pendant la
/// construction de l'écran envoie donc sa requête **après** la tâche qui
/// contient toute la construction, la mise en page et la peinture du nouvel
/// écran. Mesuré au ticket 042, en mode profil dans Chrome, du relâchement du
/// clic au départ de la requête : 28 ms sur cette machine sans bridage,
/// 75 ms avec le processeur bridé ×4, 117 ms bridé ×6 — et c'est l'écran le
/// plus lourd du produit qui est peint pendant ce temps, pour ne montrer qu'un
/// squelette. Les mêmes transitions coûtent 3, 9 et 14 ms une fois branché ici.
///
/// Appelé depuis la redirection de `go_router`, qui s'exécute dans la tâche du
/// geste, la même requête part avant que cette image ne commence.
///
/// Trois propriétés qui rendent ce raccourci sûr :
///
/// - **il ne demande rien de plus** que ce que l'écran demanderait de toute
///   façon, une image plus tard : le compte de requêtes d'une transition est
///   le même avant et après (vérifié au journal réseau, ticket 042) ;
/// - **il est idempotent** : la redirection est rejouée à chaque
///   rafraîchissement du routeur, et un chemin déjà préchargé ne l'est pas
///   deux fois ;
/// - **il ne retient que la route en cours** : arriver ailleurs relâche la
///   précédente, et l'écran monté entre-temps tient lui-même ce qu'il affiche.
class PrechargementRoutes {
  String? _chemin;
  List<ProviderSubscription<Object?>> _abonnements =
      const <ProviderSubscription<Object?>>[];

  /// Réveille les données de [chemin].
  ///
  /// **L'abonnement est ce qui fait tenir le préchargement.** Les contrôleurs
  /// d'écran sont auto-disposés : sans personne pour les écouter, Riverpod les
  /// jette avant même que l'écran ne se monte, et l'écran redemande tout —
  /// chaque requête partait deux fois, vu au journal réseau pendant le
  /// ticket 042.
  void versLaRoute(Ref ref, String chemin) {
    if (chemin == _chemin) return;
    relacher();
    _chemin = chemin;
    _abonnements = <ProviderSubscription<Object?>>[
      for (final reveil in donneesDEcran(chemin)) reveil(ref),
    ];
  }

  /// Relâche ce qui était retenu. Les écrans montés, eux, gardent leurs
  /// données : ils les écoutent pour de bon.
  void relacher() {
    for (final abonnement in _abonnements) {
      abonnement.close();
    }
    _abonnements = const <ProviderSubscription<Object?>>[];
    _chemin = null;
  }
}
