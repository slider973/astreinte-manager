import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/calendrier_providers.dart';
import 'bloc_regle.dart';

/// **« Ajouter à mon calendrier »** — l'adresse d'abonnement, comment s'en
/// servir, et comment la révoquer.
///
/// Posé après le réglage des notifications : les deux répondent à la même
/// famille de question — comment cette application entre dans ma journée
/// (`design/028-export-ics.md § 5`).
///
/// **L'adresse est affichée en entier**, et c'est un choix. Elle vaut mot de
/// passe, mais son seul usage est d'être copiée : la masquer ajouterait une
/// friction devant la seule chose qu'on est venu chercher, devant un écran de
/// profil qu'on regarde seul. L'avertissement est écrit juste en dessous, et le
/// bouton de révocation est dans le même bloc.
class BlocCalendrier extends ConsumerWidget {
  const BlocCalendrier({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final etat = ref.watch(calendrierControllerProvider);

    return BlocRegle(
      titre: AppStrings.calendrierTitre,
      enfants: <Widget>[
        Text(
          AppStrings.calendrierIntro,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (etat.adresse case final AdresseAbonnement adresse) ...<Widget>[
          _Adresse(url: adresse.url),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            libelle: AppStrings.calendrierCopier,
            variante: PrimaryButtonVariante.secondaire,
            icone: Icons.content_copy_outlined,
            onPressed: () => unawaited(
              ref.read(calendrierControllerProvider.notifier).copier(),
            ),
          ),
        ] else
          _EnAttente(enCours: etat.enCours),
        if (_phrase(etat) case final _Phrase phrase) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _LigneEtat(texte: phrase.texte, enErreur: phrase.enErreur),
        ],
        if (etat.echec != null && !etat.enCours) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            libelle: AppStrings.calendrierRelire,
            variante: PrimaryButtonVariante.secondaire,
            icone: Icons.refresh,
            onPressed: () => unawaited(
              ref.read(calendrierControllerProvider.notifier).charger(),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const _Avertissement(texte: AppStrings.calendrierAvertissement),
        const SizedBox(height: AppSpacing.md),
        const _ModeEmploi(),
        const SizedBox(height: AppSpacing.lg),
        const AppDivider(),
        const SizedBox(height: AppSpacing.lg),
        // Même grammaire que « Supprimer mon compte », parce que c'est la même
        // catégorie : ça casse quelque chose qui marchait.
        PrimaryButton(
          libelle: AppStrings.calendrierRegenerer,
          variante: PrimaryButtonVariante.danger,
          icone: Icons.autorenew,
          chargement: etat.enCours && etat.prete,
          onPressed: () => unawaited(_regenerer(context, ref)),
        ),
      ],
    );
  }

  Future<void> _regenerer(BuildContext context, WidgetRef ref) async {
    final confirme = await demanderRegenerationLien(context);
    if (!confirme) return;
    await ref.read(calendrierControllerProvider.notifier).regenerer();
  }

  /// Ce qu'il y a à dire sous l'adresse, ou `null` quand il n'y a rien à dire.
  ///
  /// Une seule ligne à la fois, et dans cet ordre : ce qui vient d'échouer, ce
  /// qui vient de se passer, puis rien. Empiler « lien copié » et « nouveau
  /// lien en place » ferait lire deux fois ce qui s'est passé une fois.
  static _Phrase? _phrase(EtatCalendrier etat) {
    if (etat.message case final String erreur) {
      return _Phrase(erreur, enErreur: true);
    }
    if (etat.regenere) {
      return const _Phrase(AppStrings.calendrierRegenereFait);
    }
    if (etat.copie) return const _Phrase(AppStrings.calendrierCopie);
    return null;
  }
}

/// Une phrase d'état et sa gravité.
@immutable
class _Phrase {
  const _Phrase(this.texte, {this.enErreur = false});

  final String texte;
  final bool enErreur;
}

/// L'adresse, en entier, sélectionnable.
///
/// **Chasse fixe**, et pas par coquetterie technique : 48 caractères
/// hexadécimaux se relisent lettre à lettre quand la copie a échoué, et c'est
/// exactement le cas où confondre `0` et `O` coûte un abonnement qui ne marche
/// pas. Même raison que les compteurs du registre (`DESIGN.md § Typography`).
class _Adresse extends StatelessWidget {
  const _Adresse({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: AppStrings.calendrierAdresseLabel,
      value: url,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: AppRadius.controleRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SelectableText(
            url,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: AppFonts.nombre,
              fontFamilyFallback: AppFonts.replis,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Le bloc pendant la première lecture, ou après un échec.
///
/// Pas de squelette animé : une ligne d'adresse, une lecture brève, et un
/// balayage de 300 ms attirerait l'œil sur une attente au lieu de la faire
/// oublier (même décision qu'au bloc d'identité, ticket 007).
class _EnAttente extends StatelessWidget {
  const _EnAttente({required this.enCours});

  final bool enCours;

  @override
  Widget build(BuildContext context) {
    if (!enCours) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final encre = theme.colorScheme.onSurfaceVariant;

    return Semantics(
      liveRegion: true,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: AppSpacing.lg,
            height: AppSpacing.lg,
            child: CircularProgressIndicator(strokeWidth: 2, color: encre),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AppStrings.actionChargement,
              style: theme.textTheme.bodyMedium?.copyWith(color: encre),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le résultat, **sur place**, sous le bouton — jamais dans un message passager
/// qui part avant qu'on ait fini de le lire. Porté par icône + libellé, la
/// couleur en quatrième (`DESIGN.md § Do's`).
class _LigneEtat extends StatelessWidget {
  const _LigneEtat({required this.texte, required this.enErreur});

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

/// « Ce lien vaut mot de passe ». Icône + texte, sans fond coloré : ce n'est pas
/// un état de l'écran, c'est une consigne permanente — une bannière lui
/// donnerait l'urgence d'un incident.
class _Avertissement extends StatelessWidget {
  const _Avertissement({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.lock_outline,
          size: AppTouch.icone,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Les trois modes d'emploi, repliés.
///
/// Fermé par défaut : trois listes dépliées feraient un mur au milieu d'un
/// écran de réglages, et deux personnes sur trois n'en liront qu'une seule
/// (`design/028-export-ics.md § 5`).
class _ModeEmploi extends StatelessWidget {
  const _ModeEmploi();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Theme(
      // Le filet par défaut d'un `ExpansionTile` ajouterait un second cadre
      // **dans** le bloc réglé : les blocs ne s'imbriquent jamais
      // (`DESIGN.md § Cards`).
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          AppStrings.calendrierModeEmploi,
          style: theme.textTheme.titleSmall,
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          _Recette(
            titre: AppStrings.calendrierGoogleTitre,
            texte: AppStrings.calendrierGoogle,
          ),
          SizedBox(height: AppSpacing.md),
          _Recette(
            titre: AppStrings.calendrierAppleTitre,
            texte: AppStrings.calendrierApple,
          ),
          SizedBox(height: AppSpacing.md),
          _Recette(
            titre: AppStrings.calendrierOutlookTitre,
            texte: AppStrings.calendrierOutlook,
          ),
          SizedBox(height: AppSpacing.lg),
          _Delai(),
        ],
      ),
    );
  }
}

class _Recette extends StatelessWidget {
  const _Recette({required this.titre, required this.texte});

  final String titre;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(titre, style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          texte,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Le délai de rafraîchissement : il n'est pas à nous, chaque agenda décide.
/// Le dire ici évite la question « pourquoi ma garde d'hier n'est pas là ».
class _Delai extends StatelessWidget {
  const _Delai();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.schedule,
          size: AppTouch.icone,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            AppStrings.calendrierDelai,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// La confirmation avant de couper une adresse qui marche.
///
/// Un dialogue, pas une feuille : la question est courte, binaire, et elle
/// interrompt à bon droit — c'est exactement le cas qu'un modal sert
/// (`reference/craft-floor.md`). Rend vrai si la personne confirme.
Future<bool> demanderRegenerationLien(BuildContext context) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text(AppStrings.calendrierRegenereTitre),
        content: Text(
          AppStrings.calendrierRegenereCorps,
          style: theme.textTheme.bodyMedium,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.calendrierRegenereAnnuler),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text(AppStrings.calendrierRegenereConfirmer),
          ),
        ],
      );
    },
  );
  return confirme ?? false;
}
