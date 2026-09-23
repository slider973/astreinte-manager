import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// **La carte du monde du pompier** (`design/064 § 2`, ticket 064c).
///
/// Fond `surface` posé sur le papier doux `surface-container-low` de la page,
/// rayon [AppRadius.carte], filet `outline-variant` de 1 dp, **aucune ombre**.
/// Les deux marques vont ensemble et pas par hasard : un cran de cette palette
/// ne vaut que 1,06:1 — mesuré au 064a —, c'est donc le filet qui détache la
/// carte, et le cran qui l'habille (`DESIGN.md § Elevation & Depth`, niveau 0 :
/// « un filet 1 dp **et/ou** une surface tonale d'un cran »).
///
/// Elle est née au 064c d'un constat de doublon : l'accueil du 064a écrivait
/// déjà deux fois le même `Material` — la ligne de proposition et la ligne
/// « mois saisi » —, et le Calendrier comme les Astreintes en demandaient
/// quatre de plus.
///
/// **Elle ne s'imbrique jamais.** `DESIGN.md § Don't` interdit la carte dans
/// la carte : ce qui vit dans une carte est un contrôle (une puce de raccourci
/// à rayon 4, un carré d'initiale à rayon 12), jamais une seconde carte.
class CarteDouce extends StatelessWidget {
  const CarteDouce({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.enErreur = false,
    this.hauteurMin = 0,
  });

  /// Sans rembourrage : la carte n'est plus qu'un fond et un filet, et c'est
  /// l'enfant qui décide de ses marges — une liste dont les lignes doivent
  /// toucher les bords, une grille qui porte déjà les siennes.
  const CarteDouce.nue({
    required this.child,
    super.key,
    this.onTap,
    this.enErreur = false,
    this.hauteurMin = 0,
  }) : padding = EdgeInsets.zero;

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Rend la carte entière actionnable. `null` : la carte ne commande rien.
  final VoidCallback? onTap;

  /// Le filet passe à `error` et à 2 dp. Réservé à une carte qui **porte**
  /// une erreur de saisie ; une erreur de chargement reste un état de contenu.
  final bool enErreur;

  /// Hauteur minimale du corps. `AppTouch.cible` pour une carte qu'on touche.
  final double hauteurMin;

  /// **Le filet de la carte**, à l'épaisseur nommée du système.
  ///
  /// Public parce que deux autres formes dessinent la même carte sans passer
  /// par ce widget : [CarteDouceSliver], qui l'enroule autour d'un groupe de
  /// slivers, et la carte fantôme du squelette des astreintes, qui la dessine
  /// en creux. Trois `Border.all` écrits à la main cessent d'être la même
  /// carte au premier réglage.
  static BorderSide filet(ColorScheme scheme, {bool enErreur = false}) =>
      BorderSide(
        color: enErreur ? scheme.error : scheme.outlineVariant,
        width: enErreur ? AppStroke.etat : AppStroke.filet,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final corps = ConstrainedBox(
      constraints: BoxConstraints(minHeight: hauteurMin),
      child: Padding(padding: padding, child: child),
    );

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.carteRadius,
        side: filet(scheme, enErreur: enErreur),
      ),
      child: onTap == null
          ? corps
          : InkWell(
              onTap: onTap,
              borderRadius: AppRadius.carteRadius,
              child: corps,
            ),
    );
  }
}

/// La même carte, **autour d'un groupe de slivers**.
///
/// La grille du mois fait soixante-deux lignes : elle ne peut pas entrer dans
/// une boîte, elle doit rester un sliver pour que seules les lignes visibles
/// se construisent. [SliverMainAxisGroup] réunit l'en-tête épinglé et la
/// grille en un seul sliver — l'en-tête s'épingle alors **à l'intérieur du
/// groupe** et s'en va avec lui —, et [DecoratedSliver] peint la carte
/// derrière, sur toute l'étendue défilante.
class CarteDouceSliver extends StatelessWidget {
  const CarteDouceSliver({required this.slivers, super.key});

  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // **Deux décorations, et le filet par-dessus** (chantier 064d).
    //
    // Écrites en une seule, fond et filet se peignaient tous deux *derrière*
    // le groupe : le premier sliver venu recouvrait le trait. C'était le cas
    // de l'en-tête de colonnes épinglé de la grille du mois, qui remplit le
    // rayon haut en `surface` opaque — mesuré au pixel, le bord haut de la
    // carte valait `surface` et non `outline-variant` —, et ce l'aurait été
    // de toute ligne à fond plein touchant un bord, la ligne de week-end du
    // registre par exemple. Le papier reste derrière, le filet passe devant,
    // et la carte est continue quoi qu'on pose dedans.
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.carteRadius,
      ),
      sliver: DecoratedSliver(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: AppRadius.carteRadius,
          border: Border.fromBorderSide(CarteDouce.filet(scheme)),
        ),
        sliver: SliverMainAxisGroup(slivers: slivers),
      ),
    );
  }
}
