import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/profil_repository.dart';

/// Le dépôt du profil. Surchargé par un faux dans les tests.
final Provider<ProfilRepository> profilRepositoryProvider =
    Provider<ProfilRepository>(
      (ref) => SupabaseProfilRepository(ref.watch(supabaseClientProvider)),
    );

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
