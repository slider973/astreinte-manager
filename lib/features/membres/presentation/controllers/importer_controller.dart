import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/plateforme/selection_fichier.dart';
import '../../../../core/plateforme/telechargement.dart';
import '../../../../core/reseau/connectivite.dart';
import '../../../../core/session/session_providers.dart';
import '../../domain/fichier_membres.dart';
import '../../domain/import_membres.dart';
import '../../domain/invitation.dart';
import '../../domain/membre_caserne.dart';
import '../../domain/membres_providers.dart';

/// Les trois temps de l'écran, sur une seule route.
///
/// Ce n'est pas un assistant : le deuxième temps renvoie au premier autant de
/// fois qu'on veut, et un repère « étape 2 sur 3 » mentirait.
enum EtapeImport { choix, apercu, rapport }

/// L'état de l'import, du choix du fichier au compte rendu.
@immutable
class EtatImport {
  const EtatImport({
    this.etape = EtapeImport.choix,
    this.lectureEnCours = false,
    this.erreurLecture,
    this.apercu,
    this.envoiEnCours = false,
    this.envoyees = 0,
    this.rapport,
    this.erreurRequete,
    this.reprendreApres,
  });

  final EtapeImport etape;

  /// Le sélecteur est ouvert, ou le fichier est en cours de découpage.
  final bool lectureEnCours;

  /// Ce qui empêche d'aller plus loin avec ce fichier, déjà en français.
  final String? erreurLecture;

  final ApercuImport? apercu;

  final bool envoiEnCours;

  /// Combien d'invitations sont **parties**, pour l'avancement.
  ///
  /// Le compte des verdicts rendus par le serveur n'est pas celui-là : une
  /// adresse refusée reçoit un verdict sans que personne ne soit invité. Les
  /// mêler faisait annoncer « 60 invitations sur 60 envoyées » pendant
  /// l'envoi, puis « 57 envoyées, 3 échecs » à l'écran suivant.
  final int envoyees;

  final RapportInvitations? rapport;

  /// Le refus qui porte sur la requête entière — plafond atteint avant le
  /// premier envoi, caserne suspendue, droit perdu. Sa phrase peut venir du
  /// serveur (ticket 038), c'est donc l'échec qu'on garde, pas son code.
  final EchecInvitation? erreurRequete;

  /// Le moment où l'import pourra reprendre, quand le plafond l'a coupé.
  final DateTime? reprendreApres;
}

/// Lit un fichier de membres, le montre, puis l'envoie par lots de vingt.
///
/// **Rien ne part avant [lancer].** La lecture, le jugement de chaque ligne et
/// l'annonce de budget sont des lectures : elles n'écrivent rien, et elles
/// peuvent être rejouées autant de fois qu'on redépose un fichier corrigé.
class ImporterController extends Notifier<EtatImport> {
  @override
  EtatImport build() => const EtatImport();

  /// Ouvre le sélecteur, lit le fichier, et prépare l'aperçu.
  Future<void> choisirFichier() async {
    if (state.lectureEnCours || state.envoiEnCours) return;
    state = const EtatImport(lectureEnCours: true);

    final selection = await ref.read(selectionFichierProvider)(
      typesAcceptes: typesFichierAcceptes,
      tailleMaxOctets: maxOctetsFichier,
    );

    switch (selection) {
      // Refermer le sélecteur n'est pas un échec : on revient au temps 1 sans
      // rien dire.
      case SelectionAnnulee():
        state = const EtatImport();
      case SelectionIndisponible():
        state = const EtatImport(erreurLecture: AppStrings.importIndisponible);
      case FichierTropGros(:final octets, :final limite):
        state = EtatImport(
          erreurLecture: AppStrings.importTropGros(
            tailleLisible(octets),
            tailleLisible(limite),
          ),
        );
      case FichierChoisi(:final nom, :final octets):
        await _preparer(nom, octets);
    }
  }

  Future<void> _preparer(String nomFichier, Uint8List octets) async {
    final lecture = lireFichierMembres(nomFichier: nomFichier, octets: octets);
    if (!lecture.lisible) {
      state = EtatImport(
        erreurLecture: _phraseDeLecture(lecture, octets.length),
      );
      return;
    }

    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) {
      state = const EtatImport(
        erreurRequete: EchecInvitation(ErreurInvitation.caserneInconnue),
      );
      return;
    }

    final depot = ref.read(membresRepositoryProvider);
    try {
      final (List<MembreCaserne> membres, List<Invitation> invitations) = await (
        depot.membres(stationId),
        depot.invitationsEnAttente(stationId),
      ).wait;

      // Le budget a le droit d'échouer : c'est un confort d'annonce, pas une
      // condition de l'import. Le serveur, lui, comptera de toute façon.
      BudgetInvitations? budget;
      try {
        budget = await depot.budgetInvitations(stationId);
      } on Object {
        budget = null;
      }

      state = EtatImport(
        etape: EtapeImport.apercu,
        apercu: preparerApercu(
          lecture: lecture,
          membres: membres,
          invitations: invitations,
          budget: budget,
        ),
      );
    } on Object {
      // Ce qui a échoué est une **lecture** de la caserne. On ne sait pas
      // pourquoi : seul un navigateur qui se dit hors ligne autorise à parler
      // de connexion, un « oui » de sa part ne prouvant rien
      // (`lib/core/reseau/connectivite.dart`). Sinon, on s'en tient à ce qu'on
      // sait, et relire garde du sens.
      state = EtatImport(
        erreurRequete: EchecInvitation(
          ref.read(connectiviteProvider).enLigne
              ? ErreurInvitation.inconnue
              : ErreurInvitation.reseau,
        ),
      );
    }
  }

  /// La phrase d'un fichier qu'on ne peut pas lire. [octets] est la taille
  /// **réelle** du fichier déposé : l'annoncer à la place de la limite faisait
  /// dire au message « Ce fichier fait 512 Ko. La limite est de 512 Ko. »
  static String _phraseDeLecture(LectureFichier lecture, int octets) =>
      switch (lecture.erreur!) {
        ErreurFichier.vide => AppStrings.importFichierVide,
        ErreurFichier.colonneAdresseAbsente =>
          AppStrings.importColonneAdresseAbsente,
        ErreurFichier.tropDeLignes => AppStrings.importTropDeLignes(
          lecture.lignes.length,
          maxLignesFichier,
        ),
        ErreurFichier.tropGros => AppStrings.importTropGros(
          tailleLisible(octets),
          tailleLisible(maxOctetsFichier),
        ),
        ErreurFichier.illisible => AppStrings.importFichierIllisible,
      };

  /// Envoie les invitations, par lots de vingt, jusqu'au bout ou jusqu'au
  /// plafond.
  ///
  /// **On s'arrête franchement.** L'Edge Function court-circuite déjà les
  /// adresses suivantes dès qu'une est refusée pour cause de débit ; le client
  /// fait pareil entre deux lots. Tenter les quarante restantes pour récolter
  /// quarante fois la même phrase ne sert personne.
  Future<void> lancer() async {
    final apercu = state.apercu;
    if (apercu == null || state.envoiEnCours || !apercu.envoyable) return;

    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) {
      state = EtatImport(
        etape: state.etape,
        apercu: apercu,
        erreurRequete: const EchecInvitation(ErreurInvitation.caserneInconnue),
      );
      return;
    }

    final lots = decouperEnLots(
      apercu.aInviter
          .map((LigneApercu l) => PersonneAInviter.depuisLigne(l.ligne))
          .toList(growable: false),
    );

    state = EtatImport(
      etape: EtapeImport.apercu,
      apercu: apercu,
      envoiEnCours: true,
    );

    final depot = ref.read(membresRepositoryProvider);
    final resultats = <ResultatInvitation>[];
    EchecInvitation? echecGlobal;
    DateTime? reprendreApres;

    for (final lot in lots) {
      try {
        final rapport = await depot.inviterPersonnes(
          stationId: stationId,
          personnes: lot,
        );
        resultats.addAll(rapport.resultats);
        state = EtatImport(
          etape: EtapeImport.apercu,
          apercu: apercu,
          envoiEnCours: true,
          envoyees: _parties(resultats),
        );

        final coupe = rapport.resultats.firstWhere(
          (ResultatInvitation r) =>
              r.motif == MotifEchecInvitation.debitAtteint,
          orElse: () => const ResultatInvitation(
            email: '',
            statut: StatutResultatInvitation.invitee,
          ),
        );
        if (coupe.motif == MotifEchecInvitation.debitAtteint) {
          reprendreApres = coupe.plafond?.reessayerLe;
          break;
        }
      } on EchecInvitation catch (echec) {
        // Le refus global : aucune adresse du lot n'est passée. Ce qui précède
        // reste acquis, et c'est précisément pourquoi on ne jette pas tout.
        echecGlobal = echec;
        reprendreApres = echec.plafond?.reessayerLe;
        break;
      } on Object {
        echecGlobal = const EchecInvitation(ErreurInvitation.inconnue);
        break;
      }
    }

    // La liste de l'écran précédent n'a pas de temps réel : elle se relit.
    ref.invalidate(membresControllerProvider);

    final rapport = RapportInvitations(
      resultats: List<ResultatInvitation>.unmodifiable(resultats),
    );

    // Rien n'a été tenté : on reste sur l'aperçu avec la bannière, plutôt que
    // d'afficher un « Résultat par adresse » vide.
    if (resultats.isEmpty) {
      state = EtatImport(
        etape: EtapeImport.apercu,
        apercu: apercu,
        erreurRequete: echecGlobal,
        reprendreApres: reprendreApres,
      );
      return;
    }

    state = EtatImport(
      etape: EtapeImport.rapport,
      apercu: apercu,
      envoyees: rapport.envoyees,
      rapport: rapport,
      erreurRequete: echecGlobal,
      reprendreApres: reprendreApres,
    );
  }

  /// Le seul compte qui vaille pour l'avancement : les adresses que le serveur
  /// a acceptées. Un refus est un verdict, pas un envoi.
  static int _parties(List<ResultatInvitation> resultats) =>
      resultats.where((ResultatInvitation r) => !r.enEchec).length;

  /// Revient au choix d'un fichier, tout effacé.
  void recommencer() => state = const EtatImport();

  // Pas de `effacerErreur` : l'écran a choisi de ne pas mettre de croix sur
  // ses bannières — « une bannière qui décrit un état persistant ne se ferme
  // pas » (`_banniere`) —, et le refus disparaît en déposant un autre fichier.

  /// Remet un fichier d'exemple à la personne. Vrai si le navigateur l'a rangé.
  Future<bool> telechargerExemple() async {
    final resultat = await ref.read(telechargementProvider)(
      nomFichier: nomFichierExemple,
      contenu: fichierExempleMembres(),
      typeMime: 'text/csv;charset=utf-8',
    );
    return resultat != ResultatTelechargement.impossible;
  }
}

/// Auto-disposé : un fichier lu ne survit pas à la fermeture de l'écran. Il
/// porte des noms et des adresses, et rien ne justifie de les garder en mémoire
/// une fois l'import fait.
final NotifierProvider<ImporterController, EtatImport> importerControllerProvider =
    NotifierProvider<ImporterController, EtatImport>(
      ImporterController.new,
      isAutoDispose: true,
    );
