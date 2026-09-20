import 'package:astreinte_sp/core/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Env', () {
    test('sans --dart-define, vaut dev et sans configuration Supabase', () {
      const env = Env.fromDefines;

      expect(env.appEnv, Env.devEnv);
      expect(env.isDev, isTrue);
      expect(env.isProd, isFalse);
      expect(env.hasSupabaseConfig, isFalse);
    });

    test('isProd et hasSupabaseConfig reflètent les valeurs fournies', () {
      const env = Env(
        supabaseUrl: 'https://x.supabase.co',
        supabaseAnonKey: 'anon',
        firebaseProjectId: '',
        appEnv: Env.prodEnv,
      );

      expect(env.isProd, isTrue);
      expect(env.hasSupabaseConfig, isTrue);
    });

    test('une clé anon vide rend la configuration Supabase incomplète', () {
      const env = Env(
        supabaseUrl: 'https://x.supabase.co',
        supabaseAnonKey: '',
        firebaseProjectId: '',
        appEnv: Env.devEnv,
      );

      expect(env.hasSupabaseConfig, isFalse);
    });
  });
}
