import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../domain/etat_notifications.dart';
import '../../domain/notifications_providers.dart';

/// Le réglage des notifications dans le profil.
///
/// Un **bloc réglé** (`DESIGN.md § Cards / Containers`) : filet 1 dp, rayon 8,
/// aucune ombre. Il déménagera tel quel dans l'écran de profil du ticket 007.
///
/// L'ordre compte : **l'état d'abord, l'interrupteur ensuite**. Savoir si les
/// notifications arrivent sur cet appareil est la question qu'on se pose en
/// ouvrant ce bloc ; régler ce qu'on reçoit vient après, et n'a de sens que si
/// la réponse à la première est « oui ».
class ReglageNotifications extends ConsumerStatefulWidget {
  const ReglageNotifications({super.key});

  @override
  ConsumerState<ReglageNotifications> createState() =>
      _ReglageNotificationsState();
}

class _ReglageNotificationsState extends ConsumerState<ReglageNotifications> {
  String? _erreur;

  Future<void> _basculer({required bool actif}) async {
    setState(() => _erreur = null);
    final ok = await ref
        .read(pushNonCritiquesProvider.notifier)
        .definir(actif: actif);
    if (!mounted || ok) return;
    setState(() => _erreur = AppStrings.notifReglageEchec);
  }

  Future<void> _activer() async {
    await ref
        .read(notificationsControllerProvider.notifier)
        .demanderAutorisation();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etat = ref.watch(notificationsControllerProvider).value;
    final nonCritiques = ref.watch(pushNonCritiquesProvider).value ?? true;
    final active = etat?.estActive ?? false;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: AppRadius.controleRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                AppStrings.notifReglageTitre,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _LigneEtat(etat: etat),
            if (etat?.peutDemander ?? false) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => unawaited(_activer()),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text(AppStrings.notifActiver),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SwitchListTile.adaptive(
              value: nonCritiques,
              // Un interrupteur sans autorisation ne réglerait rien : il est
              // désactivé, et la raison est écrite juste en dessous
              // (`DESIGN.md § Buttons`).
              onChanged: active
                  ? (bool valeur) => unawaited(_basculer(actif: valeur))
                  : null,
              title: const Text(AppStrings.notifReglageBascule),
              subtitle: const Text(AppStrings.notifReglageBasculeAide),
              contentPadding: EdgeInsets.zero,
            ),
            if (!active)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  AppStrings.notifReglageRaisonInactive,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.notifReglageToujours,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_erreur != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.error_outline,
                      size: AppTouch.icone,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _erreur!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Le fait, porté par **icône + libellé**, la couleur en quatrième
/// (`DESIGN.md § Named Rules`). Quand l'état a une sortie, elle est écrite
/// juste dessous.
class _LigneEtat extends StatelessWidget {
  const _LigneEtat({required this.etat});

  final EtatNotifications? etat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;

    final (IconData icone, String libelle, String? sortie) = switch (etat) {
      EtatNotifications.active => (
        Icons.notifications_active,
        AppStrings.notifEtatActive,
        null,
      ),
      EtatNotifications.aDemander => (
        Icons.notifications_paused_outlined,
        AppStrings.notifEtatADemander,
        null,
      ),
      EtatNotifications.refusee => (
        Icons.notifications_off,
        AppStrings.notifEtatRefusee,
        AppStrings.notifEtatRefuseeSortie,
      ),
      EtatNotifications.installationRequise => (
        Icons.install_mobile,
        AppStrings.notifEtatInstallation,
        null,
      ),
      EtatNotifications.nonSupporte => (
        Icons.notifications_off_outlined,
        AppStrings.notifEtatNonSupporte,
        AppStrings.notifSansPushTexte,
      ),
      EtatNotifications.horsWeb => (
        Icons.notifications_off_outlined,
        AppStrings.notifEtatHorsWeb,
        null,
      ),
      EtatNotifications.nonConfigure || null => (
        Icons.notifications_off_outlined,
        AppStrings.notifEtatNonConfigure,
        AppStrings.notifSansPushTexte,
      ),
    };

    // L'encre suit l'état : « actives » emprunte le vert de la disponibilité,
    // tout le reste reste gris-encre. Une notification qui n'arrive pas n'est
    // pas une panne, et rien ici n'est rouge.
    final encre = etat == EtatNotifications.active
        ? statuts.disponibilite(DisponibiliteEtat.disponible).encre
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          label: libelle,
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icone, size: AppTouch.icone, color: encre),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  libelle,
                  style: theme.textTheme.bodyLarge?.copyWith(color: encre),
                ),
              ),
            ],
          ),
        ),
        if (sortie != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              top: AppSpacing.xs,
              start: AppTouch.icone + AppSpacing.sm,
            ),
            child: Text(
              sortie,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
