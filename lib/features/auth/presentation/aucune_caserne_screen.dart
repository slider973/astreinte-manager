import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/reseau/connectivite.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/appartenance.dart';
import '../../../core/session/deconnexion.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/empty_state.dart';
import '../../invitation/domain/invitation_providers.dart';
import '../../invitation/domain/invitation_recue.dart';
import '../../invitation/presentation/widgets/panneau_invitations_recues.dart';

/// Connecté, mais rattaché à aucune caserne active.
///
/// **Cet écran pose la question avant de répondre** (ticket 051). Il a
/// longtemps affirmé « Ton compte existe, mais il n'est rattaché à aucune
/// caserne. Demande une invitation à ton chef de centre » sans l'avoir jamais
/// vérifié : entre `invite-member`, qui crée le compte, et `accept_invitation`,
/// qui crée l'appartenance, vit exactement ce compte-là — et souvent une
/// invitation qui l'attend. Le produit demandait alors d'aller réclamer ce
/// qu'on avait déjà.
///
/// Cinq formes, un seul meuble — même `Scaffold`, même `SafeArea`, même
/// « Se déconnecter » en bas, qui reste la sortie de qui s'est trompé
/// d'adresse :
///
/// 1. pendant la recherche : titre neutre et squelette, **jamais la phrase** ;
/// 2. une invitation en attente, ou plusieurs : le panneau, et le geste ;
/// 3. uniquement des expirées : le panneau, en échéance manquée ;
/// 4. rien du tout : l'état vide du ticket 006, inchangé — cette phrase n'a
///    jamais été mauvaise, elle était mal adressée ;
/// 5. recherche en échec ou hors ligne : le **fait** seul, sans le conseil.
///
/// L'accès désactivé garde son écran, et gagne un rappel en bannière quand une
/// invitation occupe le centre : la seule chose actionnable est alors
/// l'invitation.
class AucuneCaserneScreen extends ConsumerStatefulWidget {
  const AucuneCaserneScreen({super.key});

  @override
  ConsumerState<AucuneCaserneScreen> createState() =>
      _AucuneCaserneScreenState();
}

class _AucuneCaserneScreenState extends ConsumerState<AucuneCaserneScreen> {
  /// `invitations` n'entre pas dans le canal Realtime — c'est une décision de
  /// sécurité écrite (`docs/SCHEMA.md § 9`). La fraîcheur est donc portée par
  /// des relectures : à l'ouverture et au retour depuis `/rejoindre` (le
  /// provider est auto-disposé), au retour de l'application au premier plan,
  /// et sur « Réessayer ».
  late final AppLifecycleListener _cycleDeVie;

  @override
  void initState() {
    super.initState();
    _cycleDeVie = AppLifecycleListener(onResume: _relire);
  }

  @override
  void dispose() {
    _cycleDeVie.dispose();
    super.dispose();
  }

  void _relire() {
    if (!mounted) return;
    ref.invalidate(invitationsRecuesProvider);
  }

  /// Rejoindre **ouvre l'écran d'invitation**, il n'accepte pas sur place.
  ///
  /// Trois raisons, dont la dernière est décisive : les six fins de parcours
  /// existent déjà et une seule fois ; ce qui suit l'acceptation n'est pas
  /// l'accueil mais « Bienvenue », le profil et le guide ; et dès que
  /// l'appartenance apparaît, `redirectionAuth` renvoie tout ce qui est sur
  /// `/aucune-caserne` vers `/accueil` — une acceptation jouée ici serait
  /// arrachée de l'écran à la seconde où elle réussit.
  void _rejoindre(InvitationRecue invitation) => context.goNamed(
    AppRoutes.rejoindreName,
    pathParameters: <String, String>{
      AppRoutes.parametreInvitation: invitation.id,
    },
  );

  @override
  Widget build(BuildContext context) {
    final toutes =
        ref.watch(appartenancesProvider).value ?? const <Appartenance>[];

    // La ligne désactivée, pas la première venue : un compte peut porter une
    // appartenance `invited` restée en plan, et ce n'est pas elle qui explique
    // pourquoi la caserne a disparu de l'écran.
    final desactivee = toutes
        .where((Appartenance a) => a.statut == StatutMembre.desactive)
        .firstOrNull;

    final invitations = ref.watch(invitationsRecuesProvider);
    final liste = invitations.value ?? const <InvitationRecue>[];
    final echec = invitations.hasError && !invitations.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            ?_banniere(echec: echec, desactivee: desactivee, liste: liste),
            Expanded(
              child: _zoneCentrale(
                invitations: invitations,
                liste: liste,
                echec: echec,
                desactivee: desactivee,
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: BoutonDeconnexion(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoneCentrale({
    required AsyncValue<List<InvitationRecue>> invitations,
    required List<InvitationRecue> liste,
    required bool echec,
    required Appartenance? desactivee,
  }) {
    if (liste.isNotEmpty ||
        invitations.isLoading ||
        (echec && desactivee == null)) {
      return PanneauInvitationsRecues(
        invitations: invitations,
        email: ref.watch(sessionProvider).value?.email ?? '',
        onRejoindre: _rejoindre,
      );
    }

    if (desactivee != null) {
      return EmptyState(
        titre: AppStrings.caserneDesactiveeTitre,
        texte: desactivee.nomCaserne.isEmpty
            ? AppStrings.caserneDesactiveeTexteSansNom
            : AppStrings.caserneDesactiveeTexte(desactivee.nomCaserne),
        icone: Icons.no_accounts_outlined,
      );
    }

    return const EmptyState(
      titre: AppStrings.aucuneCaserneTitre,
      texte: AppStrings.aucuneCaserneTexte,
      icone: Icons.markunread_mailbox_outlined,
    );
  }

  /// Au plus une bannière, et jamais deux faits à la fois.
  AppBanner? _banniere({
    required bool echec,
    required Appartenance? desactivee,
    required List<InvitationRecue> liste,
  }) {
    if (echec) {
      // Hors ligne et en panne ne se disent pas de la même façon : accuser la
      // connexion à tort est une piste fausse, et l'inverse aussi.
      final enLigne = ref.watch(enLigneProvider).value ?? true;
      return AppBanner(
        variante: enLigne
            ? AppBannerVariante.erreur
            : AppBannerVariante.horsLigne,
        texte: enLigne
            ? AppStrings.invitationsRecuesEchec
            : AppStrings.invitationsRecuesHorsLigne,
        libelleAction: AppStrings.actionReessayer,
        onAction: _relire,
      );
    }

    if (desactivee == null || liste.isEmpty) return null;

    return AppBanner(
      variante: AppBannerVariante.information,
      texte: desactivee.nomCaserne.isEmpty
          ? AppStrings.caserneDesactiveeRappelSansNom
          : AppStrings.caserneDesactiveeRappel(desactivee.nomCaserne),
    );
  }
}
