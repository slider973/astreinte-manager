import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../domain/administration_membre.dart';
import '../../domain/membre_caserne.dart';

/// Ouvre les actions d'administration d'un membre et rend celle qui a été
/// choisie, ou `null` si la feuille a été refermée.
///
/// Une feuille de bas d'écran, pas un écran ni une modale de dialogue : c'est
/// le détail d'une ligne qu'on a déjà sous les yeux, sur téléphone
/// (`DESIGN.md § Don't` et § Points de rupture). Le geste retour et le bouton
/// retour du navigateur la referment, parce qu'elle est une route.
Future<ActionMembre?> afficherActionsMembre({
  required BuildContext context,
  required MembreCaserne membre,
  required ContexteAdministration contexte,
}) => showModalBottomSheet<ActionMembre>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) =>
      _FeuilleActionsMembre(membre: membre, contexte: contexte),
);

class _FeuilleActionsMembre extends StatelessWidget {
  const _FeuilleActionsMembre({required this.membre, required this.contexte});

  final MembreCaserne membre;
  final ContexteAdministration contexte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;
    final saisie = membre.derniereSaisie;

    return Semantics(
      namesRoute: true,
      label: AppStrings.membreActions(membre.libelle),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(membre.libelle, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                membre.email,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _Fait(libelle: AppStrings.membreRole, valeur: membre.role.libelle),
              _Fait(
                libelle: AppStrings.membreStatut,
                valeur: membre.estDesactive
                    ? AppStrings.membreStatutDesactive
                    : AppStrings.membreStatutActif,
              ),
              _Fait(
                libelle: AppStrings.membreDispos,
                valeur: saisie == null
                    ? AppStrings.membreAucuneSaisie
                    : formaterDateLongue(saisie),
              ),
              const SizedBox(height: AppSpacing.md),
              const AppDivider(),
              for (final action in actionsPour(membre))
                _LigneAction(
                  action: action,
                  refus: refusPour(
                    action: action,
                    membre: membre,
                    contexte: contexte,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un fait de la ligne, en clair : « Rôle : Admin de caserne ».
class _Fait extends StatelessWidget {
  const _Fait({required this.libelle, required this.valeur});

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              // Espace insécable avant le deux-points : règle française, et
              // un « : » orphelin en début de ligne se remarque.
              text: '$libelle\u00A0: ',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(text: valeur, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

/// Une action de la feuille, ou son refus expliqué.
///
/// Une action interdite **reste affichée**, inerte, avec sa raison en dessous :
/// `DESIGN.md § Do` — « Expliquer pourquoi un contrôle est désactivé, à côté du
/// contrôle ». La faire disparaître laisserait le chef de centre chercher une
/// action qui n'est plus là.
class _LigneAction extends StatelessWidget {
  const _LigneAction({required this.action, required this.refus});

  final ActionMembre action;
  final RefusAdministration? refus;

  static const Map<ActionMembre, IconData> _icones = <ActionMembre, IconData>{
    ActionMembre.renommer: Icons.badge_outlined,
    ActionMembre.promouvoir: Icons.admin_panel_settings_outlined,
    ActionMembre.retrograder: Icons.person_outline,
    ActionMembre.desactiver: Icons.block,
    ActionMembre.reactiver: Icons.check_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final motif = refus;
    final encre = motif == null
        ? theme.colorScheme.onSurface
        : theme.colorScheme.outline;

    return Semantics(
      button: true,
      enabled: motif == null,
      hint: motif?.message,
      child: InkWell(
        onTap: motif == null
            ? () => Navigator.of(context).pop(action)
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.cible),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(_icones[action], size: AppTouch.icone, color: encre),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        action.libelle,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: encre,
                        ),
                      ),
                      if (motif != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          motif.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
