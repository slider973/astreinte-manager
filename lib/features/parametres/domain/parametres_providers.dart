import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/theme/app_status.dart';
import '../data/parametres_repository.dart';
import 'parametres_caserne.dart';
import 'validation_parametres.dart';

/// Le dépôt des paramètres. Surchargé par un faux dans les tests.
final Provider<ParametresRepository> parametresRepositoryProvider =
    Provider<ParametresRepository>(
      (ref) => SupabaseParametresRepository(ref.watch(supabaseClientProvider)),
    );

/// Ce que l'écran « Paramètres » affiche : ce qui est enregistré, ce qui est
/// en cours de saisie, et ce qui a déjà été vu de travers.
///
/// Les deux documents sont gardés côte à côte parce que l'écran n'enregistre
/// pas au fil de la frappe : ces réglages forment un tout, et un effectif
/// enregistré à mi-saisie produirait un planning faux.
@immutable
class EtatParametres {
  const EtatParametres({
    required this.enregistres,
    required this.brouillon,
    this.touches = const <ChampParametre>{},
    this.tentative = false,
    this.sync = SyncEtat.repos,
    this.echecServeur,
  });

  const EtatParametres.initial(ParametresCaserne parametres)
    : this(enregistres: parametres, brouillon: parametres);

  /// L'état de la caserne dans la base, à la dernière lecture.
  final ParametresCaserne enregistres;

  /// L'état en cours de saisie.
  final ParametresCaserne brouillon;

  /// Les champs déjà quittés. Leur erreur s'affiche sans attendre
  /// l'enregistrement : personne ne doit découvrir une faute de frappe après
  /// avoir fait défiler six sections.
  final Set<ChampParametre> touches;

  /// Un enregistrement a été tenté : toutes les erreurs sont désormais
  /// visibles, touchées ou non.
  final bool tentative;

  final SyncEtat sync;

  /// La phrase du dernier refus venu du serveur, ou `null`.
  final String? echecServeur;

  Map<ChampParametre, String> get erreurs => validerParametres(brouillon);

  bool get modifie => brouillon != enregistres;

  bool get valide => erreurs.isEmpty;

  bool get enregistrement => sync == SyncEtat.enregistrement;

  /// L'erreur d'un champ, si elle doit être montrée maintenant.
  String? erreurVisible(ChampParametre champ) =>
      tentative || touches.contains(champ) ? erreurs[champ] : null;

  EtatParametres copyWith({
    ParametresCaserne? enregistres,
    ParametresCaserne? brouillon,
    Set<ChampParametre>? touches,
    bool? tentative,
    SyncEtat? sync,
    String? Function()? echecServeur,
  }) => EtatParametres(
    enregistres: enregistres ?? this.enregistres,
    brouillon: brouillon ?? this.brouillon,
    touches: touches ?? this.touches,
    tentative: tentative ?? this.tentative,
    sync: sync ?? this.sync,
    echecServeur: echecServeur == null ? this.echecServeur : echecServeur(),
  );
}

/// Le verdict d'un enregistrement, prêt à annoncer.
@immutable
class ResultatEnregistrement {
  const ResultatEnregistrement({required this.reussi, required this.message});

  final bool reussi;
  final String message;
}

/// Les paramètres de la caserne courante.
///
/// Auto-disposé : les réglages sont rares mais partagés — deux adjoints
/// peuvent régler la même caserne. L'écran rouvert relit, plutôt que de
/// rejouer un brouillon d'il y a dix minutes par-dessus le travail d'un autre.
class ParametresController extends AsyncNotifier<EtatParametres?> {
  @override
  Future<EtatParametres?> build() async {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (appartenance == null || !appartenance.estAdmin) return null;

    final parametres = await ref
        .read(parametresRepositoryProvider)
        .lire(appartenance.stationId);
    return EtatParametres.initial(parametres);
  }

  /// Relit la caserne et **jette le brouillon**. Appelée par « Réessayer » et
  /// par le bouton de relecture : reprendre depuis l'état réel est le but.
  Future<void> relire() async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) return;

    state = const AsyncValue<EtatParametres?>.loading();
    state = await AsyncValue.guard(() async {
      final parametres = await ref
          .read(parametresRepositoryProvider)
          .lire(stationId);
      return EtatParametres.initial(parametres);
    });
  }

  /// Modifie le brouillon. Le champ passé est marqué comme touché : son erreur
  /// devient visible dès qu'il est quitté.
  void modifier(
    ParametresCaserne brouillon, {
    ChampParametre? champ,
    bool toucher = false,
  }) {
    final etat = state.value;
    if (etat == null) return;

    state = AsyncValue<EtatParametres?>.data(
      etat.copyWith(
        brouillon: brouillon,
        touches: toucher && champ != null
            ? <ChampParametre>{...etat.touches, champ}
            : etat.touches,
        // Un refus serveur porte sur ce qui vient d'être envoyé : il cesse
        // d'être vrai dès que la saisie change.
        sync: etat.sync == SyncEtat.echec ? SyncEtat.repos : etat.sync,
        echecServeur: () => null,
      ),
    );
  }

  /// Marque un champ comme quitté, sans rien changer à sa valeur.
  void toucher(ChampParametre champ) {
    final etat = state.value;
    if (etat == null || etat.touches.contains(champ)) return;

    state = AsyncValue<EtatParametres?>.data(
      etat.copyWith(touches: <ChampParametre>{...etat.touches, champ}),
    );
  }

  /// Envoie le brouillon. Rien ne part tant qu'il ne passerait pas la
  /// contrainte de la base : le refus est montré ici, avec sa phrase.
  Future<ResultatEnregistrement> enregistrer() async {
    final etat = state.value;
    if (etat == null) {
      return const ResultatEnregistrement(
        reussi: false,
        message: AppStrings.parametresEchecGenerique,
      );
    }

    if (!etat.modifie) {
      return const ResultatEnregistrement(
        reussi: false,
        message: AppStrings.parametresAucuneModification,
      );
    }

    final erreurs = etat.erreurs;
    if (erreurs.isNotEmpty) {
      // Toutes les erreurs deviennent visibles, y compris celles des champs
      // jamais ouverts : c'est le seul moment où on peut les montrer toutes.
      state = AsyncValue<EtatParametres?>.data(
        etat.copyWith(tentative: true, sync: SyncEtat.repos),
      );
      return ResultatEnregistrement(
        reussi: false,
        message: AppStrings.parametresACorriger(erreurs.length),
      );
    }

    state = AsyncValue<EtatParametres?>.data(
      etat.copyWith(
        tentative: true,
        sync: SyncEtat.enregistrement,
        echecServeur: () => null,
      ),
    );

    try {
      final enregistres = await ref
          .read(parametresRepositoryProvider)
          .enregistrer(etat.brouillon);

      state = AsyncValue<EtatParametres?>.data(
        EtatParametres(
          enregistres: enregistres,
          brouillon: enregistres,
          sync: SyncEtat.enregistre,
        ),
      );
      return const ResultatEnregistrement(
        reussi: true,
        message: AppStrings.parametresEnregistres,
      );
    } on EchecParametres catch (echec) {
      state = AsyncValue<EtatParametres?>.data(
        etat.copyWith(
          tentative: true,
          sync: SyncEtat.echec,
          echecServeur: () => echec.message,
        ),
      );
      return ResultatEnregistrement(reussi: false, message: echec.message);
    } on Object {
      state = AsyncValue<EtatParametres?>.data(
        etat.copyWith(
          tentative: true,
          sync: SyncEtat.echec,
          echecServeur: () => AppStrings.parametresEchecGenerique,
        ),
      );
      return const ResultatEnregistrement(
        reussi: false,
        message: AppStrings.parametresEchecGenerique,
      );
    }
  }
}

final AsyncNotifierProvider<ParametresController, EtatParametres?>
parametresControllerProvider =
    AsyncNotifierProvider<ParametresController, EtatParametres?>(
      ParametresController.new,
      isAutoDispose: true,
    );
