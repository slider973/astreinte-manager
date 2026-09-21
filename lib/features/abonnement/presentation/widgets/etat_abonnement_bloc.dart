import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/abonnement.dart';

/// Le bloc d'état : **une ligne qu'on lit à 40 cm**, une seconde qui donne la
/// date, et rien d'autre.
///
/// Les cinq états réemploient les encres déjà posées par `DESIGN.md` — ocre
/// d'attente, vert de validation, vermillon, gris-encre hachuré, gris atténué.
/// Aucune couleur n'est inventée ici, et aucun état n'est porté par la teinte
/// seule : marque, icône et libellé viennent d'abord.
class EtatAbonnementBloc extends StatelessWidget {
  const EtatAbonnementBloc({
    required this.abonnement,
    required this.maintenant,
    super.key,
  });

  final Abonnement abonnement;

  /// L'instant de référence, injecté : « il reste 12 jours » se teste.
  final DateTime maintenant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripteur = descripteurAbonnement(context, abonnement.statut);
    final detail = _detail();

    return Semantics(
      container: true,
      label: AppStrings.abonnementEtatSemantique(descripteur.libelle, detail),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatusBadge.descripteur(descripteur),
              if (detail.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(detail, style: theme.textTheme.bodyLarge),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// La deuxième ligne. **Elle disparaît quand la date manque** : une phrase
  /// d'état incomplète vaut mieux qu'un trou nommé « Non définie ».
  String _detail() {
    switch (abonnement.statut) {
      case StatutAbonnement.essai:
        final fin = abonnement.finEssai;
        if (fin == null) return '';
        return abonnement.essaiExpire(maintenant: maintenant)
            ? AppStrings.abonnementEssaiTermine(formaterDateLongue(fin))
            : AppStrings.abonnementEssaiJusquau(
                formaterDateLongue(fin),
                abonnement.joursEssaiRestants(maintenant: maintenant) ?? 0,
              );

      case StatutAbonnement.actif:
        final fin = abonnement.finPeriode;
        return fin == null
            ? ''
            : AppStrings.abonnementProchainPaiement(formaterDateLongue(fin));

      case StatutAbonnement.retardPaiement:
        final bascule = abonnement.bascule;
        return bascule == null
            ? AppStrings.abonnementRetardSansDate
            : AppStrings.abonnementRetardEcheance(formaterDateLongue(bascule));

      // « Rien n'a été supprimé » est obligatoire ici : c'est la promesse de
      // `docs/PRD.md § 6.6`, et la seule phrase qui compte pour un chef de
      // centre qui découvre l'écran un mardi soir.
      case StatutAbonnement.suspendu:
      case StatutAbonnement.resilie:
        final depuis = abonnement.finPeriode;
        return depuis == null
            ? AppStrings.abonnementLectureSeule
            : AppStrings.abonnementLectureSeuleDepuis(
                formaterDateLongue(depuis),
              );
    }
  }
}

/// Le descripteur d'un statut d'abonnement, composé à partir des encres du
/// thème courant — donc suivant le mode clair/sombre comme les autres familles.
///
/// « Suspendu » et « résilié » sont **gris**, jamais rouges : `DESIGN.md § Do's`
/// — une caserne suspendue est un fait, pas une panne, et c'est réversible.
/// Seul le retard de paiement est rouge, parce qu'il y a une action à faire et
/// une échéance réelle.
StatusDescriptor descripteurAbonnement(
  BuildContext context,
  StatutAbonnement statut,
) {
  final statuts = context.statuts;
  final couleurs = Theme.of(context).colorScheme;

  return switch (statut) {
    StatutAbonnement.essai => _renommer(
      statuts.attribution(AttributionEtat.propose),
      AppStrings.abonnementEtatEssai,
    ),
    StatutAbonnement.actif => _renommer(
      statuts.planning(PlanningEtat.valide),
      AppStrings.abonnementEtatActif,
    ),
    StatutAbonnement.retardPaiement => StatusDescriptor(
      icone: Icons.error_outline,
      libelle: AppStrings.abonnementEtatRetard,
      encre: couleurs.onErrorContainer,
      fond: couleurs.errorContainer,
      filet: couleurs.error,
    ),
    StatutAbonnement.suspendu => _renommer(
      statuts.periode(PeriodeEtat.verrouillee),
      AppStrings.abonnementEtatSuspendu,
      icone: Icons.visibility_outlined,
    ),
    StatutAbonnement.resilie => _renommer(
      statuts.planning(PlanningEtat.archive),
      AppStrings.abonnementEtatResilie,
    ),
  };
}

StatusDescriptor _renommer(
  StatusDescriptor source,
  String libelle, {
  IconData? icone,
}) => StatusDescriptor(
  icone: icone ?? source.icone,
  libelle: libelle,
  encre: source.encre,
  fond: source.fond,
  filet: source.filet,
  hachure: source.hachure,
  barre: source.barre,
);
