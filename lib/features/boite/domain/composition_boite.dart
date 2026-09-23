import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/domain/centre_providers.dart';
import '../../notifications/domain/notification_interne.dart';
import '../../propositions/domain/proposition.dart';
import '../../propositions/domain/propositions_providers.dart';

/// La composition de la Boîte : deux lectures déjà faites ailleurs, réunies
/// derrière trois onglets.
///
/// **Aucune requête nouvelle.** Les propositions viennent du contrôleur du
/// ticket 021, les rappels de celui du ticket 026 ; la Boîte ne fait que les
/// assembler. C'est la condition posée par le chantier 064b, et c'est aussi
/// pourquoi ces deux contrôleurs ne sont pas auto-disposés : trois onglets qui
/// relanceraient chacun leur lecture feraient six requêtes pour un écran.

/// Une ligne de l'onglet « Tout ».
sealed class ElementBoite {
  const ElementBoite();

  /// L'instant qui classe la ligne dans la liste fusionnée.
  DateTime get instant;

  /// La clé d'identité de la ligne, pour `ValueKey`.
  String get cle;
}

/// Une proposition en attente. Elle ouvre la réponse.
final class PropositionBoite extends ElementBoite {
  const PropositionBoite(this.proposition);

  final Proposition proposition;

  /// **L'instant où la question a été posée**, pas le jour du créneau : la
  /// Boîte est un journal d'arrivée, et une proposition reçue ce matin pour
  /// mars se lit au-dessus d'un rappel d'hier. `proposed_at` est nul en
  /// théorie seulement (`Proposition.proposeeLe`) ; le jour du créneau est le
  /// repli, faute de mieux.
  @override
  DateTime get instant => proposition.proposeeLe ?? proposition.jour;

  @override
  String get cle => proposition.id;
}

/// Un rappel : une notification qui n'est pas une proposition.
final class RappelBoite extends ElementBoite {
  const RappelBoite(this.notification);

  final NotificationInterne notification;

  @override
  DateTime get instant => notification.creeLe;

  @override
  String get cle => notification.id;
}

/// Les deux listes fusionnées, **la plus récente en premier**.
///
/// Fonction pure : c'est elle que les tests éprouvent. L'égalité des instants
/// est départagée par la proposition — ce à quoi il faut répondre passe devant
/// ce qui est seulement à lire.
List<ElementBoite> fusionner({
  required List<Proposition> propositions,
  required List<NotificationInterne> rappels,
}) {
  final elements = <ElementBoite>[
    for (final proposition in propositions) PropositionBoite(proposition),
    for (final rappel in rappels) RappelBoite(rappel),
  ]..sort((ElementBoite a, ElementBoite b) {
    final parInstant = b.instant.compareTo(a.instant);
    if (parInstant != 0) return parInstant;
    if (a is PropositionBoite && b is! PropositionBoite) return -1;
    if (b is PropositionBoite && a is! PropositionBoite) return 1;
    return 0;
  });
  return List<ElementBoite>.unmodifiable(elements);
}

/// Ce que la Boîte a à montrer, et ce qui a échoué.
///
/// **Une source en panne n'efface jamais l'autre** : les propositions restent
/// justes quand les notifications tombent, et réciproquement. Chaque onglet
/// porte alors son propre bloc « Réessayer ».
@immutable
class EtatBoite {
  const EtatBoite({
    required this.propositions,
    required this.rappels,
    required this.tout,
    required this.nonLus,
    required this.chargePropositions,
    required this.chargeRappels,
    required this.echecPropositions,
    required this.echecRappels,
  });

  /// Les propositions en attente, dans l'ordre du dépôt (le tri par mois est
  /// fait par `elementsPropositionsProvider`).
  final List<Proposition> propositions;

  /// Les notifications de l'onglet « Rappels », la plus récente en premier.
  final List<NotificationInterne> rappels;

  /// Les deux, fusionnées par date décroissante.
  final List<ElementBoite> tout;

  /// Les rappels non lus : le nombre du titre, de la cloche et de la pastille.
  final int nonLus;

  /// Une source n'a encore **rien** rendu : l'onglet montre son squelette.
  final bool chargePropositions;
  final bool chargeRappels;

  /// Une source a échoué **et n'a rien à montrer**.
  ///
  /// La condition porte sur le contenu, jamais sur `hasValue` : un
  /// `AsyncValue` en erreur garde la valeur du calcul précédent, et les deux
  /// contrôleurs en produisent une avant même d'avoir lu. C'est le piège
  /// consigné au ticket 023 puis au 064a, et il se reverra.
  final bool echecPropositions;
  final bool echecRappels;

  bool get toutVide => tout.isEmpty;
}

/// Compose [EtatBoite] à partir des deux états asynchrones. Fonction pure.
EtatBoite etatBoiteDe({
  required AsyncValue<EtatPropositions> propositions,
  required AsyncValue<EtatCentre> centre,
}) {
  final listePropositions = propositions.value?.propositions;
  final etatCentre = centre.value;
  final rappels = etatCentre?.rappels ?? const <NotificationInterne>[];

  return EtatBoite(
    propositions: listePropositions ?? const <Proposition>[],
    rappels: rappels,
    tout: fusionner(
      propositions: listePropositions ?? const <Proposition>[],
      rappels: rappels,
    ),
    nonLus: etatCentre?.nonLues ?? 0,
    chargePropositions: listePropositions == null && !propositions.hasError,
    chargeRappels: etatCentre == null && !centre.hasError,
    echecPropositions:
        propositions.hasError && (listePropositions?.isEmpty ?? true),
    echecRappels: centre.hasError && (etatCentre?.notifications.isEmpty ?? true),
  );
}

/// L'état de la Boîte, recomposé à chaque changement de l'une des deux
/// sources.
final Provider<EtatBoite> etatBoiteProvider = Provider<EtatBoite>(
  (ref) => etatBoiteDe(
    propositions: ref.watch(propositionsControllerProvider),
    centre: ref.watch(centreNotificationsProvider),
  ),
);

/// L'identifiant de la proposition dont la réponse est ouverte, ou `null`.
///
/// Un provider et non un `setState` : la feuille de bas d'écran vit dans une
/// autre route que l'écran, et le volet latéral dans une autre branche de
/// l'arbre. Les deux doivent lire la même sélection, et la perdre ensemble
/// quand la proposition quitte la liste.
class PropositionEnReponse extends Notifier<String?> {
  @override
  String? build() => null;

  void choisir(String id) => state = id;

  void fermer() => state = null;
}

final NotifierProvider<PropositionEnReponse, String?>
propositionEnReponseProvider =
    NotifierProvider<PropositionEnReponse, String?>(PropositionEnReponse.new);

/// La proposition dont la réponse est ouverte, résolue **contre la liste
/// courante**.
///
/// D'où le fait qu'elle devienne `null` toute seule quand la réponse part :
/// la ligne quitte la liste, et le volet se referme sans que personne n'ait à
/// y penser.
final Provider<Proposition?> propositionOuverteProvider =
    Provider<Proposition?>((ref) {
      final id = ref.watch(propositionEnReponseProvider);
      if (id == null) return null;
      for (final proposition
          in ref.watch(etatBoiteProvider).propositions) {
        if (proposition.id == id) return proposition;
      }
      return null;
    });
