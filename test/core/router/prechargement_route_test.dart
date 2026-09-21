import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/router/prechargement_route.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/features/dispos/domain/dispos_providers.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/membres/domain/membres_providers.dart';
import 'package:astreinte_sp/features/planning/domain/matrice_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';

/// Expose le `Ref` d'un provider : c'est ce que la redirection de `go_router`
/// passe au préchargement.
final Provider<Ref> _refProvider = Provider<Ref>((ref) => ref);

/// Ce que [periodeAdmin] rend, tel quel — une période ou un futur.
final Provider<Object?> _sondePeriode = Provider<Object?>(periodeAdmin);

Future<ProviderContainer> _conteneur({
  required FauxMembresRepository membres,
  Appartenance appartenance = appartenanceAdmin,
  FauxDisposRepository? dispos,
}) async {
  final conteneur = ProviderContainer(
    overrides: [
      appartenancesProvider.overrideWith(
        (ref) async => <Appartenance>[appartenance],
      ),
      membresRepositoryProvider.overrideWithValue(membres),
      disposRepositoryProvider.overrideWithValue(
        dispos ?? FauxDisposRepository(),
      ),
    ],
  );
  addTearDown(conteneur.dispose);

  conteneur.listen(appartenancesProvider, (_, _) {});
  await conteneur.read(appartenancesProvider.future);
  return conteneur;
}

void main() {
  group('La table des données d\'écran', () {
    test('la matrice en réveille deux : le mois et le planning du mois', () {
      expect(donneesDEcran(AppRoutes.planningAdmin), hasLength(2));
      expect(donneesDEcran(AppRoutes.suivi), hasLength(2));
    });

    test('chaque écran qui lit la base a sa ligne', () {
      for (final chemin in <String>[
        AppRoutes.planningAdmin,
        AppRoutes.suivi,
        AppRoutes.membres,
        AppRoutes.periodes,
        AppRoutes.parametres,
        AppRoutes.abonnement,
        AppRoutes.notifications,
      ]) {
        expect(donneesDEcran(chemin), isNotEmpty, reason: chemin);
      }
    });

    test('un chemin sans requête à lui ne précharge rien', () {
      // L'accueil est déjà chargé au démarrage ; les pages légales et l'aide à
      // l'installation ne demandent rien à la base.
      for (final chemin in <String>[
        AppRoutes.accueil,
        AppRoutes.demarrage,
        AppRoutes.confidentialite,
        AppRoutes.aideInstallation,
        '/chemin/inconnu',
      ]) {
        expect(donneesDEcran(chemin), isEmpty, reason: chemin);
      }
    });
  });

  group('PrechargementRoutes', () {
    test('la requête de l\'écran part avant que l\'écran n\'existe', () async {
      final depot = FauxMembresRepository();
      final conteneur = await _conteneur(membres: depot);
      final prechargement = PrechargementRoutes();
      addTearDown(prechargement.relacher);

      expect(depot.lectures, 0);
      prechargement.versLaRoute(
        conteneur.read(_refProvider),
        AppRoutes.membres,
      );
      // Aucun widget n'a été construit : c'est tout l'objet du préchargement.
      await Future<void>.delayed(Duration.zero);
      expect(depot.lectures, 1);
    });

    test('le même chemin rejoué ne redemande rien', () async {
      final depot = FauxMembresRepository();
      final conteneur = await _conteneur(membres: depot);
      final prechargement = PrechargementRoutes();
      addTearDown(prechargement.relacher);
      final ref = conteneur.read(_refProvider);

      // La redirection de `go_router` est rejouée à chaque rafraîchissement du
      // routeur : elle ne doit pas relancer la lecture à chaque fois.
      prechargement.versLaRoute(ref, AppRoutes.membres);
      prechargement.versLaRoute(ref, AppRoutes.membres);
      prechargement.versLaRoute(ref, AppRoutes.membres);
      await Future<void>.delayed(Duration.zero);

      expect(depot.lectures, 1);
    });

    test('arriver ailleurs relâche ce qui était retenu', () async {
      final depot = FauxMembresRepository();
      final conteneur = await _conteneur(membres: depot);
      final prechargement = PrechargementRoutes();
      addTearDown(prechargement.relacher);
      final ref = conteneur.read(_refProvider);

      prechargement.versLaRoute(ref, AppRoutes.membres);
      await Future<void>.delayed(Duration.zero);
      expect(depot.lectures, 1);

      prechargement.versLaRoute(ref, AppRoutes.accueil);
      await Future<void>.delayed(Duration.zero);

      // Le contrôleur des membres est auto-disposé : plus personne ne l'écoute,
      // donc revenir sur l'écran relit vraiment.
      prechargement.versLaRoute(ref, AppRoutes.membres);
      await Future<void>.delayed(Duration.zero);
      expect(depot.lectures, 2);
    });
  });

  group('Le mois des écrans d\'administration', () {
    test('rendu sans futur quand la liste des mois est déjà lue', () async {
      final dispos = FauxDisposRepository(
        periodes: <PeriodeSaisie>[
          periodeOuverte(annee: 2026, mois: 10),
          periodeOuverte(annee: 2026, mois: 11),
        ],
      );
      final conteneur = await _conteneur(
        membres: FauxMembresRepository(),
        dispos: dispos,
      );

      conteneur.listen(periodesProvider, (_, _) {});
      await conteneur.read(periodesProvider.future);

      // C'est **tout** le gain du ticket 042 : attendre ici coûterait une image
      // entière, celle de la transition de route.
      final rendu = conteneur.read(_sondePeriode);
      expect(rendu, isA<PeriodeSaisie>());
      expect(rendu, isNot(isA<Future<Object?>>()));
    });

    test('un futur tant que la liste n\'est pas là', () async {
      final conteneur = await _conteneur(
        membres: FauxMembresRepository(),
        dispos: FauxDisposRepository(),
      );

      expect(conteneur.read(_sondePeriode), isA<Future<PeriodeSaisie?>>());
    });

    test('rien à afficher pour un membre ordinaire', () async {
      final conteneur = await _conteneur(
        membres: FauxMembresRepository(),
        appartenance: appartenanceMembre,
      );

      expect(conteneur.read(_sondePeriode), isNull);
    });
  });
}
