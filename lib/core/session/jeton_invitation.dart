import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Le jeton d'invitation en cours de traitement, le temps du parcours.
///
/// L'invité arrive par un lien, puis passe par la connexion par code : entre
/// les deux, l'URL change et le jeton doit survivre. Il vit **en mémoire
/// seulement** — c'est un porteur de droits, il n'a rien à faire dans le
/// stockage du navigateur. Le routeur s'en sert pour ramener l'invité sur son
/// invitation dès que la session s'ouvre, au lieu de l'envoyer sur « aucune
/// caserne ».
class JetonInvitation extends Notifier<String?> {
  @override
  String? build() => null;

  void memoriser(String jeton) {
    final propre = jeton.trim();
    if (propre.isEmpty || propre == state) return;
    state = propre;
  }

  /// Appelé une fois l'invitation acceptée, ou définitivement refusée.
  void oublier() => state = null;
}

final NotifierProvider<JetonInvitation, String?> jetonInvitationProvider =
    NotifierProvider<JetonInvitation, String?>(JetonInvitation.new);
