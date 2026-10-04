import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/caserne_ouverte.dart';
import '../../../core/theme/app_status.dart';
import '../../dispos/domain/disponibilite_mois.dart';
import '../../dispos/domain/dispos_providers.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../../planning/domain/ligne_matrice.dart';
import '../../planning/domain/matrice_providers.dart';
import 'echange.dart';
import 'echanges_providers.dart';

/// La charge d'une personne **après** l'échange, sur le mois de la garde qui
/// change de main (`design/073 § 8.3`).
@immutable
class ChargePersonne {
  const ChargePersonne({
    required this.userId,
    required this.nom,
    required this.mois,
    required this.annee,
    required this.astreintes,
    required this.unitesWeekend,
    this.maxAstreintes,
    this.maxWeekends,
    this.libere = false,
    this.weekendAjoute = false,
    this.disponibilite,
  });

  final String userId;
  final String nom;
  final int mois;
  final int annee;

  /// Astreintes du mois après le mouvement, comptées comme `v_member_load`.
  final int astreintes;

  /// Unités de weekend du mois après le mouvement. **Un majorant** quand
  /// [weekendAjoute] : la garde reçue tombe dans une unité de weekend, que la
  /// personne couvre peut-être déjà — la matrice ne dit que le compte, pas
  /// les unités. La base tranche à la validation.
  final int unitesWeekend;

  final int? maxAstreintes;
  final int? maxWeekends;

  /// Vrai pour A dans une cession : sa charge baisse.
  final bool libere;

  final bool weekendAjoute;

  /// La disponibilité déclarée de celui qui reprend, sur le créneau repris.
  /// `null` pour celui qui libère.
  final DisponibiliteEtat? disponibilite;

  /// Le plafond d'astreintes serait dépassé : **règle bloquante** à la
  /// validation, « Valider » est grisé.
  bool get depasseAstreintes =>
      !libere && maxAstreintes != null && astreintes > maxAstreintes!;

  /// Le plafond de weekends **pourrait** être dépassé : averti, non bloquant
  /// — voir [unitesWeekend].
  bool get depasseWeekends =>
      !libere &&
      weekendAjoute &&
      maxWeekends != null &&
      unitesWeekend > maxWeekends!;
}

/// Calcule la charge après l'échange. Fonction pure : c'est elle qui est
/// testée.
///
/// [lignes] rend la ligne de matrice d'un membre pour un mois (`AAAA-MM`), ou
/// `null` quand le mois n'a pas pu être lu.
List<ChargePersonne> chargeApresEchange(
  Echange echange,
  LigneMatrice? Function(String cleMois, String userId) lignes,
) {
  final resultat = <ChargePersonne>[];
  final pairId = echange.pairId;
  if (pairId == null) return resultat;
  final rendue = echange.gardeRendue;

  ChargePersonne? recoit({
    required String userId,
    required String nom,
    required GardeEchange recue,
    GardeEchange? donnee,
  }) {
    final ligne = lignes(recue.cleMois, userId);
    if (ligne == null) return null;
    final memeMois = donnee != null && donnee.cleMois == recue.cleMois;
    final weekend = uniteWeekend(recue.jour) != null;
    return ChargePersonne(
      userId: userId,
      nom: nom,
      mois: recue.jour.month,
      annee: recue.jour.year,
      astreintes: ligne.astreintes + 1 - (memeMois ? 1 : 0),
      unitesWeekend: ligne.unitesWeekend + (weekend ? 1 : 0),
      maxAstreintes: ligne.maxAstreintes,
      maxWeekends: ligne.maxWeekends,
      weekendAjoute: weekend,
      disponibilite: ligne.etatDe(recue.jour.day, recue.creneau),
    );
  }

  final b = recoit(
    userId: pairId,
    nom: echange.pairNom,
    recue: echange.garde,
    donnee: rendue,
  );
  if (b != null) resultat.add(b);

  if (rendue != null) {
    final a = recoit(
      userId: echange.demandeurId,
      nom: echange.demandeurNom,
      recue: rendue,
      donnee: echange.garde,
    );
    if (a != null) resultat.add(a);
  } else {
    final ligne = lignes(echange.garde.cleMois, echange.demandeurId);
    if (ligne != null) {
      resultat.add(
        ChargePersonne(
          userId: echange.demandeurId,
          nom: echange.demandeurNom,
          mois: echange.garde.jour.month,
          annee: echange.garde.jour.year,
          astreintes: ligne.astreintes > 0 ? ligne.astreintes - 1 : 0,
          unitesWeekend: ligne.unitesWeekend,
          maxAstreintes: ligne.maxAstreintes,
          maxWeekends: ligne.maxWeekends,
          libere: true,
        ),
      );
    }
  }
  return resultat;
}

/// La charge après l'échange [echangeId], lue depuis la matrice du ou des
/// mois concernés : `availability_matrix` porte déjà les plafonds, la charge
/// de `v_member_load` et la disponibilité déclarée — **aucune requête
/// nouvelle**, une lecture par mois touché.
final chargeEchangeProvider = FutureProvider.autoDispose
    .family<List<ChargePersonne>, String>((ref, String echangeId) async {
      final caserne = ref.watch(caserneOuverteIdProvider);
      final echange = caserneOuverteSeulement(
        ref,
        echangesControllerProvider,
      ).value?.parId(echangeId);
      if (caserne == null || echange == null) {
        return const <ChargePersonne>[];
      }
      final periodes = await ref.watch(periodesProvider.future);
      final mois = <String>{
        echange.garde.cleMois,
        ?echange.gardeRendue?.cleMois,
      };
      final matrices = <String, Map<String, LigneMatrice>>{};
      for (final cle in mois) {
        PeriodeSaisie? periode;
        for (final p in periodes) {
          if (p.cle == cle) periode = p;
        }
        if (periode == null) continue;
        final lignes = await ref
            .read(matriceRepositoryProvider)
            .matrice(stationId: caserne, periodeId: periode.id);
        matrices[cle] = <String, LigneMatrice>{
          for (final ligne in lignes) ligne.userId: ligne,
        };
      }
      return chargeApresEchange(
        echange,
        (String cle, String userId) => matrices[cle]?[userId],
      );
    });
