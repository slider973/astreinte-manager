import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/email.dart';

/// Le plafond de l'Edge Function `invite-member` : vingt adresses par envoi.
const int maxAdressesParEnvoi = 20;

/// Une saisie libre d'adresses, découpée et jugée.
///
/// Le champ accepte ce qu'un chef de centre a sous la main : une liste collée
/// depuis un tableur, une ligne par pompier, ou des virgules. Le découpage est
/// ici et non dans le widget : c'est une règle, pas un affichage.
@immutable
class ListeAdresses {
  const ListeAdresses._({
    required this.adresses,
    required this.invalides,
    required this.erreur,
  });

  /// Découpe [saisie] sur les virgules, points-virgules, espaces et retours à
  /// la ligne, normalise et dédoublonne en gardant l'ordre de saisie.
  factory ListeAdresses.depuisSaisie(String saisie) {
    final morceaux = saisie
        .split(RegExp(r'[\s,;]+'))
        .map(normaliserEmail)
        .where((String part) => part.isNotEmpty);

    final vues = <String>{};
    final retenues = <String>[];
    final invalides = <String>[];
    for (final adresse in morceaux) {
      if (!vues.add(adresse)) continue;
      if (emailValide(adresse)) {
        retenues.add(adresse);
      } else {
        invalides.add(adresse);
      }
    }

    return ListeAdresses._(
      adresses: List<String>.unmodifiable(retenues),
      invalides: List<String>.unmodifiable(invalides),
      erreur: _juger(retenues, invalides),
    );
  }

  /// Les adresses valides, dédoublonnées.
  final List<String> adresses;

  /// Les morceaux qui ne ressemblent pas à une adresse.
  final List<String> invalides;

  /// Ce qui empêche l'envoi, ou `null` si la liste est envoyable.
  final String? erreur;

  bool get envoyable => erreur == null;

  static String? _juger(List<String> retenues, List<String> invalides) {
    if (invalides.isNotEmpty) {
      return AppStrings.inviterAdresseInvalide(invalides.first);
    }
    if (retenues.isEmpty) return AppStrings.inviterAucuneAdresse;
    if (retenues.length > maxAdressesParEnvoi) {
      return AppStrings.inviterPlafond(retenues.length);
    }
    return null;
  }
}
