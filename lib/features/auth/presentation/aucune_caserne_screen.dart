import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';
import '../../../core/session/deconnexion.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';

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

    // La ligne désactivée, pas la première venue : un compte peut porter une
    // appartenance `invited` restée en plan, et ce n'est pas elle qui explique
    // pourquoi la caserne a disparu de l'écran.
    final desactivee = toutes
        .where((Appartenance a) => a.statut == StatutMembre.desactive)
        .firstOrNull;

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
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: BoutonDeconnexion(),
            ),
          ],
        ),
      ),
    );
  }
}
