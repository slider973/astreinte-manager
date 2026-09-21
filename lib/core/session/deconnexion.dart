import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Le cache d'astreintes appartient à sa fonctionnalité, mais **c'est ici que
// s'écrit la règle** « rien de cette personne ne reste sur l'appareil ». Le
// lien est donc direct, comme celui du routeur vers les écrans : une liste que
// les fonctionnalités viendraient garnir d'elles-mêmes serait une liste qu'on
// oublie de garnir, et c'est exactement le défaut qu'on corrige.
import '../../features/astreintes/data/cache_astreintes.dart';
import '../../features/astreintes/data/cache_planning_caserne.dart';
import '../l10n/app_strings.dart';
import '../theme/app_spacing.dart';
import '../widgets/primary_button.dart';
import 'appartenances_locales.dart';
import 'auth_erreur.dart';
import 'session_providers.dart';

/// L'état de la déconnexion en cours.
@immutable
class EtatDeconnexion {
  const EtatDeconnexion({this.enCours = false, this.erreur});

  final bool enCours;

  /// `null` tant que rien n'a échoué.
  final AuthErreur? erreur;
}

/// Ferme la session, et dit où elle en est.
///
/// Une déconnexion qui échoue en silence laisse quelqu'un croire qu'il est
/// sorti alors que son jeton est encore là : sur un téléphone prêté ou dans un
/// véhicule partagé, c'est exactement ce qu'il ne faut pas.
class DeconnexionController extends Notifier<EtatDeconnexion> {
  @override
  EtatDeconnexion build() => const EtatDeconnexion();

  Future<void> seDeconnecter() async {
    if (state.enCours) return;

    state = const EtatDeconnexion(enCours: true);
    try {
      await _oublierLesCaches();
      await ref.read(authRepositoryProvider).seDeconnecter();
      // Le routeur emmène vers la connexion dès que la session tombe : ce
      // contrôleur n'a personne à pousser.
      state = const EtatDeconnexion();
    } on Object catch (erreur) {
      state = EtatDeconnexion(
        erreur: traduireErreurAuth(erreur, etape: AuthEtape.envoi),
      );
    }
  }

  /// Oublie tout ce que l'appareil garde de cette personne.
  ///
  /// **Avant la fermeture de session**, parce qu'après, ni l'identifiant du
  /// membre ni celui de sa caserne ne sont plus lisibles : les deux caches
  /// rangent par clé, et une clé qu'on ne sait plus composer ne s'efface pas.
  ///
  /// Ce qui part : le nom de la caserne (`session.appartenances.…`),
  /// l'instantané des astreintes (`astreintes.cache.…`), qui porte **les noms
  /// des autres membres du créneau**, et les mois du planning de la caserne
  /// (`planning.caserne.…`), qui portent **les noms de toute la caserne**. Sur
  /// un téléphone prêté ou dans un véhicule partagé, ce sont des données de
  /// tiers qui n'ont rien à faire là pour la personne suivante — même règle que
  /// la destination en attente, oubliée elle aussi à la déconnexion
  /// (`DESIGN.md § Écarts, ticket 024`).
  ///
  /// Aucune panne de stockage ne remonte : elles sont déjà avalées par les
  /// dépôts. Un effacement qui échoue ne doit pas retenir quelqu'un dans une
  /// session qu'il veut quitter.
  Future<void> _oublierLesCaches() async {
    final userId = ref.read(sessionProvider).value?.userId;
    if (userId == null) return;

    await ref.read(appartenancesLocalesProvider).effacer(userId);

    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) return;
    await ref
        .read(cacheAstreintesProvider)
        .effacer(stationId: stationId, userId: userId);
    await ref
        .read(cachePlanningCaserneProvider)
        .effacer(stationId: stationId, userId: userId);
  }
}

final NotifierProvider<DeconnexionController, EtatDeconnexion>
deconnexionControllerProvider =
    NotifierProvider<DeconnexionController, EtatDeconnexion>(
      DeconnexionController.new,
      isAutoDispose: true,
    );

/// Le bouton « Se déconnecter » et son état, partout pareil.
///
/// Le libellé ne change pas pendant l'envoi (`DESIGN.md § Buttons` : « le
/// libellé reste, un indicateur de 20 dp le précède, la largeur ne bouge
/// pas ») ; c'est la ligne sous le bouton qui dit où on en est, et elle est
/// annoncée sans déplacer le focus.
class BoutonDeconnexion extends ConsumerWidget {
  const BoutonDeconnexion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(deconnexionControllerProvider);
    final erreur = etat.erreur;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PrimaryButton(
          libelle: AppStrings.seDeconnecter,
          variante: PrimaryButtonVariante.secondaire,
          icone: Icons.logout,
          chargement: etat.enCours,
          onPressed: () => unawaited(
            ref.read(deconnexionControllerProvider.notifier).seDeconnecter(),
          ),
        ),
        if (etat.enCours || erreur != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _LigneEtat(
            texte: erreur?.message ?? AppStrings.deconnexionEnCours,
            enErreur: erreur != null,
          ),
        ],
      ],
    );
  }
}

class _LigneEtat extends StatelessWidget {
  const _LigneEtat({required this.texte, required this.enErreur});

  final String texte;
  final bool enErreur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = enErreur
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            enErreur ? Icons.error_outline : Icons.logout,
            size: AppSpacing.lg,
            color: encre,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(color: encre),
            ),
          ),
        ],
      ),
    );
  }
}
