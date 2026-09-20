import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/champ_texte.dart';
import '../../../core/widgets/ecran_simple.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/parcours_accueil.dart';
import '../domain/profil_providers.dart';

/// Le complément de profil, juste après l'entrée dans la caserne.
///
/// Trois champs, dont un facultatif : c'est le minimum pour qu'un planning
/// nomme quelqu'un. Tout le reste du profil attend le ticket 007.
class ProfilAccueilScreen extends ConsumerStatefulWidget {
  const ProfilAccueilScreen({super.key});

  @override
  ConsumerState<ProfilAccueilScreen> createState() =>
      _ProfilAccueilScreenState();
}

class _ProfilAccueilScreenState extends ConsumerState<ProfilAccueilScreen> {
  final TextEditingController _prenom = TextEditingController();
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _telephone = TextEditingController();

  @override
  void dispose() {
    _prenom.dispose();
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final enregistre = await ref
        .read(profilControllerProvider.notifier)
        .enregistrer(
          prenom: _prenom.text,
          nom: _nom.text,
          telephone: _telephone.text,
        );
    if (!enregistre || !mounted) return;

    // L'étape suivante est choisie avant de naviguer : un guide déjà vu ne
    // s'ouvre pas pour se refermer aussitôt.
    final suite = await ref.read(parcoursAccueilProvider).apresLeProfil();
    if (!mounted || !context.mounted) return;
    context.goNamed(suite);
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(profilControllerProvider);
    final effacer = ref.read(profilControllerProvider.notifier).effacerErreurs;

    return EcranSimple(
      titre: AppStrings.profilTitre,
      banniere: etat.erreurGenerale == null
          ? null
          : AppBanner(
              variante: AppBannerVariante.erreur,
              texte: etat.erreurGenerale!,
              libelleAction: AppStrings.actionReessayer,
              onAction: () => unawaited(_enregistrer()),
            ),
      children: <Widget>[
        Text(
          AppStrings.profilIntro,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ChampTexte(
          libelle: AppStrings.profilPrenomLabel,
          controleur: _prenom,
          clavier: TextInputType.name,
          erreur: etat.erreurPrenom,
          indicesRemplissage: const <String>[AutofillHints.givenName],
          actif: !etat.enregistrementEnCours,
          autofocus: true,
          onChanged: (_) => effacer(),
        ),
        const SizedBox(height: AppSpacing.lg),
        ChampTexte(
          libelle: AppStrings.profilNomLabel,
          controleur: _nom,
          clavier: TextInputType.name,
          erreur: etat.erreurNom,
          indicesRemplissage: const <String>[AutofillHints.familyName],
          actif: !etat.enregistrementEnCours,
          onChanged: (_) => effacer(),
        ),
        const SizedBox(height: AppSpacing.lg),
        ChampTexte(
          libelle: AppStrings.profilTelephoneLabel,
          controleur: _telephone,
          clavier: TextInputType.phone,
          texteInvite: AppStrings.profilTelephoneExemple,
          indicesRemplissage: const <String>[AutofillHints.telephoneNumber],
          actif: !etat.enregistrementEnCours,
          onChanged: (_) => effacer(),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          libelle: AppStrings.profilEnregistrer,
          icone: Icons.check,
          chargement: etat.enregistrementEnCours,
          onPressed: () => unawaited(_enregistrer()),
        ),
      ],
    );
  }
}
