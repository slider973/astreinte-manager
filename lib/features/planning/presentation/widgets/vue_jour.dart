import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/slot_chip.dart';
import '../../domain/cle_cellule.dart';
import '../../domain/creneau_planning.dart';
import '../../domain/ligne_matrice.dart';
import '../../domain/matrice_mois.dart';
import '../../domain/planning_mois.dart';
import 'entete_ligne_membre.dart';
import 'ligne_creneaux.dart';
import 'ligne_disponibles.dart';

/// **La vue par jour** — ce que le chef voit sur son téléphone.
///
/// Sous 840 dp, la matrice n'existe pas : 360 dp moins la colonne des noms
/// laissent quatre journées, et faire défiler sept écrans pour atteindre le 28
/// n'est pas une consultation, c'est une punition (brief § 6.6).
///
/// Une journée à la fois, tous les membres, **et la même saisie** : ce sont
/// des cibles de 48 dp, pas la densité dense. Rien n'est perdu sauf la vue à
/// deux dimensions.
class VueJour extends StatefulWidget {
  const VueJour({
    required this.matrice,
    required this.lignes,
    required this.annee,
    required this.mois,
    required this.aujourdhui,
    required this.commentaires,
    required this.erreurs,
    required this.saisieActive,
    required this.onCase,
    required this.planning,
    required this.creneauSelectionne,
    required this.onCreneau,
    super.key,
    this.enTete,
  });

  /// Hauteur d'une ligne de membre : le nom en 16, les quotas, le commentaire.
  static const double hauteurLigne = 76;

  /// Largeur d'une journée du ruban.
  static const double largeurJourRuban = 72;

  /// Hauteur du ruban : le nom du jour, son numéro, et les deux comptes de
  /// disponibles.
  static const double hauteurRuban = 88;

  /// Hauteur de l'en-tête épinglé des deux créneaux.
  static const double hauteurEnteteCreneaux = 52;

  final MatriceMois matrice;
  final List<LigneMatrice> lignes;
  final int annee;
  final int mois;
  final DateTime aujourdhui;
  final bool commentaires;
  final Set<CleCellule> erreurs;
  final bool saisieActive;
  final ValueChanged<CleCellule> onCase;

  /// Le planning du mois. Sur un téléphone, ses deux créneaux du jour sont des
  /// **cibles de 48 dp**, pas des cases de 28 px : la matrice n'existe pas
  /// ici, le panneau s'ouvre d'ici.
  final PlanningMois planning;

  final String? creneauSelectionne;
  final ValueChanged<String> onCreneau;

  /// La barre de commande, posée en tête du défilement. Sur un téléphone,
  /// elle défile avec le reste : la fixer ne laisserait plus de place aux
  /// membres.
  final Widget? enTete;

  @override
  State<VueJour> createState() => _VueJourState();
}

class _VueJourState extends State<VueJour> {
  int? _choisi;

  /// La journée affichée : celle qu'on a choisie, sinon aujourd'hui s'il est
  /// dans le mois, sinon le premier.
  int get _jour {
    final choisi = _choisi;
    if (choisi != null && choisi <= widget.matrice.nombreDeJours) {
      return choisi;
    }
    if (widget.aujourdhui.year == widget.annee &&
        widget.aujourdhui.month == widget.mois) {
      return widget.aujourdhui.day;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime(widget.annee, widget.mois, _jour);
    final echelle = MediaQuery.textScalerOf(context);

    // **Un seul défilement**, et un seul en-tête épinglé : celui des deux
    // créneaux. Sur un téléphone, la barre de commande et le ruban des jours
    // ne peuvent pas être fixes tous les deux — il ne resterait plus de place
    // pour les membres, qui sont l'objet de l'écran.
    return CustomScrollView(
      slivers: <Widget>[
        if (widget.enTete != null) SliverToBoxAdapter(child: widget.enTete),
        // Le fait, **sous la barre de commande** : la matrice existe, elle
        // s'ouvre ailleurs. Une phrase, pas une excuse, et pas un lien vers
        // rien.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              AppStrings.matriceEcranLarge,
              style: AppTextStyles.mention.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            // Le ruban suit l'échelle de texte : à ×1.7, le nom du jour et son
            // numéro demandent la place qu'ils demandent, et la vue par jour
            // est précisément la composition qui la leur donne.
            height: echelle.scale(VueJour.hauteurRuban),
            child: _ruban(),
          ),
        ),
        const SliverToBoxAdapter(child: AppDivider()),
        if (widget.planning.existe)
          SliverToBoxAdapter(
            child: BlocCreneauxJour(
              planning: widget.planning,
              jour: _jour,
              date: date,
              selectionne: widget.creneauSelectionne,
              onCreneau: widget.onCreneau,
            ),
          ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _EnteteCreneaux(
            hauteur: echelle.scale(VueJour.hauteurEnteteCreneaux),
          ),
        ),
        SliverList.builder(
          itemCount: widget.lignes.length,
          itemBuilder: (BuildContext context, int index) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Ligne(
                ligne: widget.lignes[index],
                date: date,
                jour: _jour,
                commentaires: widget.commentaires,
                erreurs: widget.erreurs,
                saisieActive: widget.saisieActive,
                onCase: widget.onCase,
              ),
              const AppDivider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            ],
          ),
        ),
      ],
    );
  }

  /// Le ruban des jours, qui porte **le même compte de disponibles** que la
  /// ligne du grand écran : on balaie le mois et on voit les trous, sans
  /// matrice.
  Widget _ruban() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      itemCount: widget.matrice.nombreDeJours,
      itemExtent: VueJour.largeurJourRuban,
      itemBuilder: (BuildContext context, int index) {
        final jour = index + 1;
        return _BoutonJour(
          date: DateTime(widget.annee, widget.mois, jour),
          jour: jour,
          matrice: widget.matrice,
          choisi: jour == _jour,
          onChoisir: () => setState(() => _choisi = jour),
        );
      },
    );
  }
}

/// L'en-tête des créneaux, épinglé : **c'est le seul endroit où les icônes de
/// jour et de nuit sont écrites**, exactement comme dans la matrice.
///
/// Opaque, parce que le contenu défile dessous, et séparé par un filet — pas
/// par une ombre (`DESIGN.md § Elevation & Depth`).
class _EnteteCreneaux extends SliverPersistentHeaderDelegate {
  const _EnteteCreneaux({required this.hauteur});

  final double hauteur;

  @override
  double get minExtent => hauteur;

  @override
  double get maxExtent => hauteur;

  @override
  Widget build(BuildContext context, double decalage, bool chevauche) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _EnteteCreneau(creneau: CreneauType.jour),
                  SizedBox(width: AppSpacing.entreCibles),
                  _EnteteCreneau(creneau: CreneauType.nuit),
                ],
              ),
            ),
          ),
          AppDivider.enTete(),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_EnteteCreneaux ancien) => ancien.hauteur != hauteur;
}

class _EnteteCreneau extends StatelessWidget {
  const _EnteteCreneau({required this.creneau});

  final CreneauType creneau;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripteur = context.statuts.creneau(creneau);

    return SizedBox(
      width: AppTouch.caseConfortable,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Icon(
            descripteur.icone,
            size: AppTouch.iconePetite,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          Text(
            descripteur.libelle,
            style: AppTextStyles.etiquette.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoutonJour extends StatelessWidget {
  const _BoutonJour({
    required this.date,
    required this.jour,
    required this.matrice,
    required this.choisi,
    required this.onChoisir,
  });

  final DateTime date;
  final int jour;
  final MatriceMois matrice;
  final bool choisi;
  final VoidCallback onChoisir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ferie = nomJourFerie(date);

    return Semantics(
      button: true,
      selected: choisi,
      label: <String>[
        dateAvecJourSemaine(date),
        if (ferie != null) AppStrings.jourFerieNomme(ferie),
      ].join(', '),
      onTap: choisi ? null : onChoisir,
      excludeSemantics: true,
      child: InkWell(
        onTap: choisi ? null : onChoisir,
        borderRadius: AppRadius.controleRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: choisi ? theme.colorScheme.secondaryContainer : null,
            borderRadius: AppRadius.controleRadius,
            border: Border.all(
              color: choisi
                  ? theme.colorScheme.secondary
                  : context.statuts.filetDecoratif,
              width: choisi ? AppStroke.etat : AppStroke.filet,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  AppStrings.grilleJoursCourts[date.weekday - 1],
                  style: AppTextStyles.etiquette.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text('${date.day}', style: AppTextStyles.nombrePetit),
                const SizedBox(height: AppSpacing.xxs),
                CasesDisponibles(matrice: matrice, jour: jour, date: date),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.ligne,
    required this.date,
    required this.jour,
    required this.commentaires,
    required this.erreurs,
    required this.saisieActive,
    required this.onCase,
  });

  final LigneMatrice ligne;
  final DateTime date;
  final int jour;
  final bool commentaires;
  final Set<CleCellule> erreurs;
  final bool saisieActive;
  final ValueChanged<CleCellule> onCase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final montrerCommentaire = commentaires && ligne.aUnCommentaire;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              container: true,
              label: AppStrings.matriceLigneSemantique(
                nom: ligne.nomAffiche,
                quotas: EnteteLigneMembre.semantiqueQuotas(ligne),
                commentaire: ligne.aUnCommentaire
                    ? ligne.commentaire!
                    : AppStrings.matriceCommentaireVide,
              ),
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    ligne.nomAffiche,
                    // Le nom en 16 : la taille de base, enfin possible.
                    style: AppTextStyles.corps,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _quotas(ligne),
                    style: AppTextStyles.mention.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (montrerCommentaire)
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.chat_bubble_outline,
                          size: AppTouch.iconePetite,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            ligne.commentaire!,
                            style: AppTextStyles.mention.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _Case(
            ligne: ligne,
            date: date,
            jour: jour,
            creneau: CreneauType.jour,
            erreurs: erreurs,
            saisieActive: saisieActive,
            onCase: onCase,
          ),
          const SizedBox(width: AppSpacing.entreCibles),
          _Case(
            ligne: ligne,
            date: date,
            jour: jour,
            creneau: CreneauType.nuit,
            erreurs: erreurs,
            saisieActive: saisieActive,
            onCase: onCase,
          ),
        ],
      ),
    );
  }

  /// « 2/3 Astr. · 1/1 W-E », ou la charge seule quand il n'y a pas de
  /// plafond. La barre de fraction dit qu'un plafond existe.
  static String _quotas(LigneMatrice ligne) {
    final astreintes = ligne.maxAstreintes == null
        ? '${ligne.astreintes}'
        : '${ligne.astreintesRestantes}/${ligne.maxAstreintes}';
    final weekends = ligne.maxWeekends == null
        ? '${ligne.unitesWeekend}'
        : '${ligne.weekendsRestants}/${ligne.maxWeekends}';
    return '$astreintes ${AppStrings.matriceColonneAstreintes} · '
        '$weekends ${AppStrings.matriceColonneWeekends}';
  }
}

class _Case extends StatelessWidget {
  const _Case({
    required this.ligne,
    required this.date,
    required this.jour,
    required this.creneau,
    required this.erreurs,
    required this.saisieActive,
    required this.onCase,
  });

  final LigneMatrice ligne;
  final DateTime date;
  final int jour;
  final CreneauType creneau;
  final Set<CleCellule> erreurs;
  final bool saisieActive;
  final ValueChanged<CleCellule> onCase;

  @override
  Widget build(BuildContext context) {
    final statuts = context.statuts;
    final cellule = ligne.cellule(jour, creneau);
    final cle = CleCellule(userId: ligne.userId, jour: jour, creneau: creneau);

    return SlotChip(
      etat: cellule.etat,
      creneau: creneau,
      saisiParAdmin: cellule.parAdmin,
      erreur: erreurs.contains(cle),
      libelleSemantique: AppStrings.matriceCaseSemantique(
        membre: ligne.nomAffiche,
        jourEtDate: dateAvecJourSemaine(date),
        creneau: statuts.creneau(creneau).libelle,
        etat: statuts.disponibilite(cellule.etat).libelle,
      ),
      actionSemantique: saisieActive
          ? AppStrings.matriceCaseAction(
              statuts
                  .disponibilite(CelluleMatrice.suivant(cellule.etat))
                  .libelle,
            )
          : null,
      onTap: saisieActive ? () => onCase(cle) : null,
    );
  }
}

/// Les deux créneaux du jour affiché, en cibles de **48 dp**.
///
/// C'est le seul accès au panneau des candidats sous 840 dp, et il est en
/// pleine cible tactile : attribuer est un geste court, sur un objet unique,
/// avec une liste — exactement ce qu'un téléphone fait bien. Un chef qui reçoit
/// un refus le samedi soir doit pouvoir réattribuer depuis sa cuisine.
class BlocCreneauxJour extends StatelessWidget {
  const BlocCreneauxJour({
    required this.planning,
    required this.jour,
    required this.date,
    required this.selectionne,
    required this.onCreneau,
    super.key,
  });

  final PlanningMois planning;
  final int jour;
  final DateTime date;
  final String? selectionne;
  final ValueChanged<String> onCreneau;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _BoutonCreneau(
              couverture: planning.couverture(jour, CreneauType.jour),
              creneau: CreneauType.jour,
              date: date,
              selectionne: selectionne,
              onCreneau: onCreneau,
            ),
          ),
          const SizedBox(width: AppSpacing.entreCibles),
          Expanded(
            child: _BoutonCreneau(
              couverture: planning.couverture(jour, CreneauType.nuit),
              creneau: CreneauType.nuit,
              date: date,
              selectionne: selectionne,
              onCreneau: onCreneau,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoutonCreneau extends StatelessWidget {
  const _BoutonCreneau({
    required this.couverture,
    required this.creneau,
    required this.date,
    required this.selectionne,
    required this.onCreneau,
  });

  final ({CreneauPlanning creneau, int pourvus, EtatCouverture etat})?
  couverture;
  final CreneauType creneau;
  final DateTime date;
  final String? selectionne;
  final ValueChanged<String> onCreneau;

  @override
  Widget build(BuildContext context) {
    final valeur = couverture;
    if (valeur == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final descripteurCreneau = context.statuts.creneau(creneau);
    final descripteur = descripteurCouverture(
      context,
      valeur.etat,
      personne: valeur.pourvus == 0 && valeur.etat == EtatCouverture.aPourvoir,
    );
    final choisi = selectionne == valeur.creneau.id;

    return Semantics(
      key: ValueKey<String>('creneau-${valeur.creneau.id}'),
      button: true,
      selected: choisi,
      label: AppStrings.planningCouvertureSemantique(
        jourEtDate: dateAvecJourSemaine(date),
        creneau: descripteurCreneau.libelle,
        pourvus: valeur.pourvus,
        requis: valeur.creneau.effectifRequis,
        etat: descripteur.libelle,
      ),
      onTapHint: AppStrings.planningCouvertureAction,
      // L'action vit sur le nœud qui exclut ses enfants : sinon le geste de
      // l'`InkWell` disparaît avec eux, et le bouton n'est plus activable au
      // clavier ni au lecteur d'écran.
      onTap: () => onCreneau(valeur.creneau.id),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onCreneau(valeur.creneau.id),
        borderRadius: AppRadius.controleRadius,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTouch.cible),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.controleRadius,
            border: Border.all(
              color: choisi
                  ? theme.colorScheme.primary
                  : context.statuts.filetDecoratif,
              width: choisi ? AppStroke.etat : AppStroke.filet,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                descripteurCreneau.icone,
                size: AppTouch.icone,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  descripteurCreneau.libelle,
                  style: AppTextStyles.corpsSecondaire,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              PastilleCouverture(
                descripteur: descripteur,
                pourvus: valeur.pourvus,
                requis: valeur.creneau.effectifRequis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
