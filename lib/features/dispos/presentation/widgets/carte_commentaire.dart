import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../controllers/saisie_controller.dart';
import 'champ_commentaire.dart';

/// **Le mot du mois pour le chef, sous la grille** (chantier 064d).
///
/// Il vivait au bas de la carte des maximums, au-dessus du registre, et il y
/// coûtait deux lignes de jour à chaque ouverture de l'écran alors qu'on
/// l'écrit une fois par mois. Il descend donc sous la grille, dans sa propre
/// carte, avec exactement la même édition : replié c'est une rangée de 56
/// points, ouvert c'est le même champ multiligne en place, la même limite de
/// caractères et le même compteur.
///
/// **Le prix est connu et assumé** : pour l'atteindre, il faut défiler le
/// mois. C'est le sens du chantier — la grille est la tâche, le commentaire
/// est l'exception. Il porte pour cela le nom de son destinataire, « Ton
/// commentaire pour le chef » : à trente lignes de la carte des maximums,
/// « Un mot pour ton chef » ne disait plus de quoi il était le commentaire.
///
/// **Sur téléphone seulement.** En `medium` et au-delà, la section des
/// préférences le garde : rien n'y est en concurrence avec la grille.
class CarteCommentaire extends ConsumerStatefulWidget {
  const CarteCommentaire({super.key});

  @override
  ConsumerState<CarteCommentaire> createState() => _CarteCommentaireState();
}

class _CarteCommentaireState extends ConsumerState<CarteCommentaire> {
  /// Le mois dont l'ouverture a été décidée : changer de mois replie.
  String? _moisVu;
  bool _ouvert = false;

  @override
  Widget build(BuildContext context) {
    // Le commentaire n'a rien à faire à côté de la grille tant qu'elle n'est
    // pas celle de cet écran-ci : en `medium` et au-delà, la section des
    // préférences le porte toujours.
    if (!AppWindowClass.of(context).estCompact) return const SizedBox.shrink();

    final etat = ref.watch(saisieControllerProvider).value;
    if (etat == null) return const SizedBox.shrink();

    final valeurs = etat.preferences.valeurs;
    // Sur un mois verrouillé et sans un mot écrit, il n'y a rien à lire et
    // rien à écrire : une carte vide serait un trou sous la grille.
    if (!etat.modifiable && valeurs.commentaire.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_moisVu != etat.periode.cle) {
      _moisVu = etat.periode.cle;
      _ouvert = false;
    }

    final marge = AppWindowClass.of(context).margePage;

    return Padding(
      padding: EdgeInsets.fromLTRB(marge, AppSpacing.md, marge, 0),
      child: Semantics(
        container: true,
        child: CarteDouce.nue(
          child: etat.modifiable
              ? ChampCommentaire(
                  texte: valeurs.commentaire,
                  ouvert: _ouvert,
                  libelle: AppStrings.preferencesCommentaireCarte,
                  filetHaut: false,
                  onOuvrir: () => setState(() => _ouvert = true),
                  onChange: ref
                      .read(saisieControllerProvider.notifier)
                      .definirCommentaire,
                )
              : _Relecture(texte: valeurs.commentaire),
        ),
      ),
    );
  }
}

/// Un mois verrouillé : les mots du membre, en entier, sans filet au-dessus —
/// la carte en tient lieu.
class _Relecture extends StatelessWidget {
  const _Relecture({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            AppStrings.preferencesCommentaireCarte,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(texte, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
