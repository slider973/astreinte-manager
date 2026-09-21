import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/plateforme/telechargement.dart';
import 'astreinte.dart';
import 'ics_astreinte.dart';

/// Où en est l'ajout d'**une** astreinte à l'agenda de l'appareil.
///
/// Un seul état pour toute la feuille de détail, et pas un par créneau : on ne
/// télécharge qu'un fichier à la fois, et [astreinteId] dit lequel. Un bouton
/// n'affiche sa ligne d'état que si elle le concerne — sans quoi appuyer sur
/// « jour » ferait apparaître une confirmation sous « nuit ».
@immutable
class EtatAjoutCalendrier {
  const EtatAjoutCalendrier({
    this.astreinteId,
    this.enCours = false,
    this.resultat,
    this.nomFichier,
  });

  /// L'attribution concernée. `null` tant que rien n'a été tenté.
  final String? astreinteId;

  final bool enCours;

  /// Ce qu'il est advenu du fichier. `null` tant que rien n'a abouti.
  final ResultatTelechargement? resultat;

  /// Le nom du fichier remis. L'écran le **nomme** : dans une PWA installée il
  /// n'y a pas de barre de téléchargement pour le dire à sa place, et « c'est
  /// fait » sans nom de fichier n'apprend rien (même règle qu'au ticket 034).
  final String? nomFichier;

  /// Vrai quand cet état parle de cette astreinte-là.
  bool concerne(String id) => astreinteId == id;
}

/// Compose le fichier d'une astreinte et le remet à la personne.
///
/// **Rien n'est demandé au serveur.** Tout ce qu'il faut — la date, le créneau,
/// les heures de la caserne, son nom — a été lu avec la liste. C'est ce qui
/// permet à ce bouton de fonctionner hors ligne, comme le reste de la feuille
/// de détail (`design/027-mes-astreintes.md`, `design/028-export-ics.md § 6`).
///
/// L'enregistrement passe par [telechargementProvider] et rien d'autre :
/// partage système sur iPhone, ancre `download` ailleurs, les quatre issues
/// déjà écrites au ticket 034.
class AjoutCalendrierController extends Notifier<EtatAjoutCalendrier> {
  @override
  EtatAjoutCalendrier build() => const EtatAjoutCalendrier();

  /// Vrai si le fichier a été remis (enregistré ou partagé).
  Future<bool> ajouter({
    required Astreinte astreinte,
    required HeuresAffichage heures,
    required String nomCaserne,
  }) async {
    if (state.enCours) return false;
    state = EtatAjoutCalendrier(astreinteId: astreinte.id, enCours: true);

    final fichier = IcsAstreinte(
      astreinte: astreinte,
      heures: heures,
      nomCaserne: nomCaserne,
    );

    final resultat = await ref.read(telechargementProvider)(
      nomFichier: fichier.nomFichier,
      contenu: fichier.composer(),
      typeMime: IcsAstreinte.typeMime,
    );

    state = EtatAjoutCalendrier(
      astreinteId: astreinte.id,
      resultat: resultat,
      nomFichier: fichier.nomFichier,
    );

    return resultat == ResultatTelechargement.enregistre ||
        resultat == ResultatTelechargement.partage;
  }
}

/// `autoDispose` : la feuille refermée, il ne reste aucune confirmation à
/// rouvrir la prochaine fois.
final NotifierProvider<AjoutCalendrierController, EtatAjoutCalendrier>
ajoutCalendrierControllerProvider =
    NotifierProvider<AjoutCalendrierController, EtatAjoutCalendrier>(
      AjoutCalendrierController.new,
      isAutoDispose: true,
    );
