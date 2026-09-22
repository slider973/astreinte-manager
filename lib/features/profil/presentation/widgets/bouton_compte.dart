import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_providers.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/avatar_initiales.dart';

/// Le compte, à droite de l'en-tête de la zone de travail (`design/061 § 5`).
///
/// Un disque d'initiales qui mène au profil. Il ne remplace pas la
/// destination « Profil » de la colonne : il est là où la référence le met,
/// et il dit **qui** est connecté — ce qu'aucune destination ne dit. Sur un
/// poste de caserne partagé, c'est la question qui se pose en premier.
///
/// Le nom vient de l'appartenance déjà en mémoire, jamais d'une lecture de
/// profil : l'en-tête est sur tous les écrans, et il ne doit rien coûter au
/// réseau.
class BoutonCompte extends ConsumerWidget {
  const BoutonCompte({super.key});

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

    return IconButton(
      onPressed: () => _ouvrir(context),
      tooltip: libelle,
      icon: Semantics(
        label: libelle,
        button: true,
        excludeSemantics: true,
        child: AvatarInitiales(nom: nom),
      ),
    );
  }

  /// Le profil est l'onglet 3 de la coquille d'accueil, admin ou non
  /// (`AppDestination.indexProfil`). Il n'a pas de route à lui : y mener par
  /// une autre adresse ouvrirait un second exemplaire de la coquille.
  static void _ouvrir(BuildContext context) => context.goNamed(
    AppRoutes.accueilName,
    queryParameters: <String, String>{
      AppRoutes.parametreOnglet: '${AppDestination.indexProfil}',
    },
  );
}
