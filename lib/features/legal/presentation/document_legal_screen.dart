import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/bouton_retour.dart';
import '../domain/document_legal.dart';
import '../domain/documents_legaux.dart';

/// **Une page de texte long**, et c'est tout ce qu'elle est.
///
/// Trois raisons d'en faire une route plutôt qu'une feuille ou une modale
/// (`design/034-rgpd-export.md § 5.3`) :
///
/// 1. Une politique de confidentialité doit être lisible **sans compte** — par
///    une mairie, par quelqu'un qui vient de recevoir une invitation. Les deux
///    routes `/legal/…` traversent `redirectionAuth` sans condition, comme le
///    lien d'invitation.
/// 2. Elle doit avoir une **URL** qu'on colle dans un courriel ou dans une
///    délibération.
/// 3. Elle doit rester lisible sur quatre écrans de haut, ce qu'une feuille de
///    bas d'écran ne permet pas.
///
/// L'écran ne contient **aucune chaîne littérale** : tout vient de
/// `DocumentsLegaux`, dont la source de vérité est `docs/RGPD.md`.
class DocumentLegalScreen extends StatelessWidget {
  const DocumentLegalScreen({required this.document, super.key});

  /// La page de confidentialité.
  const DocumentLegalScreen.confidentialite({super.key})
    : document = DocumentsLegaux.confidentialite;

  /// Les mentions légales.
  const DocumentLegalScreen.mentions({super.key})
    : document = DocumentsLegaux.mentions;

  final DocumentLegal document;

  /// L'autre document. Le pied de page y renvoie : les deux se répondent, et
  /// qui lit l'un cherche souvent l'autre.
  bool get _estConfidentialite =>
      document.titre == DocumentsLegaux.confidentialite.titre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return Scaffold(
      appBar: AppBar(
        // Le geste de retour du navigateur marche déjà ; cette sortie existe
        // pour la PWA installée, où il n'y a pas de barre d'adresse — et pour
        // qui arrive ici par une URL collée, auquel cas elle ramène à
        // l'accueil plutôt que de ne rien faire, et **elle le dit**.
        //
        // La flèche faite main de cet écran est devenue `BoutonRetour`
        // (ticket 052) : le centre de notifications avait le même besoin, et
        // deux flèches à repli écrites deux fois divergent toujours.
        leading: const BoutonRetour(),
        leadingWidth: BoutonRetour.largeur(context),
        title: Text(document.titre),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: marge,
            vertical: AppSpacing.lg,
          ),
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                // 720 dp : la mesure de lecture du système de design. Un
                // paragraphe juridique sur 1400 dp de large se perd d'une
                // ligne à l'autre.
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.colonneMax,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        document.titre,
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sousTitre),
                    Text(
                      document.version,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(document.chapeau, style: theme.textTheme.bodyLarge),
                    for (final SectionLegale section in document.sections)
                      _Section(section: section),
                    const SizedBox(height: AppSpacing.xxl),
                    _LienVersLAutre(versConfidentialite: !_estConfidentialite),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un titre, ses paragraphes, et ce qui reste à décider.
class _Section extends StatelessWidget {
  const _Section({required this.section});

  final SectionLegale section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Toujours plus d'espace au-dessus d'un titre qu'en dessous
        // (`DESIGN.md § Espacement`) : 24 / 8.
        const SizedBox(height: AppSpacing.auDessusTitre),
        Semantics(
          header: true,
          child: Text(section.titre, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: AppSpacing.sousTitre),
        for (final String paragraphe in section.paragraphes) ...<Widget>[
          Text(paragraphe, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
        ],
        if (section.aCompleter.isNotEmpty)
          _ACompleter(lignes: section.aCompleter),
      ],
    );
  }
}

/// Ce que le propriétaire du produit doit décider, **visible**.
///
/// Un bloc réglé au cran de surface au-dessus, porté par une icône et un
/// libellé — jamais par la seule couleur (`DESIGN.md § Do's`). Il ne se ferme
/// pas et ne s'atténue pas : une mention légale inventée se croirait, celle-ci
/// se corrige.
class _ACompleter extends StatelessWidget {
  const _ACompleter({required this.lignes});

  final List<String> lignes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: AppRadius.controleRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.edit_note, size: AppTouch.icone, color: encre),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      AppStrings.legalACompleterTitre,
                      style: theme.textTheme.titleSmall?.copyWith(color: encre),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final String ligne in lignes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    ligne,
                    style: theme.textTheme.bodyMedium?.copyWith(color: encre),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le renvoi vers l'autre document, en pied de page.
class _LienVersLAutre extends StatelessWidget {
  const _LienVersLAutre({required this.versConfidentialite});

  final bool versConfidentialite;

  @override
  Widget build(BuildContext context) {
    final libelle = versConfidentialite
        ? AppStrings.legalConfidentialiteLien
        : AppStrings.legalMentionsLien;
    final route = versConfidentialite
        ? AppRoutes.confidentialiteName
        : AppRoutes.mentionsName;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.cible),
        child: TextButton.icon(
          // **Un mouvement latéral, pas un détour dans le détour.** Les deux
          // documents se répondent : passer de l'un à l'autre remplace le
          // sommet de la pile au lieu de l'empiler, donc la flèche ramène
          // toujours à la provenance — l'onglet « Profil », l'écran de
          // connexion — et jamais à l'autre document (ticket 052).
          onPressed: () => context.pushReplacementNamed(route),
          icon: const Icon(Icons.description_outlined, size: AppTouch.icone),
          label: Text(libelle),
        ),
      ),
    );
  }
}
