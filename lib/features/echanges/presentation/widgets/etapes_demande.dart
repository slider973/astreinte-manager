import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/avatar_initiales.dart';
import '../../../../core/widgets/carre_creneau.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/choix_exclusif.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/entete_section.dart';
import '../../../../core/widgets/loading_skeleton.dart';
import '../../../../core/widgets/rangee_garde.dart';
import '../../../astreintes/domain/astreinte.dart';
import '../../domain/demande_echange.dart';
import '../../domain/echange.dart';
import '../../domain/echanges_providers.dart';
import '../etat_echange.dart';

/// Au-delà de ce nombre de collègues, un champ de recherche précède la liste
/// (`design/073 § 5.1`).
const int seuilRecherche = 12;

class _TitreEtape extends StatelessWidget {
  const _TitreEtape(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: AppSpacing.auDessusTitre,
      bottom: AppSpacing.md,
    ),
    child: Semantics(
      header: true,
      child: Text(texte, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

/// **Étape 1 — « À qui ? »** : un collègue, ou toute la caserne.
class EtapeQui extends ConsumerStatefulWidget {
  const EtapeQui({
    required this.modeCollegue,
    required this.modeCaserne,
    required this.collegueId,
    required this.onCollegueMode,
    required this.onCaserne,
    required this.onCollegue,
    super.key,
  });

  final bool modeCollegue;
  final bool modeCaserne;
  final String? collegueId;
  final VoidCallback onCollegueMode;
  final VoidCallback onCaserne;
  final ValueChanged<Collegue> onCollegue;

  @override
  ConsumerState<EtapeQui> createState() => _EtapeQuiState();
}

class _EtapeQuiState extends ConsumerState<EtapeQui> {
  final TextEditingController _recherche = TextEditingController();

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collegues = ref.watch(colleguesEchangeProvider);
    final liste = collegues.value;
    final seul = liste != null && liste.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TitreEtape(AppStrings.echangeQuiTitre),
        ChoixExclusif(
          icone: Icons.person_outline,
          titre: AppStrings.echangeCollegue,
          aide: AppStrings.echangeCollegueAide,
          choisi: widget.modeCollegue,
          onChoisir: seul ? null : widget.onCollegueMode,
          raisonInerte: AppStrings.echangeSeul,
        ),
        const SizedBox(height: AppSpacing.entreCibles),
        ChoixExclusif(
          icone: Icons.groups_outlined,
          titre: AppStrings.echangeCaserne,
          aide: AppStrings.echangeCaserneAide,
          choisi: widget.modeCaserne,
          onChoisir: widget.onCaserne,
        ),
        if (widget.modeCollegue) ..._liste(collegues),
      ],
    );
  }

  List<Widget> _liste(AsyncValue<List<Collegue>> collegues) {
    final liste = collegues.value;
    if (liste == null) {
      if (collegues.hasError) {
        return <Widget>[
          const SizedBox(height: AppSpacing.lg),
          EmptyState.erreur(
            texte: AppStrings.echangeCollegueErreur,
            onAction: () => ref.invalidate(colleguesEchangeProvider),
          ),
        ];
      }
      return const <Widget>[
        SizedBox(height: AppSpacing.lg),
        _Fantomes(),
      ];
    }

    final q = _recherche.text.trim().toLowerCase();
    final filtres = q.isEmpty
        ? liste
        : <Collegue>[
            for (final c in liste)
              if (c.nom.toLowerCase().contains(q)) c,
          ];

    return <Widget>[
      const EnteteSection(
        titre: AppStrings.echangeCollegues,
        discret: true,
      ),
      if (liste.length > seuilRecherche) ...<Widget>[
        ChampTexte(
          libelle: AppStrings.echangeChercher,
          controleur: _recherche,
          clavier: TextInputType.name,
          icone: Icons.search,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (filtres.isEmpty)
        Text(
          AppStrings.echangeChercherVide(_recherche.text.trim()),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      for (final collegue in filtres)
        Padding(
          key: ValueKey<String>('collegue-${collegue.userId}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.entreCibles),
          child: ChoixExclusif(
            avantTitre: ExcludeSemantics(
              child: AvatarInitiales(nom: collegue.nom, taille: 32),
            ),
            titre: collegue.nom,
            choisi: collegue.userId == widget.collegueId,
            onChoisir: () => widget.onCollegue(collegue),
          ),
        ),
    ];
  }
}

/// **Étape 2 — « Céder ou échanger ? »** (collègue seulement).
class EtapeQuoi extends ConsumerWidget {
  const EtapeQuoi({
    required this.collegue,
    required this.echanger,
    required this.rendueId,
    required this.heures,
    required this.onCeder,
    required this.onEchanger,
    required this.onRendue,
    super.key,
  });

  final Collegue? collegue;
  final bool echanger;
  final String? rendueId;
  final HeuresAffichage heures;
  final VoidCallback onCeder;
  final VoidCallback onEchanger;
  final ValueChanged<GardeProposable> onRendue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = collegue;
    if (pair == null) return const _Fantomes();
    final gardes = ref.watch(gardesProposablesProvider(pair.userId));
    final aucune = gardes.value?.isEmpty ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TitreEtape(AppStrings.echangeQuoiTitre),
        ChoixExclusif(
          icone: Icons.redo,
          titre: AppStrings.echangeCeder,
          aide: AppStrings.echangeCederAide(pair.nom),
          choisi: !echanger,
          onChoisir: onCeder,
        ),
        const SizedBox(height: AppSpacing.entreCibles),
        ChoixExclusif(
          icone: Icons.swap_horiz,
          titre: AppStrings.echangeEchanger,
          aide: AppStrings.echangeEchangerAide(pair.nom),
          choisi: echanger && !aucune,
          onChoisir: aucune ? null : onEchanger,
          raisonInerte: AppStrings.echangeAucuneGarde(pair.nom),
        ),
        if (echanger && !aucune) ..._gardes(context, ref, pair, gardes),
      ],
    );
  }

  List<Widget> _gardes(
    BuildContext context,
    WidgetRef ref,
    Collegue pair,
    AsyncValue<List<GardeProposable>> gardes,
  ) {
    final liste = gardes.value;
    if (liste == null) {
      if (gardes.hasError) {
        return <Widget>[
          const SizedBox(height: AppSpacing.lg),
          EmptyState.erreur(
            texte: AppStrings.echangeGardesErreur,
            onAction: () => ref.invalidate(gardesProposablesProvider(pair.userId)),
          ),
        ];
      }
      return const <Widget>[SizedBox(height: AppSpacing.lg), _Fantomes()];
    }

    final plusieursMois = liste.map((GardeProposable g) => g.garde.cleMois).toSet().length > 1;
    final elements = <Widget>[
      EnteteSection(titre: AppStrings.echangeSesGardes(pair.nom), discret: true),
    ];
    String? mois;
    for (final garde in liste) {
      if (plusieursMois && garde.garde.cleMois != mois) {
        mois = garde.garde.cleMois;
        elements.add(
          EnteteSection(
            titre: AppStrings.moisNomEtAnnee(garde.jour.month, garde.jour.year),
            discret: true,
          ),
        );
      }
      final (debut, fin) = bornes(heures, garde.creneau);
      elements.add(
        Padding(
          key: ValueKey<String>('garde-${garde.attributionId}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.entreCibles),
          child: ChoixExclusif(
            avantTitre: ExcludeSemantics(
              child: CarreCreneau(creneau: garde.creneau),
            ),
            titre: '${gardeCourte(context, garde.garde)} · '
                '${AppStrings.astreintesIntervalle(debut, fin)}',
            libelleAnnonce: AppStrings.echangeRangeeSemantique(
              verbe: AppStrings.echangeTuPrends,
              jourEtDate: dateAvecJourSemaine(garde.jour),
              creneau: context.statuts.creneau(garde.creneau).libelle,
              debut: debut,
              fin: fin,
            ),
            choisi: garde.attributionId == rendueId,
            onChoisir: () => onRendue(garde),
          ),
        ),
      );
    }
    return elements;
  }
}

/// **Étape 3 — « Vérifie ta demande »** : un récapitulatif, rien d'éditable.
/// Cet écran **est** la confirmation : l'envoi est annulable.
class EtapeVerifier extends ConsumerWidget {
  const EtapeVerifier({
    required this.astreinte,
    required this.collegue,
    required this.rendue,
    required this.heures,
    super.key,
  });

  final Astreinte astreinte;

  /// `null` pour une demande à la caserne.
  final Collegue? collegue;
  final GardeProposable? rendue;
  final HeuresAffichage heures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reglages =
        ref.watch(reglagesEchangeProvider).value ?? ReglagesEchange.defaut;
    final garde = gardeDe(astreinte);
    final rendueGarde = rendue?.garde;
    final echeance = reglages.echeance(<GardeEchange>[garde, ?rendueGarde]);
    final (debut, fin) = bornes(heures, garde.creneau);
    final nom = collegue?.nom;

    final validation = reglages.validationAuto
        ? (nom == null
              ? AppStrings.echangeInfoAutoCaserne
              : AppStrings.echangeInfoAuto(nom))
        : (nom == null
              ? AppStrings.echangeInfoValidationCaserne
              : AppStrings.echangeInfoValidation(nom));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TitreEtape(AppStrings.echangeVerifierTitre),
        CarteDouce(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              RangeeGarde(
                verbe: AppStrings.echangeTuDonnes,
                sens: SensGarde.donne,
                jour: garde.jour,
                creneau: garde.creneau,
                debut: debut,
                fin: fin,
              ),
              if (rendueGarde != null) ...<Widget>[
                const AppDivider(),
                () {
                  final (d, f) = bornes(heures, rendueGarde.creneau);
                  return RangeeGarde(
                    verbe: AppStrings.echangeTuPrends,
                    sens: SensGarde.prend,
                    jour: rendueGarde.jour,
                    creneau: rendueGarde.creneau,
                    debut: d,
                    fin: f,
                  );
                }(),
              ],
              const AppDivider(),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    AppStrings.echangeA,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Text(
                      nom ?? AppStrings.echangeLesDisponibles,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Le patron « bloc dans le contenu » du 023 : fond d'information,
        // icône, sans filet coloré à gauche.
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.statuts.planning(PlanningEtat.publie).fond,
            borderRadius: AppRadius.controleRadius,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: AppTouch.icone,
                  color: context.statuts.planning(PlanningEtat.publie).encre,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '$validation\n${AppStrings.echangeExpireLe(dateAvecJourSemaine(echeance), heureMinute(echeance))}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.statuts.planning(PlanningEtat.publie).encre,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Trois lignes fantômes pendant qu'une liste arrive.
class _Fantomes extends StatelessWidget {
  const _Fantomes();

  @override
  Widget build(BuildContext context) => const LoadingSkeleton(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SkeletonLigne(hauteur: ChoixExclusif.hauteurMin),
        SizedBox(height: AppSpacing.entreCibles),
        SkeletonLigne(hauteur: ChoixExclusif.hauteurMin),
        SizedBox(height: AppSpacing.entreCibles),
        SkeletonLigne(hauteur: ChoixExclusif.hauteurMin),
      ],
    ),
  );
}
