import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../astreintes/domain/astreinte.dart';
import '../../domain/tableau_bord.dart';

/// Une carte de la rangée de l'accueil : un jour, un créneau, un état.
///
/// **La couleur n'est jamais seule** : chaque carte porte l'icône de son
/// créneau — ou de son état pour un jour libre — et le mot qui va avec. En
/// niveaux de gris, l'indigo plein, l'orange plein et le gris clair se
/// distinguent déjà par la valeur ; l'icône et le libellé closent la règle
/// (`DESIGN.md § Do's`).
///
/// La carte ne borne pas sa hauteur : elle la reçoit de la rangée, qui la
/// calcule à partir de l'échelle de texte ([CarteJourVue.hauteur]). Son
/// contenu est rangé du haut vers le bas et chaque ligne tient sur une ligne :
/// un jour de garde ne se lit pas en trois lignes tronquées.
class CarteJourVue extends StatelessWidget {
  const CarteJourVue({
    required this.carte,
    required this.aujourdhui,
    required this.heures,
    required this.nomCaserne,
    required this.onRepondre,
    super.key,
  });

  /// Largeur de la carte (`design/064 § 2`).
  static const double largeur = 144;

  /// Hauteur de référence, à échelle de texte 1.
  static const double hauteurBase = 168;

  /// Au-delà de cette échelle, la rangée cesse de grandir : elle mangerait
  /// l'écran entier, et le contenu de la carte se réduit alors par ses propres
  /// replis.
  static const double echelleMax = 1.6;

  /// La hauteur que la rangée réserve, échelle de texte comprise.
  static double hauteur(BuildContext context) {
    final echelle = MediaQuery.textScalerOf(context).scale(16) / 16;
    return hauteurBase * echelle.clamp(1, echelleMax);
  }

  final CarteJour carte;

  /// Le jour courant, injecté : « Aujourd'hui » ne se décide pas à partir de
  /// l'horloge du système dans un widget, sinon un test échoue à minuit.
  final DateTime aujourdhui;

  final HeuresAffichage heures;
  final String nomCaserne;

  /// Le bouton « Répondre » d'une carte de proposition.
  final ValueChanged<CarteJour> onRepondre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statuts = context.statuts;
    final propose = statuts.attribution(AttributionEtat.propose);

    final (Color fond, Color encre, Color? filet) = switch (carte.etat) {
      EtatCarte.acceptee => (scheme.primary, scheme.onPrimary, null),
      // L'orange vif ne fait que 2,26:1 sur le papier : c'est son contour
      // `etatAttente` qui porte la limite du bloc, comme dans la matrice
      // (`DESIGN.md § Écarts, 061c-2`, WCAG 1.4.11).
      EtatCarte.proposition => (
        propose.blocFond,
        propose.blocEncre,
        propose.filet,
      ),
      EtatCarte.libre => (scheme.surfaceContainerHigh, scheme.onSurface, null),
    };

    final creneau = carte.creneau;
    final descripteurCreneau = creneau == null
        ? null
        : statuts.creneau(creneau);
    final libelleDate = _libelleDate();

    return Semantics(
      container: true,
      label: AppStrings.accueilCarteSemantique(
        date: libelleDate,
        creneau: descripteurCreneau?.libelle,
        heures: creneau == null ? null : heures.intervalle(creneau),
        etat: switch (carte.etat) {
          EtatCarte.acceptee => AppStrings.accueilEtatAcceptee,
          EtatCarte.proposition => AppStrings.accueilEtatProposition,
          EtatCarte.libre => AppStrings.accueilEtatLibre,
        },
        caserne: carte.etat == EtatCarte.acceptee ? nomCaserne : null,
      ),
      child: Container(
        width: largeur,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: AppRadius.carteRadius,
          border: filet == null
              ? null
              : Border.all(color: filet, width: AppStroke.etat),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // **Deux groupes, pas six enfants flexibles.** La date monte, le
              // créneau descend, et l'espace libre se met entre les deux :
              // c'est la composition de la référence, et c'est aussi la seule
              // qui ne fasse pas dépendre la taille du numéro d'un partage de
              // place avec un `Spacer`.
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Le numéro du jour, en chiffres tabulaires : c'est la
                  // mesure qu'on lit d'abord, à un mètre, en plein soleil.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${carte.jour.day}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: encre,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  _Ligne(
                    texte: libelleDate,
                    encre: encre,
                    style: theme.textTheme.labelLarge,
                  ),
                  if (creneau != null && carte.etat == EtatCarte.acceptee)
                    _Ligne(
                      texte: heures.intervalle(creneau),
                      encre: encre,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (descripteurCreneau != null)
                    _LigneIcone(
                      icone: descripteurCreneau.icone,
                      texte: descripteurCreneau.libelle,
                      encre: encre,
                    )
                  else
                    _LigneIcone(
                      icone: Icons.event_available_outlined,
                      texte: AppStrings.accueilLibre,
                      encre: encre,
                    ),
                  if (carte.etat == EtatCarte.acceptee && nomCaserne.isNotEmpty)
                    _Ligne(
                      texte: nomCaserne,
                      encre: encre,
                      style: theme.textTheme.bodySmall,
                    ),
                  if (carte.etat == EtatCarte.proposition) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    _BoutonRepondre(
                      encre: encre,
                      onPressed: () => onRepondre(carte),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _libelleDate() {
    final minuit = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
    if (carte.jour == minuit) return AppStrings.accueilAujourdhui;
    return '${nomJourCourt(carte.jour)} ${carte.jour.day}';
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.texte, required this.encre, this.style});

  final String texte;
  final Color encre;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    style: style?.copyWith(color: encre),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

class _LigneIcone extends StatelessWidget {
  const _LigneIcone({
    required this.icone,
    required this.texte,
    required this.encre,
  });

  final IconData icone;
  final String texte;
  final Color encre;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icone, size: AppTouch.icone, color: encre),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          texte,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: encre),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// « Répondre », sur la carte orange.
///
/// Un contour plutôt qu'un aplat : un second bloc plein sur un bloc plein
/// aurait demandé une troisième teinte, et l'encre du bloc suffit — 7,64:1
/// sur l'orange vif.
class _BoutonRepondre extends StatelessWidget {
  const _BoutonRepondre({required this.encre, required this.onPressed});

  final Color encre;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: AppTouch.plancher,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: encre,
        padding: EdgeInsets.zero,
        side: BorderSide(color: encre),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.controleRadius,
        ),
      ),
      child: const Text(
        AppStrings.accueilRepondre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}
