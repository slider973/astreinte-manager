import 'dart:convert';

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/telechargement.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/profil/domain/export_donnees.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_export.dart';

/// Les treize sections que l'export doit porter (`docs/RGPD.md § 4`).
///
/// La liste est **écrite ici**, et pas dérivée du faux : un faux qui perdrait
/// une section ferait passer un test qui la dérive, et c'est justement ce que
/// ce test doit attraper.
const List<String> _sections = <String>[
  'compte',
  'profil',
  'casernes',
  'appartenances',
  'disponibilites',
  'preferences_de_charge',
  'attributions',
  'notifications',
  'appareils',
  'invitations_recues',
  'invitations_envoyees',
  'actes_administratifs_me_concernant',
  'mes_actes_administratifs',
  'editeur_du_produit',
];

typedef Decor = ({FauxExportRepository depot, FauxTelechargement fichiers});

Future<Decor> _ouvrirProfil(
  WidgetTester tester, {
  FauxExportRepository? depot,
  FauxTelechargement? fichiers,
}) async {
  final export = depot ?? FauxExportRepository();
  final telechargement = fichiers ?? FauxTelechargement();

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    export: export,
    telechargement: telechargement,
  );

  await ouvrirProfil(tester);
  await defilerJusqua(tester, find.text(AppStrings.exportBouton));

  return (depot: export, fichiers: telechargement);
}

Future<void> _exporter(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.exportBouton).first);
  await tester.pumpAndSettle();
}

void main() {
  group('Export des données personnelles', () {
    testWidgets('le bouton est dans « Ton compte », au-dessus de la '
        'suppression', (tester) async {
      await _ouvrirProfil(tester);

      expect(find.text(AppStrings.exportBouton), findsOneWidget);
      // La phrase dit ce que contient le fichier **avant** qu'on le demande.
      expect(find.text(AppStrings.exportAide), findsOneWidget);

      final export = tester.getTopLeft(find.text(AppStrings.exportBouton));
      final supprimer = tester.getTopLeft(
        find.text(AppStrings.profilSupprimerCompte),
      );
      expect(export.dy, lessThan(supprimer.dy));
    });

    testWidgets('exporter remet un fichier nommé, et le dit', (tester) async {
      final decor = await _ouvrirProfil(tester);
      await _exporter(tester);

      expect(decor.depot.demandes, 1);
      expect(decor.fichiers.fichiers, hasLength(1));

      final fichier = decor.fichiers.dernier!;
      // Le nom porte la date **du serveur**, pas celle de l'appareil.
      expect(fichier.nom, 'astreinte-sp-export-2026-10-17.json');
      expect(fichier.typeMime, 'application/json');

      // Et l'écran nomme le fichier : dans une PWA installée, il n'y a pas de
      // barre de téléchargement pour le dire à sa place.
      expect(
        find.text(AppStrings.exportEnregistre(fichier.nom)),
        findsOneWidget,
      );
    });

    testWidgets('le fichier contient toutes les sections, et rien d\'un '
        'autre', (tester) async {
      final decor = await _ouvrirProfil(tester);
      await _exporter(tester);

      final texte = decor.fichiers.dernier!.contenu;
      final relu = jsonDecode(texte) as Map<String, dynamic>;
      final donnees = relu['donnees']! as Map<String, dynamic>;

      for (final section in _sections) {
        expect(
          donnees.containsKey(section),
          isTrue,
          reason: 'la section « $section » manque au fichier remis',
        );
      }

      // L'entête porte l'inventaire : c'est ce qui permet de vérifier un
      // export sans le relire en entier.
      expect(
        (relu['export']! as Map<String, dynamic>)['inventaire'],
        isNotNull,
      );

      // Lisible par un humain, pas seulement par une machine : un JSON sur une
      // seule ligne de 20 000 caractères ne s'ouvre pas dans une mairie.
      expect(texte.contains('\n'), isTrue);
      expect(texte.contains('\n  "donnees"'), isTrue);
    });

    testWidgets('un partage abouti se dit autrement qu\'un enregistrement', (
      tester,
    ) async {
      final decor = await _ouvrirProfil(
        tester,
        fichiers: FauxTelechargement(resultat: ResultatTelechargement.partage),
      );
      await _exporter(tester);

      expect(decor.fichiers.fichiers, hasLength(1));
      expect(find.text(AppStrings.exportPartage), findsOneWidget);
    });

    testWidgets('un partage refermé ne dit rien : ce n\'est pas une erreur', (
      tester,
    ) async {
      await _ouvrirProfil(
        tester,
        fichiers: FauxTelechargement(resultat: ResultatTelechargement.annule),
      );
      await _exporter(tester);

      expect(find.text(AppStrings.exportEchec), findsNothing);
      expect(find.text(AppStrings.exportFichierImpossible), findsNothing);
      expect(find.textContaining('Fichier enregistré'), findsNothing);
    });

    testWidgets('un enregistrement impossible dit que les données, elles, '
        'sont prêtes', (tester) async {
      await _ouvrirProfil(
        tester,
        fichiers: FauxTelechargement(
          resultat: ResultatTelechargement.impossible,
        ),
      );
      await _exporter(tester);

      expect(find.text(AppStrings.exportFichierImpossible), findsOneWidget);
    });

    testWidgets('un refus du serveur nomme le problème et la sortie', (
      tester,
    ) async {
      final decor = await _ouvrirProfil(
        tester,
        depot: FauxExportRepository(
          echec: const EchecExport(ErreurExport.reseau),
        ),
      );
      await _exporter(tester);

      expect(find.text(AppStrings.exportReseau), findsOneWidget);
      // Rien n'a été remis : un fichier vide serait pire que pas de fichier.
      expect(decor.fichiers.fichiers, isEmpty);
    });

    testWidgets('une session expirée renvoie vers la reconnexion', (
      tester,
    ) async {
      await _ouvrirProfil(
        tester,
        depot: FauxExportRepository(
          echec: const EchecExport(ErreurExport.nonAuthentifie),
        ),
      );
      await _exporter(tester);

      expect(find.text(AppStrings.exportNonAuthentifie), findsOneWidget);
    });

    testWidgets('les deux liens légaux ferment le bloc « Ton compte »', (
      tester,
    ) async {
      await _ouvrirProfil(tester);
      await defilerJusqua(
        tester,
        find.text(AppStrings.legalConfidentialiteLien),
      );

      expect(find.text(AppStrings.legalConfidentialiteLien), findsOneWidget);
      expect(find.text(AppStrings.legalMentionsLien), findsOneWidget);
    });
  });

  group('ExportDonnees', () {
    // Midi UTC, et non minuit : la date du fichier est celle de la personne,
    // donc convertie dans son fuseau. Une heure proche de minuit ferait
    // dépendre ce test du fuseau de la machine qui l'exécute.
    test('le nom du fichier vient de la date du serveur', () {
      final export = ExportDonnees(
        exportDeTest(genereLe: '2027-01-05T12:00:00.000Z'),
      );
      expect(
        export.nomFichier(maintenant: DateTime(2026, 6, 30)),
        'astreinte-sp-export-2027-01-05.json',
      );
    });

    test('sans date du serveur, l\'horloge de l\'appareil sert de repli', () {
      final contenu = exportDeTest();
      (contenu['export']! as Map<String, dynamic>).remove('genere_le');

      expect(
        ExportDonnees(contenu).nomFichier(maintenant: DateTime(2026, 6, 3)),
        'astreinte-sp-export-2026-06-03.json',
      );
    });

    test('une date illisible ne fait pas échouer l\'export', () {
      final contenu = exportDeTest(genereLe: 'pas une date');
      expect(
        ExportDonnees(contenu).nomFichier(maintenant: DateTime(2026, 6, 3)),
        'astreinte-sp-export-2026-06-03.json',
      );
    });

    test('le texte remis est le contenu du serveur, tel quel', () {
      final contenu = exportDeTest();
      final relu =
          jsonDecode(ExportDonnees(contenu).texte) as Map<String, dynamic>;
      expect(relu, equals(contenu));
    });
  });
}
