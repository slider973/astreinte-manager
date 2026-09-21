import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_divider.dart';
import '../../../core/widgets/barre_actions_basse.dart';
import '../../../core/widgets/entete_section.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/import_membres.dart';
import '../domain/invitation.dart';
import 'controllers/importer_controller.dart';
import 'widgets/bloc_format_fichier.dart';
import 'widgets/ligne_apercu_import.dart';
import 'widgets/rapport_invitations_vue.dart';

/// Importer des membres depuis un fichier tableur.
///
/// **Trois temps, une seule route.** Choisir, relire, rendre compte : l'écran
/// change de contenu sans changer d'adresse, comme le formulaire d'invitation
/// du ticket 006 devient son propre compte rendu. Le bouton retour du
/// navigateur ramène à « Membres » à n'importe lequel des trois.
class ImporterScreen extends ConsumerWidget {
  const ImporterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(importerControllerProvider);
    final marge = AppWindowClass.of(context).margePage;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.importTitre)),
      body: Column(
        children: <Widget>[
          ?_banniere(etat),
          Expanded(
            child: switch (etat.etape) {
              EtapeImport.choix => _Choix(etat: etat, marge: marge),
              EtapeImport.apercu => _Apercu(etat: etat, marge: marge),
              EtapeImport.rapport => _Rapport(etat: etat, marge: marge),
            },
          ),
          BarreActionsBasse(child: _Actions(etat: etat)),
        ],
      ),
    );
  }

  /// Une seule bannière à la fois, par ordre de priorité (`DESIGN.md`).
  ///
  /// L'erreur passe devant le budget : un refus du serveur est plus urgent
  /// qu'une prévision, et il la dément.
  ///
  /// **Le plafond n'est pas rouge**, et c'est une correction faite en voyant
  /// l'écran contre la base : ne pas pouvoir envoyer soixante courriels dans
  /// la même minute est la règle de la maison, pas une panne — `DESIGN.md
  /// § Do` range « verrouillé », « suspendu » et « annulé » parmi les faits.
  /// Une caserne suspendue ou un droit perdu, eux, restent des erreurs : il y
  /// a quelque chose à réparer avant de réessayer.
  Widget? _banniere(EtatImport etat) {
    final refus = etat.erreurRequete;
    if (refus != null) {
      return AppBanner(
        variante: refus.erreur == ErreurInvitation.debitAtteint
            ? AppBannerVariante.attention
            : AppBannerVariante.erreur,
        texte: refus.message,
        detail: etat.reprendreApres == null
            ? null
            : AppStrings.importReprendreApres(
                formaterHeureDuJour(etat.reprendreApres!),
              ),
      );
    }

    // Pas de croix : « une bannière qui décrit un état persistant ne se ferme
    // pas » (`AppBanner`). Le refus décrit le fichier qu'on vient de déposer,
    // et il disparaît en en déposant un autre — ce que le bouton propose.
    final lecture = etat.erreurLecture;
    if (lecture != null) {
      return AppBanner(variante: AppBannerVariante.erreur, texte: lecture);
    }

    // Le plafond a coupé l'envoi, mais une partie est passée : un fait, pas une
    // panne. Jamais en rouge (`design/047-import-membres.md § 3`).
    if (etat.reprendreApres != null && etat.etape == EtapeImport.rapport) {
      return AppBanner(
        variante: AppBannerVariante.attention,
        texte: AppStrings.importReprendreApres(
          formaterHeureDuJour(etat.reprendreApres!),
        ),
      );
    }
    return null;
  }
}

/// Temps 1 — ce que le fichier doit contenir, et par où on le donne.
class _Choix extends StatelessWidget {
  const _Choix({required this.etat, required this.marge});

  final EtatImport etat;
  final double marge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(marge, AppSpacing.lg, marge, AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                AppStrings.importIntro,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const BlocFormatFichier(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Temps 2 — le fichier relu, ligne par ligne.
class _Apercu extends StatelessWidget {
  const _Apercu({required this.etat, required this.marge});

  final EtatImport etat;
  final double marge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apercu = etat.apercu!;
    final budget = apercu.budget;
    final ecartees = apercu.ecartees;

    // **Les écartées d'abord.** L'ordre de lecture suit la priorité de qui
    // regarde, pas l'ordre du tableur : sur soixante-trois lignes dont trois
    // fautives en fin de fichier, rien ne menait aux trois. Ce qui ne partira
    // pas est la seule chose à vérifier ; le reste, le compte du résumé le
    // dit déjà. L'ordre du fichier est conservé dans chaque section.
    //
    // Liste virtualisée : cinq cents lignes réglées ne se construisent pas
    // d'un bloc, et c'est le seul endroit de l'écran où la performance décide
    // d'une structure de widget. Deux sections, donc deux `SliverList` —
    // jamais une `Column` de cinq cents enfants.
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(marge, 0, marge, 0),
          sliver: SliverToBoxAdapter(
            child: _Colonne(
              enfants: <Widget>[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  apercu.nomFichier,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    AppStrings.importApercuResume(
                      lues: apercu.lignes.length,
                      aInviter: apercu.nombreAInviter,
                      ecartees: apercu.nombreEcartees,
                    ),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                if (budget != null && apercu.envoyable) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  _BanniereBudget(apercu: apercu, budget: budget),
                ],
                if (etat.envoiEnCours) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      AppStrings.importAvancement(
                        faites: etat.envoyees,
                        total: apercu.nombreAInviter,
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Rien d'écarté : une seule section, et l'aperçu garde exactement la
        // forme qu'il avait. Pas de titre orphelin pour annoncer un vide.
        if (ecartees.isEmpty)
          ..._section(AppStrings.importApercuTitre, apercu.lignes)
        else ...<Widget>[
          ..._section(AppStrings.importSectionEcartees, ecartees),
          ..._section(AppStrings.importSectionAInviter, apercu.aInviter),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }

  /// Un intitulé et ses lignes. Une section sans ligne ne s'ouvre pas.
  List<Widget> _section(String titre, List<LigneApercu> lignes) {
    if (lignes.isEmpty) return const <Widget>[];

    return <Widget>[
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: marge),
        sliver: SliverToBoxAdapter(
          child: _Colonne(enfants: <Widget>[EnteteSection(titre: titre)]),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: marge),
        sliver: SliverList.builder(
          itemCount: lignes.length,
          itemBuilder: (BuildContext context, int index) => _Colonne(
            enfants: <Widget>[
              LigneApercuImport(apercu: lignes[index]),
              const AppDivider(),
            ],
          ),
        ),
      ),
    ];
  }
}

/// La colonne du corps, bornée à 720 dp et centrée.
///
/// Chaque élément de la liste virtualisée la refait pour lui-même : un sliver
/// ne peut pas hériter d'une colonne posée plus haut, et borner le
/// `CustomScrollView` entier condamnerait la barre de défilement au milieu de
/// l'écran sur un poste de bureau.
class _Colonne extends StatelessWidget {
  const _Colonne({required this.enfants});

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: enfants,
        ),
      ),
    );
  }
}

/// L'annonce du budget d'envoi, avant que rien ne parte.
class _BanniereBudget extends StatelessWidget {
  const _BanniereBudget({required this.apercu, required this.budget});

  final ApercuImport apercu;
  final BudgetInvitations budget;

  @override
  Widget build(BuildContext context) {
    final maintenant = DateTime.now();
    final partiront = apercu.partiraMaintenant(budget);
    final reste = apercu.nombreAInviter - partiront;

    if (reste <= 0) {
      return AppBanner(
        variante: AppBannerVariante.information,
        texte: AppStrings.importBudgetToutPasse(partiront),
      );
    }

    final heure = formaterHeureDuJour(
      budget.ouvertureApresEpuisement(maintenant),
    );
    return AppBanner(
      variante: AppBannerVariante.attention,
      texte: partiront == 0
          ? AppStrings.importBudgetNul(heure)
          : AppStrings.importBudgetPartiel(
              maintenant: partiront,
              reste: reste,
              heure: heure,
            ),
    );
  }
}

/// Temps 3 — le compte rendu, dans le vocabulaire du ticket 006.
class _Rapport extends StatelessWidget {
  const _Rapport({required this.etat, required this.marge});

  final EtatImport etat;
  final double marge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ecartees = _phraseDesEcartees(etat.apercu);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(marge, AppSpacing.lg, marge, AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (ecartees != null) ...<Widget>[
                Text(
                  ecartees,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              RapportInvitationsVue(rapport: etat.rapport!),
            ],
          ),
        ),
      ),
    );
  }

  /// « 2 lignes du fichier n'ont rien reçu : 1 déjà membre, 1 adresse
  /// invalide. » Elles ne descendent pas dans « Résultat par adresse » : on n'y
  /// met que ce qui a été tenté.
  static String? _phraseDesEcartees(ApercuImport? apercu) {
    if (apercu == null || apercu.nombreEcartees == 0) return null;

    // Le motif est celui du verdict, et un verdict qui part n'en a pas : la
    // traduction vit sur l'énumération, où l'absence de motif est dite par
    // `null` plutôt que par une phrase prise au hasard.
    final motifs = <String>[
      for (final MapEntry<VerdictApercu, int> entree
          in apercu.ecarteesParMotif.entries)
        if (entree.key.motifEcartee case final String motif)
          AppStrings.importEcarteesMotif(entree.value, motif),
    ];
    return AppStrings.importEcarteesResume(
      apercu.nombreEcartees,
      motifs.join(', '),
    );
  }
}

/// Les sorties du bas, différentes à chacun des trois temps.
class _Actions extends ConsumerWidget {
  const _Actions({required this.etat});

  final EtatImport etat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controleur = ref.read(importerControllerProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (etat.etape) {
        EtapeImport.choix => <Widget>[
          PrimaryButton(
            libelle: AppStrings.importChoisir,
            icone: Icons.upload_file_outlined,
            chargement: etat.lectureEnCours,
            onPressed: () => unawaited(controleur.choisirFichier()),
          ),
          const SizedBox(height: AppSpacing.entreCibles),
          _BoutonExemple(controleur: controleur),
        ],
        EtapeImport.apercu => <Widget>[
          PrimaryButton(
            libelle: AppStrings.importEnvoyer(etat.apercu?.nombreAInviter ?? 0),
            icone: Icons.send_outlined,
            chargement: etat.envoiEnCours,
            raisonDesactivation: AppStrings.importRienAEnvoyer,
            onPressed: (etat.apercu?.envoyable ?? false)
                ? () => unawaited(controleur.lancer())
                : null,
          ),
          const SizedBox(height: AppSpacing.entreCibles),
          // Inerte pendant l'envoi, et il dit pourquoi. La raison n'est pas
          // écrite sous le bouton : la ligne d'avancement, juste au-dessus,
          // porte déjà l'information à l'écran. Elle reste annoncée aux
          // lecteurs d'écran, qui n'ont pas cette ligne sous les yeux.
          PrimaryButton(
            libelle: AppStrings.importChoisirAutre,
            variante: PrimaryButtonVariante.secondaire,
            icone: Icons.upload_file_outlined,
            raisonDesactivation: AppStrings.importEnvoiEnCours,
            raisonVisible: false,
            onPressed: etat.envoiEnCours ? null : controleur.recommencer,
          ),
        ],
        EtapeImport.rapport => <Widget>[
          if (etat.reprendreApres != null) ...<Widget>[
            PrimaryButton(
              libelle: AppStrings.importReprendre,
              variante: PrimaryButtonVariante.secondaire,
              icone: Icons.refresh,
              onPressed: controleur.recommencer,
            ),
            const SizedBox(height: AppSpacing.entreCibles),
          ],
          PrimaryButton(
            libelle: AppStrings.inviterTerminer,
            icone: Icons.arrow_back,
            onPressed: () => context.goNamed(AppRoutes.membresName),
          ),
        ],
      },
    );
  }
}

/// Le fichier d'exemple, produit sur place. Trois lignes fictives : assez pour
/// montrer la forme, pas assez pour qu'on soit tenté de les garder.
class _BoutonExemple extends StatelessWidget {
  const _BoutonExemple({required this.controleur});

  final ImporterController controleur;

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      libelle: AppStrings.importExemple,
      variante: PrimaryButtonVariante.secondaire,
      icone: Icons.download_outlined,
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final remis = await controleur.telechargerExemple();
        if (remis) return;
        messenger.showSnackBar(
          const SnackBar(content: Text(AppStrings.importExempleEchec)),
        );
      },
    );
  }
}
