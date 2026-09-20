import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/hachures.dart';
import '../../domain/suivi_planning.dart';
import 'ligne_creneaux.dart';

/// Une journée du suivi : son en-tête et ses créneaux.
///
/// Weekend et jour férié se marquent comme dans la grille du mois — fond
/// `surface-dim`, nom en gras, `Icons.star` — pour qu'un chef n'ait rien à
/// réapprendre d'un écran à l'autre.
class JourneeSuiviBloc extends StatelessWidget {
  const JourneeSuiviBloc({required this.journee, super.key});

  final JourneeSuivi journee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ferie = nomJourFerie(journee.date);
    final weekend =
        journee.date.weekday == DateTime.saturday ||
        journee.date.weekday == DateTime.sunday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: weekend || ferie != null
              ? theme.colorScheme.surfaceDim
              : null,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              if (ferie != null) ...<Widget>[
                Icon(
                  Icons.star,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                  semanticLabel: ferie,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    dateAvecJourSemaine(journee.date),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: weekend ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const AppDivider(),
        for (final creneau in journee.creneaux)
          _LigneCreneauSuivi(journee: journee, creneau: creneau),
      ],
    );
  }
}

/// Un créneau et les réponses reçues.
///
/// **La ligne n'est pas cliquable.** Il n'y a rien à ouvrir : la réattribution
/// est le ticket 020, et un élément qui a l'air cliquable sans rien faire est
/// pire qu'un élément inerte.
class _LigneCreneauSuivi extends StatelessWidget {
  const _LigneCreneauSuivi({required this.journee, required this.creneau});

  final JourneeSuivi journee;
  final CreneauSuivi creneau;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripteurCreneau = context.statuts.creneau(creneau.creneau.creneau);
    final couverture = descripteurCouverture(
      context,
      creneau.couverture,
      personne: creneau.pourvus == 0 && creneau.nonPourvu,
    );

    final reponses = creneau.attributions
        .map((AttributionSuivi a) => _resume(context, a))
        .toList(growable: false);

    return Semantics(
      container: true,
      label: AppStrings.suiviLigneSemantique(
        jourEtDate: dateAvecJourSemaine(journee.date),
        creneau: descripteurCreneau.libelle,
        pourvus: creneau.pourvus,
        requis: creneau.creneau.effectifRequis,
        detail: reponses.isEmpty ? AppStrings.suiviPersonne : reponses.join('. '),
      ),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              descripteurCreneau.icone,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 56,
              child: Text(
                descripteurCreneau.libelle,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            // La fraction, exactement celle de la ligne des créneaux du 017 :
            // même grammaire, même signification, rien à réapprendre.
            _Fraction(couverture: couverture, creneau: creneau),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: creneau.attributions.isEmpty
                  ? const _Personne()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final attribution in creneau.attributions)
                          _LigneReponse(attribution: attribution),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _resume(BuildContext context, AttributionSuivi attribution) {
    final etat = context.statuts.attribution(attribution.etat).libelle;
    final motif = attribution.aUnMotif
        ? ' ${AppStrings.suiviMotifRefus(attribution.motifRefus!)}'
        : '';
    return '${attribution.nom} — ${etat.toLowerCase()}$motif';
  }
}

class _Fraction extends StatelessWidget {
  const _Fraction({required this.couverture, required this.creneau});

  final StatusDescriptor couverture;
  final CreneauSuivi creneau;

  @override
  Widget build(BuildContext context) {
    final texte = Text(
      AppStrings.planningFraction(
        creneau.pourvus,
        creneau.creneau.effectifRequis,
      ),
      style: AppTextStyles.nombrePetit.copyWith(color: couverture.encre),
    );

    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: couverture.fond,
        borderRadius: AppRadius.caseRegistreRadius,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (couverture.hachure)
            Positioned.fill(
              child: Hachures(
                encre: couverture.encre,
                borderRadius: AppRadius.caseRegistreRadius,
              ),
            ),
          texte,
        ],
      ),
    );
  }
}

/// Le créneau que personne ne couvre. **Hachuré** : troisième emploi des
/// hachures, déjà acté au ticket 017, et toujours la même sémantique — le vide.
class _Personne extends StatelessWidget {
  const _Personne();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attente = context.statuts.attribution(AttributionEtat.propose);

    return Row(
      children: <Widget>[
        Icon(Icons.person_off_outlined, size: 16, color: attente.encre),
        const SizedBox(width: AppSpacing.xs),
        Text(
          AppStrings.suiviPersonne,
          style: theme.textTheme.bodyMedium?.copyWith(color: attente.encre),
        ),
      ],
    );
  }
}

/// Une réponse : le nom, son état, et le motif quand il existe.
class _LigneReponse extends StatelessWidget {
  const _LigneReponse({required this.attribution});

  final AttributionSuivi attribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripteur = context.statuts.attribution(attribution.etat);
    final instant = attribution.repondueLe ?? attribution.proposeeLe;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(descripteur.icone, size: 16, color: descripteur.encre),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  attribution.nom,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    decoration: descripteur.barre
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  instant == null
                      ? descripteur.libelle.toLowerCase()
                      : AppStrings.suiviEtatDepuis(
                          descripteur.libelle.toLowerCase(),
                          formaterInstantRelatif(instant),
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // **Le motif de refus est l'information la plus utile de l'écran** :
          // il dit au chef s'il doit chercher quelqu'un d'autre ou attendre.
          if (attribution.aUnMotif)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                AppStrings.suiviMotifRefus(attribution.motifRefus!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
