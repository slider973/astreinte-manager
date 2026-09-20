import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_divider.dart';
import 'widgets/dev_catalogue.dart';

/// Comment le catalogue est affiché.
enum DevApparence {
  clair,
  sombre,

  /// Les deux côte à côte : c'est sous cette forme que la revue vérifie qu'un
  /// état se lit dans les deux thèmes.
  lesDeux,
}

/// Catalogue des composants du système de design — **build de développement
/// uniquement**.
///
/// La route `/dev/components` n'est pas déclarée quand `Env.appEnv` vaut
/// `prod` (voir `lib/core/router/app_router.dart`) : cet écran n'existe pas
/// en production.
///
/// Il porte deux contrôles locaux de démonstration : l'apparence (clair,
/// sombre, les deux) et l'échelle de texte (1.0, 1.3, 2.0). Ils ne changent
/// rien au reste de l'application — le choix du thème par l'utilisateur arrive
/// au ticket 007.
class DevComponentsScreen extends StatefulWidget {
  const DevComponentsScreen({super.key});

  @override
  State<DevComponentsScreen> createState() => _DevComponentsScreenState();
}

class _DevComponentsScreenState extends State<DevComponentsScreen> {
  DevApparence _apparence = DevApparence.lesDeux;
  double _echelle = 1;

  static const List<double> _echelles = <double>[1, 1.3, 2];

  @override
  Widget build(BuildContext context) {
    final classe = AppWindowClass.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.devComposantsTitre)),
      body: Column(
        children: <Widget>[
          _Controles(
            apparence: _apparence,
            echelle: _echelle,
            echelles: _echelles,
            onApparence: (valeur) => setState(() => _apparence = valeur),
            onEchelle: (valeur) => setState(() => _echelle = valeur),
          ),
          const AppDivider(),
          Expanded(
            child: _apparence == DevApparence.lesDeux && !classe.estCompact
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: _Volet(
                          sombre: false,
                          echelle: _echelle,
                          titre: AppStrings.devThemeClair,
                        ),
                      ),
                      const AppDivider.vertical(),
                      Expanded(
                        child: _Volet(
                          sombre: true,
                          echelle: _echelle,
                          titre: AppStrings.devThemeSombre,
                        ),
                      ),
                    ],
                  )
                : _Volet(
                    sombre: _apparence == DevApparence.sombre,
                    echelle: _echelle,
                    titre: _apparence == DevApparence.sombre
                        ? AppStrings.devThemeSombre
                        : AppStrings.devThemeClair,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Le catalogue sous un thème et une échelle de texte donnés.
class _Volet extends StatefulWidget {
  const _Volet({
    required this.sombre,
    required this.echelle,
    required this.titre,
  });

  final bool sombre;
  final double echelle;
  final String titre;

  @override
  State<_Volet> createState() => _VoletState();
}

class _VoletState extends State<_Volet> {
  // Chaque volet défile pour son compte : deux ListView `primary` se
  // disputeraient le PrimaryScrollController de l'écran.
  final ScrollController _defilement = ScrollController();

  @override
  void dispose() {
    _defilement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.sombre ? AppTheme.sombre : AppTheme.clair;

    return Theme(
      data: theme,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(widget.echelle)),
        // `Material` — et non `ColoredBox` — pour que le volet porte le
        // DefaultTextStyle de **son** thème : un style de token sans couleur
        // (AppTextStyles.nombre) hériterait sinon de l'encre de l'écran hôte
        // et disparaîtrait sur le fond sombre.
        child: Material(
          color: theme.colorScheme.surface,
          child: Scrollbar(
            controller: _defilement,
            child: ListView(
              controller: _defilement,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              children: <Widget>[
                Text(widget.titre, style: theme.textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppStrings.devComposantsSousTitre,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const DevCatalogue(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Les deux contrôles locaux du catalogue.
class _Controles extends StatelessWidget {
  const _Controles({
    required this.apparence,
    required this.echelle,
    required this.echelles,
    required this.onApparence,
    required this.onEchelle,
  });

  final DevApparence apparence;
  final double echelle;
  final List<double> echelles;
  final ValueChanged<DevApparence> onApparence;
  final ValueChanged<double> onEchelle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        children: <Widget>[
          // Chaque groupe s'annonce par son rôle ; les segments gardent leur
          // libellé visible.
          Semantics(
            label: AppStrings.devTheme,
            container: true,
            child: SegmentedButton<DevApparence>(
              segments: const <ButtonSegment<DevApparence>>[
                ButtonSegment<DevApparence>(
                  value: DevApparence.clair,
                  label: Text(AppStrings.devThemeClair),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment<DevApparence>(
                  value: DevApparence.sombre,
                  label: Text(AppStrings.devThemeSombre),
                  icon: Icon(Icons.bedtime),
                ),
                ButtonSegment<DevApparence>(
                  value: DevApparence.lesDeux,
                  label: Text(AppStrings.devThemeLesDeux),
                  icon: Icon(Icons.vertical_split),
                ),
              ],
              selected: <DevApparence>{apparence},
              onSelectionChanged: (valeurs) => onApparence(valeurs.first),
            ),
          ),
          Semantics(
            label: AppStrings.devEchelleTexte,
            container: true,
            child: SegmentedButton<double>(
              segments: <ButtonSegment<double>>[
                for (final valeur in echelles)
                  ButtonSegment<double>(
                    value: valeur,
                    label: Text(AppStrings.devEchelleValeur(valeur)),
                    tooltip: AppStrings.devEchelleSemantique(valeur),
                  ),
              ],
              selected: <double>{echelle},
              onSelectionChanged: (valeurs) => onEchelle(valeurs.first),
            ),
          ),
        ],
      ),
    );
  }
}
