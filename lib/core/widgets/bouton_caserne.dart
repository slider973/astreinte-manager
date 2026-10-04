import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/domain/centre_providers.dart';
import '../l10n/app_strings.dart';
import '../router/app_router.dart';
import '../session/caserne_choisie.dart';
import '../session/session_providers.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';
import 'liste_casernes.dart';

/// **La caserne ouverte, et le moyen d'en changer** (ticket 072,
/// `design/072 § 6.1`).
///
/// Deux formes, un seul geste :
///
/// - [BoutonCaserne.puce] sous la salutation de l'accueil, en `compact` et
///   `medium` : bouton de 48 à filet, nom de la caserne, chevron ;
/// - [BoutonCaserne.titre] à la place du titre de l'en-tête de travail, dès
///   `expanded`, sur toutes les destinations.
///
/// **Il n'existe qu'à partir de deux appartenances actives.** La puce ne se
/// construit pas ; le titre reste un titre, inerte. Pour la très grande
/// majorité des pompiers, rien ne change à l'écran.
///
/// Les non-lues des autres casernes s'y lisent en chiffre : la Boîte ne compte
/// que la caserne ouverte.
class BoutonCaserne extends ConsumerWidget {
  /// Sous la salutation de l'accueil.
  const BoutonCaserne.puce({super.key}) : repli = null;

  /// Le titre de l'en-tête de travail ; [repli] quand il n'y a qu'une caserne.
  const BoutonCaserne.titre({required String this.repli, super.key});

  final String? repli;

  bool get _estTitre => repli != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plusieurs = ref.watch(plusieursCasernesProvider);
    final courante = ref.watch(appartenanceCouranteProvider);
    final theme = Theme.of(context);

    if (!plusieurs || courante == null) {
      if (!_estTitre) return const SizedBox.shrink();
      return Semantics(
        header: true,
        child: Text(
          repli!,
          style: theme.textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final ailleurs = ref
        .watch(nonLuesAilleursProvider)
        .entries
        .where(
          (MapEntry<String, int> e) => ref
              .read(appartenancesActivesProvider)
              .any((a) => a.stationId == e.key),
        )
        .fold<int>(0, (int total, MapEntry<String, int> e) => total + e.value);

    final semantique = <String>[
      AppStrings.caserneSelecteurSemantique(courante.nomCaserne),
      if (ailleurs > 0) AppStrings.caserneSelecteurNonLuesAilleurs(ailleurs),
    ].join(' ');

    return _Declencheur(
      nom: courante.nomCaserne,
      nonLues: ailleurs,
      semantique: semantique,
      titre: _estTitre,
    );
  }
}

/// Le déclencheur et son contenant : feuille sous `expanded`, menu ancré
/// au-delà (`design/072 § 6.2`).
class _Declencheur extends StatefulWidget {
  const _Declencheur({
    required this.nom,
    required this.nonLues,
    required this.semantique,
    required this.titre,
  });

  final String nom;
  final int nonLues;
  final String semantique;
  final bool titre;

  @override
  State<_Declencheur> createState() => _DeclencheurState();
}

class _DeclencheurState extends State<_Declencheur> {
  final MenuController _menu = MenuController();
  bool _focus = false;

  void _ouvrir() {
    if (AppWindowClass.of(context).supporteDeuxVolets) {
      if (_menu.isOpen) {
        _menu.close();
      } else {
        _menu.open();
      }
      return;
    }
    unawaited(ouvrirFeuilleCasernes(context));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titre = widget.titre;

    final contenu = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!titre) ...<Widget>[
          Icon(
            Icons.local_fire_department_outlined,
            size: AppTouch.icone,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            widget.nom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titre
                ? theme.textTheme.titleLarge
                : theme.textTheme.labelLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Icon(
          Icons.expand_more,
          size: titre ? AppTouch.glypheConfortable : AppTouch.icone,
          color: scheme.onSurface,
        ),
        if (widget.nonLues > 0) ...<Widget>[
          const SizedBox(width: AppSpacing.xs),
          Badge.count(count: widget.nonLues, maxCount: 9),
        ],
      ],
    );

    final bordure = _focus
        ? BorderSide(color: scheme.primary, width: AppStroke.etat)
        : titre
        ? BorderSide.none
        : BorderSide(color: scheme.outlineVariant);

    final bouton = Semantics(
      button: true,
      label: widget.semantique,
      excludeSemantics: true,
      child: Padding(
        // Le décalage de l'anneau de focus : il ne colle pas au filet.
        padding: const EdgeInsets.all(AppStroke.focusOffset),
        child: Material(
          color: titre ? Colors.transparent : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.controleRadius,
            side: bordure,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _ouvrir,
            onFocusChange: (bool focus) => setState(() => _focus = focus),
            mouseCursor: SystemMouseCursors.click,
            overlayColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> etats) =>
                  etats.contains(WidgetState.pressed) ||
                      etats.contains(WidgetState.hovered)
                  ? scheme.onSurface.withValues(alpha: 0.08)
                  : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.cible),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: titre ? AppSpacing.sm : AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: contenu,
              ),
            ),
          ),
        ),
      ),
    );

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, AppSpacing.xs),
      style: const MenuStyle(
        elevation: WidgetStatePropertyAll<double>(2),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.feuilleCarreeRadius),
        ),
        padding: WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.all(AppSpacing.sm),
        ),
      ),
      menuChildren: <Widget>[
        SizedBox(
          width: 320,
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                ListeCasernes(
                  onChoisie: _menu.close,
                  onInvitation: (String id) {
                    _menu.close();
                    context.go(AppRoutes.cheminRejoindre(id));
                  },
                ),
          ),
        ),
      ],
      // `Échap` et le clic extérieur ferment le menu : c'est le
      // comportement de `MenuAnchor`.
      child: bouton,
    );
  }
}

/// La feuille de bas d'écran du choix, en `compact` et `medium`.
Future<void> ouvrirFeuilleCasernes(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (BuildContext feuille) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  AppStrings.caserneChoixTitre,
                  style: Theme.of(feuille).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ListeCasernes(
                onChoisie: () => Navigator.of(feuille).pop(),
                onInvitation: (String id) {
                  Navigator.of(feuille).pop();
                  GoRouter.of(context).go(AppRoutes.cheminRejoindre(id));
                },
              ),
            ],
          ),
        ),
      ),
    );
