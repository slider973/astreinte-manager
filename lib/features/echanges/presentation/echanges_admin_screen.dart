import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/caserne/fait_caserne_ecran.dart';
import '../../../core/fraicheur/couche_fraicheur.dart';
import '../../../core/fraicheur/fraicheur.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/destinations.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../astreintes/domain/astreintes_providers.dart';
import '../../membres/domain/membres_providers.dart';
import '../domain/echange.dart';
import '../domain/echanges_providers.dart';
import '../domain/filtre_echanges.dart';
import 'widgets/ligne_echange_admin.dart';
import 'widgets/panneau_decision_echange.dart';

/// **La file des échanges** de l'administrateur (`design/073 § 8`).
///
/// Trois filtres dans l'adresse — « À valider » par défaut, « En attente d'un
/// collègue », « Terminés » (trente jours) —, une ligne par demande, et le
/// panneau de décision : à droite en `expanded` et `large`, la première ligne
/// à valider ouverte d'office ; en feuille en dessous.
///
/// L'écran n'est pas filtré par mois : un échange se juge à la garde.
class EchangesAdminScreen extends ConsumerStatefulWidget {
  const EchangesAdminScreen({required this.filtre, super.key});

  final FiltreEchanges filtre;

  @override
  ConsumerState<EchangesAdminScreen> createState() =>
      _EchangesAdminScreenState();
}

class _EchangesAdminScreenState extends ConsumerState<EchangesAdminScreen>
    with FraicheurEcran<EchangesAdminScreen> {
  String? _selection;

  @override
  Set<Donnee> get donneesAffichees => const <Donnee>{Donnee.echanges};

  void _relire() =>
      unawaited(ref.read(echangesControllerProvider.notifier).rafraichir());

  List<Echange> _liste(EtatEchanges etat) => switch (widget.filtre) {
    FiltreEchanges.aValider => etat.aValider,
    FiltreEchanges.enAttente => etat.enAttente,
    FiltreEchanges.termines => etat.termines,
  };

  bool _volet(BuildContext context) =>
      AppWindowClass.of(context).supporteDeuxVolets;

  void _ouvrir(Echange echange) {
    setState(() => _selection = echange.id);
    if (_volet(context)) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (BuildContext feuille) => SafeArea(
          top: false,
          child: PanneauDecisionEchange(
            echangeId: echange.id,
            onDecide: () => Navigator.of(feuille).pop(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(estAdminCaserneProvider);
    final destinations = ref.watch(destinationsProvider);
    final asynchrone = ref.watch(echangesControllerProvider);
    final etat = asynchrone.value;
    final liste = etat == null ? const <Echange>[] : _liste(etat);

    // En deux volets, la première ligne « À valider » est ouverte d'office,
    // et la ligne suivante prend la place d'une demande tranchée.
    var ouverte = _selection;
    if (ouverte != null && !liste.any((Echange e) => e.id == ouverte)) {
      ouverte = null;
    }
    if (ouverte == null &&
        _volet(context) &&
        widget.filtre == FiltreEchanges.aValider &&
        liste.isNotEmpty) {
      ouverte = liste.first.id;
    }

    return AppScaffold(
      titre: AppStrings.echangesTitre,
      destinations: destinations,
      indexSelectionne: indexDestination(
        destinations,
        AppRoutes.planningAdminName,
      ),
      onDestination: (int index) =>
          allerVersDestination(context, destinations, index),
      actions: <Widget>[
        IconButton(
          onPressed: _relire,
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.echangesRafraichir,
        ),
      ],
      banniere: faitCaserneEcran(context, ref)?.banniere,
      panneauLateral: admin && _volet(context)
          ? (ouverte == null
                ? (liste.isEmpty
                      ? null
                      : const Center(
                          child: EmptyState(
                            titre: AppStrings.echangesTitre,
                            texte: AppStrings.echangesVoletVide,
                            icone: Icons.touch_app_outlined,
                          ),
                        ))
                : PanneauDecisionEchange(
                    key: ValueKey<String>('decision-$ouverte'),
                    echangeId: ouverte,
                    etendu: true,
                    onDecide: () => setState(() => _selection = null),
                  ))
          : null,
      child: !admin
          ? const EmptyState(
              titre: AppStrings.echangesTitre,
              texte: AppStrings.echangesReserveAdmin,
              icone: Icons.lock_outline,
            )
          : _corps(asynchrone, etat, liste, ouverte),
    );
  }

  Widget _corps(
    AsyncValue<EtatEchanges> asynchrone,
    EtatEchanges? etat,
    List<Echange> liste,
    String? ouverte,
  ) {
    final marge = AppWindowClass.of(context).margePage;
    final maintenant = ref.watch(horlogeAstreintesProvider)();

    final Widget contenu;
    if (etat == null && !asynchrone.hasError) {
      contenu = const _Squelette();
    } else if (asynchrone.hasError && (etat?.vide ?? true)) {
      contenu = EmptyState.erreur(
        texte: AppStrings.echangesErreur,
        onAction: _relire,
      );
    } else if (liste.isEmpty) {
      contenu = switch (widget.filtre) {
        FiltreEchanges.aValider => const EmptyState(
          titre: AppStrings.echangesVideAValiderTitre,
          texte: AppStrings.echangesVideAValiderTexte,
          icone: Icons.how_to_reg,
        ),
        FiltreEchanges.enAttente => const EmptyState(
          titre: AppStrings.echangesVideTitre,
          texte: AppStrings.echangesVideEnAttente,
          icone: Icons.hourglass_empty,
        ),
        FiltreEchanges.termines => const EmptyState(
          titre: AppStrings.echangesVideTitre,
          texte: AppStrings.echangesVideTermines,
          icone: Icons.history,
        ),
      };
    } else {
      contenu = RefreshIndicator(
        onRefresh: () =>
            ref.read(echangesControllerProvider.notifier).rafraichir(),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            marge,
            AppSpacing.md,
            marge,
            AppSpacing.xl,
          ),
          itemCount: liste.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: AppSpacing.entreCibles),
          itemBuilder: (BuildContext context, int index) {
            final echange = liste[index];
            return LigneEchangeAdmin(
              key: ValueKey<String>(echange.id),
              echange: echange,
              maintenant: maintenant,
              choisie: _volet(context) && echange.id == ouverte,
              onOuvrir: () => _ouvrir(echange),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: marge),
          child: _Filtres(
            filtre: widget.filtre,
            etat: etat,
            onChoisir: (FiltreEchanges f) {
              setState(() => _selection = null);
              context.go(AppRoutes.echangesAdminFiltre(f));
            },
          ),
        ),
        Expanded(child: contenu),
      ],
    );
  }
}

/// Les trois filtres, chacun avec son compte, dans la forme des filtres du
/// suivi. Ils s'enroulent à grande échelle de texte.
class _Filtres extends StatelessWidget {
  const _Filtres({
    required this.filtre,
    required this.etat,
    required this.onChoisir,
  });

  final FiltreEchanges filtre;
  final EtatEchanges? etat;
  final ValueChanged<FiltreEchanges> onChoisir;

  @override
  Widget build(BuildContext context) {
    final aValider = etat?.aValider.length ?? 0;
    final enAttente = etat?.enAttente.length ?? 0;
    String libelle(FiltreEchanges f) => switch (f) {
      FiltreEchanges.aValider => AppStrings.echangesFiltreAValider(aValider),
      FiltreEchanges.enAttente => AppStrings.echangesFiltreEnAttente(enAttente),
      FiltreEchanges.termines => AppStrings.echangesFiltreTermines,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.entreCibles,
        runSpacing: AppSpacing.entreCibles,
        children: <Widget>[
          for (final f in FiltreEchanges.values)
            Semantics(
              label: f == FiltreEchanges.aValider
                  ? AppStrings.echangesAnnonceFiltre(aValider)
                  : null,
              child: ChoiceChip(
                selected: f == filtre,
                showCheckmark: true,
                onSelected: (bool _) => onChoisir(f),
                label: Text(libelle(f), style: AppTextStyles.corps),
              ),
            ),
        ],
      ),
    );
  }
}

class _Squelette extends StatelessWidget {
  const _Squelette();

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;
    return LoadingSkeleton(
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: marge,
          vertical: AppSpacing.md,
        ),
        children: const <Widget>[
          SkeletonBloc(hauteur: 72),
          SizedBox(height: AppSpacing.entreCibles),
          SkeletonBloc(hauteur: 72),
          SizedBox(height: AppSpacing.entreCibles),
          SkeletonBloc(hauteur: 72),
        ],
      ),
    );
  }
}
