import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/primary_button.dart';

/// Connecté, mais rattaché à aucune caserne active.
///
/// Deux cas, deux phrases : le compte qui n'a jamais été invité, et celui dont
/// l'accès a été désactivé — un membre désactivé garde son historique
/// (`docs/PRD.md § 6.2`), il doit pouvoir constater son état.
class AucuneCaserneScreen extends ConsumerWidget {
  const AucuneCaserneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toutes =
        ref.watch(appartenancesProvider).value ?? const <Appartenance>[];
    final desactivee = toutes.firstOrNull;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: desactivee == null
                  ? const EmptyState(
                      titre: AppStrings.aucuneCaserneTitre,
                      texte: AppStrings.aucuneCaserneTexte,
                      icone: Icons.markunread_mailbox_outlined,
                    )
                  : EmptyState(
                      titre: AppStrings.caserneDesactiveeTitre,
                      texte: AppStrings.caserneDesactiveeTexte(
                        desactivee.nomCaserne,
                      ),
                      icone: Icons.no_accounts_outlined,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: PrimaryButton(
                libelle: AppStrings.seDeconnecter,
                variante: PrimaryButtonVariante.secondaire,
                icone: Icons.logout,
                onPressed: () => unawaited(
                  ref.read(authRepositoryProvider).seDeconnecter(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
