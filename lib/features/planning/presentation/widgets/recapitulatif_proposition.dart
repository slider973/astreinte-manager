import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/count_stat.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/proposition_automatique.dart';
import 'recapitulatif_publication.dart' show libelleCreneauCourt;

/// Ce que la machine propose, avant que le chef ne dise oui.
///
/// **Une feuille sous 1200 dp, un dialogue en `large`** — le patron du
/// bordereau de publication (ticket 019), et la seconde exception méritée à
/// « pas de modale pour une tâche qui ne demande ni interruption ni protection »
/// (`DESIGN.md § Don't`) : un appui écrit quarante-huit lignes sur le mois de
/// quinze personnes, et le chef doit voir ce qu'il engage avant de l'engager.
///
/// Rend `true` quand la proposition a été appliquée.
Future<bool> ouvrirProposition(
  BuildContext context, {
  required PropositionAutomatique proposition,
  required String mois,
  required Future<bool> Function() onAppliquer,
}) async {
  final corps = _CorpsProposition(
    proposition: proposition,
    mois: mois,
    onAppliquer: onAppliquer,
  );

  if (AppWindowClass.of(context).estLarge) {
    final applique = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child: corps,
        ),
      ),
    );
    return applique ?? false;
  }

  final applique = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) =>
        FractionallySizedBox(heightFactor: 0.9, child: corps),
  );
  return applique ?? false;
}

class _CorpsProposition extends StatefulWidget {
  const _CorpsProposition({
    required this.proposition,
    required this.mois,
    required this.onAppliquer,
  });

  final PropositionAutomatique proposition;
  final String mois;

  /// Rend `true` quand la proposition a abouti. **La feuille ne se ferme pas
  /// d'elle-même en cas d'échec** : rien n'est perdu, l'application est atomique
  /// en base, et le chef doit pouvoir réessayer là où il est.
  final Future<bool> Function() onAppliquer;

  @override
  State<_CorpsProposition> createState() => _CorpsPropositionState();
}

class _CorpsPropositionState extends State<_CorpsProposition> {
  bool _enVol = false;

  Future<void> _appliquer() async {
    setState(() => _enVol = true);
    final abouti = await widget.onAppliquer();
    if (!mounted) return;
    setState(() => _enVol = false);
    if (abouti) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proposition = widget.proposition;

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      AppStrings.proposerTitre(widget.mois),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                  tooltip: AppStrings.proposerFermer,
                ),
              ],
            ),
          ),
          const AppDivider(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Ampleur(proposition: proposition),
                  const SizedBox(height: AppSpacing.xl),
                  if (proposition.decouverts.isNotEmpty)
                    _SansCandidat(proposition: proposition),
                  if (proposition.decouverts.isNotEmpty)
                    const SizedBox(height: AppSpacing.xl),
                  // La promesse du ticket, écrite avant qu'on la croie.
                  Text(
                    AppStrings.proposerPromesse,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const AppDivider(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: PrimaryButton(
                    libelle: AppStrings.proposerAnnuler,
                    variante: PrimaryButtonVariante.secondaire,
                    onPressed: _enVol
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: AppSpacing.entreCibles),
                Expanded(
                  child: PrimaryButton(
                    // **Le bouton porte le compte.** Appliquer 48 attributions
                    // n'est pas en appliquer 3, et le chef doit le lire sur le
                    // contrôle qu'il actionne, pas seulement au-dessus.
                    libelle: AppStrings.proposerConfirmer(
                      proposition.attributions,
                    ),
                    icone: Icons.auto_fix_high,
                    chargement: _enVol,
                    onPressed: _enVol ? null : () => unawaited(_appliquer()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Les trois nombres du ticket : ce qui se remplit, ce que ça coûte en
/// astreintes, ce qui reste à découvert.
class _Ampleur extends StatelessWidget {
  const _Ampleur({required this.proposition});

  final PropositionAutomatique proposition;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: CountStat(
          libelle: AppStrings.proposerCreneauxRemplis,
          valeur: proposition.creneauxRemplis,
          plafondAttendu: false,
        ),
      ),
      Expanded(
        child: CountStat(
          libelle: AppStrings.proposerAstreintes,
          valeur: proposition.attributions,
          plafondAttendu: false,
        ),
      ),
      Expanded(
        child: CountStat(
          libelle: AppStrings.proposerDecouverts,
          valeur: proposition.creneauxDecouverts,
          plafondAttendu: false,
        ),
      ),
    ],
  );
}

/// Les créneaux que personne ne peut tenir, nommés.
///
/// **Ce bloc n'est pas rouge**, et c'est une décision : ce n'est pas une panne,
/// c'est l'état des disponibilités de la caserne. Le vermillon reste
/// « absent, refusé, cassé » (`DESIGN.md`).
class _SansCandidat extends StatelessWidget {
  const _SansCandidat({required this.proposition});

  /// Au-delà, la liste s'arrête et dit combien elle tait.
  static const int maximum = 6;

  final PropositionAutomatique proposition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attente = context.statuts.attribution(AttributionEtat.propose);
    final creneaux = <String>[
      for (final creneau in proposition.decouverts)
        libelleCreneauCourt(context, creneau),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.report_problem_outlined, size: 20, color: attente.encre),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                AppStrings.proposerSansCandidat(creneaux.length),
                style: theme.textTheme.bodyLarge,
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  _extrait(creneaux),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  AppStrings.proposerSansCandidatDetail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _extrait(List<String> valeurs) {
    if (valeurs.length <= maximum) return valeurs.join(' · ');
    return '${valeurs.take(maximum).join(' · ')} · '
        '${AppStrings.publierEtAutres(valeurs.length - maximum)}';
  }
}
