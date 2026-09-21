import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/plateforme/telechargement.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/export_repository.dart';
import 'export_donnees.dart';

/// Le dépôt de l'export. Surchargé par un faux dans les tests.
final Provider<ExportRepository> exportRepositoryProvider =
    Provider<ExportRepository>(
      (ref) => SupabaseExportRepository(ref.watch(supabaseClientProvider)),
    );

/// Où en est l'export des données personnelles.
@immutable
class EtatExport {
  const EtatExport({
    this.enCours = false,
    this.resultat,
    this.echec,
    this.nomFichier,
  });

  final bool enCours;

  /// Ce qu'il est advenu du fichier. `null` tant que rien n'a été tenté.
  final ResultatTelechargement? resultat;

  /// `null` tant que rien n'a échoué.
  final EchecExport? echec;

  /// Le nom du fichier remis, quand il y en a un. L'écran le **nomme** dans sa
  /// confirmation : dans une PWA installée il n'y a pas de barre de
  /// téléchargement pour le dire à sa place, et « c'est fait » sans nom de
  /// fichier n'apprend rien à quelqu'un qui doit ensuite le retrouver.
  final String? nomFichier;

  String? get message => echec?.message;
}

/// Demande l'export au serveur, puis le remet à la personne.
///
/// **Deux gestes, une seule attente.** Le serveur compose le dossier, la
/// plateforme range le fichier. Le second peut réussir ou être refusé sans que
/// le premier soit en cause — d'où deux catégories de résultat distinctes, et
/// pas une seule case « erreur ».
///
/// Un partage refermé sans rien faire n'est **pas** une erreur : c'est un choix.
/// L'écran ne dit rien de plus dans ce cas (`design/034-rgpd-export.md § 4`).
class ExportController extends Notifier<EtatExport> {
  @override
  EtatExport build() => const EtatExport();

  /// Vrai si le fichier a été remis (enregistré ou partagé).
  Future<bool> exporter() async {
    if (state.enCours) return false;
    state = const EtatExport(enCours: true);

    final ExportDonnees export;
    try {
      export = await ref.read(exportRepositoryProvider).demander();
    } on EchecExport catch (echec) {
      state = EtatExport(echec: echec);
      return false;
    } on Object {
      state = const EtatExport(echec: EchecExport(ErreurExport.inconnue));
      return false;
    }

    final nom = export.nomFichier();
    final resultat = await ref.read(telechargementProvider)(
      nomFichier: nom,
      contenu: export.texte,
    );

    if (resultat == ResultatTelechargement.impossible) {
      // Le dossier est arrivé, c'est l'enregistrement qui a manqué. Le message
      // doit le dire : réessayer a un sens, se reconnecter n'en a aucun.
      state = const EtatExport(
        resultat: ResultatTelechargement.impossible,
        echec: EchecExport(ErreurExport.enregistrementImpossible),
      );
      return false;
    }

    state = EtatExport(resultat: resultat, nomFichier: nom);
    return resultat != ResultatTelechargement.annule;
  }
}

final NotifierProvider<ExportController, EtatExport> exportControllerProvider =
    NotifierProvider<ExportController, EtatExport>(
      ExportController.new,
      isAutoDispose: true,
    );
