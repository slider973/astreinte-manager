import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/colonne_navigation.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/astreintes/presentation/astreintes_screen.dart';
import 'package:astreinte_sp/features/boite/presentation/boite_screen.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/presentation/mois_screen.dart';
import 'package:astreinte_sp/features/membres/presentation/inviter_screen.dart';
import 'package:astreinte_sp/features/membres/presentation/membres_screen.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/presentation/matrice_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_profil.dart';

/// Un poste d'administration : la colonne de navigation porte ses libellés,
/// et c'est sur elle que la plainte a été faite (ticket 063).
const Size _poste = Size(1280, 900);

final DateTime _maintenant = DateTime.now();
final int _joursDuMois = DateTime(
  _maintenant.year,
  _maintenant.month + 1,
  0,
).day;

/// Le glissement d'une page poussée, dans les deux dialectes que le thème
/// installe (`core/theme/app_theme.dart`) : `CupertinoPageTransition` sur iOS
/// et macOS, et le `SlideTransition` que `FadeForwardsPageTransitionsBuilder`
/// pose sur Android et sur le web.
///
/// Les deux restent dans l'arbre une fois l'animation finie : c'est bien leur
/// **présence** qu'on regarde, image par image, et non une valeur d'animation.
final Finder _glissement = find.byWidgetPredicate(
  (Widget widget) =>
      widget is CupertinoPageTransition || widget is SlideTransition,
  description: 'une transition de glissement',
);

/// Le poste d'un administrateur, ouvert sur l'accueil.
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
    membres: FauxMembresRepository(),
    profils: FauxProfilRepository(),
    taille: _poste,
  );
}

/// Touche [libelle] dans la colonne de navigation, puis avance **image par
/// image** en regardant l'arbre à chaque image.
///
/// `pumpAndSettle` ne conviendrait pas : il saute par-dessus l'animation, et
/// c'est l'animation qu'on juge. Une seconde de frames couvre largement les
/// transitions du thème, les plus longues durant 300 ms.
Future<void> _toucherEtRegarder(
  WidgetTester tester,
  String libelle,
  void Function(int image) regard,
) async {
  // **Dans la colonne, et nulle part ailleurs.** « Astreintes » est aussi le
  // libellé d'un compteur de la barre du Calendrier : un `find.text` nu en
  // trouve deux et ne sait pas lequel toucher.
  await tester.tap(
    find.descendant(
      of: find.byType(ColonneNavigation),
      matching: find.text(libelle),
    ),
  );
  for (var image = 0; image < 60; image++) {
    await tester.pump(const Duration(milliseconds: 16));
    regard(image);
  }
}

void main() {
  group('Passer d\'une destination à l\'autre', () {
    testWidgets(
      'aucun glissement entre les cinq destinations',
      (tester) async {
        await _ouvrirLePoste(tester);
        expect(_glissement, findsNothing);

        // Le geste même de la plainte : « quand tu cliques sur Admin,
        // l'animation part de droite à gauche, et quand tu recliques sur Profil
        // ça recommence ».
        await _toucherEtRegarder(
          tester,
          AppStrings.navAdmin,
          (int image) => expect(
            _glissement,
            findsNothing,
            reason: 'vers « Admin », image $image',
          ),
        );
        expect(find.byType(MatriceScreen), findsOneWidget);
        expect(emplacementCourant(tester), AppRoutes.planningAdmin);

        await _toucherEtRegarder(
          tester,
          AppStrings.navAccueil,
          (int image) => expect(
            _glissement,
            findsNothing,
            reason: 'vers « Accueil », image $image',
          ),
        );
        expect(emplacementCourant(tester), AppRoutes.accueil);
        expect(find.byType(AccueilScreen), findsOneWidget);

        await _toucherEtRegarder(
          tester,
          AppStrings.navCalendrier,
          (int image) => expect(
            _glissement,
            findsNothing,
            reason: 'vers « Calendrier », image $image',
          ),
        );
        // Chaque destination a sa route depuis le ticket 064 : l'adresse
        // change, la page ne glisse pas.
        expect(find.byType(MoisScreen), findsOneWidget);
        expect(emplacementCourant(tester), AppRoutes.calendrier);

        // Les deux dernières entrées de la barre, pour que le parcours les
        // couvre toutes les cinq : une seule qui glisserait suffirait à
        // rouvrir la plainte.
        await _toucherEtRegarder(
          tester,
          AppStrings.navAstreintes,
          (int image) => expect(
            _glissement,
            findsNothing,
            reason: 'vers « Astreintes », image $image',
          ),
        );
        expect(find.byType(AstreintesScreen), findsOneWidget);
        expect(emplacementCourant(tester), AppRoutes.astreintes);

        await _toucherEtRegarder(
          tester,
          AppStrings.navBoite,
          (int image) => expect(
            _glissement,
            findsNothing,
            reason: 'vers « Boîte », image $image',
          ),
        );
        expect(find.byType(BoiteScreen), findsOneWidget);
        expect(emplacementCourant(tester), AppRoutes.boite);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.android,
      }),
    );
  });

  group('Pousser un écran de détail', () {
    testWidgets(
      '« Inviter » glisse, et le retour du navigateur ramène à la '
      'liste',
      (tester) async {
        await _ouvrirLePoste(tester);
        await ouvrirRoute(tester, AppRoutes.membres);
        expect(find.byType(MembresScreen), findsOneWidget);

        // L'invitation, elle, se pousse par-dessus la liste : il y a un avant,
        // un après, et une flèche pour revenir. Le glissement dit vrai.
        await tester.tap(find.text(AppStrings.membresInviter));
        await tester.pumpAndSettle();
        expect(find.byType(InviterScreen), findsOneWidget);
        expect(_glissement, findsWidgets);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(InviterScreen), findsNothing);
        expect(find.byType(MembresScreen), findsOneWidget);
        expect(emplacementCourant(tester), AppRoutes.membres);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  });
}
