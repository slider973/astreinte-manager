import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/profil_repository.dart';
import 'profil.dart';

/// Le dépôt du profil. Surchargé par un faux dans les tests.
final Provider<ProfilRepository> profilRepositoryProvider =
    Provider<ProfilRepository>(
      (ref) => SupabaseProfilRepository(ref.watch(supabaseClientProvider)),
    );

/// Le profil de la personne connectée.
///
/// Relu à chaque changement de session, et **invalidé après un
/// enregistrement** : l'écran de profil montre alors ce que la base a accepté,
/// pas ce qu'on lui a envoyé.
final FutureProvider<Profil> monProfilProvider = FutureProvider<Profil>((
  ref,
) async {
  final session = ref.watch(sessionProvider).value;
  if (session == null) {
    // Pas d'exception : personne n'est connecté, il n'y a rien à lire et rien
    // à signaler. L'écran de profil n'est pas atteignable dans cet état.
    return const Profil(prenom: '', nom: '', email: '');
  }
  return ref.watch(profilRepositoryProvider).lire(session.userId);
});

/// L'état du complément de profil.
@immutable
class EtatProfil {
  const EtatProfil({
    this.enregistrementEnCours = false,
    this.erreurPrenom,
    this.erreurNom,
    this.erreurGenerale,
  });

  final bool enregistrementEnCours;
  final String? erreurPrenom;
  final String? erreurNom;

  /// L'échec d'écriture, affiché en bannière.
  final String? erreurGenerale;
}

/// Enregistre prénom, nom et téléphone, dans cet ordre d'importance.
///
/// Le téléphone est facultatif : le champ le dit dans son libellé, et rien ne
/// bloque sans lui.
class ProfilController extends Notifier<EtatProfil> {
  @override
  EtatProfil build() => const EtatProfil();

  void effacerErreurs() {
    if (state.erreurPrenom == null &&
        state.erreurNom == null &&
        state.erreurGenerale == null) {
      return;
    }
    state = EtatProfil(enregistrementEnCours: state.enregistrementEnCours);
  }

  /// Vrai si le profil est enregistré.
  Future<bool> enregistrer({
    required String prenom,
    required String nom,
    required String telephone,
  }) async {
    if (state.enregistrementEnCours) return false;

    final prenomPropre = prenom.trim();
    final nomPropre = nom.trim();
    if (prenomPropre.isEmpty || nomPropre.isEmpty) {
      state = EtatProfil(
        erreurPrenom: prenomPropre.isEmpty
            ? AppStrings.profilPrenomManquant
            : null,
        erreurNom: nomPropre.isEmpty ? AppStrings.profilNomManquant : null,
      );
      return false;
    }

    final session = ref.read(sessionProvider).value;
    if (session == null) {
      state = const EtatProfil(erreurGenerale: AppStrings.profilEchec);
      return false;
    }

    state = const EtatProfil(enregistrementEnCours: true);
    try {
      await ref
          .read(profilRepositoryProvider)
          .completer(
            userId: session.userId,
            prenom: prenomPropre,
            nom: nomPropre,
            telephone: telephone,
          );
      // La lecture repart de la base : l'écran de profil affiche ce qui a été
      // accepté, jamais ce qu'on croit avoir écrit.
      ref.invalidate(monProfilProvider);
      state = const EtatProfil();
      return true;
    } on Object {
      state = const EtatProfil(erreurGenerale: AppStrings.profilEchec);
      return false;
    }
  }
}

final NotifierProvider<ProfilController, EtatProfil> profilControllerProvider =
    NotifierProvider<ProfilController, EtatProfil>(
      ProfilController.new,
      isAutoDispose: true,
    );
