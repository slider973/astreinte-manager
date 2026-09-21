import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/planning_caserne.dart';
import '../../domain/planning_caserne_providers.dart';
import 'barre_mois.dart';
import 'bloc_attente_validation.dart';
import 'journee_caserne.dart';
import 'squelette_astreintes.dart';

/// **« La caserne »** — le planning du mois, jour après jour, avec les noms.
///
/// Pas une grille à sept colonnes : « Camille G. » fait 68 dp en `corps` et une
/// case du calendrier de « Mes astreintes » en fait 45,7 sur un téléphone de
/// 360 (`design/023 § 3`). Le mot « calendrier » du ticket est tenu par **le
/// mois entier, dans l'ordre**, ce qu'un calendrier est.
class VuePlanningCaserne extends StatelessWidget {
  const VuePlanningCaserne({
    required this.etat,
    required this.onMois,
    required this.onRafraichir,
    required this.onVersMoi,
    super.key,
  });

  final EtatPlanningCaserne etat;

  /// Va au mois demandé.
  final ValueChanged<MoisPlanning> onMois;

  final Future<void> Function() onRafraichir;

  /// L'action de l'état vide : il n'y a pas de planning à lire, il y a
  /// peut-être ses propres astreintes.
  final VoidCallback onVersMoi;

  @override
  Widget build(BuildContext context) {
    // Aucun planning publié dans cette caserne : il n'y a pas de mois à
    // choisir, donc pas de barre de mois non plus.
    if (etat.aucunPlanning) {
      return _Defilable(
        onRafraichir: onRafraichir,
        child: EmptyState(
          titre: AppStrings.planningCaserneAucunTitre,
          texte: AppStrings.planningCaserneAucunTexte,
          icone: Icons.event_busy_outlined,
          libelleAction: AppStrings.planningCaserneAucunAction,
          onAction: onVersMoi,
        ),
      );
    }

    final precedent = etat.precedent;
    final suivant = etat.suivant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
            child: BarreMois(
              libelle: etat.affiche?.libelle ?? '',
              onPrecedent: precedent == null ? null : () => onMois(precedent),
              onSuivant: suivant == null ? null : () => onMois(suivant),
              libellePrecedent: AppStrings.astreintesMoisPrecedent,
              libelleSuivant: AppStrings.astreintesMoisSuivant,
              raisonPrecedent: AppStrings.planningCaserneMoisAvantDebut,
              raisonSuivant: AppStrings.planningCaserneMoisApresFin,
            ),
          ),
        ),
        Expanded(child: _contenu(context)),
      ],
    );
  }

  Widget _contenu(BuildContext context) {
    final planning = etat.planning;

    if (planning == null) {
      if (etat.introuvable) {
        return _Defilable(
          onRafraichir: onRafraichir,
          child: EmptyState.erreur(
            titre: AppStrings.planningCaserneIntrouvableTitre,
            texte: AppStrings.planningCaserneIntrouvableTexte,
            onAction: onRafraichir,
          ),
        );
      }
      // Une lecture qui échoue **sans rien à montrer pour ce mois** : l'écran
      // n'a rien à dire d'autre que ce qui manque.
      if (etat.echec case final String echec) {
        return _Defilable(
          onRafraichir: onRafraichir,
          child: EmptyState.erreur(
            texte: echec,
            onAction: onRafraichir,
          ),
        );
      }
      return const SquelettePlanningCaserne();
    }

    return _Registre(
      planning: planning,
      onRafraichir: onRafraichir,
      onVersMoi: onVersMoi,
    );
  }
}

/// Le registre du mois : un bloc par journée, **virtualisé**.
///
/// Un mois validé porte jusqu'à trente et une journées de deux créneaux, et
/// chaque créneau jusqu'à cinquante noms (`required_*` va jusqu'à 50). Un
/// `Column` dans un `SingleChildScrollView` les construirait toutes à chaque
/// image.
class _Registre extends StatelessWidget {
  const _Registre({
    required this.planning,
    required this.onRafraichir,
    required this.onVersMoi,
  });

  final PlanningCaserne planning;
  final Future<void> Function() onRafraichir;
  final VoidCallback onVersMoi;

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    // Le bloc d'attente est le **premier élément de la liste**, pas un en-tête
    // figé : il appartient au mois affiché, il défile avec lui.
    final entete = planning.complet ? 0 : 1;
    final vide = planning.vide;

    return _Defilable(
      onRafraichir: onRafraichir,
      liste: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.xxl),
        itemCount: entete + (vide ? 1 : planning.journees.length),
        itemBuilder: (BuildContext context, int index) {
          if (entete == 1 && index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.lg),
              child: BlocAttenteValidation(),
            );
          }
          if (vide) {
            return ConstrainedBox(
              // Un **minimum**, jamais une hauteur figée : l'état vide grandit
              // avec l'échelle de texte au lieu de déborder.
              constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: planning.complet
                  ? const EmptyState(
                      titre: AppStrings.planningCaserneMoisVideTitre,
                      texte: AppStrings.planningCaserneMoisVideTexte,
                      icone: Icons.event_busy_outlined,
                    )
                  : EmptyState(
                      titre: AppStrings.planningCaserneSansMoiTitre(
                        planning.mois.libelle,
                      ),
                      texte: AppStrings.planningCaserneSansMoiTexte,
                      icone: Icons.event_available_outlined,
                      libelleAction: AppStrings.planningCaserneAucunAction,
                      onAction: onVersMoi,
                    ),
            );
          }

          final journee = planning.journees[index - entete];
          return JourneeCaserneBloc(
            key: ValueKey<String>(
              '${planning.mois.cle}.${journee.date.day}',
            ),
            journee: journee,
            heures: planning.heures,
          );
        },
      ),
    );
  }
}

/// Le geste de tirage et la colonne bornée, partout pareil dans cette vue.
class _Defilable extends StatelessWidget {
  const _Defilable({required this.onRafraichir, this.child, this.liste})
    : assert(
        (child == null) != (liste == null),
        'Un contenu ou une liste, jamais les deux.',
      );

  final Future<void> Function() onRafraichir;

  /// Un contenu court, posé dans une liste défilable pour rester tirable :
  /// c'est ainsi qu'on vérifie qu'il n'y a vraiment rien.
  final Widget? child;

  final Widget? liste;

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return RefreshIndicator(
      onRefresh: onRafraichir,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child:
              liste ??
              ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.xxl),
                children: <Widget>[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.sizeOf(context).height * 0.5,
                    ),
                    child: child,
                  ),
                ],
              ),
        ),
      ),
    );
  }
}
