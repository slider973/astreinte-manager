import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/env.dart';
import 'package:astreinte_sp/core/supabase/supabase_bootstrap.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/auth/data/auth_providers.dart';
import 'package:astreinte_sp/features/auth/domain/appartenance.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/demarrage/presentation/configuration_absente_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/faux_auth.dart';

void main() {
  testWidgets('sans session, l\'app ouvre sur la connexion', (tester) async {
    await monterApp(tester);

    expect(find.byType(ConnexionScreen), findsOneWidget);
  });

  testWidgets(
    'une session persistée est restaurée au lancement : l\'app ouvre sur '
    'l\'accueil',
    (tester) async {
      // C'est exactement ce que fait un redémarrage : le SDK a restauré la
      // session depuis le stockage local avant que l'arbre soit monté.
      final faux = await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );

      expect(find.byType(AccueilScreen), findsOneWidget);
      expect(faux.memberships.lectures, 1);
    },
  );

  testWidgets('sans configuration Supabase, l\'app l\'explique', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Sans `--dart-define`, la configuration compilée est vide : c'est
          // exactement le cas qu'on veut montrer.
          envProvider.overrideWithValue(Env.fromDefines),
          supabaseDemarrageProvider.overrideWithValue(
            SupabaseDemarrage.configurationAbsente,
          ),
          authRepositoryProvider.overrideWithValue(FauxAuthRepository()),
          membershipRepositoryProvider.overrideWithValue(
            FauxMembershipRepository(),
          ),
        ],
        child: const AstreinteApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ConfigurationAbsenteScreen), findsOneWidget);
    expect(find.byType(ConnexionScreen), findsNothing);
  });
}
