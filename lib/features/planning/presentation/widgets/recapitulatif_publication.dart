import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/count_stat.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/recapitulatif_publication.dart';

/// Le bordereau d'expédition d'une publication.
///
/// **Une feuille sous 1200 dp, un dialogue en `large`.** C'est la seule
/// exception du produit à « pas de modale pour une tâche qui ne demande ni
/// interruption ni protection » (`DESIGN.md § Don't`), et elle est méritée :
/// publier est irréversible et sort de l'application. Le brief du 017 avait
/// déjà ouvert cette porte pour l'attribution hors disponibilité.
///
/// Rend `true` quand le chef confirme.
Future<bool> ouvrirRecapitulatif(
  BuildContext context, {
  required RecapitulatifPublication recapitulatif,
  required String mois,
  required Future<bool> Function() onPublier,
}) async {
  final corps = _CorpsRecapitulatif(
    recapitulatif: recapitulatif,
    mois: mois,
    onPublier: onPublier,
  );

  if (AppWindowClass.of(context).estLarge) {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child: corps,
        ),
      ),
    );
    return confirme ?? false;
  }

  final confirme = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) =>
        FractionallySizedBox(heightFactor: 0.9, child: corps),
  );
  return confirme ?? false;
}

class _CorpsRecapitulatif extends StatefulWidget {
  const _CorpsRecapitulatif({
    required this.recapitulatif,
    required this.mois,
    required this.onPublier,
  });

  final RecapitulatifPublication recapitulatif;
  final String mois;

  /// Rend `true` quand la publication a abouti. **La feuille ne se ferme pas
  /// d'elle-même en cas d'échec** : rien n'est perdu, la publication est
  /// atomique en base, et le chef doit pouvoir réessayer là où il est.
  final Future<bool> Function() onPublier;

  @override
  State<_CorpsRecapitulatif> createState() => _CorpsRecapitulatifState();
}

class _CorpsRecapitulatifState extends State<_CorpsRecapitulatif> {
  bool _enVol = false;

  Future<void> _publier() async {
    setState(() => _enVol = true);
    final abouti = await widget.onPublier();
    if (!mounted) return;
    setState(() => _enVol = false);
    if (abouti) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recap = widget.recapitulatif;

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
                      AppStrings.publierTitre(widget.mois),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                  tooltip: AppStrings.publierFermer,
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
                  _Ampleur(recapitulatif: recap),
                  const SizedBox(height: AppSpacing.xl),
                  if (recap.sansReserve)
                    const _SansReserve()
                  else
                    _Reserves(recapitulatif: recap),
                  const SizedBox(height: AppSpacing.xl),
                  // La promesse du ticket, écrite avant qu'on la croie.
                  Text(
                    AppStrings.publierPromesse,
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
                    libelle: AppStrings.publierAnnuler,
                    variante: PrimaryButtonVariante.secondaire,
                    onPressed: _enVol
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: AppSpacing.entreCibles),
                Expanded(
                  child: PrimaryButton(
                    libelle: AppStrings.publierConfirmer,
                    icone: Icons.campaign,
                    chargement: _enVol,
                    onPressed: _enVol ? null : () => unawaited(_publier()),
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

/// Ce qu'on s'apprête à envoyer, en trois nombres. Ils disent l'ampleur avant
/// les réserves.
class _Ampleur extends StatelessWidget {
  const _Ampleur({required this.recapitulatif});

  final RecapitulatifPublication recapitulatif;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: CountStat(
          libelle: AppStrings.publierCreneaux,
          valeur: recapitulatif.creneaux,
          plafondAttendu: false,
        ),
      ),
      Expanded(
        child: CountStat(
          libelle: AppStrings.publierPompiers,
          valeur: recapitulatif.membres,
          plafondAttendu: false,
        ),
      ),
      Expanded(
        child: CountStat(
          libelle: AppStrings.publierAstreintes,
          valeur: recapitulatif.attributions,
          plafondAttendu: false,
        ),
      ),
    ],
  );
}

/// Rien à signaler, et le dire vaut autant que de signaler : un récapitulatif
/// silencieux ferait douter qu'il ait regardé.
class _SansReserve extends StatelessWidget {
  const _SansReserve();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acceptee = context.statuts.attribution(AttributionEtat.accepte);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.task_alt, size: 20, color: acceptee.encre),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            AppStrings.publierSansReserve,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

/// Les trois réserves, toujours dans le même ordre, chacune absente quand elle
/// est vide.
///
/// **Aucune n'est rouge**, et c'est une décision : ce ne sont pas des erreurs,
/// ce sont des décisions que le chef a prises et qu'on lui remet sous les yeux.
/// Le vermillon reste « absent, refusé, cassé » (`DESIGN.md`).
class _Reserves extends StatelessWidget {
  const _Reserves({required this.recapitulatif});

  /// Au-delà, la liste s'arrête et dit combien elle tait.
  static const int maximum = 6;

  final RecapitulatifPublication recapitulatif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recap = recapitulatif;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          AppStrings.publierAVerifier,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (recap.nonPourvus.isNotEmpty)
          _Reserve(
            icone: Icons.report_problem_outlined,
            titre: AppStrings.publierNonPourvus(recap.nonPourvus.length),
            lignes: <String>[
              _extrait(
                <String>[
                  for (final creneau in recap.nonPourvus)
                    libelleCreneauCourt(context, creneau),
                ],
              ),
            ],
          ),
        if (recap.horsQuota.isNotEmpty)
          _Reserve(
            // `warning_amber` et non `person_alert`, qui n'existe pas dans le
            // jeu Material embarqué. C'est déjà l'icône de l'avertissement de
            // quota sur la ligne de candidat du ticket 017.
            icone: Icons.warning_amber,
            titre: AppStrings.publierHorsQuota(recap.horsQuota.length),
            lignes: <String>[
              for (final membre in recap.horsQuota) _quota(membre),
            ],
          ),
        if (recap.horsDispo.isNotEmpty)
          _Reserve(
            icone: Icons.event_busy,
            titre: AppStrings.publierHorsDispo(recap.horsDispo.length),
            lignes: <String>[
              for (final membre in recap.horsDispo)
                AppStrings.publierMembreEtCreneaux(
                  membre.nom,
                  _extrait(<String>[
                    for (final creneau in membre.creneaux)
                      libelleCreneauCourt(context, creneau),
                  ]),
                ),
            ],
          ),
      ],
    );
  }

  static String _quota(MembreHorsQuota membre) {
    if (membre.astreintesDepassees) {
      return AppStrings.publierQuotaLigne(
        membre: membre.nom,
        astreintes: membre.astreintes,
        plafond: membre.maxAstreintes!,
      );
    }
    return AppStrings.publierQuotaLigne(
      membre: membre.nom,
      astreintes: membre.unitesWeekend,
      plafond: membre.maxWeekends!,
    );
  }

  static String _extrait(List<String> valeurs) {
    if (valeurs.length <= maximum) return valeurs.join(' · ');
    return '${valeurs.take(maximum).join(' · ')} · '
        '${AppStrings.publierEtAutres(valeurs.length - maximum)}';
  }
}

/// Le libellé court d'un créneau : « sam. 11 nuit ».
String libelleCreneauCourt(BuildContext context, CreneauNonPourvu creneau) {
  final type = context.statuts.creneau(creneau.creneau).libelle.toLowerCase();
  return '${nomJourCourt(creneau.date)} ${creneau.date.day} $type';
}

class _Reserve extends StatelessWidget {
  const _Reserve({
    required this.icone,
    required this.titre,
    required this.lignes,
  });

  final IconData icone;
  final String titre;
  final List<String> lignes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attente = context.statuts.attribution(AttributionEtat.propose);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: 20, color: attente.encre),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(titre, style: theme.textTheme.bodyLarge),
                for (final ligne in lignes)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      ligne,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
