import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/candidat.dart';
import '../../domain/creneau_planning.dart';
import 'champ_effectif.dart';
import 'ligne_candidat.dart';
import 'ligne_creneaux.dart';

/// **Le panneau des candidats d'un créneau.**
///
/// Le même objet des deux côtés : le volet de droite en `large`
/// (`AppScaffold.panneauLateral`), une feuille de bas d'écran en dessous.
/// Jamais un dialogue : ce n'est ni une interruption ni une protection
/// (`DESIGN.md § Don't`). Il ne sait rien de son contenant, et rien des
/// providers : l'écran lui passe ses données et ses rappels.
///
/// Trois listes disjointes, dans l'ordre du travail : ceux qui sont déjà
/// posés, ceux qu'on peut poser, et — repliés — ceux qu'on peut poser contre
/// leur déclaration.
class PanneauCreneau extends StatefulWidget {
  const PanneauCreneau({
    required this.panneau,
    required this.onFermer,
    required this.onAttribuer,
    required this.onRetirer,
    required this.onEffectif,
    super.key,
    this.raisonInactif,
    this.messageDistant,
    this.messageReattribution,
  });

  final PanneauCandidats panneau;

  final VoidCallback onFermer;

  /// Attribuer un candidat. L'écran garde la main : c'est lui qui pose la
  /// question quand le membre n'est pas disponible.
  final ValueChanged<Candidat> onAttribuer;

  /// Retirer une attribution existante.
  final ValueChanged<Candidat> onRetirer;

  final ValueChanged<int> onEffectif;

  /// Pourquoi rien n'est actionnable : caserne suspendue, planning publié,
  /// hors ligne. **Affichée**, jamais seulement supposée.
  final String? raisonInactif;

  /// « Modifié à l'instant par Jean D. » — quand ce créneau-là a bougé sous
  /// une autre main.
  final String? messageDistant;

  /// Ce que coûte un appui sur un planning publié : « la personne choisie sera
  /// notifiée tout de suite », et le nom de qui a refusé quand l'écran le sait.
  ///
  /// **Il remplace [messageDistant]** quand les deux voudraient s'afficher :
  /// l'en-tête porte une mention, une seule, et celle-ci décrit la conséquence
  /// du geste — elle passe devant l'anecdote de qui a touché le créneau.
  final String? messageReattribution;

  @override
  State<PanneauCreneau> createState() => _PanneauCreneauState();
}

class _PanneauCreneauState extends State<PanneauCreneau> {
  /// La section des non disponibles est **fermée par défaut** : attribuer
  /// quelqu'un contre sa déclaration n'est pas le geste ordinaire.
  bool _deplie = false;

  @override
  void didUpdateWidget(PanneauCreneau ancien) {
    super.didUpdateWidget(ancien);
    // Changer de créneau referme la section : le dépliage appartient au
    // créneau qu'on regardait, pas au panneau.
    if (ancien.panneau.creneau.id != widget.panneau.creneau.id) {
      _deplie = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final panneau = widget.panneau;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EnTete(
          panneau: panneau,
          onFermer: widget.onFermer,
          messageDistant: widget.messageDistant,
          messageReattribution: widget.messageReattribution,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ChampEffectif(
            valeur: panneau.requis,
            onChanger: widget.onEffectif,
            actif: panneau.modifiable && widget.raisonInactif == null,
            raison: widget.raisonInactif,
          ),
        ),
        const AppDivider(),
        Expanded(child: _liste(panneau)),
      ],
    );
  }

  Widget _liste(PanneauCandidats panneau) {
    final elements = _elements(panneau);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: elements.length,
      itemBuilder: (BuildContext context, int index) => elements[index],
    );
  }

  /// La liste mise à plat : titres, lignes, messages. Une seule structure,
  /// donc un seul défilement et aucune liste imbriquée.
  List<Widget> _elements(PanneauCandidats panneau) {
    final actif = panneau.modifiable && widget.raisonInactif == null;

    // Le geste ne change pas, sa conséquence si : sur un planning publié,
    // poser quelqu'un le notifie et retirer quelqu'un l'annule.
    final poser = panneau.notifie
        ? ActionCandidat.reattribuer
        : ActionCandidat.attribuer;
    final oter = panneau.notifie
        ? ActionCandidat.annuler
        : ActionCandidat.retirer;

    return <Widget>[
      _Titre(texte: AppStrings.planningSectionAttribues(panneau.pourvus)),
      if (panneau.attribues.isEmpty)
        const _Message(texte: AppStrings.planningAucunAttribue)
      else
        for (final candidat in panneau.attribues)
          _ligne(candidat, oter, actif: actif),

      _Titre(
        texte: AppStrings.planningSectionDisponibles(
          panneau.disponibles.length,
        ),
      ),
      if (panneau.disponibles.isEmpty)
        _AucunDisponible(
          onVoirNonDisponibles: panneau.nonDisponibles.isEmpty || _deplie
              ? null
              : () => setState(() => _deplie = true),
        )
      else
        for (final candidat in panneau.disponibles)
          _ligne(candidat, poser, actif: actif),

      if (panneau.nonDisponibles.isNotEmpty) ...<Widget>[
        _BasculeNonDisponibles(
          nombre: panneau.nonDisponibles.length,
          deplie: _deplie,
          onBasculer: () => setState(() => _deplie = !_deplie),
        ),
        if (_deplie)
          for (final candidat in panneau.nonDisponibles)
            _ligne(candidat, poser, actif: actif),
      ],
    ];
  }

  Widget _ligne(
    Candidat candidat,
    ActionCandidat action, {
    required bool actif,
  }) => Padding(
    key: ValueKey<String>('${action.name}-${candidat.userId}'),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LigneCandidat(
          candidat: candidat,
          action: action,
          raison: actif ? null : widget.raisonInactif,
          onAction: !actif
              ? null
              : () => action.pose
                    ? widget.onAttribuer(candidat)
                    : widget.onRetirer(candidat),
        ),
        const AppDivider(),
      ],
    ),
  );
}

/// La date, le créneau, l'état de couverture, et de quoi fermer.
class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.panneau,
    required this.onFermer,
    this.messageDistant,
    this.messageReattribution,
  });

  final PanneauCandidats panneau;
  final VoidCallback onFermer;
  final String? messageDistant;
  final String? messageReattribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripteur = descripteurCouverture(
      context,
      panneau.etat,
      personne:
          panneau.pourvus == 0 && panneau.etat == EtatCouverture.aPourvoir,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      dateAvecJourSemaine(panneau.jour),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    StatusBadge.creneau(
                      panneau.creneau.creneau,
                      taille: StatusBadgeTaille.compacte,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onFermer,
                icon: const Icon(Icons.close),
                tooltip: AppStrings.planningPanneauFermer,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              StatusBadge.descripteur(descripteur),
              Text(
                AppStrings.planningCouvertureCompte(
                  panneau.pourvus,
                  panneau.requis,
                ),
                style: AppTextStyles.corpsSecondaire.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: AppTextStyles.chiffresTabulaires,
                ),
              ),
            ],
          ),
          // **Ce que coûte un appui**, dit avant l'appui. Bleu de réglure :
          // c'est une information, pas une alarme.
          if (messageReattribution != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _BandeauReattribution(texte: messageReattribution!),
          ],
          // **Une seule mention, et seulement là où elle sert.** Aucun toast
          // par événement : deux adjoints qui attribuent trente créneaux
          // produiraient trente `SnackBar`, et le signal est déjà à l'écran.
          if (messageDistant != null && messageReattribution == null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                messageDistant!,
                style: AppTextStyles.mention.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// « Planning publié : la personne choisie sera notifiée tout de suite. »
///
/// Icône + libellé, jamais la couleur seule. Pas de filet coloré à gauche : le
/// fond `secondary-container` et l'icône suffisent, et un liseré de 4 dp sur un
/// bloc d'information est une habitude, pas une décision (`DESIGN.md § Don't`).
class _BandeauReattribution extends StatelessWidget {
  const _BandeauReattribution({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: AppRadius.controleRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.campaign,
            size: AppTouch.iconePetite,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: AppTextStyles.corpsSecondaire.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Toujours plus d'espace au-dessus d'un titre qu'en dessous.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          texte,
          style: AppTextStyles.etiquette.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Text(
        texte,
        style: AppTextStyles.corpsSecondaire.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Aucun candidat disponible : **un état vide explique et propose une
/// action** (`DESIGN.md § Don't`). L'action, ici, est de regarder ceux qui ne
/// le sont pas — c'est exactement ce que le chef fera ensuite.
class _AucunDisponible extends StatelessWidget {
  const _AucunDisponible({required this.onVoirNonDisponibles});

  final VoidCallback? onVoirNonDisponibles;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: EmptyState(
      titre: AppStrings.planningAucunDisponibleTitre,
      texte: AppStrings.planningAucunDisponibleTexte,
      icone: Icons.person_off_outlined,
      libelleAction: onVoirNonDisponibles == null
          ? null
          : AppStrings.planningVoirNonDisponibles,
      onAction: onVoirNonDisponibles,
    ),
  );
}

class _BasculeNonDisponibles extends StatelessWidget {
  const _BasculeNonDisponibles({
    required this.nombre,
    required this.deplie,
    required this.onBasculer,
  });

  final int nombre;
  final bool deplie;
  final VoidCallback onBasculer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.sm,
        0,
      ),
      child: Semantics(
        button: true,
        expanded: deplie,
        child: InkWell(
          onTap: onBasculer,
          borderRadius: AppRadius.controleRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.cible),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    AppStrings.planningSectionNonDisponibles(nombre),
                    style: AppTextStyles.etiquette.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  deplie ? Icons.expand_less : Icons.expand_more,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
