import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_spacing.dart';
import 'primary_button.dart';

/// État vide, erreur ou hors ligne : **jamais muet**.
///
/// `DESIGN.md § Don't` : « pas d'état vide muet ; un état vide explique et
/// propose une action ». Le titre et l'explication sont donc obligatoires, et
/// le texte « Aucune donnée » est proscrit.
///
/// L'erreur nomme le problème **et** la sortie, et elle est annoncée
/// (`liveRegion`) : un lecteur d'écran l'entend sans que le focus bouge.
class EmptyState extends StatelessWidget {
  /// État vide ordinaire : rien à afficher, et une piste pour en sortir.
  const EmptyState({
    required this.titre,
    required this.texte,
    super.key,
    this.icone = Icons.inbox_outlined,
    this.libelleAction,
    this.onAction,
  }) : _annonce = false;

  /// Échec : ce qui n'a pas marché, et « Réessayer ».
  const EmptyState.erreur({
    super.key,
    this.titre = AppStrings.erreurTitre,
    this.texte = AppStrings.erreurTexteGenerique,
    this.icone = Icons.error_outline,
    this.libelleAction = AppStrings.actionReessayer,
    required this.onAction,
  }) : _annonce = true;

  /// Écran sans rien en cache et sans réseau.
  const EmptyState.horsLigne({
    super.key,
    this.titre = AppStrings.erreurReseauTitre,
    this.texte = AppStrings.erreurReseauTexte,
    this.icone = Icons.cloud_off,
    this.libelleAction = AppStrings.actionReessayer,
    required this.onAction,
  }) : _annonce = true;

  final String titre;
  final String texte;
  final IconData icone;
  final String? libelleAction;
  final VoidCallback? onAction;

  /// Vrai pour les variantes qui doivent être annoncées sans déplacer le focus.
  final bool _annonce;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = onAction;
    final libelle = libelleAction;

    return Semantics(
      liveRegion: _annonce,
      container: true,
      child: Center(
        child: ConstrainedBox(
          // Mesure de lecture : la prose reste entre 65 et 75 caractères.
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icone,
                  size: AppSpacing.xxxl,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  titre,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  texte,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (action != null && libelle != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    libelle: libelle,
                    onPressed: action,
                    icone: _annonce ? Icons.refresh : null,
                    variante: PrimaryButtonVariante.secondaire,
                    pleineLargeur: false,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
