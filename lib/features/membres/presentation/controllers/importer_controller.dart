import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/plateforme/selection_fichier.dart';
import '../../../../core/plateforme/telechargement.dart';
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

  /// Combien d'adresses ont reçu un verdict du serveur, pour l'avancement.
  final int envoyees;

  final RapportInvitations? rapport;

  /// Le refus qui porte sur la requête entière — plafond atteint avant le
  /// premier envoi, caserne suspendue, droit perdu. Sa phrase peut venir du
  /// serveur (ticket 038), c'est donc l'échec qu'on garde, pas son code.
  final EchecInvitation? erreurRequete;

  /// Le moment où l'import pourra reprendre, quand le plafond l'a coupé.
  final DateTime? reprendreApres;

  /// Combien d'invitations restent à envoyer pour finir ce fichier.
  int get restantAEnvoyer {
    final total = apercu?.nombreAInviter ?? 0;
    final reste = total - envoyees;
    return reste < 0 ? 0 : reste;
  }
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
      state = EtatImport(erreurLecture: _phraseDeLecture(lecture));
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
      state = const EtatImport(
        erreurRequete: EchecInvitation(ErreurInvitation.reseau),
      );
    }
  }

  static String _phraseDeLecture(LectureFichier lecture) =>
      switch (lecture.erreur!) {
        ErreurFichier.vide => AppStrings.importFichierVide,
        ErreurFichier.colonneAdresseAbsente =>
          AppStrings.importColonneAdresseAbsente,
        ErreurFichier.tropDeLignes => AppStrings.importTropDeLignes(
          lecture.lignes.length,
          maxLignesFichier,
        ),
        ErreurFichier.tropGros => AppStrings.importTropGros(
          tailleLisible(maxOctetsFichier),
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
          envoyees: resultats.length,
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
      envoyees: resultats.length,
      rapport: rapport,
      erreurRequete: echecGlobal,
      reprendreApres: reprendreApres,
    );
  }

  /// Revient au choix d'un fichier, tout effacé.
  void recommencer() => state = const EtatImport();

  /// Efface la seule bannière, en gardant l'aperçu sous les yeux.
  void effacerErreur() {
    if (state.erreurLecture == null && state.erreurRequete == null) return;
    state = EtatImport(
      etape: state.etape,
      apercu: state.apercu,
      envoyees: state.envoyees,
      rapport: state.rapport,
      reprendreApres: state.reprendreApres,
    );
  }

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
