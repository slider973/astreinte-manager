import 'package:flutter/foundation.dart';

/// Une invitation qui attend l'adresse de la session, telle que la rend
/// `my_pending_invitations()` (migration `0036`, `docs/SCHEMA.md § 3`).
///
/// **Cinq champs, et pas un de plus** : ni jeton, ni identifiant de caserne,
/// ni rôle. Ce qu'un compte membre d'aucune caserne lit ne porte que ce dont
/// le geste a besoin — le nom pour savoir où l'on entre, l'identifiant pour
/// désigner laquelle, l'échéance pour dater, l'état pour ne pas le deviner.
@immutable
class InvitationRecue {
  const InvitationRecue({
    required this.id,
    required this.caserne,
    required this.echeance,
    required this.expiree,
    this.inviteur,
  });

  /// Lit une ligne de la réponse, ou rend `null` quand elle est inexploitable.
  ///
  /// **Une ligne incomplète est ignorée, jamais une exception.** Une exception
  /// ferait basculer l'écran entier sur « Impossible de vérifier tes
  /// invitations » alors que les autres lignes sont lisibles — c'est-à-dire
  /// qu'elle remettrait l'écran à se tromper, ce que ce ticket répare.
  static InvitationRecue? depuisJson(Object? brut) {
    if (brut is! Map) return null;

    final id = _texte(brut['id']);
    final caserne = _texte(brut['station_name']);
    final echeance = DateTime.tryParse(_texte(brut['expires_at']));
    if (id.isEmpty || caserne.isEmpty || echeance == null) return null;

    // **C'est le serveur qui tranche l'expiration, jamais l'horloge de
    // l'appareil** (`docs/SCHEMA.md § 3`) : une horloge dérive, celle d'un
    // téléphone de caserne prêté davantage, et l'écran et `accept_invitation`
    // doivent placer la frontière au même endroit. Un état qu'on ne connaît
    // pas n'est pas un état qu'on devine : la ligne est ignorée.
    final expiree = switch (_texte(brut['status'])) {
      'pending' => false,
      'expired' => true,
      _ => null,
    };
    if (expiree == null) return null;

    final inviteur = _texte(brut['invited_by_name']);
    return InvitationRecue(
      id: id,
      caserne: caserne,
      echeance: echeance,
      expiree: expiree,
      inviteur: inviteur.isEmpty ? null : inviteur,
    );
  }

  /// La réponse entière, lue ligne à ligne et remise dans l'ordre de l'écran.
  static List<InvitationRecue> depuisListe(Object? brut) {
    if (brut is! List) return const <InvitationRecue>[];

    final lues = <InvitationRecue>[
      for (final Object? ligne in brut) ?InvitationRecue.depuisJson(ligne),
    ]..sort(_ordreDAffichage);
    return List<InvitationRecue>.unmodifiable(lues);
  }

  /// L'identifiant de la ligne `invitations`. **Ce n'est pas un porteur de
  /// droits** : seul le compte dont l'adresse correspond peut en faire quelque
  /// chose, et `accept_invitation_by_id` le revérifie.
  final String id;

  /// Le nom de la caserne : le point focal de l'écran. Personne ne rejoint
  /// « une caserne », on rejoint le CS Maurepas.
  final String caserne;

  /// Prénom et nom de la personne qui a invité, recomposés côté serveur.
  /// `null` quand le profil n'a pas de nom — la ligne est alors omise, et
  /// **jamais remplacée par une adresse**.
  final String? inviteur;

  final DateTime echeance;

  /// Vrai quand le serveur a répondu `expired`.
  final bool expiree;

  bool get valide => !expiree;

  /// L'ordre de l'écran (brief 051 § 5.2) : les invitations encore valables
  /// d'abord, échéance la plus proche en tête ; les expirées ensuite, la plus
  /// récemment périmée en tête.
  ///
  /// Le serveur, lui, trie par `expires_at` décroissant et borne à dix lignes
  /// (`docs/SCHEMA.md § 3`) : c'est son tri qui décide **lesquelles** arrivent,
  /// celui-ci ne décide que de l'ordre de lecture.
  static int _ordreDAffichage(InvitationRecue a, InvitationRecue b) {
    if (a.expiree != b.expiree) return a.expiree ? 1 : -1;
    return a.expiree
        ? b.echeance.compareTo(a.echeance)
        : a.echeance.compareTo(b.echeance);
  }

  static String _texte(Object? valeur) => valeur is String ? valeur.trim() : '';

  @override
  bool operator ==(Object other) =>
      other is InvitationRecue &&
      other.id == id &&
      other.caserne == caserne &&
      other.inviteur == inviteur &&
      other.echeance == echeance &&
      other.expiree == expiree;

  @override
  int get hashCode => Object.hash(id, caserne, inviteur, echeance, expiree);

  @override
  String toString() =>
      'InvitationRecue($id, $caserne, ${expiree ? 'expirée' : 'en attente'})';
}
