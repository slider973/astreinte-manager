import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/echanges/domain/echanges_providers.dart';
import 'fraicheur.dart';

/// **Le retour au premier plan, écouté une fois pour toute l'application**
/// (ticket 070).
///
/// Sur le web, Flutter remonte `visibilitychange` vers `visible` et le retour
/// du focus en `AppLifecycleState.resumed`. Avant ce ticket, chaque écran
/// posait son propre écouteur, et l'accueil ne relisait que les mois. Ici, un
/// seul écouteur demande au coordinateur de relire la caserne, le rôle, et ce
/// qu'affichent les écrans montés — lesquels se sont déclarés par
/// [FraicheurEcran].
///
/// Posée au-dessus des routes, comme la couche des notifications : le retour
/// au premier plan ne choisit pas l'écran sur lequel il tombe.
class CoucheFraicheur extends ConsumerStatefulWidget {
  const CoucheFraicheur({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CoucheFraicheur> createState() => _CoucheFraicheurState();
}

class _CoucheFraicheurState extends ConsumerState<CoucheFraicheur> {
  late final AppLifecycleListener _cycleDeVie;
  late final Fraicheur _fraicheur;

  @override
  void initState() {
    super.initState();
    // Créé dès le montage de l'application : ses abonnements — retour du
    // réseau, réponse à une proposition — doivent exister avant le premier
    // événement.
    _fraicheur = ref.read(fraicheurProvider);
    _cycleDeVie = AppLifecycleListener(
      onResume: () => unawaited(_fraicheur.auPremierPlan()),
    );
  }

  @override
  void dispose() {
    _cycleDeVie.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // **Les échanges (ticket 073) restent écoutés au-dessus des routes.**
    // L'accueil, Astreintes et la Boîte les lisent ; sans écoute qui tienne,
    // Riverpod mettait le contrôleur en pause dès qu'aucun de ces écrans
    // n'était à l'écran, et un changement de caserne ou de rôle pendant ce
    // temps le faisait se relire **pendant** la construction de l'accueil
    // (assertion de débogage, vue au retour d'un écran d'administration
    // après une rétrogradation). Écouté ici, il se relit tout de suite.
    ref.listen<AsyncValue<EtatEchanges>>(echangesControllerProvider, (_, _) {});
    return widget.child;
  }
}

/// **Ce qu'un écran affiche**, déclaré au coordinateur.
///
/// À l'ouverture de l'écran, ses données sont relues si elles ont vieilli
/// (au plus une fois toutes les dix secondes) ; puis, tant qu'il est monté, à
/// chaque retour au premier plan. Un écran dont le contenu change de source —
/// la portée de « Astreintes » — rappelle [declarerDonnees].
mixin FraicheurEcran<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Les données que l'écran affiche **maintenant**.
  Set<Donnee> get donneesAffichees;

  late final Fraicheur _fraicheur;

  @override
  void initState() {
    super.initState();
    _fraicheur = ref.read(fraicheurProvider);
    // Reporté d'une image : lire un provider qui publie pendant `initState`
    // est interdit par Riverpod.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) declarerDonnees();
    });
  }

  /// Déclare (ou redéclare) [donneesAffichees], et les relit si elles ont
  /// vieilli.
  void declarerDonnees() =>
      unawaited(_fraicheur.afficher(this, donneesAffichees));

  @override
  void dispose() {
    _fraicheur.retirer(this);
    super.dispose();
  }
}
