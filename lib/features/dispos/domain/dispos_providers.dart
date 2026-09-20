import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/dispos_repository.dart';
import 'periode_saisie.dart';

/// Le dépôt des disponibilités. Surchargé par un faux dans les tests.
final Provider<DisposRepository> disposRepositoryProvider =
    Provider<DisposRepository>(
      (ref) => SupabaseDisposRepository(ref.watch(supabaseClientProvider)),
    );

/// Les périodes de saisie de la caserne courante.
///
/// Lues une fois et partagées : le sélecteur de mois, la grille et la
/// bannière de date limite parlent tous de la même liste. Un rechargement
/// passe par `ref.invalidate`.
final FutureProvider<List<PeriodeSaisie>> periodesProvider =
    FutureProvider<List<PeriodeSaisie>>((ref) async {
      final appartenance = ref.watch(appartenanceCouranteProvider);
      if (appartenance == null) return const <PeriodeSaisie>[];

      return ref
          .watch(disposRepositoryProvider)
          .periodes(appartenance.stationId);
    });

/// Le mois affiché, sous la forme `2026-10`.
///
/// `null` signifie « celui par défaut » : la première période ouverte, ou à
/// défaut la période verrouillée la plus récente. La valeur voyage dans
/// l'URL (`?mois=AAAA-MM`), donc le retour du navigateur et le geste retour
/// iOS ramènent au mois précédemment consulté, jamais à un état perdu.
class MoisSelectionne extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? cle) {
    if (state == cle) return;
    state = cle;
  }
}

final NotifierProvider<MoisSelectionne, String?> moisSelectionneProvider =
    NotifierProvider<MoisSelectionne, String?>(MoisSelectionne.new);

/// La période effectivement affichée, une fois le choix et le défaut résolus.
///
/// Une clé de mois inconnue de la caserne — un lien partagé, une URL bricolée
/// — retombe sur le défaut plutôt que de rendre un écran vide.
final Provider<PeriodeSaisie?> periodeCouranteProvider =
    Provider<PeriodeSaisie?>((ref) {
      final periodes =
          ref.watch(periodesProvider).value ?? const <PeriodeSaisie>[];
      if (periodes.isEmpty) return null;

      final choisie = ref.watch(moisSelectionneProvider);
      for (final periode in periodes) {
        if (periode.cle == choisie) return periode;
      }
      return periodeParDefaut(periodes);
    });
