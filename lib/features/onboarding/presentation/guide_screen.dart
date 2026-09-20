import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/ecran_simple.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/parcours_accueil.dart';

/// Une étape du guide : ce que le membre fera, dans l'ordre où il le fera.
@immutable
class _EtapeGuide {
  const _EtapeGuide({
    required this.icone,
    required this.titre,
    required this.texte,
  });

  final IconData icone;
  final String titre;
  final String texte;
}

const List<_EtapeGuide> _etapes = <_EtapeGuide>[
  _EtapeGuide(
    icone: Icons.calendar_month_outlined,
    titre: AppStrings.guideDisposTitre,
    texte: AppStrings.guideDisposTexte,
  ),
  _EtapeGuide(
    icone: Icons.inbox_outlined,
    titre: AppStrings.guidePropositionsTitre,
    texte: AppStrings.guidePropositionsTexte,
  ),
  _EtapeGuide(
    icone: Icons.groups_outlined,
    titre: AppStrings.guidePlanningTitre,
    texte: AppStrings.guidePlanningTexte,
  ),
];

/// Le guide d'accueil : trois écrans, pas un de plus, et toujours passable.
///
/// Il ne revient pas : le repère est posé dès qu'on en sort, par la fin ou par
/// « Passer le guide » (`core/preferences/reperes_locaux.dart`).
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({super.key});

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _sortir() async {
    final suite = await ref.read(parcoursAccueilProvider).apresLeGuide();
    if (!mounted || !context.mounted) return;
    context.goNamed(suite);
  }

  void _suivant() {
    if (_index >= _etapes.length - 1) {
      unawaited(_sortir());
      return;
    }
    unawaited(
      _pages.animateToPage(
        _index + 1,
        duration: AppMotion.surface(context),
        curve: AppCurves.sortie,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final derniere = _index == _etapes.length - 1;

    return EcranSimple(
      titre: AppStrings.guideTitre,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          child: Text(
            AppStrings.guideEtape(_index + 1, _etapes.length),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 320,
          child: PageView.builder(
            controller: _pages,
            itemCount: _etapes.length,
            onPageChanged: (int index) => setState(() => _index = index),
            itemBuilder: (BuildContext context, int index) =>
                _PageGuide(etape: _etapes[index]),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          libelle: derniere
              ? AppStrings.guideTerminer
              : AppStrings.guideSuivant,
          icone: derniere ? Icons.check : Icons.arrow_forward,
          onPressed: _suivant,
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: AlignmentDirectional.center,
          child: TextButton(
            onPressed: () => unawaited(_sortir()),
            child: const Text(AppStrings.guidePasser),
          ),
        ),
      ],
    );
  }
}

class _PageGuide extends StatelessWidget {
  const _PageGuide({required this.etape});

  final _EtapeGuide etape;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            etape.icone,
            size: AppSpacing.xxxl,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(etape.titre, style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            etape.texte,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
