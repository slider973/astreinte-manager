import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../domain/centre_providers.dart';

/// La cloche de la barre d'application, avec sa pastille de non-lues.
///
/// **Elle mène à la Boîte, qui est une destination** depuis le ticket 064.
/// Jusque-là le centre était un écran poussé, parce que la barre n'avait pas
/// de place pour lui ; le profil l'a libérée. La cloche reste malgré tout :
/// elle porte le compte de non-lues à l'endroit où on le cherche, en tête
/// d'écran, et sur l'accueil c'est elle que le brief met à droite de la
/// salutation (`design/064 § 3.1`).
///
/// **Elle remplace, elle n'empile plus** : une destination n'a ni avant ni
/// après, et le glissement de page y raconterait le contraire de ce qui se
/// passe (ticket 063). Personne n'est enfermé pour autant — la Boîte porte la
/// barre de navigation, ce qu'un écran poussé n'avait pas.
///
/// La pastille est plafonnée à « 9+ » et doublée d'un libellé annoncé qui
/// porte le nombre réel.
class BoutonNotifications extends ConsumerWidget {
  const BoutonNotifications({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nonLues = ref.watch(notificationsNonLuesProvider);
    final libelle = nonLues == 0
        ? AppStrings.centreOuvrir
        : AppStrings.centreNonLuesBadge(nonLues);

    final icone = Icon(
      nonLues == 0 ? Icons.notifications_outlined : Icons.notifications,
    );

    return IconButton(
      onPressed: () => _ouvrir(context),
      tooltip: libelle,
      icon: nonLues == 0
          ? icone
          : Badge.count(
              count: nonLues,
              maxCount: 9,
              child: Semantics(label: libelle, child: icone),
            ),
    );
  }

  /// Va à la Boîte. Quand on y est déjà, la cloche ne fait rien : `go` sur
  /// l'emplacement courant rejouerait la page pour rien.
  static void _ouvrir(BuildContext context) {
    final routeur = GoRouter.of(context);
    if (routeur.state.matchedLocation == AppRoutes.boite) return;
    routeur.goNamed(AppRoutes.boiteName);
  }
}
