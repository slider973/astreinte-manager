import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/astreinte.dart';
import '../../domain/planning_caserne.dart';

/// Une journée du registre de la caserne : son en-tête de date et ses créneaux.
///
/// **Ce n'est pas une carte** (`DESIGN.md § Cards / Containers`) : c'est un
/// registre — en-tête, filets, marge. Weekend et jour férié se marquent comme
/// dans la grille du mois et comme dans le suivi du ticket 019, fond
/// `surface-dim` et `Icons.star`, pour qu'un pompier n'ait rien à réapprendre
/// d'un écran à l'autre.
///
/// **Rien n'est cliquable ici.** La journée n'ouvre pas de détail : tout ce
/// qu'un détail dirait est déjà à l'écran. Une zone cliquable de la largeur de
/// l'écran qui ne mène nulle part est une fausse affordance, et elle s'ouvre au
/// doigt, avec des gants, pendant un défilement.
class JourneeCaserneBloc extends StatelessWidget {
  const JourneeCaserneBloc({
    required this.journee,
    required this.heures,
    super.key,
  });

  final JourneeCaserne journee;
  final HeuresAffichage heures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ferie = nomJourFerie(journee.date);
    final marque = journee.weekend || ferie != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: marque ? theme.colorScheme.surfaceDim : null,
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
                      fontWeight: journee.weekend ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const AppDivider(),
        for (final creneau in journee.creneaux) ...<Widget>[
          _LigneCreneau(date: journee.date, creneau: creneau, heures: heures),
          const AppDivider(),
        ],
      ],
    );
  }
}

/// Un créneau et ses noms.
class _LigneCreneau extends StatelessWidget {
  const _LigneCreneau({
    required this.date,
    required this.creneau,
    required this.heures,
  });

  final DateTime date;
  final CreneauCaserne creneau;
  final HeuresAffichage heures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripteur = context.statuts.creneau(creneau.creneau);

    // La ligne entière se lit d'une phrase : quatre fragments annoncés l'un
    // après l'autre feraient répéter la date à chaque nom.
    return Semantics(
      container: true,
      label: AppStrings.planningCaserneCreneauSemantique(
        jourEtDate: dateAvecJourSemaine(date),
        creneau: descripteur.libelle,
        heures: AppStrings.astreintesIntervalleDit(
          creneau.creneau == CreneauType.jour
              ? heures.debutJour
              : heures.finJour,
          creneau.creneau == CreneauType.jour
              ? heures.finJour
              : heures.debutJour,
        ),
        personnes: AppStrings.planningCaserneAvec(_dites()),
      ),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                StatusBadge.creneau(creneau.creneau),
                Text(
                  heures.intervalle(creneau.creneau),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (creneau.personne)
              // Un créneau que personne ne couvre est un **trou du planning**,
              // donc une information. Il ne se tait pas, et il n'est pas rouge
              // non plus : ce n'est pas une panne, c'est un fait.
              Text(
                AppStrings.planningCaserneCreneauVide,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              _Noms(creneau: creneau),
          ],
        ),
      ),
    );
  }

  /// Les personnes, telles qu'on les dit : « toi » compris, dans l'ordre de
  /// l'affichage.
  List<String> _dites() => <String>[
    if (creneau.moi) AppStrings.planningCaserneToi.toLowerCase(),
    ...creneau.noms,
    if (creneau.anonymes > 0)
      AppStrings.planningCaserneAutres(creneau.anonymes),
  ];
}

/// Les noms d'un créneau.
///
/// **Du texte qui s'enroule, pas des pastilles.** Une liste de puces de 28 dp
/// pour douze personnes mangerait trois hauteurs d'écran ; un `Wrap` de noms
/// séparés par un point médian se lit d'un coup et tient à ×2 d'échelle de
/// texte (`design/023 § 3`).
class _Noms extends StatelessWidget {
  const _Noms({required this.creneau});

  final CreneauCaserne creneau;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        // **Moi, en tête et marqué.** Trois signaux : l'icône pleine, l'encre
        // d'accent, et la phrase annoncée qui dit « toi ». Jamais la couleur
        // seule. L'encre est `accentTexte` et non `primary` : la journée
        // marquée a un fond `surfaceDim`, où l'indigo vif tombe à 3.96:1.
        if (creneau.moi) ...<Widget>[
          Icon(
            Icons.person,
            size: AppTouch.iconePetite,
            color: context.statuts.accentTexte,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            AppStrings.planningCaserneToi,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.statuts.accentTexte,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (creneau.noms.isNotEmpty || creneau.anonymes > 0)
            Text(
              AppStrings.planningCaserneSeparateurNoms,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
        // Indexé, pas `for in` : deux membres peuvent porter le même nom
        // d'usage, et comparer à `last` mettrait alors un séparateur de trop.
        for (var index = 0; index < creneau.noms.length; index++) ...<Widget>[
          Text(creneau.noms[index], style: theme.textTheme.bodyLarge),
          if (index < creneau.noms.length - 1 || creneau.anonymes > 0)
            Text(
              AppStrings.planningCaserneSeparateurNoms,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
        if (creneau.anonymes > 0)
          Text(
            AppStrings.planningCaserneAutres(creneau.anonymes),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
