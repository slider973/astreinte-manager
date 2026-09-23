import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_profil.dart';
import '../../support/faux_push.dart';

const String _safariIphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const String _chromeAndroid =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

final ContextePlateforme _androidInstalle = ContextePlateforme.depuisAgent(
  userAgent: _chromeAndroid,
  affichageAutonome: true,
);
final ContextePlateforme _iphoneSafari = ContextePlateforme.depuisAgent(
  userAgent: _safariIphone,
);

Future<AppMontee> _ouvrirProfil(
  WidgetTester tester, {
  required FauxMessageriePush messagerie,
  FirebaseDemarrage firebase = FirebaseDemarrage.pret,
  ContextePlateforme? plateforme,
  FauxProfilRepository? profils,
}) async {
  final faux = await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    firebase: firebase,
    plateforme: plateforme ?? _androidInstalle,
    messagerie: messagerie,
    profils: profils,
  );
  await ouvrirProfil(tester);
  // **Vers l'interrupteur, pas vers le titre du bloc.** L'écran de profil s'est
  // allongé au ticket 034 (export, liens légaux) : amener le titre à l'écran ne
  // garantit plus que la cible tactile y soit aussi, et un `tap` qui manque sa
  // cible ne lève pas — il ne fait rien.
  await defilerJusqua(tester, find.byType(Switch).first);
  return faux;
}

void main() {
  group('Réglage des notifications dans le profil', () {
    testWidgets('dit toujours que les propositions ne se coupent pas', (
      tester,
    ) async {
      await _ouvrirProfil(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
      );

      expect(find.text(AppStrings.notifReglageTitre), findsOneWidget);
      expect(find.text(AppStrings.notifReglageToujours), findsOneWidget);
      expect(find.text(AppStrings.notifEtatActive), findsOneWidget);
    });

    testWidgets('l\'interrupteur coupe les non critiques, et seulement elles', (
      tester,
    ) async {
      final profils = FauxProfilRepository();
      await _ouvrirProfil(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
        profils: profils,
      );

      expect(profils.pushNonCritiquesActifs, isTrue);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(profils.pushNonCritiquesActifs, isFalse);
    });

    testWidgets('sans autorisation, l\'interrupteur est inerte et dit '
        'pourquoi', (tester) async {
      await _ouvrirProfil(tester, messagerie: FauxMessageriePush());

      final bascule = tester.widget<Switch>(find.byType(Switch).first);
      expect(bascule.onChanged, isNull);
      expect(find.text(AppStrings.notifReglageRaisonInactive), findsOneWidget);
      expect(find.text(AppStrings.notifActiver), findsOneWidget);
    });

    testWidgets('un refus affiche sa sortie, pas une erreur', (tester) async {
      await _ouvrirProfil(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.refusee),
      );

      expect(find.text(AppStrings.notifEtatRefusee), findsOneWidget);
      expect(find.text(AppStrings.notifEtatRefuseeSortie), findsOneWidget);
      // Un refus n'est pas une panne : rien ne propose de redemander.
      expect(find.text(AppStrings.notifActiver), findsNothing);
    });

    testWidgets('sur iPhone non installé, le profil dit quoi faire', (
      tester,
    ) async {
      await _ouvrirProfil(
        tester,
        plateforme: _iphoneSafari,
        messagerie: FauxMessageriePush(supportee: false),
      );

      expect(find.text(AppStrings.notifEtatInstallation), findsOneWidget);
      expect(find.text(AppStrings.notifActiver), findsNothing);
    });

    testWidgets('sans configuration Firebase, l\'état le dit sans alarmer', (
      tester,
    ) async {
      await _ouvrirProfil(
        tester,
        firebase: FirebaseDemarrage.configurationAbsente,
        messagerie: FauxMessageriePush(),
      );

      expect(find.text(AppStrings.notifEtatNonConfigure), findsOneWidget);
      expect(find.text(AppStrings.notifSansPushTexte), findsOneWidget);
    });

    testWidgets('une écriture refusée revient en place et le dit', (
      tester,
    ) async {
      final profils = FauxProfilRepository();
      await _ouvrirProfil(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
        profils: profils,
      );

      profils.echoue = true;
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.notifReglageEchec), findsOneWidget);
      expect(
        tester.widget<Switch>(find.byType(Switch).first).value,
        isTrue,
        reason: 'l\'interrupteur revient à sa valeur enregistrée',
      );
    });
  });
}
