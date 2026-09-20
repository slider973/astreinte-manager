import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/appartenance.dart';
import '../../../../core/session/session_providers.dart';
import '../../domain/invitation.dart';
import '../../domain/liste_adresses.dart';
import '../../domain/membres_providers.dart';

/// L'état du formulaire d'invitation.
@immutable
class EtatInviter {
  const EtatInviter({
    this.role = RoleMembre.membre,
    this.envoiEnCours = false,
    this.erreurChamp,
    this.erreurRequete,
    this.rapport,
  });

  /// Le rôle donné à tout le lot. L'Edge Function n'en accepte qu'un.
  final RoleMembre role;

  final bool envoiEnCours;

  /// Ce qui cloche dans la saisie, avant tout appel réseau.
  final String? erreurChamp;

  /// Le refus de la requête entière : ni adresse ni rôle en cause.
  final ErreurInvitation? erreurRequete;

  /// Le sort de chaque adresse, une fois l'envoi fait.
  final RapportInvitations? rapport;

  /// Vrai quand l'écran montre le résultat d'un envoi plutôt que le
  /// formulaire.
  bool get montreLeRapport => rapport != null;
}

/// Envoie un lot d'invitations et rapporte le sort de chaque adresse.
///
/// La validation de forme est faite ici, avant l'appel : vingt adresses dont
/// une tronquée ne méritent pas un aller-retour en 4G rurale.
class InviterController extends Notifier<EtatInviter> {
  @override
  EtatInviter build() => const EtatInviter();

  void choisirRole(RoleMembre role) {
    if (state.envoiEnCours) return;
    state = EtatInviter(role: role, rapport: state.rapport);
  }

  /// Efface l'erreur dès que la saisie change.
  void effacerErreur() {
    if (state.erreurChamp == null && state.erreurRequete == null) return;
    state = EtatInviter(role: state.role, rapport: state.rapport);
  }

  /// Revient au formulaire après un envoi, pour corriger et réessayer.
  void recommencer() => state = EtatInviter(role: state.role);

  /// Vrai si l'envoi a eu lieu, quel que soit le sort de chaque adresse.
  Future<bool> envoyer(String saisie) async {
    if (state.envoiEnCours) return false;

    final liste = ListeAdresses.depuisSaisie(saisie);
    if (!liste.envoyable) {
      state = EtatInviter(role: state.role, erreurChamp: liste.erreur);
      return false;
    }

    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) {
      state = EtatInviter(
        role: state.role,
        erreurRequete: ErreurInvitation.caserneInconnue,
      );
      return false;
    }

    state = EtatInviter(role: state.role, envoiEnCours: true);
    try {
      final rapport = await ref
          .read(membresRepositoryProvider)
          .inviter(
            stationId: stationId,
            emails: liste.adresses,
            role: state.role,
          );
      state = EtatInviter(role: state.role, rapport: rapport);

      // Pas de temps réel sur les invitations : la liste de l'écran précédent
      // se relit, elle ne se met pas à jour toute seule.
      ref.invalidate(membresControllerProvider);
      return true;
    } on EchecInvitation catch (echec) {
      state = EtatInviter(role: state.role, erreurRequete: echec.erreur);
      return false;
    } on Object {
      state = EtatInviter(
        role: state.role,
        erreurRequete: ErreurInvitation.inconnue,
      );
      return false;
    }
  }
}

final NotifierProvider<InviterController, EtatInviter>
inviterControllerProvider = NotifierProvider<InviterController, EtatInviter>(
  InviterController.new,
  isAutoDispose: true,
);
