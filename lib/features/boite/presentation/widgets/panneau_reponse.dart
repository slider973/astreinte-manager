import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../astreintes/domain/astreinte.dart';
import '../../../propositions/domain/proposition.dart';

/// **La réponse à une proposition.**
///
/// Le même objet des deux côtés : le volet de droite en `large`
/// (`AppScaffold.panneauLateral`), une feuille de bas d'écran en dessous —
/// la règle du panneau des candidats de l'admin (`DESIGN.md § Don't` :
/// jamais une modale pour une tâche qui ne demande ni interruption ni
/// protection). Il ne sait rien de son contenant ni des providers : la Boîte
/// lui passe la proposition et ses deux rappels.
///
/// **L'asymétrie des deux boutons est l'information** (`design/021 § 6.2`) :
/// « Accepter » prend trois cinquièmes de la largeur, « Refuser » deux. Le
/// produit sait quelle réponse il espère, et le pouce trouve la plus grande
/// cible sans viser.
class PanneauReponse extends StatelessWidget {
  const PanneauReponse({
    required this.proposition,
    required this.heures,
    required this.onAccepter,
    required this.onRefuser,
    required this.onFermer,
    super.key,
    this.raisonBlocage,
    this.maintenant,
    this.etendu = false,
  });

  /// En dessous de cette largeur de rangée, les deux boutons s'empilent.
  ///
  /// Mesurée : « Refuser », son glyphe et le rembourrage de 24 points de
  /// `PrimaryButton` demandent 144 points, et les deux cinquièmes que
  /// l'asymétrie lui accorde n'en valent que 128 dans le volet de 360. Le mot
  /// s'écrivait « Refu… », vu dans Chrome.
  static const double largeurCoteACote = 350;

  final Proposition proposition;

  /// Les heures d'affichage de la caserne : « 07:00 – 19:00 ».
  final HeuresAffichage heures;

  final VoidCallback onAccepter;
  final VoidCallback onRefuser;
  final VoidCallback onFermer;

  /// Pourquoi les deux boutons sont inertes (hors ligne, caserne suspendue).
  /// `null` quand on peut répondre. Un bouton grisé sans raison est un défaut
  /// (`DESIGN.md § Buttons`).
  final String? raisonBlocage;

  /// L'horloge, injectée pour que « il y a 2 h » ne dépende pas de l'heure du
  /// test.
  final DateTime? maintenant;

  /// Le panneau occupe toute la hauteur qu'on lui donne : c'est le cas du
  /// volet latéral, que `AppScaffold` pose dans une `Row` — dont l'alignement
  /// transversal par défaut **centre** un enfant de hauteur minimale. Sans
  /// ceci, la réponse flottait au milieu d'une colonne vide.
  ///
  /// Faux dans une feuille de bas d'écran, qui se règle sur son contenu.
  final bool etendu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creneau = context.statuts.creneau(proposition.creneau);
    final jourEtDate = dateAvecJourSemaine(proposition.jour);
    final libelleCreneau = '$jourEtDate, ${creneau.libelle.toLowerCase()}';
    final detail = _detail(proposition, maintenant);
    final raison = raisonBlocage;

    return Semantics(
      container: true,
      label: AppStrings.boiteReponseTitre(libelleCreneau),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: etendu ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(jourEtDate, style: theme.textTheme.titleLarge),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: <Widget>[
                          StatusBadge.creneau(
                            proposition.creneau,
                            taille: StatusBadgeTaille.compacte,
                          ),
                          Text(
                            heures.intervalle(proposition.creneau),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onFermer,
                  icon: const Icon(Icons.close),
                  tooltip: AppStrings.boiteReponseFermer,
                ),
              ],
            ),
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                '${detail[0].toUpperCase()}${detail.substring(1)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const AppDivider(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints contraintes) {
                final accepter = PrimaryButton(
                  libelle: AppStrings.propositionsAccepter,
                  libelleAnnonce: AppStrings.propositionsAccepterCreneau(
                    libelleCreneau,
                  ),
                  icone: Icons.task_alt,
                  pleineLargeur: true,
                  onPressed: raison == null ? onAccepter : null,
                  raisonDesactivation: raison,
                );
                final refuser = PrimaryButton(
                  libelle: AppStrings.propositionsRefuser,
                  libelleAnnonce: AppStrings.propositionsRefuserCreneau(
                    libelleCreneau,
                  ),
                  // Le glyphe de l'état « Refusé ». Un sens, un glyphe.
                  icone: Icons.cancel,
                  // **Pas `danger`** : le vermillon appartient à l'état qui
                  // résultera, pas au bouton qui y mène. Le seul rouge du
                  // parcours est la confirmation de la feuille de refus.
                  variante: PrimaryButtonVariante.secondaire,
                  pleineLargeur: true,
                  onPressed: raison == null ? onRefuser : null,
                  raisonDesactivation: raison,
                  // Les deux boutons partagent la raison : le premier
                  // l'écrit, le second se contente de l'annoncer.
                  raisonVisible: false,
                );

                // **L'asymétrie change de moyen, pas de sens.** Côte à côte,
                // « Accepter » prend trois cinquièmes de la largeur ; empilés,
                // il prend la première place, celle où le pouce tombe. Le
                // produit sait quelle réponse il espère dans les deux cas
                // (`design/021 § 6.2`).
                if (contraintes.maxWidth < largeurCoteACote) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      accepter,
                      const SizedBox(height: AppSpacing.entreCibles),
                      refuser,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Trois cinquièmes pour la réponse que la donnée prédit.
                    Expanded(flex: 3, child: accepter),
                    const SizedBox(width: AppSpacing.entreCibles),
                    Expanded(flex: 2, child: refuser),
                  ],
                );
              },
            ),
          ),
        ],
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
