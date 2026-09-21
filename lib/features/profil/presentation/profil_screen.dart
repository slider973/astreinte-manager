import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../notifications/presentation/widgets/bouton_notifications.dart';
import '../../notifications/presentation/widgets/reglage_notifications.dart';
import '../domain/profil.dart';
import '../domain/profil_providers.dart';
import 'widgets/bloc_caserne.dart';
import 'widgets/bloc_compte.dart';
import 'widgets/bloc_identite.dart';
import 'widgets/bloc_regle.dart';

/// **« Profil »** — tout ce que l'application sait de la personne, sur un seul
/// écran, et la porte de sortie.
///
/// Il rassemble ce que trois tickets avaient posé ailleurs faute d'écran où le
/// mettre : le complément de profil de l'accueil (006), le réglage des
/// notifications (024) et la déconnexion (027). Le seul morceau neuf est la
/// suppression de compte.
///
/// Ce n'est pas un écran de travail : on l'ouvre une ou deux fois par an, pour
/// une raison précise. Il est donc **plat, ordonné et sans surprise** — quatre
/// blocs réglés, du plus consulté au plus définitif.
///
/// Il vit dans l'onglet 3 de la coquille d'accueil. La route `/profil` annoncée
/// par `DESIGN.md § Navigation` attend que la coquille éclate en routes, comme
/// `/mois` (tickets 011 et 027).
class ProfilScreen extends ConsumerWidget {
  const ProfilScreen({
    required this.destinations,
    required this.indexSelectionne,
    required this.onDestination,
    super.key,
  });

  final List<AppDestination> destinations;
  final int indexSelectionne;
  final ValueChanged<int> onDestination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profil = ref.watch(monProfilProvider);

    return AppScaffold(
      titre: AppStrings.profilEcranTitre,
      destinations: destinations,
      indexSelectionne: indexSelectionne,
      onDestination: onDestination,
      actions: const <Widget>[BoutonNotifications()],
      // Une lecture en échec ne vide pas l'écran : la caserne, les
      // notifications et les deux sorties ne dépendent pas de `profiles`, et
      // c'est peut-être exactement pour se déconnecter qu'on est venu.
      banniere: profil.hasError
          ? AppBanner(
              variante: AppBannerVariante.erreur,
              texte: AppStrings.profilLectureEchec,
              libelleAction: AppStrings.actionReessayer,
              onAction: () => ref.invalidate(monProfilProvider),
            )
          : null,
      child: _Contenu(profil: profil.value, enChargement: profil.isLoading),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({required this.profil, required this.enChargement});

  /// `null` tant que la première lecture n'a pas répondu, ou après un échec.
  final Profil? profil;

  /// Distingue « pas encore » de « pas du tout » : un échec de lecture ne doit
  /// pas laisser un indicateur tourner indéfiniment devant quelqu'un. La
  /// bannière de l'écran porte déjà le motif et la reprise.
  final bool enChargement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final classe = AppWindowClass.of(context);

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: classe.margePage,
        vertical: AppSpacing.lg,
      ),
      children: <Widget>[
        // Une colonne bornée : un formulaire de 1400 dp de large se lit mal, et
        // l'admin ouvre cet écran sur un ordinateur.
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.colonneMax,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  AppStrings.profilEcranIntro,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.auDessusTitre),
                // Le bloc d'identité attend la première lecture : pré-remplir
                // des champs vides puis les remplacer sous les doigts de
                // quelqu'un qui écrit déjà serait le pire des deux mondes.
                if (profil case final Profil lu) ...<Widget>[
                  BlocIdentite(profil: lu),
                  const SizedBox(height: AppSpacing.auDessusTitre),
                ],
                // **Un échec de lecture ne laisse rien ici.** Ni squelette ni
                // message : la bannière de l'écran porte déjà le motif et la
                // reprise, et un indicateur qui tourne devant quelqu'un après
                // un renoncement le fait attendre pour rien.
                if (profil == null && enChargement) ...<Widget>[
                  const _IdentiteEnAttente(),
                  const SizedBox(height: AppSpacing.auDessusTitre),
                ],
                const BlocCaserne(),
                const SizedBox(height: AppSpacing.auDessusTitre),
                // Déménagé tel quel depuis l'onglet d'accueil, où le ticket 024
                // l'avait posé en attendant cet écran.
                const ReglageNotifications(),
                const SizedBox(height: AppSpacing.auDessusTitre),
                _BlocLangue(langue: profil?.langue ?? Langue.francais),
                const SizedBox(height: AppSpacing.auDessusTitre),
                const BlocCompte(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Le bloc d'identité pendant la première lecture.
///
/// Pas de squelette animé : l'écran est court, la lecture est brève, et un
/// balayage de 300 ms sur quatre champs attire l'œil sur une attente au lieu de
/// la faire oublier. Une phrase suffit, et elle est annoncée.
class _IdentiteEnAttente extends StatelessWidget {
  const _IdentiteEnAttente();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = theme.colorScheme.onSurfaceVariant;

    return BlocRegle(
      titre: AppStrings.profilIdentiteTitre,
      enfants: <Widget>[
        Semantics(
          liveRegion: true,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: AppSpacing.lg,
                height: AppSpacing.lg,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: encre,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppStrings.actionChargement,
                  style: theme.textTheme.bodyMedium?.copyWith(color: encre),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// La langue : affichée, pas réglée.
///
/// Le MVP n'existe qu'en français (`profiles.locale` a `default 'fr'`). Un
/// sélecteur à un seul choix promettrait une traduction qui n'existe pas ; la
/// ligne est donc un fait, avec sa raison écrite à côté
/// (`DESIGN.md § Do's`, `design/007-profil.md § 5.1`).
class _BlocLangue extends StatelessWidget {
  const _BlocLangue({required this.langue});

  final Langue langue;

  @override
  Widget build(BuildContext context) {
    return BlocRegle(
      titre: AppStrings.profilLangueTitre,
      enfants: <Widget>[
        LigneLecture(
          libelle: AppStrings.profilLangueTitre,
          libelleVisible: false,
          valeur: langue.libelle,
          raison: AppStrings.profilLangueRaison,
          icone: Icons.translate,
        ),
      ],
    );
  }
}
