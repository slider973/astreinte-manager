import 'package:astreinte_sp/features/notifications/data/notifications_repository.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';

/// Un [NotificationsRepository] sans réseau, qui **rejoue les règles de la
/// base**.
///
/// Deux règles sont reproduites ici, sinon le faux mentirait :
/// `marquerLue` ne touche que les lignes dont `read_at` est nul (et rend
/// `null` pour une ligne déjà lue), et `toutMarquerLu` rend le nombre de
/// lignes réellement écrites.
class FauxNotificationsRepository implements NotificationsRepository {
  FauxNotificationsRepository({
    List<NotificationInterne>? notifications,
    this.erreurLecture = false,
    this.erreurEcriture = false,
  }) : notifications = <NotificationInterne>[...?notifications];

  List<NotificationInterne> notifications;

  bool erreurLecture;

  /// Toute écriture est refusée : c'est le cas du retour arrière optimiste.
  bool erreurEcriture;

  int lectures = 0;
  final List<String> marquages = <String>[];
  int marquagesGlobaux = 0;

  /// L'instant écrit par la base. Fixe, pour que les tests s'y accrochent.
  static final DateTime instantDeLecture = DateTime.utc(2026, 9, 20, 10);

  @override
  Future<List<NotificationInterne>> lister({
    required String userId,
    int limite = SupabaseNotificationsRepository.limiteParDefaut,
  }) async {
    lectures++;
    if (erreurLecture) throw const FormatException('lecture refusée');
    final triees = <NotificationInterne>[...notifications]
      ..sort((a, b) => b.creeLe.compareTo(a.creeLe));
    return triees.take(limite).toList();
  }

  @override
  Future<DateTime?> marquerLue(String id) async {
    marquages.add(id);
    if (erreurEcriture) throw const FormatException('écriture refusée');

    var ecrite = false;
    notifications = <NotificationInterne>[
      for (final notification in notifications)
        if (notification.id == id && !notification.lue)
          () {
            ecrite = true;
            return notification.avecLecture(instantDeLecture);
          }()
        else
          notification,
    ];
    return ecrite ? instantDeLecture : null;
  }

  @override
  Future<int> toutMarquerLu(String userId) async {
    marquagesGlobaux++;
    if (erreurEcriture) throw const FormatException('écriture refusée');

    var compte = 0;
    notifications = <NotificationInterne>[
      for (final notification in notifications)
        if (notification.lue)
          notification
        else
          () {
            compte++;
            return notification.avecLecture(instantDeLecture);
          }(),
    ];
    return compte;
  }
}

/// Une notification interne de test, avec des valeurs par défaut lisibles.
NotificationInterne notification({
  required String id,
  TypeNotification type = TypeNotification.astreinteProposee,
  String titre = 'Une astreinte t\'est proposée',
  String corps = 'Samedi 4 octobre, nuit.',
  String? route = '/proposals',
  DateTime? creeLe,
  DateTime? lueLe,
  String? erreur,
}) => NotificationInterne(
  id: id,
  type: type,
  titre: titre,
  corps: corps,
  creeLe: creeLe ?? DateTime(2026, 9, 20, 9),
  route: route,
  lueLe: lueLe,
  erreur: erreur,
);
