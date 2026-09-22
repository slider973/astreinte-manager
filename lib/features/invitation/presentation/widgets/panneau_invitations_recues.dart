import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/ecran_simple.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/invitation_recue.dart';
import 'ligne_invitation_recue.dart';
import 'panneau_invitation.dart';

/// La zone centrale d'« Aucune caserne » quand elle a une question en cours,
/// une réponse, ou un échec.
///
/// Trois formes, un seul meuble : l'écran garde son `Scaffold`, sa `SafeArea`
/// et son bouton « Se déconnecter » en bas quoi qu'il arrive. Un écran qui se
/// réorganise sous les doigts pendant qu'une réponse arrive est un écran qu'on
/// quitte.
///
/// **L'attente est l'état le plus important.** Si la phrase « Demande une
/// invitation à ton chef de centre » s'affichait pendant les six cents
/// millisecondes de la requête, le défaut serait intact : la personne l'aurait
/// lue, elle aurait compris qu'elle n'est pas attendue, et elle serait partie.
/// D'où le titre neutre et le squelette, jamais une roue.
///
/// Un `AsyncData` **vide** n'arrive pas ici : l'écran rend alors l'état vide
/// du ticket 006, inchangé.
class PanneauInvitationsRecues extends StatelessWidget {
  const PanneauInvitationsRecues({
    required this.invitations,
    required this.email,
    required this.onRejoindre,
    super.key,
  });

  final AsyncValue<List<InvitationRecue>> invitations;

  /// L'adresse de la session, nommée dans le cadrage.
  final String email;

  /// Ouvre l'écran d'invitation sur l'identifiant choisi.
  final void Function(InvitationRecue) onRejoindre;

  @override
  Widget build(BuildContext context) {
    final liste = invitations.value ?? const <InvitationRecue>[];

    if (liste.isEmpty) {
      return _Colonne(
        titre: AppStrings.aucuneCaserneTitreNeutre,
        children: <Widget>[
          if (invitations.isLoading)
            const AttenteInvitation(
              phrase: AppStrings.aucuneCaserneVerification,
            )
          else
            // Le fait, sans le conseil : il vient des appartenances, déjà
            // chargées, et il reste vrai même quand la question n'a pas pu
            // être posée.
            const TexteInvitation(
              AppStrings.aucuneCaserneFait,
              principal: true,
            ),
        ],
      );
    }

    final attendues = liste.where((InvitationRecue i) => i.valide).length;
    final titre = attendues == 0
        ? AppStrings.invitationsExpireesTitre(liste.length)
        : AppStrings.invitationsRecuesTitre(attendues);

    // Une seule invitation à rejoindre : c'est l'action de l'écran. Plusieurs :
    // aucune n'est « la » bonne.
    final variante = attendues > 1
        ? PrimaryButtonVariante.secondaire
        : PrimaryButtonVariante.primaire;

    return _Colonne(
      titre: titre,
      children: <Widget>[
        if (attendues > 0) ...<Widget>[
          TexteInvitation(
            AppStrings.invitationsRecuesIntro(email, attendues),
            principal: true,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        for (final (int rang, InvitationRecue invitation) in liste.indexed) ...[
          if (rang > 0) const AppDivider(),
          LigneInvitationRecue(
            invitation: invitation,
            variante: variante,
            onRejoindre: () => onRejoindre(invitation),
          ),
        ],
      ],
    );
  }
}

/// La colonne de lecture : bornée à [EcranSimple.colonneLecture], centrée,
/// défilante.
///
/// Les mesures sont celles d'`EcranSimple` — même marge de page selon la
/// classe de fenêtre, même largeur maximale. Ce n'est pas `EcranSimple` parce
/// que celui-ci porte son propre `Scaffold` : ici le meuble appartient à
/// « Aucune caserne », qui garde sa sortie « Se déconnecter » épinglée en bas.
class _Colonne extends StatelessWidget {
  const _Colonne({required this.titre, required this.children});

  final String titre;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints contraintes) =>
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: contraintes.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: EcranSimple.colonneLecture,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: marge,
                      vertical: AppSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Semantics(
                          header: true,
                          child: Text(
                            titre,
                            style: theme.textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sousTitre),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
  }
}
