import 'package:flutter/material.dart';
/// Les types de `notification_type` (`docs/SCHEMA.md § 1`), plus le cas qui
/// compte vraiment : **celui qu'on ne connaît pas**.
///
/// Le backend peut gagner un type avant que la PWA ne soit redéployée. Une
/// notification qu'on ne sait pas classer reste une notification qu'il faut
/// lire : elle tombe sur [inconnu], garde son titre, son corps et sa
/// destination, et n'emporte pas l'écran avec elle. C'est le contraire du
/// choix fait pour `slot_type` (`core/supabase/enums.dart`), et pour la même
/// raison : là-bas, deviner un créneau de nuit est une garde non couverte ;
/// ici, refuser d'afficher est la seule faute possible.
enum TypeNotification {
  invitation('invitation', Icons.mail_outline),
  rappelSaisie('availability_reminder', Icons.schedule),
  astreinteProposee('assignment_proposed', Icons.inbox_outlined),
  rappelReponse('assignment_reminder', Icons.schedule),
  refusRecu('assignment_declined', Icons.event_busy_outlined),
  creneauModifie('assignment_changed', Icons.edit_calendar_outlined),
  creneauAnnule('assignment_cancelled', Icons.event_busy_outlined),
  planningValide('schedule_validated', Icons.event_available_outlined),
  toutAccepte('schedule_all_accepted', Icons.event_available_outlined),
  retardataires('late_responders', Icons.group_outlined),
  finEssai('subscription_trial_ending', Icons.hourglass_top),
  caserneSuspendue('subscription_suspended', Icons.visibility_outlined),

  /// Un type que cette version de l'application ne connaît pas.
  inconnu('', Icons.notifications_outlined);

  const TypeNotification(this.valeurSql, this.icone);

  /// La valeur de l'enum Postgres. Vide pour [inconnu], qui n'en a pas.
  final String valeurSql;

  /// Le glyphe de la ligne. Material Icons, style contour, jamais un emoji
  /// (`DESIGN.md § Don't`).
  final IconData icone;

  /// Ne lève jamais : un type inconnu est [inconnu].
  static TypeNotification depuisSql(String? valeur) {
    for (final type in values) {
      if (type != inconnu && type.valeurSql == valeur) return type;
    }
    return inconnu;
  }
}

/// Une ligne `notifications` de canal `inapp`, telle que le centre l'affiche.
///
/// Les colonnes sont celles de `docs/SCHEMA.md § 2.12`, et rien d'autre.
/// `channel` n'est pas porté : l'écran ne lit que l'`inapp`, le filtre est
/// dans la requête.
@immutable
class NotificationInterne {
  const NotificationInterne({
    required this.id,
    required this.type,
    required this.titre,
    required this.corps,
    required this.creeLe,
    this.route,
    this.periode,
    this.lueLe,
    this.erreur,
  });

  final String id;
  final TypeNotification type;
  final String titre;
  final String corps;

  /// `created_at`. L'ordre de la liste, et la date affichée en marge.
  final DateTime creeLe;

  /// `data.route` : le lien public (`docs/WORKFLOWS.md § 8`). `null` quand la
  /// notification n'ouvre rien. Il n'est **jamais** interprété ici : c'est
  /// `destinationInterne` qui décide, et elle seule.
  final String? route;

  /// `data.period`, `AAAA-MM`, quand la notification en porte un.
  final String? periode;

  /// `read_at`. La seule colonne que le membre a le droit d'écrire — un
  /// `grant` de colonne l'impose (`docs/SCHEMA.md § 5`).
  final DateTime? lueLe;

  /// `error`. Renseigné sur une ligne `inapp` quand la demande d'envoi a été
  /// **abandonnée** après cinq tentatives : la base la remet alors en file sur
  /// le seul canal interne, et `send-notification` écrit la ligne en échec
  /// (ticket 040, migration `0022`). Seule la présence de la colonne compte —
  /// son contenu est un motif technique, jamais montré au membre.
  final String? erreur;

  bool get lue => lueLe != null;

  /// Vrai si la ligne trace un envoi qui n'a pas abouti.
  bool get enEchec => erreur != null && erreur!.trim().isNotEmpty;

  NotificationInterne avecLecture(DateTime? instant) => NotificationInterne(
    id: id,
    type: type,
    titre: titre,
    corps: corps,
    creeLe: creeLe,
    route: route,
    periode: periode,
    lueLe: instant,
    erreur: erreur,
  );

  /// Lit une ligne PostgREST.
  ///
  /// Tolérante par construction : un titre absent ou une date illisible ne
  /// doit pas faire tomber la liste entière. Le seul champ sans repli est
  /// `id`, sans lequel la ligne ne peut ni être affichée ni être marquée lue.
  static NotificationInterne depuisJson(Map<String, dynamic> ligne) {
    final donnees = ligne['data'];
    final carte = donnees is Map<String, dynamic>
        ? donnees
        : const <String, dynamic>{};

    return NotificationInterne(
      id: ligne['id'] as String,
      type: TypeNotification.depuisSql(ligne['type'] as String?),
      titre: (ligne['title'] as String?)?.trim() ?? '',
      corps: (ligne['body'] as String?)?.trim() ?? '',
      creeLe: _instant(ligne['created_at']) ?? DateTime.now(),
      route: _texte(carte['route']),
      periode: _texte(carte['period']),
      lueLe: _instant(ligne['read_at']),
      erreur: _texte(ligne['error']),
    );
  }

  static String? _texte(Object? valeur) {
    if (valeur is! String) return null;
    final propre = valeur.trim();
    return propre.isEmpty ? null : propre;
  }

  static DateTime? _instant(Object? valeur) {
    if (valeur is! String) return null;
    return DateTime.tryParse(valeur)?.toLocal();
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationInterne &&
      other.id == id &&
      other.type == type &&
      other.titre == titre &&
      other.corps == corps &&
      other.creeLe == creeLe &&
      other.route == route &&
      other.periode == periode &&
      other.lueLe == lueLe &&
      other.erreur == erreur;

  @override
  int get hashCode =>
      Object.hash(id, type, titre, corps, creeLe, route, periode, lueLe, erreur);

  @override
  String toString() => 'NotificationInterne($id, ${type.name}, lue: $lue)';
}
