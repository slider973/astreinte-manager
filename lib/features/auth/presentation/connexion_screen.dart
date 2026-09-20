import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/email.dart';
import 'controllers/connexion_controller.dart';
import 'widgets/auth_layout.dart';
import 'widgets/champ_auth.dart';

/// Première étape : l'adresse e-mail.
///
/// Pas de mot de passe (`docs/PRD.md § 6.1`). Un code à six chiffres part par
/// courriel, doublé d'un lien à ouvrir. Les comptes naissent d'une invitation :
/// une adresse inconnue reçoit une phrase qui dit quoi faire, pas un silence.
class ConnexionScreen extends ConsumerStatefulWidget {
  const ConnexionScreen({super.key});

  @override
  ConsumerState<ConnexionScreen> createState() => _ConnexionScreenState();
}

class _ConnexionScreenState extends ConsumerState<ConnexionScreen> {
  final TextEditingController _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final email = normaliserEmail(_email.text);
    final envoye = await ref
        .read(connexionControllerProvider.notifier)
        .envoyer(email);

    if (!envoye || !mounted) return;
    if (!context.mounted) return;
    context.goNamed(
      AppRoutes.codeName,
      queryParameters: <String, String>{AppRoutes.parametreEmail: email},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etat = ref.watch(connexionControllerProvider);
    final erreur = etat.erreur;
    final erreurDeChamp = erreur != null && erreur.estErreurDeChamp;

    return AuthLayout(
      titre: AppStrings.connexionTitre,
      banniere: erreur != null && !erreurDeChamp
          ? AppBanner(
              variante: AppBannerVariante.erreur,
              texte: erreur.message,
              libelleAction: AppStrings.actionReessayer,
              onAction: () => unawaited(_envoyer()),
            )
          : null,
      children: <Widget>[
        Text(
          AppStrings.connexionIntro,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ChampAuth(
          libelle: AppStrings.connexionEmailLabel,
          controleur: _email,
          clavier: TextInputType.emailAddress,
          texteInvite: AppStrings.connexionEmailExemple,
          erreur: erreurDeChamp ? erreur.message : null,
          indicesRemplissage: const <String>[AutofillHints.email],
          formateurs: <TextInputFormatter>[
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
          ],
          actif: !etat.envoiEnCours,
          autofocus: true,
          onChanged: (_) =>
              ref.read(connexionControllerProvider.notifier).effacerErreur(),
          onSoumission: (_) => unawaited(_envoyer()),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          libelle: AppStrings.connexionEnvoyer,
          icone: Icons.mail_outline,
          chargement: etat.envoiEnCours,
          onPressed: () => unawaited(_envoyer()),
        ),
      ],
    );
  }
}
