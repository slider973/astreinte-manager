import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/notifications_repository.dart';
import 'notification_interne.dart';

/// Le dépôt des notifications internes. Surchargé par un faux dans les tests.
final Provider<NotificationsRepository> notificationsRepositoryProvider =
    Provider<NotificationsRepository>(
      (ref) => SupabaseNotificationsRepository(ref.watch(supabaseClientProvider)),
    );

/// Ce que le centre affiche : les lignes `inapp` du membre, la plus récente
/// en premier.
@immutable
class EtatCentre {
  const EtatCentre({this.notifications = const <NotificationInterne>[]});

  final List<NotificationInterne> notifications;

  bool get vide => notifications.isEmpty;

  /// Les lignes de l'onglet « Rappels » de la Boîte : tout ce qui n'est pas
  /// une proposition (`NotificationInterne.estRappel`).
  List<NotificationInterne> get rappels => <NotificationInterne>[
    for (final notification in notifications)
      if (notification.estRappel) notification,
  ];

  /// **Le nombre porté par la cloche, par la pastille de la barre et par le
  /// titre de la Boîte** — un seul compte, une seule définition.
  ///
  /// Il ne compte que les **rappels** non lus depuis le chantier 064b. Les
  /// deux types que la Boîte n'affiche pas en rappel — l'astreinte proposée
  /// et sa relance — ne peuvent donc pas gonfler une pastille que plus aucun
  /// écran ne saurait vider : elles sont dites par la ligne de proposition,
  /// qui, elle, se répond. La question qu'elles posaient n'est pas perdue,
  /// elle est écrite en toutes lettres sur l'accueil (« Propositions · 3 »)
  /// et dans l'onglet qui la porte.
  int get nonLues {
    var compte = 0;
    for (final notification in notifications) {
      if (!notification.lue && notification.estRappel) compte++;
    }
    return compte;
  }

  /// Remplace une ligne par sa version à jour, **sans retrier** : marquer lu
  /// ne déplace rien sous les yeux de qui vient de toucher la ligne.
  EtatCentre avec(NotificationInterne notification) => EtatCentre(
    notifications: List<NotificationInterne>.unmodifiable(<NotificationInterne>[
      for (final existante in notifications)
        if (existante.id == notification.id) notification else existante,
    ]),
  );

  /// Toutes les lignes marquées lues à [instant].
  EtatCentre toutesLues(DateTime instant) => EtatCentre(
    notifications: List<NotificationInterne>.unmodifiable(<NotificationInterne>[
      for (final existante in notifications)
        if (existante.lue) existante else existante.avecLecture(instant),
    ]),
  );
}

/// Le centre de notifications du membre connecté.
///
/// **Non auto-disposé, volontairement** : la pastille de la cloche lit ce même
/// état depuis la barre d'application de tous les onglets. Auto-disposé, le
/// compte repartirait de zéro — donc disparaîtrait une fraction de seconde — à
/// chaque changement d'écran.
///
/// La contrepartie, c'est qu'il faut le relire explicitement. Trois moments le
/// font, tous dans `CoucheNotifications` : un push reçu au premier plan, une
/// notification touchée depuis l'arrière-plan, et le retour de l'application
/// au premier plan. Le temps réel n'est pas une option ici :
/// `docs/SCHEMA.md § 9` dit qu'aucune table n'est encore dans la publication
/// `supabase_realtime`, et la base locale le confirme (`design/026 § 6`).
class CentreNotificationsController extends AsyncNotifier<EtatCentre> {
  @override
  Future<EtatCentre> build() async {
    final session = ref.watch(sessionProvider).value;
    if (session == null) return const EtatCentre();
    return _lire(session.userId);
  }

  Future<EtatCentre> _lire(String userId) async {
    final lignes = await ref
        .read(notificationsRepositoryProvider)
        .lister(userId: userId);
    return EtatCentre(
      notifications: List<NotificationInterne>.unmodifiable(lignes),
    );
  }

  /// Relit la liste **en la gardant à l'écran** : un rafraîchissement ne vide
  /// pas la page sous les yeux de qui la lit.
  Future<void> rafraichir() async {
    final userId = ref.read(sessionProvider).value?.userId;
    if (userId == null) return;
    state = await AsyncValue.guard(() => _lire(userId));
  }

  /// Marque une ligne lue.
  ///
  /// **Optimiste** : la ligne change d'aspect tout de suite, l'écriture part
  /// derrière. Une ligne qui attendrait le réseau pour changer donnerait une
  /// application cassée dans la 4G d'une salle de garde. Si la base refuse,
  /// la ligne redevient non lue et la méthode rend `false` — l'écran le dit.
  ///
  /// Idempotente : une ligne déjà lue rend `true` sans rien écrire.
  Future<bool> marquerLue(NotificationInterne notification) async {
    final etat = state.value;
    if (etat == null || notification.lue) return true;

    final avant = etat;
    state = AsyncValue<EtatCentre>.data(
      etat.avec(notification.avecLecture(DateTime.now())),
    );

    try {
      final ecrit = await ref
          .read(notificationsRepositoryProvider)
          .marquerLue(notification.id);

      // `null` veut dire « elle était déjà lue », pas « ça a échoué » : deux
      // appareils du même pompier, ou une ligne ouverte depuis le push. Rien
      // à défaire.
      if (ecrit != null && ref.mounted) {
        final courant = state.value;
        if (courant != null) {
          state = AsyncValue<EtatCentre>.data(
            courant.avec(notification.avecLecture(ecrit)),
          );
        }
      }
      return true;
    } on Object {
      if (ref.mounted) state = AsyncValue<EtatCentre>.data(avant);
      return false;
    }
  }

  /// Marque lues toutes les non-lues. Rend faux si la base a refusé.
  Future<bool> toutMarquerLu() async {
    final etat = state.value;
    final userId = ref.read(sessionProvider).value?.userId;
    if (etat == null || userId == null || etat.nonLues == 0) return true;

    final avant = etat;
    state = AsyncValue<EtatCentre>.data(etat.toutesLues(DateTime.now()));

    try {
      await ref.read(notificationsRepositoryProvider).toutMarquerLu(userId);
      return true;
    } on Object {
      if (ref.mounted) state = AsyncValue<EtatCentre>.data(avant);
      return false;
    }
  }
}

final AsyncNotifierProvider<CentreNotificationsController, EtatCentre>
centreNotificationsProvider =
    AsyncNotifierProvider<CentreNotificationsController, EtatCentre>(
      CentreNotificationsController.new,
    );

/// Le nombre de rappels non lus, pour la cloche, la pastille de la barre et
/// le titre de la Boîte. Voir [EtatCentre.nonLues] pour ce qu'il compte.
///
/// Un provider dérivé plutôt qu'un `select` sur place : la barre
/// d'application ne se reconstruit que quand le **compte** change, pas à
/// chaque relecture de la liste.
final Provider<int> notificationsNonLuesProvider = Provider<int>(
  (ref) => ref.watch(centreNotificationsProvider).value?.nonLues ?? 0,
);
