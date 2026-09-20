import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_erreur.dart';
import 'session_utilisateur.dart';

/// Tout ce que l'app sait faire de l'authentification.
///
/// Une interface, pas une classe Supabase : les écrans et les providers se
/// testent avec un faux dépôt, sans réseau ni client réel.
abstract interface class AuthRepository {
  /// La session courante, puis chacun de ses changements. Émet `null` quand
  /// l'utilisateur est déconnecté.
  Stream<SessionUtilisateur?> get sessions;

  /// La session connue à l'instant présent, sans attendre le flux.
  SessionUtilisateur? get sessionCourante;

  /// Envoie un code à six chiffres (et un lien magique) à [email].
  ///
  /// Lève un [AuthEchec] portant une [AuthErreur] traduite.
  Future<void> envoyerCode(String email);

  /// Échange [code] contre une session pour [email].
  ///
  /// Lève un [AuthEchec] portant une [AuthErreur] traduite.
  Future<void> verifierCode({required String email, required String code});

  Future<void> seDeconnecter();
}

/// Implémentation Supabase de [AuthRepository].
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, {String? urlRedirection})
    : _urlRedirection = urlRedirection ?? urlRedirectionParDefaut();

  final SupabaseClient _client;

  /// Où le lien magique doit retomber. `null` hors du web : le lien reste
  /// alors une simple confirmation, et le code à six chiffres fait foi.
  final String? _urlRedirection;

  GoTrueClient get _auth => _client.auth;

  /// L'origine de la PWA (`https://astreintes.example`), seule cible que le
  /// lien magique doit rouvrir. Hors du web, il n'y a pas d'origine : le lien
  /// magique n'est pas proposé (voir `tickets/.../005`).
  static String? urlRedirectionParDefaut() =>
      kIsWeb ? Uri.base.origin : null;

  @override
  Stream<SessionUtilisateur?> get sessions async* {
    // La session restaurée est déjà là après `Supabase.initialize` : on
    // l'émet tout de suite pour ne pas faire clignoter l'écran de connexion.
    yield sessionCourante;
    yield* _auth.onAuthStateChange.map((evenement) => _depuis(evenement.session));
  }

  @override
  SessionUtilisateur? get sessionCourante => _depuis(_auth.currentSession);

  @override
  Future<void> envoyerCode(String email) async {
    try {
      await _auth.signInWithOtp(
        email: email,
        // Les comptes naissent d'une invitation (ticket 006), jamais d'un
        // écran de connexion : une adresse inconnue reçoit un refus explicite
        // plutôt qu'un compte fantôme.
        //
        // Ce drapeau est une politesse, pas une garantie : la clé anon est
        // publique, donc quiconque peut appeler /auth/v1/otp sans lui. Ce qui
        // ferme vraiment la porte, c'est `auth.enable_signup = false` dans
        // `supabase/config.toml`, qui répond alors `signup_disabled` — traduit
        // ici en « Aucun compte pour cette adresse ».
        shouldCreateUser: false,
        emailRedirectTo: _urlRedirection,
      );
    } on Object catch (erreur) {
      throw AuthEchec(traduireErreurAuth(erreur, etape: AuthEtape.envoi));
    }
  }

  @override
  Future<void> verifierCode({
    required String email,
    required String code,
  }) async {
    try {
      await _auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
    } on Object catch (erreur) {
      throw AuthEchec(
        traduireErreurAuth(erreur, etape: AuthEtape.verification),
      );
    }
  }

  @override
  Future<void> seDeconnecter() => _auth.signOut();

  SessionUtilisateur? _depuis(Session? session) {
    final utilisateur = session?.user;
    if (utilisateur == null) return null;
    return SessionUtilisateur(
      userId: utilisateur.id,
      email: utilisateur.email ?? '',
    );
  }
}
