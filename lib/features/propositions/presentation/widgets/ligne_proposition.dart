import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/proposition.dart';

/// Une astreinte proposée, et les deux réponses possibles.
///
/// **Ce n'est pas une carte** (`DESIGN.md § Cards / Containers`) : une marge de
/// registre, un corps, une rangée d'actions, et un filet de réglure qui la
/// sépare de la suivante. Aucune ombre, aucun fond, aucun rayon.
///
/// L'asymétrie des deux boutons est l'information : « Accepter » prend trois
/// cinquièmes de la largeur, « Refuser » deux. Le produit sait quelle réponse
/// il espère, et le pouce trouve la plus grande cible sans viser
/// (`design/021 § 6.2`).
class LigneDeProposition extends StatelessWidget {
  const LigneDeProposition({
    required this.proposition,
    required this.onAccepter,
    required this.onRefuser,
    super.key,
    this.raisonBlocage,
    this.actionsACote = false,
    this.maintenant,
  });

  /// Largeur de la marge du registre : le numéro du jour et son abréviation.
  static const double largeurMarge = 48;

  final Proposition proposition;

  final VoidCallback onAccepter;
  final VoidCallback onRefuser;

  /// Pourquoi les deux boutons sont inertes (hors ligne, caserne suspendue).
  /// `null` quand on peut répondre. Un bouton grisé sans raison est un défaut
  /// (`DESIGN.md § Buttons`).
  final String? raisonBlocage;

  /// Les actions vivent à droite du corps plutôt qu'en dessous. Décidé par le
  /// parent, qui seul connaît la largeur réelle.
  final bool actionsACote;

  /// L'horloge, injectée pour que « il y a 2 h » ne dépende pas de l'heure du
  /// test.
  final DateTime? maintenant;

  @override
  Widget build(BuildContext context) {
    final creneau = context.statuts.creneau(proposition.creneau);
    final jourEtDate = dateAvecJourSemaine(proposition.jour);
    final libelleCreneau = '$jourEtDate, ${creneau.libelle.toLowerCase()}';

    final actions = _Actions(
      libelleCreneau: libelleCreneau,
      onAccepter: onAccepter,
      onRefuser: onRefuser,
      raisonBlocage: raisonBlocage,
    );

    final corps = _Corps(
      proposition: proposition,
      jourEtDate: jourEtDate,
      maintenant: maintenant,
    );

    return Semantics(
      container: true,
      label: AppStrings.propositionsLigneSemantique(
        jourEtDate: jourEtDate,
        creneau: creneau.libelle,
        detail: _detail(proposition, maintenant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Marge(jour: proposition.jour),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: actionsACote
                  ? Row(
                      children: <Widget>[
                        Expanded(child: corps),
                        const SizedBox(width: AppSpacing.lg),
                        SizedBox(width: 320, child: actions),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        corps,
                        const SizedBox(height: AppSpacing.md),
                        actions,
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// « proposé il y a 2 h · relancé hier », ou une chaîne vide.
  static String _detail(Proposition proposition, DateTime? maintenant) {
    final morceaux = <String>[];
    final proposee = proposition.proposeeLe;
    if (proposee != null) {
      morceaux.add(
        AppStrings.propositionsProposeeDepuis(
          formaterInstantRelatif(proposee, maintenant: maintenant),
        ),
      );
    }
    final relance = proposition.derniereRelance;
    if (proposition.relances > 0 && relance != null) {
      morceaux.add(
        AppStrings.propositionsRelanceDepuis(
          formaterInstantRelatif(relance, maintenant: maintenant),
        ),
      );
    }
    return morceaux.join(' · ');
  }
}

/// La marge du registre : le numéro du jour en chiffres tabulaires, son
/// abréviation dessous, et le fond de weekend — exactement la marge de
/// `DayCell` au ticket 011.
class _Marge extends StatelessWidget {
  const _Marge({required this.jour});

  final DateTime jour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ferie = nomJourFerie(jour);
    final weekend =
        jour.weekday == DateTime.saturday || jour.weekday == DateTime.sunday;

    return Container(
      width: LigneDeProposition.largeurMarge,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: weekend || ferie != null
            ? theme.colorScheme.surfaceDim
            : Colors.transparent,
        borderRadius: AppRadius.caseRegistreRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${jour.day}',
            style: AppTextStyles.nombre.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            nomJourCourt(jour),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: weekend ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Corps extends StatelessWidget {
  const _Corps({
    required this.proposition,
    required this.jourEtDate,
    required this.maintenant,
  });

  final Proposition proposition;
  final String jourEtDate;
  final DateTime? maintenant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = LigneDeProposition._detail(proposition, maintenant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            Text(jourEtDate, style: theme.textTheme.bodyLarge),
            StatusBadge.creneau(
              proposition.creneau,
              taille: StatusBadgeTaille.compacte,
            ),
          ],
        ),
        if (detail.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.libelleCreneau,
    required this.onAccepter,
    required this.onRefuser,
    required this.raisonBlocage,
  });

  final String libelleCreneau;
  final VoidCallback onAccepter;
  final VoidCallback onRefuser;
  final String? raisonBlocage;

  @override
  Widget build(BuildContext context) {
    final raison = raisonBlocage;
    final bloque = raison != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Trois cinquièmes pour la réponse que la donnée prédit.
        Expanded(
          flex: 3,
          child: PrimaryButton(
            libelle: AppStrings.propositionsAccepter,
            libelleAnnonce: AppStrings.propositionsAccepterCreneau(
              libelleCreneau,
            ),
            icone: Icons.task_alt,
            pleineLargeur: true,
            onPressed: bloque ? null : onAccepter,
            raisonDesactivation: raison,
          ),
        ),
        const SizedBox(width: AppSpacing.entreCibles),
        Expanded(
          flex: 2,
          child: PrimaryButton(
            libelle: AppStrings.propositionsRefuser,
            libelleAnnonce: AppStrings.propositionsRefuserCreneau(
              libelleCreneau,
            ),
            // Le glyphe de l'état « Refusé ». Un sens, un glyphe.
            icone: Icons.cancel,
            // **Pas `danger`** : le vermillon appartient à l'état qui
            // résultera, pas au bouton qui y mène. Le seul rouge du parcours
            // est le bouton de confirmation de la feuille de refus.
            variante: PrimaryButtonVariante.secondaire,
            pleineLargeur: true,
            onPressed: bloque ? null : onRefuser,
            raisonDesactivation: raison,
            // Les deux boutons partagent la raison : le premier l'écrit, le
            // second se contente de l'annoncer.
            raisonVisible: false,
          ),
        ),
      ],
    );
  }
}
