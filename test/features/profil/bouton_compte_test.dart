import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/avatar_initiales.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/profil/presentation/widgets/bouton_compte.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';

/// Un poste d'administration : le bouton de compte n'existe que là, dans
/// l'en-tête de la zone de travail.
const Size _poste = Size(1440, 900);

final DateTime _maintenant = DateTime.now();
final int _joursDuMois = DateTime(
  _maintenant.year,
  _maintenant.month + 1,
  0,
).day;

Future<void> _ouvrirLePoste(WidgetTester tester) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceAdmin],
    dispos: FauxDisposRepository(
      periodes: <PeriodeSaisie>[
        periodeOuverte(annee: _maintenant.year, mois: _maintenant.month),
      ],
    ),
    matrice: FauxMatriceRepository(
      lignes: <LigneMatrice>[
        ligneMatrice(
          userId: 'u1',
          nom: 'Dubois Jean-Marc',
          jours: moisUniforme('.', jours: _joursDuMois),
          nuits: moisUniforme('.', jours: _joursDuMois),
        ),
      ],
    ),
    taille: _poste,
  );
  await ouvrirRoute(tester, '/admin/planning');
}

/// Tous les nœuds de l'arbre sémantique qui **portent** [libelle], qu'il
/// vienne d'un `Semantics(label:)` ou d'une infobulle : un lecteur d'écran ne
/// fait pas la différence entre les deux, et c'est bien le doublon qu'on
/// traque ici.
List<SemanticsNode> _noeudsPortant(WidgetTester tester, String libelle) {
  final trouves = <SemanticsNode>[];
  void marcher(SemanticsNode noeud) {
    if (noeud.label == libelle || noeud.tooltip == libelle) trouves.add(noeud);
    noeud.visitChildren((SemanticsNode enfant) {
      marcher(enfant);
      return true;
    });
  }

  var racine = tester.getSemantics(find.byType(MaterialApp));
  while (racine.parent != null) {
    racine = racine.parent!;
  }
  marcher(racine);
  return trouves;
}

/// Combien de fois un même nœud dit [libelle] : en nom, en infobulle, ou les
/// deux. Un nœud qui le dit deux fois s'annonce deux fois.
int _fois(SemanticsNode noeud, String libelle) => <String>[
  noeud.label,
  noeud.tooltip,
].where((String texte) => texte == libelle).length;

void main() {
  group('BoutonCompte', () {
    testWidgets('un seul nœud de bouton porte le libellé du compte', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _ouvrirLePoste(tester);

      expect(find.byType(BoutonCompte), findsOneWidget);
      final libelle = AppStrings.compteOuvrirNomme(
        appartenanceAdmin.nomAffiche!,
      );

      // **Un bouton, pas deux.** L'infobulle de `IconButton` pose déjà le
      // nœud nommé — comme pour « Membres » et « Notifications » du même
      // en-tête ; un `Semantics(button: true)` autour du disque en posait un
      // second par-dessus. Fondus, ils rendaient un nœud qui dit le libellé
      // **deux fois** : une fois en nom, une fois en infobulle — deux
      // annonces à la lecture, deux boutons superposés dans le DOM du web.
      final noeuds = _noeudsPortant(tester, libelle);
      expect(noeuds, hasLength(1));
      expect(noeuds.single.flagsCollection.isButton, isTrue);
      expect(_fois(noeuds.single, libelle), 1);

      // Le voisin immédiat s'annonce exactement de la même façon : une seule
      // manière de nommer une action dans cet en-tête.
      final cloche = _noeudsPortant(tester, AppStrings.centreOuvrir);
      expect(cloche, hasLength(1));
      expect(_fois(cloche.single, AppStrings.centreOuvrir), 1);

      handle.dispose();
    });

    testWidgets('les initiales ne s\'ajoutent pas au nom annoncé', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _ouvrirLePoste(tester);

      // Le disque montre « JD » ; le bouton, lui, dit le nom entier et rien
      // de plus — deux lettres épelées à la suite du nom ne renseignent
      // personne.
      expect(find.byType(AvatarInitiales), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('JD')), findsNothing);

      handle.dispose();
    });
  });
}
