import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/count_stat.dart';
import '../../../../core/widgets/legende_etats.dart';
import '../../domain/resume_mois.dart';
import 'barre_repartition.dart';
import 'zone_planning.dart';

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
    this.actions,
    this.legendeAttributions = false,
  });

  /// La hauteur du bloc entier, **mesurée** : cadre, ligne de chiffres, barre
  /// et légende sur une ligne. Elle ne dépend pas de la largeur — la légende
  /// tient sur une ligne jusqu'à 760 points de large, c'est-à-dire partout où
  /// la matrice existe.
  ///
  /// C'est la grandeur avec laquelle l'écran décide s'il a la place du bloc
  /// (`MatriceScreen.placeBandeauComplet`). Un test la tient à jour : si le
  /// bloc grossit, la constante le dit au lieu de mentir.
  /// **C'est le plus grand des deux** — avec la zone du planning — que
  /// l'écran réserve : sinon le bloc apparaîtrait puis déborderait le jour où
  /// le planning existe.
  static const double hauteurComplet = 144;

  /// Le même bloc **avec la légende des trois blocs d'attribution**, qui
  /// s'adosse à celle de la répartition dès que le planning existe.
  ///
  /// Vingt-deux points de plus, mesurés à 1280 : une rangée de cases de 28 et
  /// l'écart qui la sépare de la légende au-dessus, moins les dix points dont
  /// la colonne des chiffres était plus courte que celle des actions. C'est le
  /// prix de nommer une marque nouvelle, et il est payé ici parce que la barre
  /// de commande le facturait 56 (`DESIGN.md § Écarts, 061c-2`).
  static const double hauteurCompletAvecLegende = 166;

  /// Le même bloc sans la zone du planning : sur un mois dont le planning
  /// n'est pas encore lu, et en `compact`.
  static const double hauteurCompletSansActions = 134;

  /// La même, réduite à sa ligne de trois chiffres, sur une fenêtre où les
  /// libellés ne se replient pas, la rangée d'actions comprise.
  static const double hauteurReduit = 68;

  /// La ligne de trois chiffres seule, sans rangée d'actions.
  static const double hauteurReduitSansActions = 58;

  /// La largeur qu'il faut au bloc pour que ses chiffres **et** la rangée
  /// d'actions tiennent côte à côte, réduits. En dessous, l'écran garde le
  /// bloc complet plutôt que de replier la rangée d'actions sur deux lignes.
  static const double largeurReduitAvecActions = 1000;

  /// Ce qu'il faut laisser aux trois chiffres et à leur barre pour qu'ils
  /// restent lisibles à côté de la colonne d'actions. En dessous, la colonne
  /// passe **sous** la barre de répartition au lieu de l'étrangler.
  static const double largeurMinimaleResume = 380;

  final ResumeMois resume;

  /// Vrai en `compact` : une seule ligne de trois chiffres, sans barre.
  final bool compact;

  /// **La zone du planning**, à droite des chiffres (chantier 061c) : son
  /// état, « Publier », « Proposer automatiquement » ou « Créer le planning »,
  /// et l'explication du geste.
  ///
  /// Elle est ici et non dans la barre de commande parce que c'est ce bloc
  /// qui décrit le planning : les trois chiffres comptent exactement ce que
  /// ces boutons changent. `null` sur téléphone, où la création reste dans la
  /// barre et « Publier » dans le fil d'actions du bas.
  final Widget? actions;

  /// **La légende des trois blocs d'attribution**, sous celle de répartition.
  ///
  /// Elle est ici et non dans la barre de commande, où vit la légende des
  /// disponibilités, parce que la barre n'a pas la place : mesurée à 1280 avec
  /// un planning, la légende complète la porte de 120 à 176 points, soit deux
  /// rangées de contrôles plus une. Le bandeau, lui, parle déjà de ces
  /// attributions — ses trois chiffres les comptent — et sa barre de
  /// répartition a une légende à laquelle celle-ci s'adosse
  /// (`DESIGN.md § Écarts, 061c-2`).
  ///
  /// Faux tant que le planning n'existe pas : aucune case ne porte alors de
  /// bloc, et nommer ce qui n'est pas à l'écran est du bruit. Faux aussi en
  /// `compact`, où la matrice n'est pas là.
  final bool legendeAttributions;

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
        // Réduit, le bloc garde ses actions : elles passent sur **une seule
        // rangée** à droite des chiffres. Un planning qu'on ne peut plus
        // publier parce que la fenêtre est courte serait un cul-de-sac.
        child: actions == null
            ? chiffres
            : Row(
                children: <Widget>[
                  Expanded(child: chiffres),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: ZonePlanning.largeurUneRangee,
                    child: actions,
                  ),
                ],
              ),
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
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints contraintes) {
              // La colonne d'actions ne passe à droite que si les chiffres
              // gardent de quoi se lire. Sur une fenêtre `expanded`, elle
              // descend sous la barre de répartition : un résumé étranglé
              // à cent points ne résume plus rien.
              final cote =
                  actions != null &&
                  contraintes.maxWidth >=
                      ZonePlanning.largeur + largeurMinimaleResume;

              final resumeDuMois = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // **Le mois n'est pas écrit ici.** Le sélecteur de la
                  // barre de commande, juste au-dessus, le porte déjà — avec
                  // l'état de la période, que lui seul connaît. La ligne des
                  // chiffres part donc du bord gauche du bloc, sur la même
                  // verticale que la barre et que sa légende : un intitulé
                  // neutre à cette place se lirait comme un quatrième
                  // compteur privé de son nombre.
                  chiffres,
                  const SizedBox(height: AppSpacing.md),
                  BarreRepartition(parts: _parts(context)),
                  if (legendeAttributions) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    const LegendeEtats.attributions(),
                  ],
                ],
              );

              if (!cote) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    resumeDuMois,
                    if (actions != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      actions!,
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: resumeDuMois),
                  const SizedBox(width: AppSpacing.xl),
                  SizedBox(width: ZonePlanning.largeur, child: actions),
                ],
              );
            },
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
