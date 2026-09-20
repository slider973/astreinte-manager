import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/champ_texte.dart';
import '../../../core/widgets/ecran_simple.dart';
import '../../../core/widgets/primary_button.dart';
import 'controllers/code_controller.dart';

/// Seconde étape : le code à six chiffres reçu par courriel.
///
/// Un seul champ, et non six cases : le collage reste possible et le lecteur
/// d'écran annonce une seule valeur (WCAG 2.2, « Accessible Authentication »).
/// Le lien du courriel est rappelé comme équivalent, pour ne pas imposer la
/// recopie manuelle.
///
/// La réussite ne navigue pas : la session ouverte change l'état
/// d'authentification, et le routeur emmène où il faut.
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({required this.email, super.key});

  /// L'adresse à qui le code a été envoyé, portée par l'URL : le bouton retour
  /// du navigateur ramène à l'étape précédente sans rien perdre.
  final String email;

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  CodeController get _controleur => ref.read(codeControllerProvider.notifier);

  Future<void> _verifier() =>
      _controleur.verifier(email: widget.email, code: _code.text);

  void _saisie(String valeur) {
    _controleur.effacerErreur();
    // Le code complet part tout seul : six chiffres tapés avec des gants, ce
    // n'est pas le moment de chercher un bouton.
    if (valeur.length == longueurCode) unawaited(_verifier());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etat = ref.watch(codeControllerProvider);
    final erreur = etat.erreur;
    final erreurDeChamp = erreur != null && erreur.estErreurDeChamp;

    return EcranSimple(
      titre: AppStrings.codeTitre,
      banniere: erreur != null && !erreurDeChamp
          ? AppBanner(variante: AppBannerVariante.erreur, texte: erreur.message)
          : null,
      children: <Widget>[
        Text(
          AppStrings.codeIntro(widget.email),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ChampTexte(
          libelle: AppStrings.codeLabel,
          controleur: _code,
          clavier: TextInputType.number,
          erreur: erreurDeChamp ? erreur.message : null,
          indicesRemplissage: const <String>[AutofillHints.oneTimeCode],
          longueurMax: longueurCode,
          formateurs: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: theme.textTheme.displaySmall?.copyWith(letterSpacing: 8),
          alignement: TextAlign.center,
          actif: !etat.verificationEnCours,
          autofocus: true,
          onChanged: _saisie,
          onSoumission: (_) => unawaited(_verifier()),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          libelle: AppStrings.codeValider,
          chargement: etat.verificationEnCours,
          onPressed: () => unawaited(_verifier()),
        ),
        const SizedBox(height: AppSpacing.xl),
        _BlocRenvoi(email: widget.email, etat: etat),
        const SizedBox(height: AppSpacing.lg),
        Text(
          AppStrings.codeLienAlternative,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => context.goNamed(AppRoutes.connexionName),
            icon: const Icon(Icons.arrow_back),
            label: const Text(AppStrings.codeChangerEmail),
          ),
        ),
      ],
    );
  }
}

/// Le renvoi de code et son compte à rebours.
///
/// Le bouton désactivé porte sa raison (`DESIGN.md § Buttons`) : « Nouveau
/// code possible dans 42 s », et non un gris muet.
class _BlocRenvoi extends ConsumerWidget {
  const _BlocRenvoi({required this.email, required this.etat});

  final String email;
  final EtatCode etat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PrimaryButton(
          libelle: AppStrings.codeRenvoyer,
          variante: PrimaryButtonVariante.secondaire,
          icone: Icons.refresh,
          chargement: etat.renvoiEnCours,
          // Pendant l'envoi, c'est l'indicateur qui parle : répéter « dans
          // 0 s » sous un bouton qui tourne n'apprend rien.
          raisonDesactivation: etat.renvoiEnCours
              ? null
              : AppStrings.codeRenvoiDans(etat.secondesAvantRenvoi),
          onPressed: etat.renvoiPossible
              ? () => unawaited(
                  ref.read(codeControllerProvider.notifier).renvoyer(email),
                )
              : null,
        ),
        if (etat.renvoye) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.mark_email_read_outlined,
                  size: AppSpacing.lg,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    AppStrings.codeRenvoye,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
