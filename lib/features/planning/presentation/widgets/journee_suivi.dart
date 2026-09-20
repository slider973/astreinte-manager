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
  const JourneeSuiviBloc({
    required this.journee,
    super.key,
    this.onReparer,
    this.raisonInactif,
  });

  final JourneeSuivi journee;

  /// Ouvrir le panneau des candidats sur un créneau à réparer. `null` quand il
  /// n'y a rien à ouvrir : planning en brouillon, archivé, ou lecteur non
  /// administrateur.
  final ValueChanged<CreneauSuivi>? onReparer;

  /// Pourquoi l'action est impossible — hors ligne, caserne suspendue.
  /// **Affichée à côté du contrôle**, jamais seulement supposée.
  final String? raisonInactif;

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
          _LigneCreneauSuivi(
            journee: journee,
            creneau: creneau,
            onReparer: onReparer,
            raisonInactif: raisonInactif,
          ),
      ],
    );
  }
}

/// Un créneau et les réponses reçues.
///
/// **La ligne n'est toujours pas cliquable ; un bouton nommé l'est.** La ligne
/// porte déjà trois cibles de lecture — la fraction, les noms, les motifs — et
/// une zone cliquable de la largeur de l'écran s'ouvre par accident au doigt,
/// avec des gants, pendant un défilement. Le bouton n'apparaît que sur les
/// créneaux qui ont quelque chose à réparer : une ligne entièrement acceptée
/// reste inerte, comme au 019.
class _LigneCreneauSuivi extends StatelessWidget {
  const _LigneCreneauSuivi({
    required this.journee,
    required this.creneau,
    this.onReparer,
    this.raisonInactif,
  });

  final JourneeSuivi journee;
  final CreneauSuivi creneau;
  final ValueChanged<CreneauSuivi>? onReparer;
  final String? raisonInactif;

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
        .map((AttributionSuivi a) => _resumeAvecRemplacant(context, a))
        .toList(growable: false);

    final reparable = onReparer != null && creneau.aReparer;

    // **La ligne se résume, le bouton reste à part.** `excludeSemantics` ne
    // couvre que la lecture : mis autour du bouton, il le ferait disparaître du
    // lecteur d'écran, et le seul geste de l'écran serait devenu inatteignable.
    final lecture = Semantics(
      container: true,
      label: AppStrings.suiviLigneSemantique(
        jourEtDate: dateAvecJourSemaine(journee.date),
        creneau: descripteurCreneau.libelle,
        pourvus: creneau.pourvus,
        requis: creneau.creneau.effectifRequis,
        detail: reponses.isEmpty ? AppStrings.suiviPersonne : reponses.join('. '),
      ),
      excludeSemantics: true,
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
                        _LigneReponse(
                          attribution: attribution,
                          remplacant: creneau.remplacantDe(attribution),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: lecture),
          if (reparable) ...<Widget>[
            const SizedBox(width: AppSpacing.entreCibles),
            _BoutonReparer(
              journee: journee,
              creneau: creneau,
              raisonInactif: raisonInactif,
              onReparer: () => onReparer!(creneau),
            ),
          ],
        ],
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

  String _resumeAvecRemplacant(
    BuildContext context,
    AttributionSuivi attribution,
  ) {
    final remplacant = creneau.remplacantDe(attribution);
    final base = _resume(context, attribution);
    return remplacant == null
        ? base
        : '$base, ${AppStrings.suiviRemplacePar(remplacant)}';
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

/// **« Réattribuer »** quand le créneau porte un refus, une annulation ou un
/// remplacement ; **« Pourvoir »** quand il est seulement vide.
///
/// Le libellé nomme l'action, l'étiquette d'accessibilité nomme le créneau :
/// soixante-deux boutons « Réattribuer » à la suite ne disent rien de ce qu'on
/// ouvre.
class _BoutonReparer extends StatelessWidget {
  const _BoutonReparer({
    required this.journee,
    required this.creneau,
    required this.onReparer,
    this.raisonInactif,
  });

  final JourneeSuivi journee;
  final CreneauSuivi creneau;
  final VoidCallback onReparer;
  final String? raisonInactif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refus = creneau.porteUnRefus;
    final jourEtDate = dateAvecJourSemaine(journee.date);
    final libelleCreneau = context.statuts
        .creneau(creneau.creneau.creneau)
        .libelle;

    // **L'étiquette passe par le texte du bouton, pas par un `Semantics`
    // englobant.** Un `Semantics(excludeSemantics: true)` autour d'un
    // `TextButton` efface l'action du nœud : le bouton se lit mais ne
    // s'active plus, et le seul geste de l'écran devient inatteignable au
    // lecteur d'écran. `Text.semanticsLabel` remplace ce qui est *annoncé*
    // sans toucher à ce qui est *affiché*, et le bouton garde son action, son
    // focus et son état désactivé.
    final bouton = TextButton.icon(
      onPressed: raisonInactif == null ? onReparer : null,
      icon: Icon(
        refus ? Icons.published_with_changes : Icons.person_add_alt_1,
        size: AppTouch.icone,
      ),
      label: Text(
        refus ? AppStrings.reattribuerAction : AppStrings.pourvoirAction,
        semanticsLabel: refus
            ? AppStrings.reattribuerSemantique(
                jourEtDate: jourEtDate,
                creneau: libelleCreneau,
              )
            : AppStrings.pourvoirSemantique(
                jourEtDate: jourEtDate,
                creneau: libelleCreneau,
              ),
      ),
    );

    if (raisonInactif == null) return bouton;

    // **Un contrôle désactivé porte sa raison** (`DESIGN.md § Do's`), à côté de
    // lui et non dans une bulle qu'il faut survoler.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        bouton,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            raisonInactif!,
            textAlign: TextAlign.end,
            style: AppTextStyles.mention.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Une réponse : le nom, son état, le motif quand il existe, et — pour une
/// attribution close — **qui a repris la garde**.
class _LigneReponse extends StatelessWidget {
  const _LigneReponse({required this.attribution, this.remplacant});

  final AttributionSuivi attribution;

  /// Le nom de celui qui a couvert ce trou, quand la base a posé le lien.
  /// Sans cette phrase, l'historique montre une sortie sans montrer l'entrée.
  final String? remplacant;

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
          if (remplacant != null)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                AppStrings.suiviRemplacePar(remplacant!),
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
