import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env.dart';
import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/plateforme/contexte_plateforme.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../onboarding/domain/profil_providers.dart';
import '../data/jeton_local.dart';
import '../data/messagerie_push.dart';
import '../data/pont_service_worker.dart';
import '../data/push_tokens_repository.dart';
import 'etat_notifications.dart';
import 'message_push.dart';

/// Le canal de notifications. Sans projet Firebase — l'état normal tant que le
/// propriétaire n'en a pas créé un — c'est [MessageriePushIndisponible] qui
/// répond, et rien n'est jamais appelé chez Google.
final Provider<MessageriePush> messageriePushProvider = Provider<MessageriePush>(
  (ref) {
    if (!ref.watch(firebaseDemarrageProvider).estPret) {
      return const MessageriePushIndisponible();
    }
    return MessageriePushFirebase(ref.watch(envProvider));
  },
);

/// Le dépôt des jetons. Surchargé par un faux dans les tests.
final Provider<PushTokensRepository> pushTokensRepositoryProvider =
    Provider<PushTokensRepository>(
      (ref) => SupabasePushTokensRepository(ref.watch(supabaseClientProvider)),
    );

/// Où en sont les notifications sur cet appareil.
///
/// Lu par l'écran d'accueil du nouveau membre, par le réglage du profil, et
/// par la couche qui enregistre le jeton. Un seul endroit décide, et la
/// décision elle-même est une fonction pure ([deciderEtatNotifications]).
class NotificationsController extends AsyncNotifier<EtatNotifications> {
  @override
  Future<EtatNotifications> build() async {
    final plateforme = ref.watch(contextePlateformeProvider);
    final configure = ref.watch(firebaseDemarrageProvider).estPret;
    final messagerie = ref.watch(messageriePushProvider);

    if (!configure) {
      return deciderEtatNotifications(
        configure: false,
        supporte: false,
        plateforme: plateforme,
        permission: PermissionPush.aDemander,
      );
    }

    return deciderEtatNotifications(
      configure: true,
      supporte: await messagerie.estSupportee(),
      plateforme: plateforme,
      permission: await messagerie.permission(),
    );
  }

  /// Ouvre la fenêtre d'autorisation du navigateur, **et rien d'autre**.
  ///
  /// À n'appeler que depuis un geste explicite, et jamais quand l'état n'est
  /// pas [EtatNotifications.aDemander] : sur iPhone hors écran d'accueil, la
  /// demande serait perdue sans retour possible.
  Future<EtatNotifications> demanderAutorisation() async {
    final courant = state.value;
    if (courant == null || !courant.peutDemander) {
      return courant ?? EtatNotifications.nonConfigure;
    }

    state = const AsyncValue<EtatNotifications>.loading();
    final messagerie = ref.read(messageriePushProvider);
    final permission = await messagerie.demanderPermission();
    final suivant = deciderEtatNotifications(
      configure: true,
      supporte: true,
      plateforme: ref.read(contextePlateformeProvider),
      permission: permission,
    );
    state = AsyncValue<EtatNotifications>.data(suivant);

    if (suivant.estActive) await ref.read(jetonPushProvider.notifier).publier();
    return suivant;
  }
}

final AsyncNotifierProvider<NotificationsController, EtatNotifications>
notificationsControllerProvider =
    AsyncNotifierProvider<NotificationsController, EtatNotifications>(
      NotificationsController.new,
    );

/// Le jeton de cet appareil, publié dans `push_tokens`.
///
/// `null` tant qu'il n'y a rien à publier : pas d'autorisation, pas de
/// session, ou navigateur qui refuse le jeton.
class JetonPushController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Demande un jeton à FCM et l'écrit en base, en remplaçant celui que cet
  /// appareil portait avant.
  ///
  /// Appelée **à chaque lancement** quand les notifications sont actives :
  /// c'est elle qui tient `last_seen_at` à jour et qui garantit qu'un jeton
  /// périmé est remplacé et non dupliqué.
  Future<void> publier() async {
    final etat = ref.read(notificationsControllerProvider).value;
    if (etat == null || !etat.estActive) return;

    final session = ref.read(sessionProvider).value;
    if (session == null) return;

    final jeton = await ref.read(messageriePushProvider).jeton();
    if (jeton == null || jeton.isEmpty) return;

    final local = ref.read(jetonLocalProvider);
    final depot = ref.read(pushTokensRepositoryProvider);
    final precedent = await local.lire();

    try {
      await depot.enregistrer(
        userId: session.userId,
        token: jeton,
        plateforme: PlateformePush.web,
        libelleAppareil: ref.read(contextePlateformeProvider).libelleAppareil,
      );

      // L'ancien ne part qu'une fois le nouveau écrit : si l'écriture échoue,
      // l'appareil garde au moins un jeton joignable.
      if (precedent != null && precedent != jeton) {
        await depot.oublier(precedent);
      }
      await local.ecrire(jeton);
      state = jeton;
    } on Object catch (erreur) {
      // Un jeton non enregistré ne se dit pas à l'utilisateur : il n'a rien à
      // en faire et rien à corriger. La prochaine ouverture réessaiera.
      if (kDebugMode) debugPrint('Jeton non enregistré : $erreur');
    }
  }
}

final NotifierProvider<JetonPushController, String?> jetonPushProvider =
    NotifierProvider<JetonPushController, String?>(JetonPushController.new);

/// Les messages reçus pendant que l'application est au premier plan.
final StreamProvider<MessagePush> messagesPremierPlanProvider =
    StreamProvider<MessagePush>(
      (ref) => ref.watch(messageriePushProvider).messagesPremierPlan,
    );

/// Les destinations postées par le service worker quand on touche une
/// notification alors que l'application tourne en arrière-plan.
final StreamProvider<String> routesServiceWorkerProvider =
    StreamProvider<String>((ref) {
      if (!ref.watch(firebaseDemarrageProvider).estPret) {
        return const Stream<String>.empty();
      }
      return routesDepuisServiceWorker();
    });

/// Les notifications **non critiques** sont-elles acceptées ?
/// (`profiles.push_enabled`, `docs/PRD.md § 6.5`.)
///
/// Les propositions d'astreinte ne passent jamais par ce réglage : elles
/// partent toujours. C'est une exigence produit, pas un oubli.
class PushNonCritiquesController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final session = ref.watch(sessionProvider).value;
    if (session == null) return true;
    return ref.read(profilRepositoryProvider).pushNonCritiques(session.userId);
  }

  /// Bascule le réglage. Renvoie vrai si la base l'a accepté.
  ///
  /// L'interrupteur bouge tout de suite — un interrupteur qui attend le réseau
  /// donne l'impression d'être cassé — puis revient en place si l'écriture
  /// échoue, et l'écran le dit.
  Future<bool> definir({required bool actif}) async {
    final session = ref.read(sessionProvider).value;
    if (session == null) return false;

    final precedent = state.value ?? true;
    state = AsyncValue<bool>.data(actif);

    try {
      await ref
          .read(profilRepositoryProvider)
          .definirPushNonCritiques(userId: session.userId, actif: actif);
      return true;
    } on Object {
      state = AsyncValue<bool>.data(precedent);
      return false;
    }
  }
}

final AsyncNotifierProvider<PushNonCritiquesController, bool>
pushNonCritiquesProvider =
    AsyncNotifierProvider<PushNonCritiquesController, bool>(
      PushNonCritiquesController.new,
    );
