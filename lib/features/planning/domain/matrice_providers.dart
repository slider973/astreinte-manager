import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/theme/app_status.dart';
import '../../dispos/domain/dispos_providers.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../data/matrice_repository.dart';
import 'cle_cellule.dart';
import 'ligne_matrice.dart';
import 'matrice_filtres.dart';
import 'matrice_mois.dart';

/// Le dépôt de la matrice. Surchargé par un faux dans les tests.
final Provider<MatriceRepository> matriceRepositoryProvider =
    Provider<MatriceRepository>(
      (ref) => SupabaseMatriceRepository(ref.watch(supabaseClientProvider)),
    );

/// Le mois affiché, sous la forme `2026-10`.
///
/// `null` signifie « celui par défaut ». La valeur voyage dans l'URL
/// (`?mois=AAAA-MM`) ; **les filtres, eux, n'y vont pas** — trois contrôles
/// qui empilent chacun une entrée d'historique transformeraient le bouton
/// retour du navigateur en machine à défaire des filtres (brief § 6.7).
class MoisMatrice extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? cle) {
    if (state == cle) return;
    state = cle;
  }
}

final NotifierProvider<MoisMatrice, String?> moisMatriceProvider =
    NotifierProvider<MoisMatrice, String?>(MoisMatrice.new);

/// Les trois filtres et le tri. Hors du contrôleur : ils ne rechargent rien,
/// et ils survivent à un changement de mois.
class FiltresNotifier extends Notifier<FiltresMatrice> {
  @override
  FiltresMatrice build() => const FiltresMatrice();

  void definir(FiltresMatrice filtres) => state = filtres;

  void effacerFiltres() =>
      state = state.copie(recherche: '', masquerNonSaisis: false);
}

final NotifierProvider<FiltresNotifier, FiltresMatrice> filtresMatriceProvider =
    NotifierProvider<FiltresNotifier, FiltresMatrice>(FiltresNotifier.new);

/// La période à ouvrir par défaut sur cet écran : **le mois le plus proche à
/// venir, mois courant inclus**.
///
/// Le chef construit octobre en septembre, pas novembre. À défaut de mois à
/// venir, le plus récent des mois écoulés : il reste consultable.
PeriodeSaisie? periodeParDefautAdmin(
  List<PeriodeSaisie> periodes,
  DateTime maintenant,
) {
  if (periodes.isEmpty) return null;

  final triees = <PeriodeSaisie>[...periodes]
    ..sort((PeriodeSaisie a, PeriodeSaisie b) => a.cle.compareTo(b.cle));
  final courant = PeriodeSaisie.cleDe(maintenant.year, maintenant.month);

  for (final periode in triees) {
    if (periode.cle.compareTo(courant) >= 0) return periode;
  }
  return triees.last;
}

/// Ce que l'écran « Planning du mois » affiche.
@immutable
class EtatMatrice {
  const EtatMatrice({
    required this.periode,
    required this.matrice,
    this.modeArme = false,
    this.sync = SyncEtat.repos,
    this.erreurs = const <CleCellule>{},
    this.messageErreur,
    this.lectureSeule = false,
  });

  final PeriodeSaisie periode;
  final MatriceMois matrice;

  /// Le mode armé de la saisie par procuration. **Faux à chaque chargement**,
  /// donc à chaque changement de mois : le mois quitté ne laisse jamais un
  /// écran armé derrière lui (brief § 6.5).
  final bool modeArme;

  final SyncEtat sync;

  /// Les cases dont l'enregistrement a échoué. Elles gardent la valeur
  /// demandée et portent le contour d'erreur.
  final Set<CleCellule> erreurs;

  /// La phrase de la bannière d'erreur, ou `null`.
  final String? messageErreur;

  /// La caserne est suspendue : la base refuse toute écriture.
  final bool lectureSeule;

  EtatMatrice copie({
    PeriodeSaisie? periode,
    MatriceMois? matrice,
    bool? modeArme,
    SyncEtat? sync,
    Set<CleCellule>? erreurs,
    String? messageErreur,
    bool effacerMessage = false,
    bool? lectureSeule,
  }) => EtatMatrice(
    periode: periode ?? this.periode,
    matrice: matrice ?? this.matrice,
    modeArme: modeArme ?? this.modeArme,
    sync: sync ?? this.sync,
    erreurs: erreurs ?? this.erreurs,
    messageErreur: effacerMessage ? null : messageErreur ?? this.messageErreur,
    lectureSeule: lectureSeule ?? this.lectureSeule,
  );
}

/// Le chargement de la matrice, le mode armé et les écritures en vol.
///
/// **Une seule requête par mois affiché.** Les filtres, le tri, la recherche
/// et le compte de couverture n'en déclenchent aucune : ils se dérivent des
/// lignes déjà en mémoire.
class MatriceController extends AsyncNotifier<EtatMatrice?> {
  @override
  Future<EtatMatrice?> build() async {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (appartenance == null || !appartenance.estAdmin) return null;

    final periodes = await ref.watch(periodesProvider.future);
    if (periodes.isEmpty) return null;

    final cle = ref.watch(moisMatriceProvider);
    final periode = _resoudre(periodes, cle);
    if (periode == null) return null;

    return _lire(appartenance.stationId, periode);
  }

  /// Une clé de mois inconnue de la caserne — un lien partagé, une URL
  /// bricolée — retombe sur le défaut plutôt que de rendre un écran vide.
  static PeriodeSaisie? _resoudre(List<PeriodeSaisie> periodes, String? cle) {
    for (final periode in periodes) {
      if (periode.cle == cle) return periode;
    }
    return periodeParDefautAdmin(periodes, DateTime.now());
  }

  Future<EtatMatrice> _lire(String stationId, PeriodeSaisie periode) async {
    final lignes = await ref
        .read(matriceRepositoryProvider)
        .matrice(stationId: stationId, periodeId: periode.id);

    return EtatMatrice(
      periode: periode,
      matrice: MatriceMois(
        lignes: List<LigneMatrice>.unmodifiable(lignes),
        nombreDeJours: periode.nombreDeJours,
      ),
    );
  }

  /// Relit le mois **en le gardant à l'écran** : un rafraîchissement ne vide
  /// pas la page sous les yeux de qui l'utilise. Le mode armé survit — c'est
  /// le même mois, et l'admin n'a rien demandé d'autre.
  Future<void> rafraichir() async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    final courant = state.value;
    if (stationId == null || courant == null) return;

    try {
      final relu = await _lire(stationId, courant.periode);
      if (!ref.mounted) return;
      state = AsyncValue<EtatMatrice?>.data(
        relu.copie(modeArme: courant.modeArme),
      );
    } on EchecMatrice catch (echec) {
      if (!ref.mounted) return;
      state = AsyncValue<EtatMatrice?>.data(
        courant.copie(messageErreur: echec.message),
      );
    }
  }

  /// Change de mois. Le chargement qui suit **désarme** la saisie.
  void choisirMois(String? cle) =>
      ref.read(moisMatriceProvider.notifier).definir(cle);

  /// Arme ou désarme la saisie par procuration.
  void armer({required bool arme}) {
    final courant = state.value;
    if (courant == null || courant.modeArme == arme) return;
    state = AsyncValue<EtatMatrice?>.data(courant.copie(modeArme: arme));
  }

  /// Le cycle d'une case, à la place d'un membre : non saisi → disponible →
  /// absent → non saisi.
  ///
  /// L'écriture part tout de suite et **aucune file ne la garde** : un chef de
  /// centre est à son bureau, et une écriture différée sur les disponibilités
  /// d'un tiers, rejouée une heure plus tard sans qu'il la voie partir, serait
  /// pire que l'échec (brief § 6.5).
  Future<void> basculer(CleCellule cle) async {
    final courant = state.value;
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (courant == null || stationId == null || !courant.modeArme) return;

    final ligne = courant.matrice.ligneDe(cle.userId);
    if (ligne == null) return;

    final vise = CelluleMatrice.suivant(ligne.etatDe(cle.jour, cle.creneau));
    final jour = DateTime(
      courant.periode.annee,
      courant.periode.mois,
      cle.jour,
    );

    // Optimiste, et **marquée comme saisie par un admin** : c'est exactement
    // ce que la base relira, puisque le déclencheur y pose `set_by`.
    state = AsyncValue<EtatMatrice?>.data(
      courant.copie(
        matrice: courant.matrice.avecCellule(
          userId: cle.userId,
          jour: cle.jour,
          creneau: cle.creneau,
          cellule: CelluleMatrice.parAdminPour(vise),
        ),
        sync: SyncEtat.enregistrement,
        erreurs: <CleCellule>{...courant.erreurs}..remove(cle),
        effacerMessage: true,
      ),
    );

    final depot = ref.read(matriceRepositoryProvider);
    try {
      final accepte = vise == DisponibiliteEtat.nonSaisi
          ? await depot.effacer(
              stationId: stationId,
              userId: cle.userId,
              jour: jour,
              creneau: cle.creneau,
            )
          : await depot.ecrire(
              stationId: stationId,
              userId: cle.userId,
              jour: jour,
              creneau: cle.creneau,
              etat: vise,
            );
      if (!accepte) throw const EchecMatrice(ErreurMatrice.lectureSeule);

      final apres = state.value;
      if (!ref.mounted || apres == null) return;
      state = AsyncValue<EtatMatrice?>.data(
        apres.copie(sync: SyncEtat.enregistre),
      );
    } on EchecMatrice catch (echec) {
      final apres = state.value;
      if (!ref.mounted || apres == null) return;
      // La case **garde la valeur demandée** et prend le contour d'erreur :
      // un rechargement rétablira la valeur du serveur.
      final suspendue = echec.erreur == ErreurMatrice.lectureSeule;
      state = AsyncValue<EtatMatrice?>.data(
        apres.copie(
          sync: SyncEtat.echec,
          erreurs: <CleCellule>{...apres.erreurs, cle},
          // Une caserne suspendue a sa propre bannière : la doubler d'une
          // bannière d'erreur dirait deux fois la même chose.
          messageErreur: suspendue ? null : AppStrings.matriceErreurEcriture,
          effacerMessage: suspendue,
          lectureSeule: apres.lectureSeule || suspendue,
        ),
      );
    }
  }
}

final AsyncNotifierProvider<MatriceController, EtatMatrice?>
matriceControllerProvider =
    AsyncNotifierProvider<MatriceController, EtatMatrice?>(
      MatriceController.new,
      isAutoDispose: true,
    );

/// Les lignes réellement affichées : filtrées, triées, **sans requête**.
///
/// Mémorisé par Riverpod : le tri de soixante lignes n'est refait que si la
/// matrice ou les filtres changent, pas à chaque image de la grille.
final Provider<List<LigneMatrice>> lignesVisiblesProvider =
    Provider<List<LigneMatrice>>((ref) {
      final etat = ref.watch(matriceControllerProvider).value;
      if (etat == null) return const <LigneMatrice>[];
      return ref.watch(filtresMatriceProvider).appliquer(etat.matrice.lignes);
    });
