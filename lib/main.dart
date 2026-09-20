import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const env = Env.fromDefines;
  // Le démarrage ne lève jamais : une configuration absente ou un client
  // impossible à créer se traduit par un écran qui l'explique, pas par un
  // écran gris.
  final demarrage = await demarrerSupabase(env);

  runApp(
    ProviderScope(
      overrides: [
        envProvider.overrideWithValue(env),
        supabaseDemarrageProvider.overrideWithValue(demarrage),
      ],
      child: const AstreinteApp(),
    ),
  );
}
