import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/ecran_simple.dart';
import '../../../core/widgets/primary_button.dart';
import '../../onboarding/domain/parcours_accueil.dart';
import '../domain/etat_notifications.dart';
import '../domain/notifications_providers.dart';

/// Dernière étape de l'accueil : « Reçois les propositions ».
///
/// **Le seul endroit de l'application qui ouvre la fenêtre d'autorisation du
/// navigateur**, et seulement sur un geste explicite, une fois que le membre
/// sait ce qu'est une proposition d'astreinte. Un refus est définitif : le
/// demander trop tôt coûterait toutes les propositions de ce pompier.
class ActivationNotificationsScreen extends ConsumerWidget {
  const ActivationNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etatAsync = ref.watch(notificationsControllerProvider);
    final etat = etatAsync.value;
    final enCours = etatAsync.isLoading;

    Future<void> continuer() async {
      final suite = await ref.read(parcoursAccueilProvider).apresLesNotifications();
      if (!context.mounted) return;
      context.goNamed(suite);
    }

    Future<void> activer() async {
      await ref.read(notificationsControllerProvider.notifier).demanderAutorisation();
      await continuer();
    }

    void versLInstallation() =>
        context.goNamed(AppRoutes.installationName);

    return EcranSimple(
      titre: AppStrings.notifAccueilTitre,
      banniere: _banniere(etat),
      children: <Widget>[
        Text(
          _intro(etat),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (etat == null || etat.peutDemander || etat.estActive) ...<Widget>[
          const SizedBox(height: AppSpacing.auDessusTitre),
          Semantics(
            header: true,
            child: Text(
              AppStrings.notifAccueilListeTitre,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Evenements(),
        ],
        const SizedBox(height: AppSpacing.xxl),
        ..._actions(
          etat: etat,
          enCours: enCours,
          activer: activer,
          continuer: continuer,
          versLInstallation: versLInstallation,
        ),
      ],
    );
  }

  /// La bannière ne porte que ce qui change tout ce qui est en dessous : une
  /// impossibilité. Quand tout va bien, il n'y en a pas.
  AppBanner? _banniere(EtatNotifications? etat) => switch (etat) {
    EtatNotifications.installationRequise => const AppBanner(
      variante: AppBannerVariante.attention,
      texte: AppStrings.notifIosBanniere,
    ),
    EtatNotifications.nonSupporte => const AppBanner(
      variante: AppBannerVariante.information,
      texte: AppStrings.notifNonSupporteBanniere,
    ),
    EtatNotifications.nonConfigure ||
    EtatNotifications.horsWeb => const AppBanner(
      variante: AppBannerVariante.information,
      texte: AppStrings.notifNonConfigureBanniere,
    ),
    EtatNotifications.refusee => const AppBanner(
      variante: AppBannerVariante.information,
      texte: AppStrings.notifEtatRefuseeSortie,
    ),
    _ => null,
  };

  String _intro(EtatNotifications? etat) => switch (etat) {
    EtatNotifications.installationRequise => AppStrings.notifIosTexte,
    EtatNotifications.nonSupporte ||
    EtatNotifications.nonConfigure ||
    EtatNotifications.horsWeb ||
    EtatNotifications.refusee => AppStrings.notifSansPushTexte,
    _ => AppStrings.notifAccueilIntro,
  };

  List<Widget> _actions({
    required EtatNotifications? etat,
    required bool enCours,
    required Future<void> Function() activer,
    required Future<void> Function() continuer,
    required VoidCallback versLInstallation,
  }) {
    // Sur iPhone hors écran d'accueil, il n'y a **aucun** bouton qui demande
    // l'autorisation : la demander ici la brûlerait sans qu'elle puisse
    // aboutir.
    if (etat == EtatNotifications.installationRequise) {
      return <Widget>[
        PrimaryButton(
          libelle: AppStrings.notifIosAction,
          icone: Icons.install_mobile,
          onPressed: versLInstallation,
        ),
        const SizedBox(height: AppSpacing.sm),
        _Passer(libelle: AppStrings.notifPlusTard, onPressed: continuer),
      ];
    }

    if (etat == null || etat.peutDemander) {
      return <Widget>[
        const Text(AppStrings.notifAccueilAvantDemande),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          libelle: AppStrings.notifActiver,
          icone: Icons.notifications_active_outlined,
          // Tant que le navigateur n'a pas répondu, le bouton porte son
          // indicateur plutôt que d'être grisé : il n'y a pas de raison à
          // afficher, seulement une attente d'un dixième de seconde.
          chargement: enCours || etat == null,
          onPressed: () => unawaited(activer()),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Passer(libelle: AppStrings.notifPlusTard, onPressed: continuer),
      ];
    }

    return <Widget>[
      PrimaryButton(
        libelle: AppStrings.notifContinuer,
        icone: Icons.arrow_forward,
        onPressed: () => unawaited(continuer()),
      ),
    ];
  }
}

/// Les trois événements, en toutes lettres. C'est la seule réponse à « qu'est
/// ce que je vais recevoir ? », la question qui décide du oui ou du non.
class _Evenements extends StatelessWidget {
  const _Evenements();

  static const List<(IconData, String)> _liste = <(IconData, String)>[
    (Icons.inbox_outlined, AppStrings.notifAccueilItemProposition),
    (Icons.verified_outlined, AppStrings.notifAccueilItemPlanning),
    (Icons.schedule, AppStrings.notifAccueilItemRappel),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final (IconData icone, String texte) in _liste)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  icone,
                  size: AppTouch.icone,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(texte, style: theme.textTheme.bodyLarge),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// « Plus tard » : un vrai bouton de 48 dp, pas un lien gris. Un accueil se
/// saute.
class _Passer extends StatelessWidget {
  const _Passer({required this.libelle, required this.onPressed});

  final String libelle;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.center,
    child: TextButton(
      onPressed: () => unawaited(onPressed()),
      child: Text(libelle),
    ),
  );
}
