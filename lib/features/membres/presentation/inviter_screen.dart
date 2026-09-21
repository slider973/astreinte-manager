import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/appartenance.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/barre_actions_basse.dart';
import '../../../core/widgets/champ_texte.dart';
import '../../../core/widgets/primary_button.dart';
import 'controllers/inviter_controller.dart';
import 'widgets/rapport_invitations_vue.dart';

/// Inviter une ou plusieurs adresses dans la caserne.
///
/// Une tâche, donc une route — et non une modale : rien ici ne demande
/// d'interrompre ni de protéger (`DESIGN.md § Don't`). Le retour du navigateur
/// ramène à la liste des membres.
class InviterScreen extends ConsumerStatefulWidget {
  const InviterScreen({super.key});

  @override
  ConsumerState<InviterScreen> createState() => _InviterScreenState();
}

class _InviterScreenState extends ConsumerState<InviterScreen> {
  final TextEditingController _adresses = TextEditingController();

  @override
  void dispose() {
    _adresses.dispose();
    super.dispose();
  }

  InviterController get _controleur =>
      ref.read(inviterControllerProvider.notifier);

  Future<void> _envoyer() => _controleur.envoyer(_adresses.text);

  void _reessayerLesEchecs(List<String> adresses) {
    _adresses.text = adresses.join('\n');
    _controleur.recommencer();
  }

  void _terminer() => context.goNamed(AppRoutes.membresName);

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(inviterControllerProvider);
    final marge = AppWindowClass.of(context).margePage;
    final rapport = etat.rapport;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.inviterTitre)),
      body: Column(
        children: <Widget>[
          if (etat.erreurRequete != null)
            AppBanner(
              variante: AppBannerVariante.erreur,
              texte: etat.erreurRequete!.message,
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                marge,
                AppSpacing.lg,
                marge,
                AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.colonneMax,
                  ),
                  child: rapport == null
                      ? _Formulaire(
                          adresses: _adresses,
                          etat: etat,
                          onChanged: (_) => _controleur.effacerErreur(),
                        )
                      : RapportInvitationsVue(rapport: rapport),
                ),
              ),
            ),
          ),
          BarreActionsBasse(
            child: rapport == null
                ? PrimaryButton(
                    libelle: AppStrings.inviterEnvoyer,
                    icone: Icons.send_outlined,
                    chargement: etat.envoiEnCours,
                    onPressed: () => unawaited(_envoyer()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (!rapport.toutEstPasse) ...<Widget>[
                        PrimaryButton(
                          libelle: AppStrings.inviterReessayerEchecs,
                          variante: PrimaryButtonVariante.secondaire,
                          icone: Icons.refresh,
                          onPressed: () =>
                              _reessayerLesEchecs(rapport.adressesEnEchec),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      PrimaryButton(
                        libelle: AppStrings.inviterTerminer,
                        icone: Icons.arrow_back,
                        onPressed: _terminer,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// La saisie : les adresses, puis le rôle du lot.
class _Formulaire extends ConsumerWidget {
  const _Formulaire({
    required this.adresses,
    required this.etat,
    required this.onChanged,
  });

  final TextEditingController adresses;
  final EtatInviter etat;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          AppStrings.inviterIntro,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ChampTexte(
          libelle: AppStrings.inviterEmailsLabel,
          controleur: adresses,
          clavier: TextInputType.emailAddress,
          texteInvite: AppStrings.inviterEmailsExemple,
          erreur: etat.erreurChamp,
          lignes: 4,
          actif: !etat.envoiEnCours,
          autofocus: true,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(AppStrings.inviterRoleLabel, style: theme.textTheme.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        _ChoixRole(
          role: etat.role,
          actif: !etat.envoiEnCours,
          onChange: (RoleMembre role) =>
              ref.read(inviterControllerProvider.notifier).choisirRole(role),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          AppStrings.inviterPlafondRappel,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Les deux rôles, en choix exclusif : un lot, un rôle.
class _ChoixRole extends StatelessWidget {
  const _ChoixRole({
    required this.role,
    required this.actif,
    required this.onChange,
  });

  final RoleMembre role;
  final bool actif;
  final ValueChanged<RoleMembre> onChange;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.cible),
      child: SegmentedButton<RoleMembre>(
        segments: <ButtonSegment<RoleMembre>>[
          for (final valeur in RoleMembre.values)
            ButtonSegment<RoleMembre>(
              value: valeur,
              label: Text(valeur.libelle),
              icon: Icon(
                valeur == RoleMembre.admin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.person_outline,
              ),
            ),
        ],
        selected: <RoleMembre>{role},
        showSelectedIcon: false,
        onSelectionChanged: actif
            ? (Set<RoleMembre> choix) => onChange(choix.first)
            : null,
      ),
    );
  }
}
