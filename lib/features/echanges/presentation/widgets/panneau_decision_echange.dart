import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/caserne/caserne_providers.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/reseau/connectivite.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/entete_section.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/slot_chip.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../astreintes/domain/astreintes_providers.dart';
import '../../domain/charge_echange.dart';
import '../../domain/echange.dart';
import '../../domain/echanges_providers.dart';
import '../../domain/issue_echange.dart';
import '../etat_echange.dart';
import 'carte_echange.dart';
import 'confirmation_echange.dart';
import 'detail_echange.dart';

/// **Le panneau de décision** de l'administrateur (`design/073 § 8.3`) : les
/// gardes, la charge de chacun après l'échange, la disponibilité déclarée,
/// puis « Valider » ou « Refuser ».
///
/// Le volet de droite en `expanded` et `large`, une feuille en dessous. Il
/// lit la demande dans la liste courante : après une décision, la relecture
/// le met à jour.
class PanneauDecisionEchange extends ConsumerStatefulWidget {
  const PanneauDecisionEchange({
    required this.echangeId,
    super.key,
    this.onDecide,
    this.onFermer,
    this.etendu = false,
  });

  final String echangeId;

  /// Appelé après une décision partie : la file ouvre la ligne suivante.
  final VoidCallback? onDecide;
  final VoidCallback? onFermer;
  final bool etendu;

  @override
  ConsumerState<PanneauDecisionEchange> createState() =>
      _PanneauDecisionEchangeState();
}

class _PanneauDecisionEchangeState
    extends ConsumerState<PanneauDecisionEchange> {
  bool _occupe = false;
  IssueEchange? _issue;

  @override
  void didUpdateWidget(PanneauDecisionEchange ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.echangeId != widget.echangeId) _issue = null;
  }

  Future<void> _decider(Echange echange, {required bool valide}) async {
    final a = _nom(echange.demandeurNom);
    final b = _nom(echange.pairNom);
    final c1 = phraseGarde(echange.garde);
    final rendue = echange.gardeRendue;
    final demande = valide
        ? confirmerEchange(
            context,
            titre: echange.estEchange
                ? AppStrings.echangesConfirmerValiderEchange
                : AppStrings.echangesConfirmerValiderCession,
            texte: rendue == null
                ? AppStrings.echangesConfirmerCession(c1, a, b)
                : AppStrings.echangesConfirmerEchange(
                    c1,
                    b,
                    phraseGarde(rendue),
                    a,
                  ),
            libelleConfirmer: AppStrings.echangesValiderEtPrevenir,
            libelleRevenir: AppStrings.echangesRevenir,
            icone: Icons.verified,
          )
        : confirmerEchange(
            context,
            titre: AppStrings.echangesRefuserTitre,
            texte: AppStrings.echangesRefuserTexte(a, c1, b),
            libelleConfirmer: AppStrings.echangesRefuserEtPrevenir,
            libelleRevenir: AppStrings.echangesRevenir,
            icone: Icons.cancel,
            variante: PrimaryButtonVariante.danger,
            avecMotif: true,
          );
    final confirme = await demande;
    if (confirme == null || !mounted) return;

    setState(() {
      _occupe = true;
      _issue = null;
    });
    final issue = await ref
        .read(echangesControllerProvider.notifier)
        .decider(echange, valide: valide, motif: confirme.motif);
    if (!mounted) return;
    setState(() => _occupe = false);
    if (issue.ok) {
      annoncerEchange(context, issue.message);
      widget.onDecide?.call();
    } else {
      setState(() => _issue = issue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etat = ref.watch(echangesOuvertsProvider).value;
    final echange = etat?.parId(widget.echangeId);
    if (etat == null || echange == null) return const SizedBox.shrink();

    final maintenant = ref.watch(horlogeAstreintesProvider)();
    final enLigne = ref.watch(enLigneProvider).value ?? true;
    final lectureSeule = ref.watch(lectureSeuleCaserneProvider);
    final aTrancher = echange.statut == StatutEchange.accepteParPair;
    final charge = aTrancher
        ? ref.watch(chargeEchangeProvider(echange.id))
        : const AsyncValue<List<ChargePersonne>>.data(<ChargePersonne>[]);
    final issue = _issue;

    // La raison qui grise « Valider » : la caserne, le réseau, puis un
    // plafond d'astreintes que l'échange dépasserait — une règle bloquante
    // que la base refuserait de toute façon (`design/073 § 8.3`).
    String? depassement;
    for (final p in charge.value ?? const <ChargePersonne>[]) {
      if (p.depasseAstreintes) {
        depassement = AppStrings.echangesDepasseAstreintes(p.maxAstreintes!);
      }
    }
    final raisonRefus = lectureSeule
        ? AppStrings.echangesLectureSeuleRaison
        : !enLigne
        ? AppStrings.echangesHorsLigneRaison
        : null;
    final raisonValider = raisonRefus ?? depassement;

    final quand =
        '${dateAvecJourSemaine(echange.garde.jour)}, '
        '${context.statuts.creneau(echange.garde.creneau).libelle.toLowerCase()}';
    final titre = echange.estEchange
        ? AppStrings.echangesPanneauTitreEchange(quand)
        : AppStrings.echangesPanneauTitreCession(quand);

    return Semantics(
      container: true,
      label: titre,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(titre, style: theme.textTheme.titleLarge),
                  ),
                ),
                if (widget.onFermer != null)
                  IconButton(
                    onPressed: widget.onFermer,
                    icon: const Icon(Icons.close),
                    tooltip: AppStrings.echangeFermer,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge.descripteur(
                descripteurEchange(context, echange),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              ligneDetail(echange, moi: etat.moi, maintenant: maintenant),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (issue != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              AppBanner(
                variante: issue.ton == TonIssue.erreur
                    ? AppBannerVariante.erreur
                    : AppBannerVariante.information,
                texte: issue.message,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            PaireGardes(
              echange: echange,
              lecteur: LecteurEchange.admin,
              heures: heuresCaserne(ref),
            ),
            if (aTrancher) ...<Widget>[
              const EnteteSection(
                titre: AppStrings.echangesChargeTitre,
                discret: true,
              ),
              _Charge(echange: echange, charge: charge),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                libelle: echange.estEchange
                    ? AppStrings.echangesValider
                    : AppStrings.echangesValiderCession,
                icone: Icons.verified,
                chargement: _occupe,
                onPressed: raisonValider == null && !_occupe
                    ? () => unawaited(_decider(echange, valide: true))
                    : null,
                raisonDesactivation: raisonValider,
              ),
              const SizedBox(height: AppSpacing.entreCibles),
              PrimaryButton(
                libelle: AppStrings.echangesRefuser,
                icone: Icons.cancel,
                variante: PrimaryButtonVariante.secondaire,
                onPressed: raisonRefus == null && !_occupe
                    ? () => unawaited(_decider(echange, valide: false))
                    : null,
                raisonDesactivation: raisonRefus,
                raisonVisible: raisonValider != raisonRefus,
              ),
            ] else ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              const AppDivider(),
              const SizedBox(height: AppSpacing.md),
              for (final ligne in filEchange(echange, moi: etat.moi))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(ligne, style: theme.textTheme.bodyMedium),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.echangesLectureSeuleLigne,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// La charge de chacun après l'échange : chiffres en Atkinson Mono, plafond
/// dépassé dit en toutes lettres avec son icône, disponibilité déclarée par la
/// marque de la case du registre.
class _Charge extends StatelessWidget {
  const _Charge({required this.echange, required this.charge});

  final Echange echange;
  final AsyncValue<List<ChargePersonne>> charge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final personnes = charge.value;
    if (personnes == null) {
      if (charge.hasError) {
        return Text(
          AppStrings.echangesChargeErreur,
          style: theme.textTheme.bodyMedium,
        );
      }
      return const LinearProgressIndicator();
    }
    if (personnes.isEmpty) {
      return Text(
        AppStrings.echangesChargeErreur,
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final p in personnes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_nom(p.nom), style: theme.textTheme.titleSmall),
                Text(
                  AppStrings.echangesCharge(
                    mois: AppStrings.moisLongs[p.mois - 1],
                    astreintes: p.astreintes,
                    maxAstreintes: p.maxAstreintes,
                    weekends: p.unitesWeekend,
                    maxWeekends: p.maxWeekends,
                  ),
                  style: AppTextStyles.nombrePetit.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                if (p.libere)
                  Text(
                    AppStrings.echangesLibere,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (p.depasseAstreintes)
                  _Alerte(
                    AppStrings.echangesDepasseAstreintes(p.maxAstreintes!),
                  ),
                if (p.depasseWeekends)
                  _Alerte(
                    '${AppStrings.echangesDepasseWeekends(p.maxWeekends!)} '
                    '${AppStrings.echangesWeekendAVerifier}',
                  ),
                if (p.disponibilite case final DisponibiliteEtat dispo)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    // Un `Wrap` : à ×1,6 d'échelle de texte, la marque passe
                    // à la ligne plutôt que de déborder du volet de 360.
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        Text(
                          '${AppStrings.echangesDispoDeclaree} :',
                          style: theme.textTheme.bodyMedium,
                        ),
                        SizedBox.square(
                          dimension: AppTouch.caseCompacte,
                          child: SlotChip(
                            etat: dispo,
                            creneau: echange.garde.creneau,
                            densite: SlotChipDensite.compacte,
                            libelleSemantique: context.statuts
                                .disponibilite(dispo)
                                .libelle,
                          ),
                        ),
                        Text(
                          context.statuts.disponibilite(dispo).libelle,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Alerte extends StatelessWidget {
  const _Alerte(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.warning_amber,
            size: AppTouch.icone,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _nom(String nom) =>
    nom.trim().isEmpty ? AppStrings.echangeMembreInconnu : nom.trim();
