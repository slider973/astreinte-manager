import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/caserne/fait_caserne_ecran.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/destinations.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../astreintes/domain/astreintes_providers.dart';
import '../../notifications/presentation/widgets/bouton_notifications.dart';
import '../../profil/presentation/widgets/bouton_compte.dart';
import '../../propositions/domain/propositions_providers.dart';
import '../domain/composition_accueil.dart';
import '../domain/tableau_bord.dart';
import 'widgets/bande_semaine.dart';
import 'widgets/bloc_dispos.dart';
import 'widgets/carte_jour.dart';
import 'widgets/entete_accueil.dart';
import 'widgets/ligne_proposition_accueil.dart';

/// **L'accueil du pompier, un tableau de bord** (ticket 064).
///
/// Il répond aux trois questions qu'on se pose entre deux activités, dans cet
/// ordre : quand est ma prochaine astreinte, qu'est-ce qu'on me demande,
/// ai-je saisi mes disponibilités. Rien d'autre.
///
/// **Il ne fait aucune requête à lui.** Tout ce qu'il affiche vient des
/// contrôleurs que les autres écrans lisent déjà — astreintes (027),
/// propositions (021), périodes et saisie (011) —, composé par
/// `tableauBordProvider`. Un tableau de bord qui redemanderait les mêmes
/// lignes sous un autre angle doublerait le coût de l'écran le plus ouvert du
/// produit.
class AccueilScreen extends ConsumerWidget {
  const AccueilScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(destinationsProvider);
    final classe = AppWindowClass.of(context);
    final maintenant = ref.watch(horlogeAstreintesProvider)();
    final tableau = ref.watch(tableauBordProvider);

    return AppScaffold(
      titre: AppStrings.accueilTitre,
      destinations: destinations,
      indexSelectionne: indexDestination(destinations, AppRoutes.accueilName),
      onDestination: (index) =>
          allerVersDestination(context, destinations, index),
      // **L'écran porte son propre en-tête** : la salutation, l'avatar et la
      // cloche. Une barre d'application au-dessus redirait « Accueil » à
      // trente points de « Bonsoir, Marie ».
      sansBarreApplication: true,
      // **La matière du monde du pompier** (`design/064 § 2`) : fond de page
      // `surface-container-low`, cartes en `surface`. Le Calendrier et les
      // Astreintes la prendront au chantier 064c.
      fondDoux: true,
      actionsEnTete: const <Widget>[BoutonNotifications(), BoutonCompte()],
      // **Le fait qui change tout ce qui est en dessous.** Une caserne
      // suspendue ou un essai qui s'achève se disait jusqu'ici sur le premier
      // écran du produit, qui était la saisie. C'est l'accueil désormais, et
      // il ne doit pas laisser découvrir la suspension deux écrans plus loin.
      banniere: faitCaserneEcran(context, ref)?.banniere,
      child: switch (tableau) {
        AsyncData<TableauBord>(:final value) => _Contenu(
          tableau: value,
          maintenant: maintenant,
          avecEntete: !classe.supporteDeuxVolets,
        ),
        AsyncError<TableauBord>() => EmptyState.erreur(
          texte: AppStrings.accueilErreurTexte,
          onAction: () => _relire(ref),
        ),
        _ => const _Squelette(),
      },
    );
  }

  /// Relit les deux sources. `invalidate` ne suffirait pas sur des contrôleurs
  /// non auto-disposés : ce sont leurs propres relectures qui savent garder
  /// l'écran pendant l'aller-retour.
  void _relire(WidgetRef ref) {
    unawaited(ref.read(astreintesControllerProvider.notifier).rafraichir());
    unawaited(ref.read(propositionsControllerProvider.notifier).rafraichir());
  }
}

class _Contenu extends ConsumerWidget {
  const _Contenu({
    required this.tableau,
    required this.maintenant,
    required this.avecEntete,
  });

  final TableauBord tableau;

  /// L'horloge de l'écran, déjà lue par son parent.
  final DateTime maintenant;

  /// L'en-tête de salutation vit dans le contenu sous `expanded`. Au-delà,
  /// c'est l'en-tête de travail du 061 qui titre, et il porte déjà l'avatar
  /// et la cloche.
  final bool avecEntete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marge = AppWindowClass.of(context).margePage;
    final dispos = tableau.dispos;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(astreintesControllerProvider.notifier).rafraichir();
        await ref.read(propositionsControllerProvider.notifier).rafraichir();
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              marge,
              AppSpacing.lg,
              marge,
              AppSpacing.xl,
            ),
            children: <Widget>[
              EnteteAccueil(maintenant: maintenant, avecActions: avecEntete),
              const SizedBox(height: AppSpacing.xl),

              _EnteteRangee(
                titre: AppStrings.accueilMesAstreintes,
                compte: tableau.astreintesAVenir,
                libelleAction: AppStrings.accueilToutVoirAstreintes,
                onAction: () => context.goNamed(AppRoutes.astreintesName),
              ),
              const SizedBox(height: AppSpacing.md),
              // **Une lecture en panne ne devient jamais un état vide.**
              // Affirmer « Aucune astreinte à venir » alors qu'on n'a rien pu
              // lire est le pire des deux mondes : c'est faux, et ça se
              // croit.
              if (tableau.echecAstreintes)
                EmptyState.erreur(
                  texte: AppStrings.accueilErreurAstreintes,
                  onAction: () => unawaited(
                    ref
                        .read(astreintesControllerProvider.notifier)
                        .rafraichir(),
                  ),
                )
              else if (!tableau.rangeeUtile)
                EmptyState(
                  titre: AppStrings.accueilVideAstreintesTitre,
                  texte: AppStrings.accueilVideAstreintesTexte,
                  icone: Icons.event_available_outlined,
                  libelleAction: AppStrings.accueilVideAstreintesAction,
                  onAction: () => context.goNamed(AppRoutes.calendrierName),
                )
              else
                _Rangee(
                  tableau: tableau,
                  maintenant: maintenant,
                  onRepondre: (_) => _ouvrirReponse(context),
                ),

              const SizedBox(height: AppSpacing.xl),
              _EnteteRangee(
                titre: AppStrings.accueilPropositionsSection,
                compte: tableau.propositions.length,
                libelleAction: AppStrings.accueilToutVoirPropositions,
                onAction: () => _ouvrirReponse(context),
              ),
              const SizedBox(height: AppSpacing.md),
              BandeSemaine(jours: tableau.semaine),
              const SizedBox(height: AppSpacing.md),
              if (tableau.echecPropositions)
                EmptyState.erreur(
                  texte: AppStrings.accueilErreurPropositions,
                  onAction: () => unawaited(
                    ref
                        .read(propositionsControllerProvider.notifier)
                        .rafraichir(),
                  ),
                )
              else if (tableau.propositions.isEmpty)
                const EmptyState(
                  titre: AppStrings.accueilVidePropositionsTitre,
                  texte: AppStrings.accueilVidePropositionsTexte,
                )
              else
                for (final proposition in tableau.propositions.take(
                  _propositionsMontrees,
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: LignePropositionAccueil(
                      key: ValueKey<String>(proposition.id),
                      proposition: proposition,
                      heures: tableau.heures,
                      maintenant: maintenant,
                      onOuvrir: () => _ouvrirReponse(context),
                    ),
                  ),

              if (dispos != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xl),
                Semantics(
                  header: true,
                  child: Text(
                    AppStrings.accueilDisponibilites,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                BlocDispos(
                  appel: dispos,
                  onSaisir: (cle) => context.goNamed(
                    AppRoutes.calendrierName,
                    queryParameters: <String, String>{
                      AppRoutes.parametreMois: cle,
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Trois au plus : au-delà, c'est une liste, et la liste a son écran.
  static const int _propositionsMontrees = 3;

  /// **Le parcours de réponse ne se dédouble pas.** L'écran des propositions
  /// porte les deux boutons, la feuille de refus, la réponse optimiste et le
  /// rattrapage d'une proposition disparue depuis le ticket 021 ; l'accueil
  /// l'ouvre, il ne le réécrit pas.
  static void _ouvrirReponse(BuildContext context) =>
      unawaited(context.pushNamed<void>(AppRoutes.propositionsName));
}

/// Le titre d'une rangée, son compte, et sa sortie.
class _EnteteRangee extends StatelessWidget {
  const _EnteteRangee({
    required this.titre,
    required this.compte,
    required this.libelleAction,
    required this.onAction,
  });

  final String titre;
  final int compte;

  /// Le nom annoncé de la sortie. « Tout voir » deux fois sur un écran ne se
  /// distingue pas à l'oreille.
  final String libelleAction;

  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Semantics(
          header: true,
          child: Text(
            AppStrings.accueilSectionCompte(titre, compte),
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      TextButton(
        onPressed: onAction,
        // Le mot lu est « Tout voir », le mot annoncé nomme la destination :
        // deux boutons du même nom sur un écran ne se distinguent pas à
        // l'oreille.
        child: Text(
          AppStrings.accueilToutVoir,
          semanticsLabel: libelleAction,
          maxLines: 1,
        ),
      ),
    ],
  );
}

/// La rangée horizontale de cartes.
class _Rangee extends StatelessWidget {
  const _Rangee({
    required this.tableau,
    required this.maintenant,
    required this.onRepondre,
  });

  final TableauBord tableau;
  final DateTime maintenant;
  final ValueChanged<CarteJour> onRepondre;

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return SizedBox(
      height: CarteJourVue.hauteur(context),
      // La liste déborde de la marge de page des deux côtés : une rangée
      // défilante qui s'arrêterait à la marge laisserait croire qu'elle est
      // finie. Le rembourrage la remet en place au repos.
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: marge),
        itemCount: tableau.cartes.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) {
          final carte = tableau.cartes[index];
          return CarteJourVue(
            key: ValueKey<String>(carte.cle),
            carte: carte,
            aujourdhui: maintenant,
            heures: tableau.heures,
            nomCaserne: tableau.nomCaserne,
            onRepondre: onRepondre,
          );
        },
      ),
    );
  }
}

/// L'ossature du contenu attendu, jamais une roue
/// (`DESIGN.md § Don't`).
class _Squelette extends StatelessWidget {
  const _Squelette();

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return LoadingSkeleton(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          marge,
          AppSpacing.lg,
          marge,
          AppSpacing.xl,
        ),
        children: <Widget>[
          const SkeletonLigne(largeur: 180, hauteur: AppSpacing.xxl),
          const SizedBox(height: AppSpacing.xl),
          const SkeletonLigne(largeur: 140),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: CarteJourVue.hauteur(context),
            // La même liste horizontale que la rangée réelle : un `Row` de
            // trois cartes de 144 déborde d'un téléphone de 390, et un
            // squelette qui déborde est un défaut avant même que les données
            // arrivent.
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) => const SizedBox(
                width: CarteJourVue.largeur,
                child: SkeletonBloc(hauteur: double.infinity),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SkeletonLigne(largeur: 140),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < 3; index++) ...<Widget>[
            const SkeletonBloc(hauteur: AppTouch.cible),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
