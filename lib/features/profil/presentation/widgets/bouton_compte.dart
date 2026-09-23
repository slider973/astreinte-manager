import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_providers.dart';
import '../../../../core/widgets/avatar_initiales.dart';

/// Le compte, à droite de l'en-tête de la zone de travail (`design/061 § 5`),
/// et **la seule porte du profil** depuis le ticket 064.
///
/// Un disque d'initiales qui mène au profil. Il dit **qui** est connecté — ce
/// qu'aucune destination ne disait. Sur un poste de caserne partagé, c'est la
/// question qui se pose en premier.
///
/// Le nom vient de l'appartenance déjà en mémoire, jamais d'une lecture de
/// profil : l'en-tête est sur tous les écrans, et il ne doit rien coûter au
/// réseau.
class BoutonCompte extends ConsumerWidget {
  const BoutonCompte({super.key, this.taille});

  /// Le diamètre du disque. `null` : celui d'`AvatarInitiales`, qui est celui
  /// d'une icône de barre d'application. L'en-tête du tableau de bord le
  /// pousse à 40, où il est le premier élément de l'écran et non une action
  /// parmi d'autres.
  final double? taille;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    final email = ref.watch(sessionProvider).value?.email ?? '';
    final nom = (appartenance?.nomAffiche ?? '').trim().isNotEmpty
        ? appartenance!.nomAffiche!.trim()
        : email;
    final libelle = nom.isEmpty
        ? AppStrings.compteOuvrir
        : AppStrings.compteOuvrirNomme(nom);

    // **Le libellé est porté une seule fois, par l'infobulle.** `tooltip` pose
    // déjà un nœud de bouton nommé — c'est ainsi que « Membres » et
    // « Notifications » s'annoncent dans le même en-tête. Un `Semantics` de
    // plus autour du disque en posait un second, superposé au premier : deux
    // boutons dans l'arbre, le même libellé lu deux fois.
    //
    // Les initiales, elles, sortent de l'arbre : elles ne s'épellent pas, et
    // fondues dans le nœud du bouton elles ajouteraient « DJ » à la fin du
    // nom qu'elles abrègent.
    return IconButton(
      onPressed: () => _ouvrir(context),
      tooltip: libelle,
      icon: ExcludeSemantics(
        child: taille == null
            ? AvatarInitiales(nom: nom)
            : AvatarInitiales(nom: nom, taille: taille!),
      ),
    );
  }

  /// **Le profil se pousse, il ne remplace pas.** C'est un détour : on y va en
  /// laissant son travail ouvert derrière soi, et on en revient par
  /// `BoutonRetour` ou par le retour du navigateur. Deux touches rapprochées
  /// n'empilent pas deux profils.
  static void _ouvrir(BuildContext context) {
    final routeur = GoRouter.of(context);
    if (routeur.state.matchedLocation == AppRoutes.profil) return;
    unawaited(routeur.pushNamed<void>(AppRoutes.profilName));
  }
}
