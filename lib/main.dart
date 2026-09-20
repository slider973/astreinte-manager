import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const env = Env.fromDefines;
  // Le démarrage ne lève jamais : une configuration absente ou un client
  // impossible à créer se traduit par un écran qui l'explique, pas par un
  // écran gris.
  final demarrage = await demarrerSupabase(env);

  // Même règle pour Firebase : sans les cinq variables `FIREBASE_*`,
  // l'application s'ouvre normalement, **sans notifications**, et le dit là où
  // il faut (`docs/FIREBASE.md`). Aucune requête ne part vers Google.
  final push = await demarrerFirebase(env);

  runApp(
    ProviderScope(
      overrides: [
        envProvider.overrideWithValue(env),
        supabaseDemarrageProvider.overrideWithValue(demarrage),
        firebaseDemarrageProvider.overrideWithValue(push),
      ],
      child: const AstreinteApp(),
    ),
  );
}
