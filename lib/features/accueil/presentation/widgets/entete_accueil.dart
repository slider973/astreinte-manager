import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../notifications/presentation/widgets/bouton_notifications.dart';
import '../../../profil/presentation/widgets/bouton_compte.dart';
import '../../domain/accueil_providers.dart';

/// L'en-tête du tableau de bord (`design/064 § 3.1`).
///
/// L'avatar à gauche mène au profil, la salutation au milieu, la cloche à
/// droite mène à la Boîte. Il **remplace** la barre d'application sous
/// `expanded` : une barre qui redirait « Accueil » trente points au-dessus de
/// « Bonsoir, Marie » serait un second titre pour le même endroit.
///
/// Dès `expanded`, l'en-tête de travail du 061 porte déjà l'avatar et la
/// cloche : [avecActions] passe à faux et il ne reste que la salutation. Le
/// même compte de non-lues à deux endroits d'un même écran serait deux fois la
/// même information, à vingt points près.
class EnteteAccueil extends ConsumerWidget {
  const EnteteAccueil({
    required this.maintenant,
    required this.avecActions,
    super.key,
  });

  /// Taille de l'avatar de l'en-tête (`design/064 § 2`).
  static const double tailleAvatar = 40;

  /// L'horloge, injectée : « Bonjour » ou « Bonsoir » se décide à 18 h, et un
  /// test qui lirait l'horloge du système dirait l'un ou l'autre selon
  /// l'heure à laquelle il tourne.
  final DateTime maintenant;

  /// Faux dès `expanded`, où l'avatar et la cloche vivent dans l'en-tête de
  /// travail.
  final bool avecActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prenom = ref.watch(prenomProvider);
    final salutation = salutationDe(maintenant);

    return Row(
      children: <Widget>[
        if (avecActions) ...<Widget>[
          const BoutonCompte(taille: tailleAvatar),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Semantics(
            header: true,
            label: AppStrings.accueilSalutation(salutation, prenom),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    salutation,
                    style: theme.textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (prenom.isNotEmpty)
                    Text(
                      prenom,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (avecActions) ...<Widget>[
          const SizedBox(width: AppSpacing.sm),
          const BoutonNotifications(),
        ],
      ],
    );
  }
}
