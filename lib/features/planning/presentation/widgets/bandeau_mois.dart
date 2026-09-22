import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/count_stat.dart';
import '../../domain/resume_mois.dart';
import 'barre_repartition.dart';

/// **Le bandeau du mois** : où en est le planning, avant tout défilement.
///
/// Trois nombres et une barre, calculés sur ce que l'écran a déjà en mémoire
/// ([ResumeMois]). Il répond à la première question du chef quand il ouvre
/// l'écran — « combien me reste-t-il ? » — que soixante-deux colonnes de
/// cases ne répondent pas d'un coup d'œil.
///
/// Sur téléphone, il se réduit à sa ligne de chiffres : la barre et sa
/// légende coûteraient 76 points de hauteur pour redire ce que les trois
/// nombres disent déjà, sur l'écran qui en a le moins.
class BandeauMois extends StatelessWidget {
  const BandeauMois({
    required this.resume,
    super.key,
    this.compact = false,
  });

  /// La hauteur du bloc entier, **mesurée** : cadre, ligne de chiffres, barre
  /// et légende sur une ligne. Elle ne dépend pas de la largeur — la légende
  /// tient sur une ligne jusqu'à 760 points de large, c'est-à-dire partout où
  /// la matrice existe.
  ///
  /// C'est la grandeur avec laquelle l'écran décide s'il a la place du bloc
  /// (`MatriceScreen.placeBandeauComplet`). Un test la tient à jour : si le
  /// bloc grossit, la constante le dit au lieu de mentir.
  static const double hauteurComplet = 134;

  /// La même, réduite à sa ligne de trois chiffres, sur une fenêtre où les
  /// libellés ne se replient pas.
  static const double hauteurReduit = 58;

  final ResumeMois resume;

  /// Vrai en `compact` : une seule ligne de trois chiffres, sans barre.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chiffres = _Chiffres(resume: resume);

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: chiffres,
      );
    }

    final marge = AppWindowClass.of(context).margePage;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        marge,
        AppSpacing.sm,
        marge,
        AppSpacing.md,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: AppRadius.controleRadius,
        ),
        child: Padding(
          // **Resserré à `md`** : le bloc est un résumé posé au-dessus de la
          // matrice, pas une carte à contempler. Les quatre points gagnés de
          // chaque côté sont quatre points rendus à la grille sur une fenêtre
          // courte, là où ils décident de ce qui se voit.
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // **Le mois n'est pas écrit ici.** Le sélecteur de la barre de
              // commande, juste au-dessus, le porte déjà — avec l'état de la
              // période, que lui seul connaît. La ligne des chiffres part
              // donc du bord gauche du bloc, sur la même verticale que la
              // barre et que sa légende : un intitulé neutre à cette place
              // se lirait comme un quatrième compteur privé de son nombre.
              chiffres,
              const SizedBox(height: AppSpacing.md),
              BarreRepartition(parts: _parts(context)),
            ],
          ),
        ),
      ),
    );
  }

  /// Les quatre familles de créneaux, dans l'ordre où elles se lisent : ce
  /// qui est fait, ce qui reste, ce qui a été refusé, ce qui ne demande rien.
  ///
  /// C'est ici que `orange-vif` et `rose-vif` servent pour la première fois,
  /// **en remplissage et jamais en texte** (`design/061 § 3`).
  List<PartDuMois> _parts(BuildContext context) {
    final theme = Theme.of(context);
    final nonSaisi = context.statuts.disponibilite(DisponibiliteEtat.nonSaisi);

    return <PartDuMois>[
      PartDuMois(
        libelle: AppStrings.bandeauPartCouverts,
        icone: Icons.done_all,
        couleur: theme.colorScheme.secondary,
        valeur: resume.couverts,
      ),
      PartDuMois(
        libelle: AppStrings.bandeauPartARemplir,
        icone: Icons.person_search,
        couleur: AppColors.orangeVif,
        valeur: resume.aPourvoir,
      ),
      PartDuMois(
        libelle: AppStrings.bandeauPartAReattribuer,
        icone: Icons.swap_horiz,
        couleur: AppColors.roseVif,
        valeur: resume.refuses,
      ),
      PartDuMois(
        libelle: AppStrings.bandeauPartNonSaisis,
        icone: nonSaisi.icone,
        couleur: nonSaisi.encre,
        valeur: resume.nonSaisis,
      ),
    ];
  }
}

class _Chiffres extends StatelessWidget {
  const _Chiffres({required this.resume});

  final ResumeMois resume;

  /// **Le nombre au-dessus du libellé**, aux deux largeurs.
  ///
  /// « Réponses en attente » se replie sur deux lignes là où « À pourvoir »
  /// tient sur une : le nombre placé dessous descendait d'une ligne pendant
  /// que ses deux voisins restaient en haut, et les trois chiffres du mois ne
  /// se lisaient plus d'un seul balayage. En tête, ils partagent la même
  /// ligne quel que soit le repli des libellés — et c'est le premier nombre,
  /// non le premier libellé, qui donne maintenant la verticale du bloc.
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: CountStat(
          libelle: AppStrings.bandeauCouverts,
          valeur: resume.couverts,
          plafondAttendu: false,
          nombreEnTete: true,
        ),
      ),
      Expanded(
        child: CountStat(
          libelle: AppStrings.bandeauAPourvoir,
          valeur: resume.manquants,
          plafondAttendu: false,
          nombreEnTete: true,
        ),
      ),
      Expanded(
        child: CountStat(
          libelle: AppStrings.bandeauEnAttente,
          valeur: resume.enAttente,
          plafondAttendu: false,
          nombreEnTete: true,
        ),
      ),
    ],
  );
}
