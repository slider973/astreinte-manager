import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/session/email.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../domain/invitation.dart';

/// Le compte rendu d'un import : ce qui est passé se compte, ce qui demande
/// un geste se lit.
///
/// **Ce n'est pas le compte rendu du ticket 006, et c'est délibéré.** Là-bas,
/// vingt adresses au plus, tapées à la main, et l'énumération est la seule
/// trace de ce qui vient d'être demandé. Ici, soixante lignes que l'aperçu a
/// déjà montrées une par une, avec leurs noms, un écran plus tôt : les
/// réénumérer alignerait soixante coches identiques sous un résumé qui dit
/// déjà « 60 invitations envoyées, 0 échec », et enterrerait les trois lignes
/// qui comptent. C'est la règle que l'aperçu applique déjà à sa marque —
/// « une coche sur cinquante-huit lignes serait du bruit ».
///
/// Deux choses seulement descendent dans le détail :
///
/// - **les refus**, nommés un par un, toujours : c'est ce qu'on vient
///   chercher, et le nom est ce qui permet de reconnaître un pompier ;
/// - **les courriels qui ne sont pas partis**, en un nombre et une phrase :
///   sans fournisseur de courriel configuré, c'est tout l'import qui est dans
///   ce cas, et le geste utile — le renvoi — se pose dans la liste des
///   invitations en attente, pas ici.
///
/// **Les deux phrases se composent, elles ne se contredisent pas.** Le résumé
/// compte ce que le serveur a retenu, et n'emploie « envoyées » que si tous
/// les courriels sont réellement sortis ; sinon il ne nomme que ce qui existe
/// — les lignes créées, celles qui étaient déjà en attente —, et la phrase du
/// dessous dit combien n'ont prévenu personne. C'est
/// [AppStrings.invitationsResume] qui tient cette règle — la même phrase sert
/// au compte rendu d'invitation, qui portait le même verbe menteur
/// (ticket 048).
class RapportImportVue extends StatelessWidget {
  const RapportImportVue({
    required this.rapport,
    this.nomsParAdresse = const <String, String>{},
    super.key,
  });

  final RapportInvitations rapport;

  /// Le nom du fichier, par adresse normalisée. L'aperçu l'affichait, le
  /// compte rendu le garde : perdre « Pompier1 Lefèbvre1 » entre deux écrans
  /// du même geste est une régression de vocabulaire.
  final Map<String, String> nomsParAdresse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refus = rapport.refus;
    // Créations et relances ensemble : c'est à cet ensemble que le compte des
    // courriels restés à quai se compare, et l'import peut relancer une
    // adresse qu'un autre administrateur venait d'inviter.
    final retenues = rapport.retenues;
    final nonPartis = rapport.courrielsNonPartis;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          child: Text(
            AppStrings.invitationsResume(
              creees: rapport.creees,
              relancees: rapport.relancees,
              parties: rapport.courrielsPartis,
              echecs: rapport.echecs,
            ),
            style: theme.textTheme.bodyLarge,
          ),
        ),
        if (nonPartis > 0) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.importCourrielsNonPartis(
              nonPartis: nonPartis,
              retenues: retenues,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (refus.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.auDessusTitre),
          Semantics(
            header: true,
            child: Text(
              AppStrings.importEchecsTitre,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.sousTitre),
          const AppDivider(),
          for (final resultat in refus) ...<Widget>[
            _LigneRefus(
              resultat: resultat,
              nom: nomsParAdresse[normaliserEmail(resultat.email)],
            ),
            const AppDivider(),
          ],
        ],
      ],
    );
  }
}

/// Une adresse que le serveur a refusée : qui c'est, et pourquoi.
///
/// La composition est celle de la ligne d'aperçu — marque, titre, adresse,
/// motif — pour que la même personne se reconnaisse d'un écran à l'autre.
class _LigneRefus extends StatelessWidget {
  const _LigneRefus({required this.resultat, this.nom});

  final ResultatInvitation resultat;
  final String? nom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = theme.colorScheme.error;
    final titre = nom ?? resultat.email;
    final sousTitre = nom == null ? null : resultat.email;
    final detail = resultat.detail;

    return Semantics(
      label: titre,
      value: <String>[?sousTitre, AppStrings.resultatEchec, ?detail].join('. '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: AppTouch.icone + AppSpacing.md,
              child: Icon(
                Icons.error_outline,
                size: AppTouch.icone,
                color: encre,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(titre, style: theme.textTheme.titleMedium),
                  if (sousTitre != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      sousTitre,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    AppStrings.resultatEchec,
                    style: theme.textTheme.labelMedium?.copyWith(color: encre),
                  ),
                  if (detail != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      detail,
                      style: theme.textTheme.bodyMedium?.copyWith(color: encre),
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
