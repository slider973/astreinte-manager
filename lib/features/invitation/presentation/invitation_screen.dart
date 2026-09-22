import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/deconnexion.dart';
import '../../../core/session/jeton_invitation.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/session/session_utilisateur.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/ecran_simple.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/acceptation.dart';
import '../domain/invitation_providers.dart';
import 'widgets/panneau_invitation.dart';

/// L'écran d'une invitation, **par ses deux entrées**.
///
/// - `/invite/<jeton>` : le lien reçu par courriel (ticket 006). Le lien ne
///   porte **que** le jeton — ni l'adresse invitée, ni le nom de la caserne —,
///   donc un lien transféré ne révèle rien, et c'est le serveur qui confronte
///   l'adresse de la session à celle de l'invitation.
/// - `/rejoindre/<identifiant>` : l'invitation choisie sur « Aucune caserne »
///   (ticket 051). Aucun jeton n'a été lu, ni affiché, ni transmis.
///
/// **Un seul écran, et c'est la décision du ticket 051.** Les six fins de
/// parcours d'`ErreurAcceptation`, la page « Bienvenue » qui nomme la caserne,
/// puis le profil et le guide : tout cela existe déjà, une seule fois, et pend
/// sous cet écran. En dessiner un second ferait deux vocabulaires pour les
/// mêmes échecs.
///
/// Séquence du lien : lien → cet écran → connexion par code → retour ici →
/// acceptation. Le retour est fait par le routeur, qui garde le jeton en
/// mémoire (`core/session/jeton_invitation.dart`). L'entrée par identifiant,
/// elle, ne mémorise rien : elle part d'une session déjà ouverte.
class InvitationScreen extends ConsumerStatefulWidget {
  const InvitationScreen({required this.entree, super.key});

  final EntreeInvitation entree;

  @override
  ConsumerState<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends ConsumerState<InvitationScreen> {
  @override
  void initState() {
    super.initState();
    // Un provider ne se modifie pas pendant la construction de l'arbre.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Seul le jeton se mémorise : il n'existe que dans l'URL reçue par
      // courriel, et le routeur doit pouvoir y ramener après la connexion. Un
      // identifiant, lui, vient d'une session déjà ouverte — rien à garder.
      if (widget.entree.mode == ModeInvitation.jeton) {
        ref
            .read(jetonInvitationProvider.notifier)
            .memoriser(widget.entree.valeur);
      }
      _tenter();
    });
  }

  void _tenter() {
    if (widget.entree.vide) return;
    if (ref.read(sessionProvider).value == null) return;
    if (!ref.read(acceptationControllerProvider).auRepos) return;

    unawaited(
      ref.read(acceptationControllerProvider.notifier).accepter(widget.entree),
    );
  }

  void _reessayer() {
    ref.read(acceptationControllerProvider.notifier).reinitialiser();
    _tenter();
  }

  @override
  Widget build(BuildContext context) {
    // Dès que la session s'ouvre — retour de la connexion par code —, le jeton
    // part au serveur sans que l'invité ait à toucher quoi que ce soit.
    ref.listen<AsyncValue<SessionUtilisateur?>>(sessionProvider, (_, suivant) {
      if (suivant.value != null) _tenter();
    });

    final session = ref.watch(sessionProvider);
    final etat = ref.watch(acceptationControllerProvider);

    if (widget.entree.vide) {
      return const _EcranErreur(
        echec: EchecAcceptation(ErreurAcceptation.jetonManquant),
      );
    }

    final echec = etat.echec;
    if (echec != null) {
      return _EcranErreur(echec: echec, onReessayer: _reessayer);
    }

    final acceptee = etat.acceptee;
    if (acceptee != null) return _EcranBienvenue(acceptation: acceptee);

    if (!session.hasValue) return const _EcranAttente();
    if (session.value == null) return const _EcranConnexion();

    return const _EcranAttente();
  }
}

/// Avant la connexion : ce qu'on sait dire sans rien révéler.
class _EcranConnexion extends StatelessWidget {
  const _EcranConnexion();

  @override
  Widget build(BuildContext context) {
    return EcranSimple(
      titre: AppStrings.invitationTitre,
      children: <Widget>[
        const TexteInvitation(
          AppStrings.invitationConnexionIntro,
          principal: true,
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          libelle: AppStrings.invitationSeConnecter,
          icone: Icons.mail_outline,
          onPressed: () => context.goNamed(AppRoutes.connexionName),
        ),
      ],
    );
  }
}

class _EcranAttente extends StatelessWidget {
  const _EcranAttente();

  @override
  Widget build(BuildContext context) => const EcranSimple(
    titre: AppStrings.invitationTitre,
    children: <Widget>[AttenteInvitation()],
  );
}

/// L'invitation est acceptée : la caserne est nommée, et la suite est un
/// bouton, pas un saut d'écran automatique.
class _EcranBienvenue extends ConsumerWidget {
  const _EcranBienvenue({required this.acceptation});

  final AcceptationInvitation acceptation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caserne = acceptation.caserne?.nom ?? AppStrings.valueUndefined;
    final inviteur = acceptation.inviteur?.libelle;

    return EcranSimple(
      titre: AppStrings.invitationAccepteeTitre,
      children: <Widget>[
        TexteInvitation(
          AppStrings.invitationRejointe(caserne),
          principal: true,
        ),
        if (inviteur != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          TexteInvitation(AppStrings.invitationParQui(inviteur)),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          libelle: AppStrings.actionContinuer,
          icone: Icons.arrow_forward,
          onPressed: () => context.goNamed(AppRoutes.profilAccueilName),
        ),
      ],
    );
  }
}

/// Une fin de parcours nommée, avec sa sortie.
class _EcranErreur extends StatelessWidget {
  const _EcranErreur({required this.echec, this.onReessayer});

  final EchecAcceptation echec;
  final VoidCallback? onReessayer;

  @override
  Widget build(BuildContext context) {
    final sortie = echec.sortie;
    final mauvaisCompte = echec.erreur == ErreurAcceptation.mauvaisCompte;

    return EcranSimple(
      titre: echec.titre,
      children: <Widget>[
        TexteInvitation(echec.message, principal: true),
        if (sortie != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          TexteInvitation(sortie),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (echec.erreur.reessayable && onReessayer != null)
          PrimaryButton(
            libelle: AppStrings.actionReessayer,
            icone: Icons.refresh,
            onPressed: onReessayer,
          )
        else if (echec.erreur == ErreurAcceptation.dejaAcceptee)
          PrimaryButton(
            libelle: AppStrings.actionContinuer,
            icone: Icons.arrow_forward,
            onPressed: () => context.goNamed(AppRoutes.accueilName),
          ),
        if (mauvaisCompte) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const TexteInvitation(AppStrings.invitationChangerCompte),
          const SizedBox(height: AppSpacing.sm),
          const BoutonDeconnexion(),
        ],
      ],
    );
  }
}
