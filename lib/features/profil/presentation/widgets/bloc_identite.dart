import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/profil.dart';
import '../../domain/profil_providers.dart';
import 'bloc_regle.dart';

/// Prénom, nom, téléphone facultatif, et l'adresse de connexion en lecture.
///
/// **La même écriture qu'à l'accueil du ticket 006** : `ProfilController`, ses
/// deux messages d'erreur et son dépôt. L'accueil remplit, le profil corrige ;
/// deux contrôleurs auraient divergé sur la première règle de validation.
class BlocIdentite extends ConsumerStatefulWidget {
  const BlocIdentite({required this.profil, super.key});

  final Profil profil;

  @override
  ConsumerState<BlocIdentite> createState() => _BlocIdentiteState();
}

class _BlocIdentiteState extends ConsumerState<BlocIdentite> {
  late final TextEditingController _prenom = TextEditingController(
    text: widget.profil.prenom,
  );
  late final TextEditingController _nom = TextEditingController(
    text: widget.profil.nom,
  );
  late final TextEditingController _telephone = TextEditingController(
    text: widget.profil.telephone ?? '',
  );

  /// Affiché sous le bouton après un enregistrement réussi, dans une région
  /// annoncée. Retombe dès qu'on retouche un champ : une confirmation qui
  /// survit à une nouvelle saisie ne confirme plus rien.
  bool _enregistre = false;

  @override
  void didUpdateWidget(BlocIdentite ancien) {
    super.didUpdateWidget(ancien);
    // Le profil relu après un enregistrement remplace ce qui est affiché **si
    // la personne n'a pas recommencé à écrire entre-temps**. Sans cette garde,
    // une relecture lente écraserait une frappe en cours.
    if (widget.profil == ancien.profil) return;
    _remplacerSiIntact(_prenom, ancien.profil.prenom, widget.profil.prenom);
    _remplacerSiIntact(_nom, ancien.profil.nom, widget.profil.nom);
    _remplacerSiIntact(
      _telephone,
      ancien.profil.telephone ?? '',
      widget.profil.telephone ?? '',
    );
  }

  static void _remplacerSiIntact(
    TextEditingController controleur,
    String avant,
    String apres,
  ) {
    if (controleur.text == avant) controleur.text = apres;
  }

  @override
  void dispose() {
    _prenom.dispose();
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final ok = await ref
        .read(profilControllerProvider.notifier)
        .enregistrer(
          prenom: _prenom.text,
          nom: _nom.text,
          telephone: _telephone.text,
        );
    if (!mounted) return;
    setState(() => _enregistre = ok);
  }

  void _modifie() {
    ref.read(profilControllerProvider.notifier).effacerErreurs();
    if (_enregistre) setState(() => _enregistre = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etat = ref.watch(profilControllerProvider);
    final actif = !etat.enregistrementEnCours;

    return BlocRegle(
      titre: AppStrings.profilIdentiteTitre,
      enfants: <Widget>[
        Text(
          AppStrings.profilIdentiteAide,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ChampTexte(
          libelle: AppStrings.profilPrenomLabel,
          controleur: _prenom,
          clavier: TextInputType.name,
          erreur: etat.erreurPrenom,
          indicesRemplissage: const <String>[AutofillHints.givenName],
          actif: actif,
          onChanged: (_) => _modifie(),
        ),
        const SizedBox(height: AppSpacing.lg),
        ChampTexte(
          libelle: AppStrings.profilNomLabel,
          controleur: _nom,
          clavier: TextInputType.name,
          erreur: etat.erreurNom,
          indicesRemplissage: const <String>[AutofillHints.familyName],
          actif: actif,
          onChanged: (_) => _modifie(),
        ),
        const SizedBox(height: AppSpacing.lg),
        ChampTexte(
          libelle: AppStrings.profilTelephoneLabel,
          controleur: _telephone,
          clavier: TextInputType.phone,
          texteInvite: AppStrings.profilTelephoneExemple,
          indicesRemplissage: const <String>[AutofillHints.telephoneNumber],
          actif: actif,
          onChanged: (_) => _modifie(),
        ),
        const SizedBox(height: AppSpacing.lg),
        // L'adresse est un fait, pas un champ : la changer veut dire changer
        // d'identifiant de connexion, ce qui n'est pas corriger une faute de
        // frappe dans un nom.
        LigneLecture(
          libelle: AppStrings.profilEmailLabel,
          valeur: widget.profil.email,
          raison: AppStrings.profilEmailRaison,
          icone: Icons.alternate_email,
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          libelle: AppStrings.profilEnregistrerIdentite,
          icone: Icons.check,
          chargement: etat.enregistrementEnCours,
          onPressed: () => unawaited(_enregistrer()),
        ),
        if (_enregistre || etat.erreurGenerale != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _LigneResultat(
            texte: etat.erreurGenerale ?? AppStrings.profilEnregistre,
            enErreur: etat.erreurGenerale != null,
          ),
        ],
      ],
    );
  }
}

/// Le résultat du geste, annoncé sans déplacer le focus — même forme que la
/// ligne d'état de la déconnexion (`core/session/deconnexion.dart`).
class _LigneResultat extends StatelessWidget {
  const _LigneResultat({required this.texte, required this.enErreur});

  final String texte;
  final bool enErreur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = enErreur
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            enErreur ? Icons.error_outline : Icons.check_circle_outline,
            size: AppTouch.icone,
            color: encre,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(color: encre),
            ),
          ),
        ],
      ),
    );
  }
}
