import 'dart:async';

import 'package:astreinte_sp/features/notifications/data/messagerie_push.dart';
import 'package:astreinte_sp/features/notifications/data/push_tokens_repository.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:astreinte_sp/features/notifications/domain/message_push.dart';

/// Une [MessageriePush] sans navigateur ni Firebase.
///
/// Elle permet de rejouer les quatre situations qui comptent : le navigateur
/// qui ne sait pas faire, l'autorisation jamais demandée, l'autorisation
/// refusée, l'autorisation accordée.
class FauxMessageriePush implements MessageriePush {
  FauxMessageriePush({
    this.supportee = true,
    this.etatPermission = PermissionPush.aDemander,
    this.reponseDemande = PermissionPush.accordee,
    this.jetonRendu = 'jeton-de-test',
  });

  bool supportee;
  PermissionPush etatPermission;

  /// Ce que répond la fenêtre du navigateur à [demanderPermission].
  PermissionPush reponseDemande;

  /// Le jeton rendu par [jeton], ou `null` pour un refus.
  String? jetonRendu;

  int demandes = 0;
  int jetonsDemandes = 0;

  final StreamController<MessagePush> messages =
      StreamController<MessagePush>.broadcast();

  @override
  Future<bool> estSupportee() async => supportee;

  @override
  Future<PermissionPush> permission() async => etatPermission;

  @override
  Future<PermissionPush> demanderPermission() async {
    demandes++;
    etatPermission = reponseDemande;
    return reponseDemande;
  }

  @override
  Future<String?> jeton() async {
    jetonsDemandes++;
    return jetonRendu;
  }

  @override
  Stream<MessagePush> get messagesPremierPlan => messages.stream;

  void fermer() => messages.close();
}

/// Un appel à `register_push_token`, tel que le dépôt l'a reçu. Pas
/// d'identifiant de membre : la base le lit dans la session.
typedef EcritureJeton = ({
  String token,
  PlateformePush plateforme,
  String? libelleAppareil,
});

/// Un [PushTokensRepository] sans réseau.
class FauxPushTokensRepository implements PushTokensRepository {
  FauxPushTokensRepository({
    this.echoue = false,
    this.suppressionSuspendue = false,
  });

  bool echoue;

  /// La suppression part et ne revient jamais : un réseau qui se tait.
  bool suppressionSuspendue;

  /// Appelé au moment où la suppression est demandée, **avant** qu'elle
  /// réussisse ou échoue : c'est là que les tests regardent ce qui est encore
  /// sur l'appareil et si la session est encore ouverte.
  Future<void> Function(String token)? auMomentDeLOubli;

  final List<EcritureJeton> ecritures = <EcritureJeton>[];
  final List<String> oublies = <String>[];

  @override
  Future<void> enregistrer({
    required String token,
    required PlateformePush plateforme,
    String? libelleAppareil,
  }) async {
    if (echoue) throw const FormatException('écriture refusée');
    ecritures.add((
      token: token,
      plateforme: plateforme,
      libelleAppareil: libelleAppareil,
    ));
  }

  @override
  Future<void> oublier(String token) async {
    await auMomentDeLOubli?.call(token);
    if (suppressionSuspendue) return Completer<void>().future;
    if (echoue) throw const FormatException('suppression refusée');
    oublies.add(token);
  }
}
