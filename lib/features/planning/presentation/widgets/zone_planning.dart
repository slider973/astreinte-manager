import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_badge.dart';
import 'barre_commande_matrice.dart';
import 'indicateur_direct.dart';

/// **La zone du planning** : son état, et le geste qui le fait avancer.
///
/// Elle vit dans le bandeau du mois, à droite des trois chiffres (chantier
/// 061c). C'est le bandeau qui décrit le planning — combien de créneaux sont
/// couverts, combien restent à pourvoir — et c'est donc là que la décision se
/// prend : créer le planning quand il n'existe pas, le remplir, le publier.
///
/// Elle a d'abord été posée dans la barre de commande. Mesurée à 1280, la
/// seconde rangée de la barre demandait 418 points pour ces contrôles quand
/// il en restait 95 : « Publier » partait seul sur une troisième ligne et la
/// puce d'état s'écrasait contre « Proposer automatiquement ».
///
/// **Sur grand écran seulement.** En `compact`, la création reste dans la
/// barre et « Publier » dans le fil d'actions du bas, qui ne défile pas avec
/// la vue par jour.
class ZonePlanning extends StatelessWidget {
  const ZonePlanning({
    required this.planning,
    required this.mois,
    required this.creneaux,
    super.key,
    this.uneRangee = false,
  });

  /// Largeur de la colonne dans le bandeau, **mesurée** : les deux boutons
  /// côte à côte, « Publier le planning » et « Proposer automatiquement ».
  ///
  /// Empilés, ils portaient le bandeau à plus de 200 points ; côte à côte, il
  /// tient sous 150. C'est l'arbitrage que le chantier a demandé.
  static const double largeur = 516;

  /// La même sur une seule rangée, bandeau réduit : l'état et les deux
  /// boutons à la suite, sans explication.
  static const double largeurUneRangee = 664;

  /// Ce que la barre de commande sait du planning : la même donnée, un autre
  /// endroit.
  final CommandePlanning planning;

  /// Le nom long du mois affiché, pour « Créer le planning d'octobre ».
  final String mois;

  /// Le nombre de créneaux que la création produira.
  final int creneaux;

  /// Le bandeau est réduit à sa ligne de chiffres : les actions tiennent sur
  /// **une seule rangée**, sans leur explication. C'est le mode d'une fenêtre
  /// courte, où chaque point revient à la grille.
  final bool uneRangee;

  @override
  Widget build(BuildContext context) {
    // **Le bouton « Publier » n'est pas toujours là** : un planning publié ne
    // se republie pas. Son explication non plus, alors — « 12 pompiers seront
    // prévenus » sans le bouton qui les prévient est une promesse sans geste.
    final publiable = planning.existe && planning.onPublier != null;

    final boutons = <Widget>[
      if (!planning.existe)
        PrimaryButton(
          libelle: AppStrings.planningCreer(mois),
          icone: Icons.event_note,
          chargement: planning.creation,
          pleineLargeur: false,
          onPressed: planning.onCreer,
          raisonDesactivation: planning.raisonCreation,
        )
      else ...<Widget>[
        if (publiable)
          PrimaryButton(
            libelle: AppStrings.publierAction,
            icone: Icons.campaign,
            chargement: planning.publication,
            pleineLargeur: false,
            onPressed: planning.raisonPublication == null
                ? planning.onPublier
                : null,
            raisonDesactivation: planning.raisonPublication,
          ),
        // Absent quand il n'y a plus rien à pourvoir : un bouton qui ne
        // ferait rien est un bouton qui ment.
        if (planning.resteAPourvoir)
          PrimaryButton(
            libelle: AppStrings.proposerAction,
            variante: PrimaryButtonVariante.secondaire,
            icone: Icons.auto_fix_high,
            chargement: planning.proposition,
            pleineLargeur: false,
            onPressed: planning.onProposer,
            raisonDesactivation: planning.raisonProposition,
          ),
      ],
    ];

    final etat = planning.existe
        ? <Widget>[
            StatusBadge.planning(
              planning.etat,
              taille: StatusBadgeTaille.compacte,
            ),
            IndicateurDirect(branche: planning.canalBranche),
          ]
        : const <Widget>[];

    // Chaque explication est **liée à son bouton** : celle de la création
    // disparaît avec « Créer le planning », celle de la publication avec
    // « Publier le planning ».
    final Widget? explication = !planning.existe
        ? _Explication(texte: AppStrings.planningCreerDetail(creneaux))
        : publiable
        ? _Explication(texte: planning.detailPublication)
        : null;

    // Une seule rangée : l'état, puis les boutons, sans explication. La
    // fenêtre est courte, et le récapitulatif de publication redit de toute
    // façon combien de pompiers seront prévenus avant que rien ne parte.
    if (uneRangee) {
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[...etat, ...boutons],
      );
    }

    // Aligné à gauche, bien que la colonne soit à droite du bandeau :
    // l'explication doit tomber **sous le bouton qu'elle décrit**. Alignée à
    // droite, « 19 pompiers seront prévenus. » se lisait sous « Proposer
    // automatiquement », qui ne prévient personne.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (etat.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: etat,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: boutons,
        ),
        if (explication != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          // **L'explication sous le bouton**, jamais seulement dans une
          // info-bulle : le geste sort de l'application et fait sonner des
          // téléphones (`DESIGN.md § Do's`).
          explication,
        ],
      ],
    );
  }
}

class _Explication extends StatelessWidget {
  const _Explication({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    style: AppTextStyles.mention.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
