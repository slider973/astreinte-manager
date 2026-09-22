import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/deconnexion.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_divider.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/caserne_supervisee.dart';
import '../domain/superadmin_providers.dart';
import 'widgets/bloc_caserne.dart';
import 'widgets/feuille_creer_caserne.dart';
import 'widgets/feuille_plannings_support.dart';
import 'widgets/feuille_saisie.dart';

/// `/superadmin` — l'écran de l'éditeur du produit.
///
/// Volontairement minimal : une liste de casernes, cinq faits par ligne, quatre
/// actions (`design/031-super-admin.md`). Ce n'est pas l'écran d'un client, et
/// il n'a pas de barre de navigation — l'éditeur n'est membre d'aucune caserne,
/// il a une URL.
///
/// La porte est gardée deux fois. Côté navigation par `redirectionAuth` ; côté
/// base par `is_super_admin()`, que chacune des quatre fonctions SQL redemande
/// (migration `0025`). Cet écran n'est donc **jamais** la seule protection :
/// quand le droit revient faux, il affiche une phrase sobre le temps que le
/// routeur reprenne la main, et rien d'autre.
///
/// **Il porte sa sortie** (ticket 053). N'avoir ni barre de navigation ni
/// profil lui avait coûté la déconnexion : la garde le dispense justement
/// d'« Aucune caserne », le seul écran qui la lui offrait
/// (`core/router/auth_redirection.dart`). Le compte le plus sensible du
/// produit était donc le seul dont on ne pouvait pas sortir sans vider le
/// stockage du navigateur.
class SuperAdminScreen extends ConsumerWidget {
  const SuperAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autorise = ref.watch(estSuperAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.superAdminTitre),
        actions: <Widget>[
          if (autorise.value ?? false)
            IconButton(
              onPressed: () =>
                  ref.read(superAdminControllerProvider.notifier).relire(),
              icon: const Icon(Icons.refresh),
              tooltip: AppStrings.superAdminRelire,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: switch (autorise) {
                AsyncData<bool>(value: false) => const _Reserve(),
                _ => const _Liste(),
              },
            ),
            // **Hors de la liste, donc visible sans défilement**, et présent
            // dans les quatre états de l'écran — squelette, erreur, liste
            // vide, droit refusé. Un écran dont la liste échoue doit rester
            // quittable.
            const _PiedDeconnexion(),
          ],
        ),
      ),
    );
  }
}

/// Le droit est revenu faux : se tromper d'URL n'est pas une faute, donc pas de
/// message d'erreur. Le routeur ramène à l'accueil au tick suivant.
class _Reserve extends StatelessWidget {
  const _Reserve();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.xl),
    child: EmptyState(
      titre: AppStrings.superAdminReserveTitre,
      texte: AppStrings.superAdminReserveTexte,
      icone: Icons.lock_outline,
    ),
  );
}

/// La sortie de l'écran : même bouton et même place que sur « Aucune
/// caserne » — ancrée en bas, pleine largeur, à la marge de page.
///
/// `BoutonDeconnexion` et lui seul : c'est lui qui passe par `OubliLocal`
/// avant de fermer la session (`core/session/deconnexion.dart`), et la règle
/// des caches locaux vaut ici plus qu'ailleurs — une session d'éditeur laissée
/// sur un téléphone prêté ouvre le parc entier.
///
/// Le filet est celui de la barre de navigation basse (`core/widgets/
/// app_scaffold.dart`) : décoratif, 1 dp, il dit seulement où s'arrête ce qui
/// défile. Sans lui, la dernière ligne de caserne glisserait sous le bouton
/// sans limite lisible.
class _PiedDeconnexion extends StatelessWidget {
  const _PiedDeconnexion();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const AppDivider(),
      Padding(
        padding: EdgeInsets.all(AppWindowClass.of(context).margePage),
        child: const BoutonDeconnexion(),
      ),
    ],
  );
}

class _Liste extends ConsumerWidget {
  const _Liste();

  SuperAdminController _controleur(WidgetRef ref) =>
      ref.read(superAdminControllerProvider.notifier);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(superAdminControllerProvider);
    final marge = AppWindowClass.of(context).margePage;

    return switch (etat) {
      AsyncLoading<VueSuperAdmin>(hasValue: false) => const _Squelette(),
      AsyncError<VueSuperAdmin>() => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: EmptyState.erreur(
          texte: AppStrings.superAdminErreurTexte,
          onAction: () => _controleur(ref).relire(),
        ),
      ),
      _ => _Contenu(vue: etat.requireValue, marge: marge),
    };
  }
}

class _Squelette extends StatelessWidget {
  const _Squelette();

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < 3; i++) ...<Widget>[
            const SkeletonBloc(hauteur: 148),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    ),
  );
}

class _Contenu extends ConsumerWidget {
  const _Contenu({required this.vue, required this.marge});

  final VueSuperAdmin vue;
  final double marge;

  SuperAdminController _controleur(WidgetRef ref) =>
      ref.read(superAdminControllerProvider.notifier);

  /// Annonce un résultat. Aucune action ne réussit en silence.
  static void _annoncer(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _creer(BuildContext context, WidgetRef ref) async {
    final saisie = await afficherCreerCaserne(context);
    if (saisie == null || !context.mounted) return;

    final creee = await _controleur(
      ref,
    ).creerCaserne(nom: saisie.nom, fuseau: saisie.fuseau);
    if (creee == null || !context.mounted) return;

    _annoncer(context, AppStrings.superAdminCaserneCreee(creee.nom));

    // Une caserne sans administrateur est un cul-de-sac : on enchaîne, plutôt
    // que de laisser l'éditeur y arriver par distraction.
    await _inviter(context, ref, creee);
  }

  Future<void> _inviter(
    BuildContext context,
    WidgetRef ref,
    CaserneSupervisee caserne,
  ) async {
    final email = await afficherFeuilleSaisie(
      context: context,
      titre: AppStrings.superAdminInviterTitre,
      aide: AppStrings.superAdminInviterAide(caserne.nom),
      libelleChamp: AppStrings.superAdminChampEmail,
      exemple: AppStrings.superAdminChampEmailExemple,
      libelleValider: AppStrings.superAdminInviterValider,
      erreurSiVide: AppStrings.superAdminEchecInvitation,
      clavier: TextInputType.emailAddress,
      icone: Icons.send_outlined,
    );
    if (email == null || !context.mounted) return;

    final resultat = await _controleur(
      ref,
    ).inviterAdministrateur(stationId: caserne.id, email: email);
    if (context.mounted) _annoncer(context, resultat.message);
  }

  Future<void> _basculerSuspension(
    BuildContext context,
    WidgetRef ref,
    CaserneSupervisee caserne,
  ) async {
    // Réactiver ne détruit rien et se refait d'un geste : pas de confirmation,
    // pas de raison demandée à l'écran — la fonction en exige une, l'écran la
    // compose. Suspendre, si.
    if (caserne.suspendue) {
      final resultat = await _controleur(ref).definirSuspension(
        stationId: caserne.id,
        suspendue: false,
        raison: AppStrings.superAdminReactivationRaison,
      );
      if (context.mounted) _annoncer(context, resultat.message);
      return;
    }

    final raison = await afficherFeuilleSaisie(
      context: context,
      titre: AppStrings.superAdminSuspendreTitre(caserne.nom),
      aide: AppStrings.superAdminSuspendreAide,
      libelleChamp: AppStrings.superAdminChampRaison,
      exemple: AppStrings.superAdminChampRaisonSuspension,
      libelleValider: AppStrings.superAdminSuspendreValider,
      erreurSiVide: AppStrings.superAdminRefusRaison,
      longueurMinimale: 10,
      lignes: 2,
      icone: Icons.pause_circle_outline,
      variante: PrimaryButtonVariante.danger,
    );
    if (raison == null || !context.mounted) return;

    final resultat = await _controleur(
      ref,
    ).definirSuspension(stationId: caserne.id, suspendue: true, raison: raison);
    if (context.mounted) _annoncer(context, resultat.message);
  }

  Future<void> _consulter(
    BuildContext context,
    WidgetRef ref,
    CaserneSupervisee caserne,
  ) async {
    final raison = await afficherFeuilleSaisie(
      context: context,
      titre: AppStrings.superAdminSupportTitre(caserne.nom),
      aide: AppStrings.superAdminSupportAide,
      mention: AppStrings.superAdminSupportPortee,
      libelleChamp: AppStrings.superAdminChampRaison,
      exemple: AppStrings.superAdminChampRaisonExemple,
      libelleValider: AppStrings.superAdminSupportValider,
      erreurSiVide: AppStrings.superAdminRefusRaison,
      longueurMinimale: 10,
      lignes: 2,
      icone: Icons.fact_check_outlined,
    );
    if (raison == null || !context.mounted) return;

    final plannings = await _controleur(
      ref,
    ).consulterPlannings(stationId: caserne.id, raison: raison);
    if (plannings == null || !context.mounted) return;

    await afficherPlanningsSupport(
      context: context,
      caserne: caserne.nom,
      plannings: plannings,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final echec = vue.echec;

    return Column(
      children: <Widget>[
        // La raison du dernier refus reste à l'écran jusqu'au geste suivant :
        // un `SnackBar` disparaît, une raison de refus doit rester lisible.
        if (echec != null)
          AppBanner(variante: AppBannerVariante.erreur, texte: echec),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              marge,
              AppSpacing.lg,
              marge,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              Text(
                AppStrings.superAdminSousTitre,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                libelle: AppStrings.superAdminCreer,
                icone: Icons.add_business_outlined,
                chargement:
                    vue.actionEnCours == SuperAdminController.creationEnCours,
                onPressed: () => _creer(context, ref),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (vue.vide)
                const EmptyState(
                  titre: AppStrings.superAdminVideTitre,
                  texte: AppStrings.superAdminVideTexte,
                  icone: Icons.domain_outlined,
                )
              else
                for (final CaserneSupervisee caserne in vue.casernes)
                  BlocCaserne(
                    key: ValueKey<String>(caserne.id),
                    caserne: caserne,
                    enCours: vue.enCours(caserne.id),
                    onInviter: () => _inviter(context, ref, caserne),
                    onSuspension: () =>
                        _basculerSuspension(context, ref, caserne),
                    onConsulter: () => _consulter(context, ref, caserne),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
