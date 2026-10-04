import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/caserne/caserne_providers.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/reseau/connectivite.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../astreintes/domain/astreintes_providers.dart';
import '../../domain/echange.dart';
import '../../domain/echanges_providers.dart';
import '../../domain/issue_echange.dart';
import 'carte_echange.dart';
import 'detail_echange.dart';

/// **La réponse de B** à une demande d'échange (`design/073 § 7.2`), frère de
/// `PanneauReponse` : volet latéral en large, feuille de bas d'écran dessous.
///
/// Le moment focal du parcours est ici : la paire « Tu donnes / Tu prends »
/// pleine largeur. **Pas de confirmation** : le panneau en est une, il s'ouvre
/// par un appui et dit les deux gardes ; la validation du chef est le filet.
///
/// Il garde la **dernière demande lue** : quand une course la fait disparaître
/// de la liste (reprise par un autre, annulée, expirée), le panneau reste à
/// l'écran le temps de dire pourquoi, boutons inertes.
class PanneauEchange extends ConsumerStatefulWidget {
  const PanneauEchange({
    required this.echangeId,
    required this.onFermer,
    super.key,
    this.etendu = false,
  });

  final String echangeId;
  final VoidCallback onFermer;
  final bool etendu;

  /// En dessous de cette largeur, les deux boutons s'empilent (même mesure
  /// que `PanneauReponse`).
  static const double largeurCoteACote = 350;

  @override
  ConsumerState<PanneauEchange> createState() => _PanneauEchangeState();
}

class _PanneauEchangeState extends ConsumerState<PanneauEchange> {
  Echange? _dernier;
  bool _occupe = false;
  IssueEchange? _issue;

  Future<void> _repondre(Echange echange, {required bool accepte}) async {
    setState(() {
      _occupe = true;
      _issue = null;
    });
    final issue = await ref
        .read(echangesControllerProvider.notifier)
        .repondre(echange, accepte: accepte);
    if (!mounted) return;
    setState(() => _occupe = false);
    if (issue.ok) {
      annoncerEchange(context, issue.message);
      widget.onFermer();
      return;
    }
    setState(() => _issue = issue);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etat = ref.watch(echangesOuvertsProvider).value;
    final lu = etat?.parId(widget.echangeId);
    if (lu != null && lu.statut == StatutEchange.ouvert) _dernier = lu;
    final echange = _dernier;
    if (echange == null) return const SizedBox.shrink();

    final maintenant = ref.watch(horlogeAstreintesProvider)();
    final enLigne = ref.watch(enLigneProvider).value ?? true;
    final lectureSeule = ref.watch(lectureSeuleCaserneProvider);
    final issue = _issue;
    final disparue =
        (issue?.retiree ?? false) ||
        lu == null ||
        lu.statut != StatutEchange.ouvert;

    final nom = echange.demandeurNom.trim().isEmpty
        ? AppStrings.echangeMembreInconnu
        : echange.demandeurNom.trim();
    final titre = echange.aLaCaserne
        ? AppStrings.echangePanneauTitreReprendre(nom)
        : echange.estEchange
        ? AppStrings.echangePanneauTitreEchange(nom)
        : AppStrings.echangePanneauTitreCession(nom);
    final mention = AppStrings.echangePanneauExpire(
      formaterInstantRelatif(echange.creeLe, maintenant: maintenant),
      formaterDateCourte(echange.expireLe),
      heureMinute(echange.expireLe),
    );
    final raison = disparue
        ? AppStrings.echangePlusOuverte
        : lectureSeule
        ? AppStrings.echangeReponseLectureSeule
        : !enLigne
        ? AppStrings.echangeHorsLigneRaison
        : null;
    final libelleAccepter = echange.aLaCaserne
        ? AppStrings.echangeJeLaPrends
        : echange.estEchange
        ? AppStrings.echangeAccepterEchange
        : AppStrings.echangeAccepterGarde;

    final accepter = PrimaryButton(
      libelle: libelleAccepter,
      icone: Icons.task_alt,
      pleineLargeur: true,
      chargement: _occupe,
      onPressed: raison == null && !_occupe
          ? () => unawaited(_repondre(echange, accepte: true))
          : null,
      raisonDesactivation: raison,
    );
    // Une demande « à la caserne » ne se décline pas : elle s'ignore, et
    // disparaît quand quelqu'un la prend ou qu'elle expire.
    final refuser = echange.aLaCaserne
        ? null
        : PrimaryButton(
            libelle: AppStrings.echangeRefuser,
            icone: Icons.cancel,
            variante: PrimaryButtonVariante.secondaire,
            pleineLargeur: true,
            onPressed: raison == null && !_occupe
                ? () => unawaited(_repondre(echange, accepte: false))
                : null,
            raisonDesactivation: raison,
            raisonVisible: false,
          );

    return Semantics(
      container: true,
      label: titre,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Semantics(
                          header: true,
                          child: Text(titre, style: theme.textTheme.titleLarge),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          mention,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onFermer,
                    icon: const Icon(Icons.close),
                    tooltip: AppStrings.echangeFermer,
                  ),
                ],
              ),
            ),
            if (issue != null)
              Semantics(
                liveRegion: true,
                child: AppBanner(
                  variante: issue.ton == TonIssue.erreur
                      ? AppBannerVariante.erreur
                      : AppBannerVariante.information,
                  texte: issue.message,
                  detail: issue.detail,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: PaireGardes(
                echange: echange,
                lecteur: LecteurEchange.pair,
                heures: heuresCaserne(ref),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
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
                      echange.aLaCaserne
                          ? AppStrings.echangePanneauInfoReprendre
                          : AppStrings.echangePanneauInfo,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const AppDivider(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints contraintes) {
                  if (refuser == null) return accepter;
                  if (contraintes.maxWidth < PanneauEchange.largeurCoteACote) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        accepter,
                        const SizedBox(height: AppSpacing.entreCibles),
                        refuser,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 3, child: accepter),
                      const SizedBox(width: AppSpacing.entreCibles),
                      Expanded(flex: 2, child: refuser),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
