import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import '../session/session_providers.dart';
import '../widgets/banniere_caserne.dart';
import 'caserne_providers.dart';

/// Le fait « caserne » du point de vue d'un écran : l'état lu, le rôle de
/// l'utilisateur, l'horloge injectable et la sortie vers l'abonnement.
///
/// Une fonction et non un provider : la sortie dépend du `BuildContext`, et un
/// provider qui capture un contexte est un provider qui survit à l'écran qui
/// l'a créé.
///
/// Les sept écrans qui écrivent l'appellent d'une ligne, puis versent
/// `fait?.variante` dans leur propre arbitrage de bannière — la règle « une
/// seule bannière à la fois » reste chez eux, où vivent les autres faits
/// (hors ligne, mois verrouillé, échec d'enregistrement).
FaitCaserne? faitCaserneEcran(BuildContext context, WidgetRef ref) {
  final admin = ref.watch(appartenanceCouranteProvider)?.estAdmin ?? false;
  return faitCaserne(
    etat: ref.watch(etatCaserneProvider).value,
    admin: admin,
    maintenant: ref.watch(horlogeCaserneProvider)(),
    versAbonnement: admin
        ? () => context.goNamed(AppRoutes.abonnementName)
        : null,
  );
}
