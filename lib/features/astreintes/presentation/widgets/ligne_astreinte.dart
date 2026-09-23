import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../domain/astreinte.dart';

/// Une astreinte acceptée, et rien d'autre.
///
/// **Une ligne de liste du monde du pompier** depuis le chantier 064c
/// (`design/064 § 2` et `§ 3.3`) : une carte `surface` à filet, un carré de 40
/// à rayon 12 portant l'initiale du créneau, la date en `titleMedium`, le
/// créneau et ses heures en `bodyMedium`. La marge de registre du ticket 027 —
/// numéro du jour, nom du jour, fond de week-end — s'en va avec le monde
/// qu'elle servait : la date est écrite en toutes lettres à côté, « samedi »
/// et « dimanche » compris.
///
/// La ligne entière est actionnable — différence assumée avec la ligne de
/// proposition du ticket 021, qui est inerte parce qu'elle porte deux boutons
/// irréversibles. Ici l'ouverture ne commet rien, et se tromper coûte un geste
/// retour (`design/027 § 7.3`).
class LigneDAstreinte extends StatelessWidget {
  const LigneDAstreinte({
    required this.astreinte,
    required this.heures,
    required this.onOuvrir,
    super.key,
    this.passee = false,
  });

  /// Côté du carré d'initiale. La même valeur qu'à la ligne de proposition de
  /// l'accueil : une seule ligne de liste dans tout le monde du pompier.
  static const double carre = 40;

  final Astreinte astreinte;
  final HeuresAffichage heures;
  final VoidCallback onOuvrir;

  /// Les passées sont atténuées : ce sont des faits, pas des rendez-vous.
  final bool passee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final creneau = context.statuts.creneau(astreinte.creneau);
    final jourEtDate = dateAvecJourSemaine(astreinte.jour);
    final soutien =
        '${creneau.libelle} · ${heures.intervalle(astreinte.creneau)}';
    final ferie = nomJourFerie(astreinte.jour);

    return Semantics(
      button: true,
      label: AppStrings.astreintesLigneSemantique(
        jourEtDate: jourEtDate,
        creneau: creneau.libelle,
        heures: AppStrings.astreintesIntervalleDit(
          astreinte.creneau == CreneauType.jour
              ? heures.debutJour
              : heures.finJour,
          astreinte.creneau == CreneauType.jour
              ? heures.finJour
              : heures.debutJour,
        ),
      ),
      excludeSemantics: true,
      child: CarteDouce(
        onTap: onOuvrir,
        hauteurMin: AppTouch.cible,
        child: Row(
          children: <Widget>[
            _CarreCreneau(
              initiale: creneau.libelle.characters.first.toUpperCase(),
              icone: creneau.icone,
              attenue: passee,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (ferie != null) ...<Widget>[
                        // Le jour férié était un fond de marge sans nom : il
                        // devient l'étoile de `DayCell`, qui, elle, se dit.
                        Icon(
                          Icons.star,
                          size: AppTouch.iconePetite,
                          color: scheme.onSurfaceVariant,
                          semanticLabel: ferie,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Flexible(
                        child: Text(
                          jourEtDate,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: passee ? scheme.onSurfaceVariant : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    soutien,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right,
              size: AppTouch.icone,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Le carré d'initiale : « J » ou « N », et l'icône du créneau à côté.
///
/// L'initiale seule serait une lettre sans système — « J » et « N » ne se
/// devinent pas. L'icône du créneau la double, et la phrase annoncée de la
/// ligne dit « jour » ou « nuit » en toutes lettres.
class _CarreCreneau extends StatelessWidget {
  const _CarreCreneau({
    required this.initiale,
    required this.icone,
    required this.attenue,
  });

  final String initiale;
  final IconData icone;

  /// Une astreinte passée : le carré descend d'un cran de surface plutôt que
  /// de garder l'indigo, réservé à ce qui vient.
  final bool attenue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final encre = attenue ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;

    return Container(
      width: LigneDAstreinte.carre,
      height: LigneDAstreinte.carre,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: attenue ? scheme.surfaceContainerHigh : scheme.primaryContainer,
        borderRadius: AppRadius.feuilleCarreeRadius,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icone, size: AppTouch.iconePetite, color: encre),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              initiale,
              style: theme.textTheme.labelLarge?.copyWith(color: encre),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// Le repli des astreintes passées : une ligne, un compte, un chevron.
///
/// **Replié par défaut, toujours** : l'écran s'ouvre sur l'avenir. Le compte
/// est dans le libellé — un repli qui ne dit pas ce qu'il cache n'apprend rien,
/// et ce nombre est lui-même une information.
class ReplisPasseesLigne extends StatelessWidget {
  const ReplisPasseesLigne({
    required this.compte,
    required this.ouvert,
    required this.onBasculer,
    super.key,
  });

  final int compte;
  final bool ouvert;
  final VoidCallback onBasculer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      expanded: ouvert,
      hint: ouvert
          ? AppStrings.astreintesPasseesMasquer
          : AppStrings.astreintesPasseesAfficher,
      child: CarteDouce(
        onTap: onBasculer,
        hauteurMin: AppTouch.cible,
        child: Row(
          children: <Widget>[
            Icon(
              ouvert ? Icons.expand_less : Icons.expand_more,
              size: AppTouch.icone,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                AppStrings.astreintesPassees(compte),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
