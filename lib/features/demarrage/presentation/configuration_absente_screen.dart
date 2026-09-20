import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/empty_state.dart';

/// L'app n'a pas reçu son URL Supabase à la compilation.
///
/// Elle ne peut rien faire, et elle le dit sans jargon ni trace technique :
/// ce n'est pas à un pompier de lire une pile d'appels.
class ConfigurationAbsenteScreen extends StatelessWidget {
  const ConfigurationAbsenteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: EmptyState(
          titre: AppStrings.configurationTitre,
          texte: AppStrings.configurationTexte,
          icone: Icons.settings_ethernet,
        ),
      ),
    );
  }
}
