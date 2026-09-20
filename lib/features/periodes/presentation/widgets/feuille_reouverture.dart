import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../dispos/domain/periode_saisie.dart';

/// Demande **jusqu'à quand** rouvrir, et rend la date limite choisie.
///
/// Rend `null` si la feuille a été refermée sans rouvrir.
///
/// La feuille existe parce que la base l'exige : `periods_guard_transition`
/// refuse une réouverture dont la date limite est déjà passée, et la tâche
/// horaire reverrouillerait de toute façon le mois dans l'heure. Rouvrir,
/// c'est dire jusqu'à quand — l'écran ne propose donc pas de rouvrir sans
/// date.
Future<DateTime?> afficherReouverture({
  required BuildContext context,
  required PeriodeSaisie periode,
  DateTime? maintenant,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => FeuilleReouverture(
    periode: periode,
    maintenant: maintenant ?? DateTime.now(),
  ),
);

/// Le contenu de la feuille. Public pour être monté seul dans un test, sans
/// passer par un `Navigator`.
class FeuilleReouverture extends StatefulWidget {
  const FeuilleReouverture({
    required this.periode,
    required this.maintenant,
    super.key,
  });

  /// Le report proposé d'emblée : trois jours, de quoi prévenir la caserne et
  /// laisser un weekend passer.
  static const int joursProposes = 3;

  /// Le report maximal : au-delà d'un an, c'est une erreur de saisie.
  static const int joursMax = 365;

  final PeriodeSaisie periode;

  /// L'instant de référence. Injecté pour que le refus d'une date passée soit
  /// testable sans faire voyager l'horloge.
  final DateTime maintenant;

  @override
  State<FeuilleReouverture> createState() => _FeuilleReouvertureState();
}

class _FeuilleReouvertureState extends State<FeuilleReouverture> {
  /// Le jour choisi, à 23:59:59 — la même heure que celle posée par
  /// `period_deadline_at` : une date limite court jusqu'au bout de son jour.
  late DateTime _limite = _finDeJournee(
    widget.maintenant.add(
      const Duration(days: FeuilleReouverture.joursProposes),
    ),
  );

  /// Le plancher : la date limite que le mois avait déjà. Descendre en
  /// dessous n'aurait aucun sens — on ne rouvre pas pour fermer plus tôt
  /// qu'avant.
  late final DateTime _plancher = _finDeJournee(widget.periode.dateLimite);

  late final DateTime _plafond = _finDeJournee(
    widget.maintenant.add(const Duration(days: FeuilleReouverture.joursMax)),
  );

  static DateTime _finDeJournee(DateTime jour) =>
      DateTime(jour.year, jour.month, jour.day, 23, 59, 59);

  /// **La règle de la base, dite avant le refus.** Une date limite déjà
  /// passée serait acceptée par la RLS puis défaite par la tâche horaire.
  bool get _valide => _limite.isAfter(widget.maintenant);

  bool get _peutReculer => _limite.isAfter(_plancher);
  bool get _peutAvancer => _limite.isBefore(_plafond);

  void _decaler(int jours) {
    final candidate = _finDeJournee(_limite.add(Duration(days: jours)));
    if (candidate.isBefore(_plancher) || candidate.isAfter(_plafond)) return;
    setState(() => _limite = candidate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                AppStrings.periodeRouvrirTitre(widget.periode.libelle),
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppStrings.periodeRouvrirRegle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              AppStrings.periodeRouvrirLibelleDate,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ChoixDeJour(
              libelle: AppStrings.periodeDateLimiteHeure(
                '${nomJourLong(_limite)} ${formaterDateLongue(_limite)}',
              ),
              onReculer: _peutReculer ? () => _decaler(-1) : null,
              onAvancer: _peutAvancer ? () => _decaler(1) : null,
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              libelle: AppStrings.periodeRouvrirConfirmer,
              icone: Icons.lock_open,
              onPressed: _valide
                  ? () => Navigator.of(context).pop<DateTime>(_limite)
                  : null,
              raisonDesactivation: _valide
                  ? null
                  : AppStrings.periodeRouvrirRefusDatePassee,
            ),
            const SizedBox(height: AppSpacing.entreCibles),
            PrimaryButton(
              libelle: AppStrings.actionAnnuler,
              variante: PrimaryButtonVariante.secondaire,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// La date, entre deux cibles de 48 dp.
///
/// Pas de `showDatePicker` : l'application n'embarque pas
/// `flutter_localizations`, et le sélecteur Material s'afficherait en anglais
/// au milieu d'un écran français. Deux boutons « un jour plus tôt / plus
/// tard » suffisent à une date limite qu'on déplace de quelques jours, et ils
/// se visent avec des gants.
class _ChoixDeJour extends StatelessWidget {
  const _ChoixDeJour({
    required this.libelle,
    required this.onReculer,
    required this.onAvancer,
  });

  final String libelle;
  final VoidCallback? onReculer;
  final VoidCallback? onAvancer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.controleRadius,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: onReculer,
              icon: const Icon(Icons.chevron_left),
              tooltip: AppStrings.periodeRouvrirJourPlusTot,
            ),
            Expanded(
              // La date change en place : elle est annoncée sans déplacer le
              // focus, qui reste sur le bouton qu'on vient d'appuyer.
              child: Semantics(
                liveRegion: true,
                child: Text(
                  libelle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            IconButton(
              onPressed: onAvancer,
              icon: const Icon(Icons.chevron_right),
              tooltip: AppStrings.periodeRouvrirJourPlusTard,
            ),
          ],
        ),
      ),
    );
  }
}
