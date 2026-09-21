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
import '../../profil/domain/profil.dart';
import '../../profil/domain/profil_providers.dart';
import '../domain/parcours_accueil.dart';

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

  /// Posé une seule fois : sans ce repère, une relecture du profil écraserait
  /// une correction en cours de frappe.
  bool _prerempli = false;

  /// Pré-remplit les deux champs avec ce que la base sait déjà du nom.
  ///
  /// **C'est ici qu'atterrit le nom saisi par l'administrateur à l'import**
  /// (ticket 047) : `accept_invitation` l'a recopié dans le profil au moment de
  /// l'acceptation, parce qu'il était vide. Rien ne le signale à l'écran —
  /// « voici ce que ton chef de centre a écrit de toi » n'apporte rien et
  /// invite à discuter. Le pompier lit son nom, le corrige s'il le faut, et
  /// **ce qu'il valide gagne** : c'est la décision du § 7 du brief.
  void _preremplir(Profil profil) {
    if (_prerempli) return;
    if (profil.prenom.isEmpty && profil.nom.isEmpty) return;
    _prerempli = true;
    _prenom.text = profil.prenom;
    _nom.text = profil.nom;
  }

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

    // Une lecture qui échoue ne bloque rien : les champs restent vides, et la
    // personne saisit son nom comme avant le ticket 047.
    final profil = ref.watch(monProfilProvider).value;
    if (profil != null) _preremplir(profil);

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
