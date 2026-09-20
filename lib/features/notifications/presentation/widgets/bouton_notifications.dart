import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../domain/centre_providers.dart';

/// La cloche de la barre d'application, avec sa pastille de non-lues.
///
/// **Pourquoi pas une destination de navigation.** `DESIGN.md § Navigation`
/// fixe cinq destinations au maximum, et un administrateur en a déjà cinq.
/// « Aucune destination ne s'ajoute sans en retirer une », et aucune des cinq
/// ne mérite d'être retirée au profit d'un journal qu'on consulte après coup.
/// La cloche vit donc dans la barre d'application de la coquille d'accueil,
/// présente sur les quatre onglets.
///
/// La pastille suit les règles de celle des propositions : plafonnée à « 9+ »,
/// doublée d'un libellé annoncé qui porte le nombre réel.
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
      onPressed: () => context.goNamed(AppRoutes.notificationsName),
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
}
