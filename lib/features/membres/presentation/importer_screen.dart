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
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(marge),
              child: _Actions(etat: etat),
            ),
          ),
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

    // Liste virtualisée : cinq cents lignes réglées ne se construisent pas
    // d'un bloc, et c'est le seul endroit de l'écran où la performance décide
    // d'une structure de widget.
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(marge, 0, marge, 0),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.colonneMax,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
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
                    const EnteteSection(titre: AppStrings.importApercuTitre),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.xl),
          sliver: SliverList.builder(
            itemCount: apercu.lignes.length,
            itemBuilder: (BuildContext context, int index) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.colonneMax,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LigneApercuImport(apercu: apercu.lignes[index]),
                    const AppDivider(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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

    final motifs = <String>[
      for (final MapEntry<VerdictApercu, int> entree
          in apercu.ecarteesParMotif.entries)
        AppStrings.importEcarteesMotif(entree.value, _motif(entree.key)),
    ];
    return AppStrings.importEcarteesResume(
      apercu.nombreEcartees,
      motifs.join(', '),
    );
  }

  static String _motif(VerdictApercu verdict) => switch (verdict) {
    VerdictApercu.dejaMembre => AppStrings.importMotifDejaMembre,
    VerdictApercu.dejaInvitee => AppStrings.importMotifDejaInvitee,
    VerdictApercu.doublon => AppStrings.importMotifDoublon,
    VerdictApercu.adresseInvalide => AppStrings.importMotifAdresseInvalide,
    VerdictApercu.adresseAbsente => AppStrings.importMotifAdresseAbsente,
    VerdictApercu.aInviter ||
    VerdictApercu.aInviterSansNom => AppStrings.importMotifDejaMembre,
  };
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
            libelle: AppStrings.importEnvoyer(
              etat.apercu?.nombreAInviter ?? 0,
            ),
            icone: Icons.send_outlined,
            chargement: etat.envoiEnCours,
            raisonDesactivation: AppStrings.importRienAEnvoyer,
            onPressed: (etat.apercu?.envoyable ?? false)
                ? () => unawaited(controleur.lancer())
                : null,
          ),
          const SizedBox(height: AppSpacing.entreCibles),
          PrimaryButton(
            libelle: AppStrings.importChoisirAutre,
            variante: PrimaryButtonVariante.secondaire,
            icone: Icons.upload_file_outlined,
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
