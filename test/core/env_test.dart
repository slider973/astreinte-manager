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
      const env = Env.sansPush(
        supabaseUrl: 'https://x.supabase.co',
        supabaseAnonKey: 'anon',
        appEnv: Env.prodEnv,
      );

      expect(env.isProd, isTrue);
      expect(env.hasSupabaseConfig, isTrue);
    });

    test('sans variables FIREBASE_*, le push est simplement absent', () {
      const env = Env.sansPush(
        supabaseUrl: 'https://x.supabase.co',
        supabaseAnonKey: 'anon',
        appEnv: Env.prodEnv,
      );

      // C'est l'état normal du projet tant qu'aucun projet Firebase n'existe :
      // l'application démarre, elle n'a simplement pas de notifications.
      expect(env.hasFirebaseConfig, isFalse);
      expect(env.hasSupabaseConfig, isTrue);
    });

    test('les cinq valeurs Firebase sont nécessaires ensemble', () {
      const complet = Env(
        supabaseUrl: 'https://x.supabase.co',
        supabaseAnonKey: 'anon',
        appEnv: Env.prodEnv,
        firebaseProjectId: 'astreinte-sp',
        firebaseApiKey: 'AIza…',
        firebaseAppId: '1:1:web:1',
        firebaseMessagingSenderId: '1',
        firebaseVapidKey: 'BP…',
      );
      expect(complet.hasFirebaseConfig, isTrue);

      // Une configuration à moitié remplie est traitée comme absente : mieux
      // vaut des notifications annoncées comme indisponibles qu'un échec
      // silencieux à chaque lancement.
      const sansVapid = Env(
        supabaseUrl: 'https://x.supabase.co',
        supabaseAnonKey: 'anon',
        appEnv: Env.prodEnv,
        firebaseProjectId: 'astreinte-sp',
        firebaseApiKey: 'AIza…',
        firebaseAppId: '1:1:web:1',
        firebaseMessagingSenderId: '1',
        firebaseVapidKey: '',
      );
      expect(sansVapid.hasFirebaseConfig, isFalse);
    });

    test('une clé anon vide rend la configuration Supabase incomplète', () {
      const env = Env.sansPush(
        supabaseUrl: 'https://x.supabase.co',
        supabaseAnonKey: '',
        appEnv: Env.devEnv,
      );

      expect(env.hasSupabaseConfig, isFalse);
    });
  });
}
