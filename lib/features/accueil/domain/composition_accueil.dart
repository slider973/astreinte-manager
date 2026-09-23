import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/session_providers.dart';
import '../../astreintes/domain/astreinte.dart';
import '../../astreintes/domain/astreintes_providers.dart';
import '../../dispos/domain/dispos_providers.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../../dispos/presentation/controllers/saisie_controller.dart';
import '../../propositions/domain/proposition.dart';
import '../../propositions/domain/propositions_providers.dart';
import 'tableau_bord.dart';

/// La composition du tableau de bord : des providers dérivés pour l'écran, et
/// les fonctions pures qu'ils appellent, qui sont ce que les tests éprouvent.
///
/// **Une limite connue de Riverpod 3.3**, consignée ici parce qu'elle se
/// reverra : Riverpod met en pause les abonnements des widgets qu'une route
/// empilée recouvre, et une chaîne de providers dérivés que seul l'écran du
/// dessous lit reste *sale* jusqu'à son retour — où elle se recalcule pendant
/// la construction d'une image, ce dont Flutter se plaint par une assertion de
/// débogage. Le cas se produit en changeant de caserne depuis le profil, puis
/// en revenant. **Sans conséquence en production** — l'assertion n'existe
/// qu'en débogage et la reconstruction a lieu à l'image suivante —, mais un
/// test qui traverse cette image doit la consommer et le dire.

/// La première période encore ouverte à la saisie, ou `null`.
///
/// C'est **exactement** celle que le Calendrier ouvre par défaut
/// (`periodeParDefaut`), à une nuance près qui compte ici : quand aucune n'est
/// ouverte, le Calendrier montre la dernière verrouillée, et l'accueil ne
/// montre rien du tout. Il n'y a alors rien à faire, et un bloc qui le dirait
/// serait du bruit permanent.
PeriodeSaisie? premierePeriodeOuverte(List<PeriodeSaisie> periodes) {
  final triees = <PeriodeSaisie>[...periodes]
    ..sort((PeriodeSaisie a, PeriodeSaisie b) => a.cle.compareTo(b.cle));
  for (final periode in triees) {
    if (periode.ouverte) return periode;
  }
  return null;
}

/// La section « Disponibilités » de l'accueil.
///
/// Elle se compose des périodes et de l'état de saisie du Calendrier :
/// **aucune requête de plus**. Le mois compté est celui que le Calendrier
/// affiche ; quand il a été déplacé ailleurs, l'accueil retombe sur l'appel à
/// saisir plutôt que d'annoncer un compte qui décrirait un autre mois.
final Provider<AppelDispos?> appelDisposProvider = Provider<AppelDispos?>(
  (ref) => appelDispos(
    periodes: ref.watch(periodesProvider).value ?? const <PeriodeSaisie>[],
    saisie: ref.watch(saisieControllerProvider).value,
    maintenant: ref.watch(horlogeAstreintesProvider)(),
  ),
);

/// La même, en fonction pure : c'est elle qui est testée.
AppelDispos? appelDispos({
  required List<PeriodeSaisie> periodes,
  required DateTime maintenant,
  EtatSaisie? saisie,
}) {
  final ouverte = premierePeriodeOuverte(periodes);
  if (ouverte == null) return null;

  if (saisie != null && saisie.periode.cle == ouverte.cle) {
    // « Tout est saisi » veut dire : plus une seule case sans valeur. Les deux
    // créneaux de chaque jour du mois, ni plus ni moins — `valeurs` ne garde
    // jamais un « non saisi » (`docs/SCHEMA.md § 2.6`).
    final attendues = ouverte.nombreDeJours * 2;
    if (saisie.mois.valeurs.length >= attendues) {
      final compteurs = saisie.compteurs;
      return SaisieFaite(
        cleMois: ouverte.cle,
        libelleMois: AppStrings.moisNomEtAnnee(ouverte.mois, ouverte.annee),
        jours: compteurs.jours,
        nuits: compteurs.nuits,
      );
    }
  }

  return SaisieAFaire(
    cleMois: ouverte.cle,
    nomMois: AppStrings.moisLongs[ouverte.mois - 1],
    joursRestants: ouverte.joursAvantLimite(maintenant) ?? 0,
  );
}

/// Tout ce que l'accueil affiche, à partir des deux lectures qui le nourrissent.
///
/// **Chargement** tant qu'aucune des deux sources n'a répondu, **erreur** si
/// aucune n'a répondu et qu'au moins une a échoué, **contenu** dès que l'une
/// des deux a quelque chose : une lecture d'astreintes en panne ne doit pas
/// effacer des propositions parfaitement lues, et réciproquement.
final Provider<AsyncValue<TableauBord>> tableauBordProvider =
    Provider<AsyncValue<TableauBord>>(
      (ref) => tableauBordDe(
        astreintes: ref.watch(astreintesControllerProvider),
        propositions: ref.watch(propositionsControllerProvider),
        aujourdhui: ref.watch(horlogeAstreintesProvider)(),
        nomCaserne: ref.watch(appartenanceCouranteProvider)?.nomCaserne ?? '',
        dispos: ref.watch(appelDisposProvider),
      ),
    );

/// La même, en fonction pure : c'est elle qui est testée.
AsyncValue<TableauBord> tableauBordDe({
  required AsyncValue<EtatAstreintes> astreintes,
  required AsyncValue<EtatPropositions> propositions,
  required DateTime aujourdhui,
  required String nomCaserne,
  AppelDispos? dispos,
}) {
  final donnees = astreintes.value?.donnees;
  final liste = propositions.value?.propositions;
  // **L'état complet des deux sources, pas leur contenu projeté.** Un
  // `whenData` pour ne garder que la liste efface l'erreur au passage : la
  // section des propositions se croyait vide alors que la lecture avait
  // échoué. Vu en test, et c'est exactement le piège du ticket 023 sous un
  // autre visage.

  if (donnees == null && liste == null) {
    final erreur = astreintes.error ?? propositions.error;
    if (erreur == null) return const AsyncValue<TableauBord>.loading();
    return AsyncValue<TableauBord>.error(
      erreur,
      astreintes.stackTrace ?? propositions.stackTrace ?? StackTrace.current,
    );
  }

  return AsyncValue<TableauBord>.data(
    composerTableauBord(
      aujourdhui: aujourdhui,
      astreintes: donnees ?? const MesAstreintes(),
      propositions: liste ?? const <Proposition>[],
      nomCaserne: nomCaserne,
      dispos: dispos,
      // **La condition porte sur le contenu, jamais sur `hasValue`.** Un
      // `AsyncValue` en erreur garde la valeur du calcul précédent, et les
      // deux contrôleurs en produisent une avant même d'avoir lu : ils
      // rendent un état vide tant que la session ou l'appartenance manque.
      // Tester la seule présence d'une valeur laissait donc une lecture en
      // panne passer pour « tu n'as rien » — le piège déjà consigné au
      // ticket 023 (`DESIGN.md § Écarts`).
      echecAstreintes:
          astreintes.hasError && (donnees?.astreintes.isEmpty ?? true),
      echecPropositions: propositions.hasError && (liste?.isEmpty ?? true),
    ),
  );
}

/// Le prénom affiché par la salutation.
///
/// Le premier mot du nom d'usage : « Dubois Jean-Marc » donne « Dubois », mais
/// la caserne écrit plutôt « Marie L. », et c'est « Marie » qu'on veut lire.
/// Vide quand la caserne n'a pas de nom d'usage — la salutation tient alors
/// toute seule, sans inventer un prénom à partir d'une adresse électronique.
String prenomDe(String? nomAffiche) {
  final nom = (nomAffiche ?? '').trim();
  if (nom.isEmpty) return '';
  return nom.split(RegExp(r'\s+')).first;
}

/// L'heure à partir de laquelle on dit « Bonsoir ».
const int heureDuSoir = 18;

/// La salutation de l'en-tête, selon l'heure.
String salutationDe(DateTime maintenant) => maintenant.hour >= heureDuSoir
    ? AppStrings.accueilBonsoir
    : AppStrings.accueilBonjour;
