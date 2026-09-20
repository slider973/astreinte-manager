import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env.dart';
import '../../../core/l10n/app_strings.dart';

/// Écran de démonstration du socle technique (ticket 001).
///
/// Affiche l'environnement courant et l'URL Supabase lus depuis [Env].
/// Sera remplacé par les écrans métier ; il n'a pas de brief de design.
class HelloScreen extends ConsumerWidget {
  const HelloScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(envProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(
              AppStrings.helloTitle,
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.helloSubtitle,
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            _EnvValueRow(
              label: AppStrings.appEnvLabel,
              value: env.appEnv,
            ),
            const SizedBox(height: 12),
            _EnvValueRow(
              label: AppStrings.supabaseUrlLabel,
              value: env.supabaseUrl,
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne « libellé / valeur » lisible par les lecteurs d'écran comme un
/// seul élément. Une valeur vide est annoncée explicitement.
class _EnvValueRow extends StatelessWidget {
  const _EnvValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final displayValue = value.isEmpty ? AppStrings.valueUndefined : value;

    return Semantics(
      label: label,
      value: displayValue,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(displayValue, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}
