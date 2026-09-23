import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/legende_etats.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/save_indicator.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../dispos/domain/periode_saisie.dart';
import '../../../dispos/presentation/widgets/selecteur_mois.dart';
import '../../domain/matrice_filtres.dart';
import 'indicateur_direct.dart';

/// La barre de commande : le mois, la recherche, les filtres, le tri, le mode
/// de saisie, l'action du planning, la légende et l'indicateur
/// d'enregistrement.
///
/// Elle ne défile pas : ses contrôles pilotent ce qui est en dessous.
///
/// **Deux rangées de 48 points dès `expanded`** (chantier 061c) : le mois, la
/// recherche et les puces en haut ; ce qui agit sur le planning en bas, la
/// légende poussée au bord droit. Elle coûtait 230 à 266 points sur quatre
/// étages, plus 70 pour le fil « Publier » qui vivait sous la grille ; la
/// hauteur qu'elle rend va à la matrice, qui est l'écran.
///
/// En `compact`, rien ne change : la barre y vit dans le défilement de la vue
/// par jour, où la hauteur ne manque pas de la même façon, et deux rangées
/// larges de 360 points n'auraient de toute façon pas tenu.
///
/// **Aucun de ces contrôles ne déclenche de requête.** Les soixante lignes
/// sont déjà en mémoire ; une recherche qui irait au serveur serait une
/// régression (brief § 2).
class BarreCommandeMatrice extends StatefulWidget {
  const BarreCommandeMatrice({
    required this.periodes,
    required this.periode,
    required this.onMois,
    required this.filtres,
    required this.onFiltres,
    required this.modeArme,
    required this.onArmer,
    required this.raisonSaisieImpossible,
    required this.sync,
    required this.onReessayer,
    required this.total,
    required this.affiches,
    required this.montrerLegende,
    required this.planning,
    super.key,
  });

  /// Largeur du champ de recherche sur grand écran : son libellé (154), son
  /// icône (32) et la marge du texte. Mesurée, pas arrondie au hasard : la
  /// rangée n'a pas un point de trop.
  static const double largeurRecherche = 208;

  /// Hauteur d'une rangée de contrôles. Le plancher tactile, et la mesure sur
  /// laquelle la barre entière est bornée.
  static const double hauteurRangee = AppTouch.cible;

  final List<PeriodeSaisie> periodes;
  final PeriodeSaisie periode;
  final ValueChanged<PeriodeSaisie> onMois;

  final FiltresMatrice filtres;
  final ValueChanged<FiltresMatrice> onFiltres;

  final bool modeArme;

  /// Demande l'armement ou le désarmement. L'écran garde la main : c'est lui
  /// qui affiche la confirmation de première fois.
  final ValueChanged<bool> onArmer;

  /// Pourquoi la saisie est impossible, ou `null` si elle l'est.
  /// **Un contrôle désactivé porte sa raison à côté de lui**, jamais
  /// seulement dans une bannière (`DESIGN.md § Do's`).
  final String? raisonSaisieImpossible;

  final SyncEtat sync;

  /// La sortie d'un échec d'enregistrement. `SaveIndicator` l'exige, et il a
  /// raison : un échec sans issue est un cul-de-sac.
  final VoidCallback onReessayer;

  final int total;
  final int affiches;

  /// La légende n'a pas sa place sur un téléphone, où la vue par jour montre
  /// déjà deux cases nommées.
  final bool montrerLegende;

  /// Ce que la barre dit du planning : le créer, le publier, son état, et
  /// l'état du canal temps réel. **`null` tant que le planning n'est pas
  /// lu** : tant qu'on ne sait pas s'il existe, on n'affirme ni qu'il existe
  /// ni le contraire.
  final CommandePlanning? planning;

  @override
  State<BarreCommandeMatrice> createState() => _BarreCommandeMatriceState();
}

class _BarreCommandeMatriceState extends State<BarreCommandeMatrice> {
  final TextEditingController _recherche = TextEditingController();
  Timer? _attente;

  @override
  void initState() {
    super.initState();
    _recherche.text = widget.filtres.recherche;
  }

  @override
  void didUpdateWidget(BarreCommandeMatrice ancien) {
    super.didUpdateWidget(ancien);
    // « Tout afficher » vide le champ sans passer par le clavier.
    if (widget.filtres.recherche != _recherche.text &&
        widget.filtres.recherche.isEmpty) {
      _recherche.clear();
    }
  }

  @override
  void dispose() {
    _attente?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  /// Débounce de 200 ms : on filtre en mémoire, mais on ne retrie pas
  /// soixante lignes à chaque frappe.
  void _chercher(String valeur) {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      widget.onFiltres(widget.filtres.copie(recherche: valeur));
    });
  }

  void _effacer() {
    _recherche.clear();
    widget.onFiltres(widget.filtres.copie(recherche: ''));
  }

  void _toutAfficher() {
    _recherche.clear();
    widget.onFiltres(
      widget.filtres.copie(recherche: '', masquerNonSaisis: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    // **Un conteneur d'accessibilité.** Sans lui, les puces de la barre
    // partaient se ranger derrière les 3 720 cases de la grille dans l'ordre
    // de parcours : l'interrupteur de saisie arrivait en dernier. Vu en vrai
    // dans Chrome.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: AppWindowClass.of(context).estCompact
          ? _empilee(context)
          : _deuxRangees(context),
    );
  }

  // --- La forme de grand écran : deux rangées -----------------------------

  Widget _deuxRangees(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Rangée 1 — quel mois, et quelles lignes.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SelecteurMois(
              periodes: widget.periodes,
              selectionnee: widget.periode,
              uneLigne: true,
              onChoisir: widget.onMois,
            ),
            SizedBox(
              width: BarreCommandeMatrice.largeurRecherche,
              child: _ChampRecherche(
                controleur: _recherche,
                vide: widget.filtres.recherche.isEmpty,
                onChanged: _chercher,
                onEffacer: _effacer,
              ),
            ),
            ..._puces(),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Rangée 2 — ce qui agit sur le planning, la légende au bord droit.
        Row(
          children: <Widget>[
            Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _InterrupteurSaisie(
                    arme: widget.modeArme,
                    possible: widget.raisonSaisieImpossible == null,
                    onArmer: widget.onArmer,
                  ),
                  ..._raisonEtCompte(context),
                  ..._actionPlanning(context, avecPublier: true),
                ],
              ),
            ),
            if (widget.montrerLegende) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              const LegendeEtats(espacement: AppSpacing.sm),
            ],
            const SizedBox(width: AppSpacing.sm),
            SaveIndicator(
              etat: widget.sync,
              compact: true,
              onReessayer: widget.onReessayer,
            ),
          ],
        ),
      ],
    ),
  );

  // --- La forme de téléphone : inchangée depuis le ticket 017 -------------

  Widget _empilee(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const SizedBox(height: AppSpacing.md),
      SelecteurMois(
        periodes: widget.periodes,
        selectionnee: widget.periode,
        onChoisir: widget.onMois,
      ),
      const SizedBox(height: AppSpacing.md),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 280,
              child: ChampTexte(
                libelle: AppStrings.matriceRechercheLibelle,
                controleur: _recherche,
                clavier: TextInputType.text,
                icone: Icons.search,
                onChanged: _chercher,
                suffixe: widget.filtres.recherche.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: AppStrings.matriceRechercheEffacer,
                        onPressed: _effacer,
                      ),
              ),
            ),
            ..._puces(),
            _InterrupteurSaisie(
              arme: widget.modeArme,
              possible: widget.raisonSaisieImpossible == null,
              onArmer: widget.onArmer,
            ),
            ..._raisonEtCompte(context),
            // Le fil « Publier » reste sous la grille en `compact` : la barre
            // y défile avec la vue par jour, et un bouton qui s'en va au
            // défilement est un bouton qu'on cherche.
            ..._actionPlanning(context, avecPublier: false),
            if (widget.montrerLegende) const LegendeEtats(),
            SaveIndicator(
              etat: widget.sync,
              compact: true,
              onReessayer: widget.onReessayer,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
    ],
  );

  // --- Les morceaux partagés ----------------------------------------------

  List<Widget> _puces() {
    final filtres = widget.filtres;
    return <Widget>[
      FilterChip(
        label: const Text(AppStrings.matriceMasquerNonSaisis),
        selected: filtres.masquerNonSaisis,
        onSelected: (bool valeur) =>
            widget.onFiltres(filtres.copie(masquerNonSaisis: valeur)),
      ),
      FilterChip(
        label: const Text(AppStrings.matriceAfficherCommentaires),
        avatar: const Icon(Icons.chat_bubble_outline, size: 18),
        selected: filtres.commentaires,
        onSelected: (bool valeur) =>
            widget.onFiltres(filtres.copie(commentaires: valeur)),
      ),
      _MenuTri(
        tri: filtres.tri,
        onTri: (TriMatrice tri) => widget.onFiltres(filtres.copie(tri: tri)),
      ),
    ];
  }

  /// La raison d'un contrôle désactivé, et le compte des lignes filtrées.
  ///
  /// **La raison est un enfant direct de la `Wrap` de son contrôle** :
  /// imbriquer un second `Wrap` renvoyait le contrôle en fin de parcours
  /// clavier, derrière les 3 720 cases.
  List<Widget> _raisonEtCompte(BuildContext context) {
    final theme = Theme.of(context);
    return <Widget>[
      if (widget.raisonSaisieImpossible != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            widget.raisonSaisieImpossible!,
            style: AppTextStyles.mention.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      if (widget.affiches != widget.total)
        Wrap(
          spacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              AppStrings.matriceCompteFiltre(widget.affiches, widget.total),
              style: AppTextStyles.mention.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton(
              onPressed: _toutAfficher,
              child: const Text(AppStrings.matriceToutAfficher),
            ),
          ],
        ),
    ];
  }

  /// L'emplacement de l'action du planning : le créer, ou le publier.
  ///
  /// **La création du planning vit ici**, pas dans un écran à part : c'est le
  /// premier geste du mois, au même endroit que tous les autres contrôles du
  /// mois. Et depuis le chantier 061c, « Publier » prend cette même place
  /// quand le planning existe, au lieu des 70 points d'un fil sous la grille.
  List<Widget> _actionPlanning(
    BuildContext context, {
    required bool avecPublier,
  }) {
    final planning = widget.planning;
    if (planning == null) return const <Widget>[];

    if (!planning.existe) {
      return <Widget>[
        PrimaryButton(
          libelle: AppStrings.planningCreer(
            AppStrings.moisLongs[widget.periode.mois - 1],
          ),
          variante: PrimaryButtonVariante.secondaire,
          icone: Icons.event_note,
          chargement: planning.creation,
          pleineLargeur: false,
          onPressed: planning.onCreer,
          raisonDesactivation: planning.raisonCreation,
        ),
        _Explication(
          texte: AppStrings.planningCreerDetail(
            widget.periode.nombreDeJours * 2,
          ),
        ),
      ];
    }

    return <Widget>[
      StatusBadge.planning(planning.etat, taille: StatusBadgeTaille.compacte),
      IndicateurDirect(branche: planning.canalBranche),
      // **Le remplissage automatique vit ici**, à côté de l'état du planning.
      //
      // Absent quand il n'y a plus rien à pourvoir : un bouton qui ne ferait
      // rien est un bouton qui ment.
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
      if (avecPublier && planning.onPublier != null) ...<Widget>[
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
        // Le nombre de **téléphones qui vont sonner**, pas le nombre
        // d'attributions : c'est la seule grandeur que le chef ait besoin de
        // sentir avant d'appuyer.
        _Explication(texte: planning.detailPublication),
      ],
    ];
  }
}

/// Ce qu'un bouton de la barre va faire, à côté de lui, **sur une ligne**.
///
/// Sans largeur maximale et sans `ellipsis` : la `Wrap` qui la porte la fait
/// passer à la ligne entière si la place manque, elle ne la coupe jamais.
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

/// Le champ de recherche de la barre de grand écran : **48 points**.
///
/// `ChampTexte` empile son libellé au-dessus du champ et fait 78 points : il
/// reste la forme de tous les formulaires du produit, et celle de la barre
/// sur téléphone. Dans une rangée de contrôles de 48, le libellé passe
/// **dedans** — un libellé flottant Material, qui remonte à la saisie et ne
/// disparaît jamais, et non un texte d'invite qui s'efface à la première
/// lettre (`DESIGN.md § Inputs / Fields`).
class _ChampRecherche extends StatelessWidget {
  const _ChampRecherche({
    required this.controleur,
    required this.vide,
    required this.onChanged,
    required this.onEffacer,
  });

  final TextEditingController controleur;
  final bool vide;
  final ValueChanged<String> onChanged;
  final VoidCallback onEffacer;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: BarreCommandeMatrice.hauteurRangee,
    child: TextField(
      controller: controleur,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      style: AppTextStyles.corpsSecondaire,
      decoration: InputDecoration(
        isDense: true,
        labelText: AppStrings.matriceRechercheLibelle,
        labelStyle: AppTextStyles.corpsSecondaire,
        floatingLabelStyle: AppTextStyles.libelleChamp,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        prefixIcon: const Icon(Icons.search, size: AppTouch.icone),
        prefixIconConstraints: const BoxConstraints(
          minWidth: AppSpacing.xxl,
          minHeight: AppSpacing.xxl,
        ),
        suffixIcon: vide
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: AppTouch.icone),
                tooltip: AppStrings.matriceRechercheEffacer,
                onPressed: onEffacer,
              ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: AppTouch.cible,
          minHeight: AppTouch.cible,
        ),
      ),
    ),
  );
}

/// Le menu de tri. **Nommé**, jamais une icône seule : trois valeurs, et
/// celle qui est active se lit sans l'ouvrir.
///
/// `ActionChip` et non `PopupMenuButton(child: Chip)` : ce dernier ne rendait
/// **aucun nœud d'accessibilité** pour son déclencheur — le contrôle était
/// invisible aux lecteurs d'écran. Vu en vrai dans Chrome.
class _MenuTri extends StatelessWidget {
  const _MenuTri({required this.tri, required this.onTri});

  final TriMatrice tri;
  final ValueChanged<TriMatrice> onTri;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: <Widget>[
        for (final valeur in TriMatrice.values)
          MenuItemButton(
            onPressed: () => onTri(valeur),
            leadingIcon: Icon(
              valeur == tri ? Icons.check : null,
              size: AppTouch.icone,
            ),
            child: Text(valeur.libelle),
          ),
      ],
      builder: (BuildContext context, MenuController controleur, Widget? _) =>
          ActionChip(
            avatar: const Icon(Icons.sort, size: 18),
            label: Text('${AppStrings.matriceTrier} : ${tri.libelle}'),
            onPressed: () =>
                controleur.isOpen ? controleur.close() : controleur.open(),
          ),
    );
  }
}

class _InterrupteurSaisie extends StatelessWidget {
  const _InterrupteurSaisie({
    required this.arme,
    required this.possible,
    required this.onArmer,
  });

  final bool arme;

  /// Faux quand la caserne est suspendue, le réseau absent, ou la densité
  /// dense inactionnable ici. La raison, elle, s'affiche à côté.
  final bool possible;

  final ValueChanged<bool> onArmer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilterChip(
      avatar: const Icon(Icons.edit_note, size: 18),
      label: const Text(AppStrings.matriceModeSaisie),
      selected: arme,
      selectedColor: theme.colorScheme.tertiaryContainer,
      checkmarkColor: theme.colorScheme.onTertiaryContainer,
      onSelected: possible ? onArmer : null,
      tooltip: arme ? AppStrings.matriceModeSaisieQuitter : null,
    );
  }
}

/// Ce que la barre de commande sait du planning du mois.
///
/// Un objet et non six paramètres : la barre en portait déjà treize, et six de
/// plus en auraient fait une signature que personne ne relit.
@immutable
class CommandePlanning {
  const CommandePlanning({
    required this.existe,
    required this.etat,
    required this.canalBranche,
    required this.creation,
    required this.onCreer,
    this.raisonCreation,
    this.resteAPourvoir = false,
    this.proposition = false,
    this.onProposer,
    this.raisonProposition,
    this.publication = false,
    this.onPublier,
    this.raisonPublication,
    this.detailPublication = '',
  });

  final bool existe;
  final PlanningEtat etat;

  /// Le canal temps réel est abonné.
  final bool canalBranche;

  /// La création est en vol : le bouton garde son libellé et sa largeur.
  final bool creation;

  /// `null` désactive le bouton — et exige alors [raisonCreation].
  final VoidCallback? onCreer;
  final String? raisonCreation;

  /// Il reste au moins un créneau dont l'effectif n'est pas atteint. Faux, le
  /// bouton « Proposer automatiquement » disparaît : il n'aurait rien à faire.
  final bool resteAPourvoir;

  /// Le remplissage est en vol : le bouton garde son libellé et sa largeur.
  final bool proposition;

  /// `null` désactive le bouton — et exige alors [raisonProposition].
  final VoidCallback? onProposer;
  final String? raisonProposition;

  /// La publication est en vol : le bouton garde son libellé et sa largeur.
  final bool publication;

  /// `null` retire « Publier » de la barre : le planning n'est plus
  /// modifiable, il est déjà parti.
  final VoidCallback? onPublier;

  /// Pourquoi « Publier » est désactivé, ou `null`.
  final String? raisonPublication;

  /// Ce que la publication va faire : le nombre de téléphones qui sonneront.
  final String detailPublication;
}
