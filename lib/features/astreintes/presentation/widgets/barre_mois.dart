import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// « ‹ Octobre 2026 › ». Les flèches font 48 dp et s'annoncent.
///
/// Une flèche qui ne mène nulle part est **désactivée, jamais cachée**, et sa
/// raison est son nom accessible et son info-bulle : une phrase permanente sous
/// la barre coûterait 20 dp pour redire ce qu'une flèche grise dit déjà
/// (`DESIGN.md § Écarts, ticket 027`).
///
/// Partagée par le calendrier de « Mes astreintes » et par le registre de la
/// caserne, qui n'ont aucune raison d'avoir deux barres de mois différentes.
class BarreMois extends StatelessWidget {
  const BarreMois({
    required this.libelle,
    required this.onPrecedent,
    required this.onSuivant,
    required this.libellePrecedent,
    required this.libelleSuivant,
    required this.raisonPrecedent,
    required this.raisonSuivant,
    super.key,
  });

  /// « Octobre 2026 ».
  final String libelle;

  /// `null` sur une borne.
  final VoidCallback? onPrecedent;
  final VoidCallback? onSuivant;

  final String libellePrecedent;
  final String libelleSuivant;

  /// Ce qu'annonce la flèche quand elle est inerte.
  final String raisonPrecedent;
  final String raisonSuivant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onPrecedent,
            icon: const Icon(Icons.chevron_left),
            tooltip: onPrecedent == null ? raisonPrecedent : libellePrecedent,
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                libelle,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          IconButton(
            onPressed: onSuivant,
            icon: const Icon(Icons.chevron_right),
            tooltip: onSuivant == null ? raisonSuivant : libelleSuivant,
          ),
        ],
      ),
    );
  }
}
