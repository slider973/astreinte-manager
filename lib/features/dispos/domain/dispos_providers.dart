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

/// L'horloge des relectures de périodes. Surchargée par une horloge figée
/// dans les tests : c'est elle qui décide si une relecture est « en rafale ».
final Provider<DateTime Function()> horlogeRafraichissementProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Les périodes de saisie de la caserne courante.
///
/// Lues une fois et partagées : le sélecteur de mois, la grille et la
/// bannière de date limite parlent tous de la même liste. Un rechargement
/// complet passe par `ref.invalidate` ; une relecture **discrète** — retour au
/// premier plan, ouverture d'un écran, tirer pour actualiser — passe par
/// [PeriodesCaserne.relire], qui ne publie rien si rien n'a changé.
///
/// **Pourquoi un notifier et plus un simple `FutureProvider`** (ticket 068) :
/// le provider n'est jamais libéré, et rien d'autre que `ref.invalidate` ne le
/// relisait. Un mois ouvert par l'admin pendant que la PWA tournait restait
/// donc invisible jusqu'au redémarrage de l'application. Relire par
/// `invalidate` aurait remis tous ses lecteurs en chargement, et reconstruit
/// la saisie deux fois à chaque retour au premier plan, même sans nouveauté.
class PeriodesCaserne extends AsyncNotifier<List<PeriodeSaisie>> {
  /// Le moment de la dernière lecture aboutie, initiale comprise.
  DateTime? _derniereLecture;

  DateTime? get derniereLecture => _derniereLecture;

  @override
  Future<List<PeriodeSaisie>> build() async {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (appartenance == null) return const <PeriodeSaisie>[];

    final lues = await ref
        .watch(disposRepositoryProvider)
        .periodes(appartenance.stationId);
    _derniereLecture = ref.read(horlogeRafraichissementProvider)();
    return lues;
  }

  /// Relit la liste **sans passer par un état de chargement**.
  ///
  /// Rend vrai si la liste a changé, et seulement alors la publie : un retour
  /// au premier plan sans nouveauté ne réveille ni la saisie ni l'accueil.
  /// Une lecture qui échoue garde la liste affichée — un réseau capricieux ne
  /// doit pas effacer des mois déjà lus ; le prochain retour réessaiera.
  Future<bool> relire() async {
    if (state.isLoading) return false;
    final appartenance = ref.read(appartenanceCouranteProvider);
    if (appartenance == null) return false;

    final List<PeriodeSaisie> lues;
    try {
      lues = await ref
          .read(disposRepositoryProvider)
          .periodes(appartenance.stationId);
    } on Object {
      return false;
    }
    // Changement de caserne pendant la lecture : la liste lue n'est plus la
    // bonne, et `build` s'occupe déjà de la nouvelle.
    if (!ref.mounted ||
        ref.read(appartenanceCouranteProvider)?.stationId !=
            appartenance.stationId ||
        state.isLoading) {
      return false;
    }
    _derniereLecture = ref.read(horlogeRafraichissementProvider)();

    final actuelles = state.value;
    if (actuelles != null && !state.hasError && _memes(actuelles, lues)) {
      return false;
    }
    state = AsyncData<List<PeriodeSaisie>>(lues);
    return true;
  }

  static bool _memes(List<PeriodeSaisie> a, List<PeriodeSaisie> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final AsyncNotifierProvider<PeriodesCaserne, List<PeriodeSaisie>>
periodesProvider = AsyncNotifierProvider<PeriodesCaserne, List<PeriodeSaisie>>(
  PeriodesCaserne.new,
);

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
