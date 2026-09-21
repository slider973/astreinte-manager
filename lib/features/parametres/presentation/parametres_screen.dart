import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/save_indicator.dart';
import '../../membres/domain/membres_providers.dart';
import '../domain/parametres_caserne.dart';
import '../domain/parametres_providers.dart';
import '../domain/validation_parametres.dart';
import 'widgets/feuille_surcharge.dart';
import 'widgets/formulaire_parametres.dart';

/// L'écran « Paramètres » de la destination Admin.
///
/// Les réglages de la caserne : nom, fuseau, heures d'affichage, effectif
/// requis et ses surcharges, jour limite de saisie, délais de relance.
///
/// **Un seul enregistrement, explicite.** Ces réglages forment un document
/// cohérent que la base valide d'un bloc (`stations_settings_valide`,
/// migration `0011`) ; un effectif enregistré à mi-saisie produirait un
/// planning faux. Le bouton est donc en fil d'actions, permanent, et dit ce
/// qu'il fait.
class ParametresScreen extends ConsumerStatefulWidget {
  const ParametresScreen({super.key});

  @override
  ConsumerState<ParametresScreen> createState() => _ParametresScreenState();
}

class _ParametresScreenState extends ConsumerState<ParametresScreen> {
  static const String _routeAdmin = 'admin';

  ParametresController get _controleur =>
      ref.read(parametresControllerProvider.notifier);

  void _relire() => unawaited(_controleur.relire());

  Future<void> _enregistrer() async {
    final resultat = await _controleur.enregistrer();
    if (!mounted) return;

    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(resultat.message),
          backgroundColor: resultat.reussi
              ? null
              : theme.colorScheme.errorContainer,
          showCloseIcon: true,
          closeIconColor: resultat.reussi
              ? null
              : theme.colorScheme.onErrorContainer,
        ),
      );
  }

  /// Ouvre la feuille d'une surcharge existante, ou d'un jour de semaine
  /// encore au défaut.
  Future<void> _modifierSurcharge(EtatParametres etat, String cle) async {
    final jour = JourSemaine.depuisCle(cle);
    final existante = etat.brouillon.surcharges
        .where((SurchargeEffectif s) => s.cle == cle)
        .firstOrNull;

    final choix = await afficherSurcharge(
      context: context,
      titre: AppStrings.parametresSurchargeTitre(
        existante?.libelle ?? jour?.libelle ?? cle,
      ),
      parametres: etat.brouillon,
      cle: cle,
      surcharge: existante,
      dateSaisie: jour == null,
      clesExistantes: _cles(etat),
    );
    if (choix == null) return;

    _controleur.modifier(_appliquer(etat.brouillon, cle, choix));
  }

  Future<void> _ajouterDate(EtatParametres etat) async {
    final choix = await afficherSurcharge(
      context: context,
      titre: AppStrings.parametresSurchargeAjouterDate,
      parametres: etat.brouillon,
      dateSaisie: true,
      clesExistantes: _cles(etat),
    );
    if (choix == null) return;

    _controleur.modifier(etat.brouillon.avecSurcharge(choix));
  }

  /// La feuille peut avoir changé la clé (une date corrigée) : l'ancienne
  /// ligne part, la nouvelle prend sa place.
  static ParametresCaserne _appliquer(
    ParametresCaserne brouillon,
    String ancienneCle,
    SurchargeEffectif choix,
  ) {
    final sans = brouillon.sansSurcharge(ancienneCle);
    return choix.estVide ? sans : sans.avecSurcharge(choix);
  }

  static Set<String> _cles(EtatParametres etat) => <String>{
    for (final SurchargeEffectif surcharge in etat.brouillon.surcharges)
      surcharge.cle,
  };

  void _versDestination(int index, List<AppDestination> destinations) {
    if (destinations[index].route == _routeAdmin) {
      // « Admin » ouvre la matrice du mois (ticket 016).
      context.goNamed(AppRoutes.planningAdminName);
      return;
    }
    context.goNamed(
      AppRoutes.accueilName,
      queryParameters: <String, String>{AppRoutes.parametreOnglet: '$index'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(estAdminCaserneProvider);
    final asynchrone = ref.watch(parametresControllerProvider);
    final destinations = AppDestination.pour(admin: admin);
    final indexAdmin = destinations.indexWhere(
      (AppDestination d) => d.route == _routeAdmin,
    );

    final etat = asynchrone.value;
    final echec = etat?.echecServeur;

    return AppScaffold(
      titre: AppStrings.parametresTitre,
      destinations: destinations,
      indexSelectionne: indexAdmin < 0 ? 0 : indexAdmin,
      onDestination: (int index) => _versDestination(index, destinations),
      actions: <Widget>[
        if (etat != null && etat.sync != SyncEtat.repos)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: SaveIndicator(
              etat: etat.sync,
              compact: true,
              onReessayer: etat.sync == SyncEtat.echec
                  ? () => unawaited(_enregistrer())
                  : null,
            ),
          ),
        if (admin)
          IconButton(
            onPressed: () => context.goNamed(AppRoutes.membresName),
            icon: const Icon(Icons.group_outlined),
            tooltip: AppStrings.parametresVersMembres,
          ),
        if (admin)
          IconButton(
            onPressed: () => context.goNamed(AppRoutes.periodesName),
            icon: const Icon(Icons.event_available_outlined),
            tooltip: AppStrings.periodesDepuisAdmin,
          ),
        if (admin)
          IconButton(
            onPressed: () => context.goNamed(AppRoutes.abonnementName),
            icon: const Icon(Icons.card_membership_outlined),
            tooltip: AppStrings.abonnementDepuisAdmin,
          ),
        IconButton(
          onPressed: _relire,
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.parametresRafraichir,
        ),
      ],
      // Le refus du serveur reste à l'écran tant que la saisie n'a pas bougé :
      // un `SnackBar` disparaît, et la raison du refus doit rester lisible.
      banniere: echec == null
          ? null
          : AppBanner(
              variante: AppBannerVariante.erreur,
              texte: echec,
              libelleAction: AppStrings.actionReessayer,
              onAction: () => unawaited(_enregistrer()),
            ),
      filActions: etat == null
          ? null
          : PrimaryButton(
              libelle: AppStrings.parametresEnregistrer,
              icone: Icons.check,
              chargement: etat.enregistrement,
              onPressed: etat.modifie ? () => unawaited(_enregistrer()) : null,
              raisonDesactivation: etat.modifie
                  ? null
                  : AppStrings.parametresAucuneModification,
            ),
      child: _corps(admin: admin, asynchrone: asynchrone, etat: etat),
    );
  }

  Widget _corps({
    required bool admin,
    required AsyncValue<EtatParametres?> asynchrone,
    required EtatParametres? etat,
  }) {
    if (!admin) {
      return const EmptyState(
        titre: AppStrings.parametresTitre,
        texte: AppStrings.parametresReserveAdmin,
        icone: Icons.lock_outline,
      );
    }

    if (etat == null) {
      return asynchrone.hasError
          ? EmptyState.erreur(
              texte: AppStrings.parametresErreurTexte,
              onAction: _relire,
            )
          : const _SqueletteParametres();
    }

    return FormulaireParametres(
      etat: etat,
      onChange: (ParametresCaserne brouillon, {ChampParametre? champ}) =>
          _controleur.modifier(brouillon, champ: champ),
      onToucher: _controleur.toucher,
      onModifierSurcharge: (String cle) =>
          unawaited(_modifierSurcharge(etat, cle)),
      onRetirerSurcharge: (String cle) =>
          _controleur.modifier(etat.brouillon.sansSurcharge(cle)),
      onAjouterDate: () => unawaited(_ajouterDate(etat)),
    );
  }
}

/// L'ossature des six sections, jamais une roue au milieu de l'écran.
class _SqueletteParametres extends StatelessWidget {
  const _SqueletteParametres();

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return LoadingSkeleton(
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: marge,
          vertical: AppSpacing.lg,
        ),
        children: <Widget>[
          const SkeletonLigne(largeur: 240, hauteur: AppSpacing.xl),
          const SizedBox(height: AppSpacing.xl),
          for (int section = 0; section < 4; section++) ...<Widget>[
            const SkeletonLigne(largeur: 180),
            const SizedBox(height: AppSpacing.md),
            const SkeletonLigne(),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonLigne(largeur: 200),
            const SizedBox(height: AppSpacing.xl),
          ],
        ],
      ),
    );
  }
}
