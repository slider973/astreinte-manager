import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
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
/// de saisie, la légende et l'indicateur d'enregistrement.
///
/// Elle ne défile pas : ses contrôles pilotent ce qui est en dessous. Elle se
/// replie en `Wrap` dès que la place manque.
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

  /// Ce que la barre dit du planning : le créer, son état, et l'état du canal
  /// temps réel. **`null` tant que le planning n'est pas lu** : tant qu'on ne
  /// sait pas s'il existe, on n'affirme ni qu'il existe ni le contraire.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtres = widget.filtres;

    // **Un conteneur d'accessibilité.** Sans lui, les puces de la barre
    // partaient se ranger derrière les 3 720 cases de la grille dans l'ordre
    // de parcours : l'interrupteur de saisie arrivait en dernier. Vu en vrai
    // dans Chrome.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
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
                    suffixe: filtres.recherche.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: AppStrings.matriceRechercheEffacer,
                            onPressed: () {
                              _recherche.clear();
                              widget.onFiltres(filtres.copie(recherche: ''));
                            },
                          ),
                  ),
                ),
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
                  onTri: (TriMatrice tri) =>
                      widget.onFiltres(filtres.copie(tri: tri)),
                ),
                _InterrupteurSaisie(
                  arme: widget.modeArme,
                  possible: widget.raisonSaisieImpossible == null,
                  onArmer: widget.onArmer,
                ),
                // **La raison à côté du contrôle**, jamais seulement dans une
                // bannière. Enfant direct de la même `Wrap` : imbriquer un
                // second `Wrap` renvoyait le contrôle en fin de parcours
                // clavier, derrière les 3 720 cases.
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
                        AppStrings.matriceCompteFiltre(
                          widget.affiches,
                          widget.total,
                        ),
                        style: AppTextStyles.mention.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _recherche.clear();
                          widget.onFiltres(
                            filtres.copie(
                              recherche: '',
                              masquerNonSaisis: false,
                            ),
                          );
                        },
                        child: const Text(AppStrings.matriceToutAfficher),
                      ),
                    ],
                  ),
                // **La création du planning vit ici**, pas dans un écran à
                // part : c'est le premier geste du mois, au même endroit que
                // tous les autres contrôles du mois.
                if (widget.planning?.existe == false) ...<Widget>[
                  PrimaryButton(
                    libelle: AppStrings.planningCreer(
                      AppStrings.moisLongs[widget.periode.mois - 1],
                    ),
                    variante: PrimaryButtonVariante.secondaire,
                    icone: Icons.event_note,
                    chargement: widget.planning!.creation,
                    pleineLargeur: false,
                    onPressed: widget.planning!.onCreer,
                    raisonDesactivation: widget.planning!.raisonCreation,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      AppStrings.planningCreerDetail(
                        widget.periode.nombreDeJours * 2,
                      ),
                      style: AppTextStyles.mention.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ] else if (widget.planning != null) ...<Widget>[
                  StatusBadge.planning(
                    widget.planning!.etat,
                    taille: StatusBadgeTaille.compacte,
                  ),
                  IndicateurDirect(branche: widget.planning!.canalBranche),
                ],
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
      ),
    );
  }
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
}
