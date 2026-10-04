import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/reseau/connectivite.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../astreintes/domain/astreinte.dart';
import '../../../astreintes/domain/astreintes_providers.dart';
import '../../domain/echange.dart';
import '../../domain/echanges_providers.dart';
import '../../domain/issue_echange.dart';
import '../etat_echange.dart';
import 'carte_echange.dart';
import 'confirmation_echange.dart';

/// Un message passager de 8 s, annoncé (`DESIGN.md § Écarts 024`).
void annoncerEchange(BuildContext context, String texte) {
  final messager = ScaffoldMessenger.maybeOf(context);
  if (messager == null) return;
  messager
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Semantics(liveRegion: true, child: Text(texte)),
        showCloseIcon: true,
        duration: const Duration(seconds: 8),
      ),
    );
}

/// Les heures d'affichage de la caserne, qui voyagent avec les astreintes
/// (ticket 027) : aucune lecture de plus.
HeuresAffichage heuresCaserne(WidgetRef ref) =>
    ref.watch(astreintesControllerProvider).value?.donnees.heures ??
    HeuresAffichage.defaut;

/// Ouvre le détail d'une demande : feuille de bas d'écran, dialogue de 480 en
/// large — la mécanique de `ouvrirDetailAstreinte`.
Future<void> ouvrirDetailEchange(BuildContext context, String echangeId) {
  final corps = DetailEchange(echangeId: echangeId);
  if (AppWindowClass.of(context).estLarge) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: corps,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => corps,
  );
}

/// Le détail d'une demande : titre, état, gardes, fil, et l'annulation pour A.
///
/// Il lit la demande **dans la liste courante** : après une annulation, la
/// relecture le met à jour sous les yeux du pompier, sans le refermer.
class DetailEchange extends ConsumerStatefulWidget {
  const DetailEchange({required this.echangeId, super.key});

  final String echangeId;

  @override
  ConsumerState<DetailEchange> createState() => _DetailEchangeState();
}

class _DetailEchangeState extends ConsumerState<DetailEchange> {
  bool _occupe = false;
  IssueEchange? _issue;

  Future<void> _annuler(Echange echange) async {
    final texte = echange.statut == StatutEchange.accepteParPair
        ? AppStrings.echangeAnnulerTexteAcceptee(echange.pairNom)
        : echange.aLaCaserne
        ? AppStrings.echangeAnnulerTexteCaserne
        : AppStrings.echangeAnnulerTexteCollegue(
            echange.pairNom,
            phraseGarde(echange.garde),
          );
    final confirme = await confirmerEchange(
      context,
      titre: AppStrings.echangeAnnulerTitre,
      texte: texte,
      libelleConfirmer: AppStrings.echangeAnnuler,
      libelleRevenir: AppStrings.echangeGarder,
      icone: Icons.block,
      variante: PrimaryButtonVariante.danger,
    );
    if (confirme == null || !mounted) return;

    setState(() {
      _occupe = true;
      _issue = null;
    });
    final issue = await ref
        .read(echangesControllerProvider.notifier)
        .annuler(echange);
    if (!mounted) return;
    setState(() => _occupe = false);
    if (issue.ok) {
      annoncerEchange(context, issue.message);
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

    final moi = etat.moi;
    final lecteur = echange.lecteur(moi);
    final enLigne = ref.watch(enLigneProvider).value ?? true;
    final maintenant = ref.watch(horlogeAstreintesProvider)();
    final issue = _issue;

    // L'annulation est une clôture : la base la permet même caserne
    // suspendue (`docs/WORKFLOWS.md § 3 bis`). Seul le réseau la bloque.
    final raison = enLigne ? null : AppStrings.echangeHorsLigneRaison;
    final peutAnnuler =
        lecteur == LecteurEchange.demandeur && echange.statut.enCours;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                titreEchange(echange),
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge.descripteur(
                descripteurEchange(context, echange),
                tampon: echange.statut == StatutEchange.valide,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              ligneDetail(echange, moi: moi, maintenant: maintenant),
              style: theme.textTheme.bodyLarge,
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
            const SizedBox(height: AppSpacing.lg),
            PaireGardes(
              echange: echange,
              lecteur: lecteur == LecteurEchange.disponible
                  ? LecteurEchange.pair
                  : lecteur,
              heures: heuresCaserne(ref),
            ),
            const SizedBox(height: AppSpacing.md),
            const AppDivider(),
            const SizedBox(height: AppSpacing.md),
            for (final ligne in filEchange(echange, moi: moi))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  ligne,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (lecteur == LecteurEchange.pair &&
                echange.statut == StatutEchange.accepteParPair) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.echangeDetailRetractation,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (peutAnnuler) ...<Widget>[
              PrimaryButton(
                libelle: AppStrings.echangeAnnuler,
                icone: Icons.block,
                variante: PrimaryButtonVariante.secondaire,
                chargement: _occupe,
                onPressed: raison == null && !_occupe
                    ? () => unawaited(_annuler(echange))
                    : null,
                raisonDesactivation: raison,
              ),
              const SizedBox(height: AppSpacing.entreCibles),
            ],
            PrimaryButton(
              libelle: AppStrings.echangeFermer,
              variante: PrimaryButtonVariante.secondaire,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
