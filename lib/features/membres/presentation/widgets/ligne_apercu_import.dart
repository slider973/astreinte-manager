import 'package:flutter/material.dart';

import '../../../../core/session/appartenance.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/import_membres.dart';

/// Une ligne du fichier dans l'aperçu : qui elle est, et ce qui va lui arriver.
///
/// **La ligne réglée du produit, pas une rangée de tableur.** C'est sous cette
/// forme que la personne reverra ces gens dans la liste des membres cinq
/// minutes plus tard, et quatre colonnes sur un téléphone sont illisibles.
/// Rien n'est éditable : le tableur est le lieu de la correction, l'écran celui
/// de la vérification.
class LigneApercuImport extends StatelessWidget {
  const LigneApercuImport({required this.apercu, super.key});

  final LigneApercu apercu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = apercu.detail;
    final sousTitre = apercu.sousTitre;

    // Une faute du fichier prend l'encre d'erreur ; un fait de la caserne —
    // « déjà membre », « déjà invitée » — reste gris (`DESIGN.md § Do`).
    final encreDetail = apercu.verdict.estUneFaute
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      label: apercu.titre,
      value: <String>[?sousTitre, ?detail].join('. '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: AppTouch.icone + AppSpacing.md,
              child: _Marque(verdict: apercu.verdict),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(apercu.titre, style: theme.textTheme.titleMedium),
                  if (sousTitre != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      apercu.ligne.role == RoleMembre.admin
                          ? '$sousTitre · ${RoleMembre.admin.libelle}'
                          : sousTitre,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (detail != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: encreDetail,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'icône du verdict. Une ligne qui part n'en a pas : l'absence de marqueur
/// est l'état normal, et une coche sur cinquante-huit lignes serait du bruit.
class _Marque extends StatelessWidget {
  const _Marque({required this.verdict});

  final VerdictApercu verdict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final icone = switch (verdict) {
      VerdictApercu.aInviter || VerdictApercu.aInviterSansNom => null,
      VerdictApercu.dejaMembre => Icons.person_outline,
      VerdictApercu.dejaInvitee => Icons.schedule_send_outlined,
      VerdictApercu.doublon => Icons.content_copy_outlined,
      VerdictApercu.adresseInvalide ||
      VerdictApercu.adresseAbsente => Icons.error_outline,
    };
    if (icone == null) return const SizedBox.shrink();

    return Icon(
      icone,
      size: AppTouch.icone,
      color: verdict.estUneFaute
          ? theme.colorScheme.error
          : theme.colorScheme.onSurfaceVariant,
    );
  }
}
