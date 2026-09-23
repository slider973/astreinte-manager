import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/raccourci.dart';
import '../controllers/saisie_controller.dart';
import 'feuille_raccourci.dart';

/// **La bande des raccourcis**, à la place que le brief du 011 lui a gardée :
/// entre le sélecteur de mois et l'en-tête épinglé sur téléphone, en tête du
/// panneau de droite en `large`.
///
/// Cinq boutons de portée — ce sont eux qui décident *quels jours* —, chacun
/// ouvrant une feuille qui décide *quel créneau*. Sous eux, une sixième ligne
/// qui n'existe que quand elle a quelque chose à dire : le résultat du dernier
/// raccourci et son bouton « Annuler ».
class BarreRaccourcis extends ConsumerWidget {
  const BarreRaccourcis({
    super.key,
    this.vertical = false,
    this.dansCarte = false,
  });

  /// Vrai dans le panneau de droite (`large`) : les boutons s'empilent au
  /// lieu de défiler.
  final bool vertical;

  /// Vrai dans la carte des raccourcis du Calendrier (ticket 064c) : la marge
  /// n'est plus celle de la page, c'est le rembourrage interne de la carte.
  ///
  /// La bande garde son défilement horizontal et son dernier bouton qui
  /// dépasse — c'est ce qui dit qu'il y en a d'autres —, mais il dépasse
  /// désormais du bord de la carte, pas de celui de l'écran.
  final bool dansCarte;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(saisieControllerProvider).value;
    if (etat == null) return const SizedBox.shrink();

    final marge = vertical
        ? 0.0
        : dansCarte
        ? AppSpacing.md
        : AppWindowClass.of(context).margePage;
    final raison = etat.periode.ouverte
        ? (etat.lectureSeule ? AppStrings.raccourcisLectureSeule : null)
        : AppStrings.raccourcisVerrouilles;

    final boutons = <Widget>[
      for (final portee in PorteeRaccourci.values)
        _BoutonPortee(
          portee: portee,
          actif: raison == null,
          chargement: etat.raccourciEnCours == portee,
          pleineLargeur: vertical,
          onChoisir: () => unawaited(_ouvrir(context, ref, portee)),
        ),
    ];

    return Semantics(
      container: true,
      label: AppStrings.raccourcisSemantique,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (vertical)
            // Dans le panneau de droite, les cinq portées s'empilent en
            // pleine largeur : une colonne de blocs alignés se lit d'un coup
            // d'œil, là où une grappe `Wrap` ferait des lignes bancales.
            for (final bouton in boutons)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.entreCibles),
                child: bouton,
              )
          else
            // Le défilement horizontal est la seule façon honnête de tenir
            // cinq portées sur 360 dp sans descendre sous la cible de 48 dp
            // ni rogner les libellés. Le dernier bouton dépasse volontiers du
            // bord : c'est ce qui dit qu'il y en a d'autres.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: marge),
              child: Row(
                children: <Widget>[
                  for (final bouton in boutons)
                    Padding(
                      padding: const EdgeInsets.only(
                        right: AppSpacing.entreCibles,
                      ),
                      child: bouton,
                    ),
                ],
              ),
            ),
          if (raison != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                marge,
                AppSpacing.sm,
                marge,
                0,
              ),
              child: _Raison(texte: raison),
            )
          else
            _LigneResultat(
              raccourci: etat.dernierRaccourci,
              message: etat.messageRaccourci,
              marge: marge,
              onAnnuler: ref
                  .read(saisieControllerProvider.notifier)
                  .annulerRaccourci,
            ),
        ],
      ),
    );
  }

  /// Portée choisie : la feuille demande le créneau, la confirmation protège
  /// ce qui s'écrase, puis le contrôleur applique. **Une seule descente**, et
  /// c'est celle de la saisie ordinaire.
  Future<void> _ouvrir(
    BuildContext context,
    WidgetRef ref,
    PorteeRaccourci portee,
  ) async {
    final etat = ref.read(saisieControllerProvider).value;
    if (etat == null || !etat.modifiable) return;

    final cible = await choisirCreneauRaccourci(
      context: context,
      portee: portee,
      cases: (cible) => _compter(etat, portee, cible),
    );
    if (cible == null || !context.mounted) return;

    if (portee.ecrase) {
      final apres = ref.read(saisieControllerProvider).value;
      if (apres == null) return;
      final confirme = await confirmerRaccourci(
        context: context,
        portee: portee,
        saisies: saisiesEcrasees(
          periode: apres.periode,
          portee: portee,
          cible: cible,
          courant: apres.mois,
        ),
      );
      if (!confirme) return;
    }

    await ref
        .read(saisieControllerProvider.notifier)
        .appliquerRaccourci(portee, cible);
  }

  /// Le nombre de cases qu'un choix changerait, affiché dans la feuille.
  ///
  /// Pour « copier le mois précédent », le mois source n'est pas encore lu :
  /// on annonce l'étendue de la portée plutôt qu'un chiffre faux. Charger le
  /// mois précédent rien que pour peupler trois nombres coûterait une requête
  /// à chaque ouverture de feuille, y compris quand l'utilisateur referme.
  static int _compter(
    EtatSaisie etat,
    PorteeRaccourci portee,
    CibleCreneau cible,
  ) {
    if (portee.litLeMoisPrecedent) {
      return joursDeLaPortee(etat.periode, portee).length *
          cible.creneaux.length;
    }
    return modificationsRaccourci(
      periode: etat.periode,
      portee: portee,
      cible: cible,
      courant: etat.mois,
    ).length;
  }
}

/// Un bouton de portée : la forme d'une case du registre, la taille d'une
/// cible tactile.
class _BoutonPortee extends StatelessWidget {
  const _BoutonPortee({
    required this.portee,
    required this.actif,
    required this.chargement,
    required this.pleineLargeur,
    required this.onChoisir,
  });

  final PorteeRaccourci portee;
  final bool actif;
  final bool chargement;

  /// Dans le panneau de droite, le bouton prend toute la largeur et son
  /// libellé se replie sur deux lignes plutôt que de déborder.
  final bool pleineLargeur;

  final VoidCallback onChoisir;

  static const Map<PorteeRaccourci, IconData> _icones =
      <PorteeRaccourci, IconData>{
        PorteeRaccourci.weekends: Icons.weekend_outlined,
        PorteeRaccourci.semaine: Icons.work_outline,
        PorteeRaccourci.moisEntier: Icons.calendar_month_outlined,
        PorteeRaccourci.copieMoisPrecedent: Icons.content_copy_outlined,
        PorteeRaccourci.effacer: Icons.backspace_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = !actif
        ? theme.colorScheme.outline
        : portee == PorteeRaccourci.effacer
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      enabled: actif,
      label: portee.libelle,
      hint: portee.detail,
      child: Material(
        color: actif
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.caseRegistreRadius,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: actif && !chargement ? onChoisir : null,
          borderRadius: AppRadius.caseRegistreRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.cible),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisSize: pleineLargeur
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                children: <Widget>[
                  if (chargement)
                    SizedBox.square(
                      dimension: AppTouch.icone,
                      child: CircularProgressIndicator(
                        strokeWidth: AppStroke.etat,
                        color: encre,
                      ),
                    )
                  else
                    Icon(_icones[portee], size: AppTouch.icone, color: encre),
                  const SizedBox(width: AppSpacing.sm),
                  // En pleine largeur, le libellé se replie plutôt que de
                  // déborder : la largeur du panneau ne dépend pas de nous.
                  // Dans la bande horizontale, il garde sa largeur naturelle
                  // et c'est le défilement qui l'accueille.
                  if (pleineLargeur)
                    Expanded(child: _Libelle(portee: portee, encre: encre))
                  else
                    _Libelle(portee: portee, encre: encre),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Libelle extends StatelessWidget {
  const _Libelle({required this.portee, required this.encre});

  final PorteeRaccourci portee;
  final Color encre;

  @override
  Widget build(BuildContext context) => Text(
    portee.libelle,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: encre),
  );
}

/// **La sortie de secours.** Ce que le dernier raccourci a changé, et le
/// bouton qui le défait.
///
/// Pas un `SnackBar` : il s'efface au bout de quatre secondes, et un membre
/// qui relève les yeux de son téléphone pour ranger un tuyau aurait perdu son
/// annulation. Pas non plus un historique général — le brief du 011 s'y
/// oppose, et il a raison : la case reste son propre annulateur. Un cran,
/// celui du dernier raccourci, affiché tant qu'il vaut, et qui tombe dès
/// qu'une case est touchée à la main.
class _LigneResultat extends StatelessWidget {
  const _LigneResultat({
    required this.raccourci,
    required this.message,
    required this.marge,
    required this.onAnnuler,
  });

  final RaccourciApplique? raccourci;
  final String? message;
  final double marge;
  final VoidCallback onAnnuler;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final applique = raccourci;
    final phrase = message;
    if (applique == null && phrase == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(marge, AppSpacing.sm, marge, 0),
      child: applique == null
          ? Text(
              phrase!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${AppStrings.raccourciResultat(applique.cases)} · '
                    '${applique.portee.libelle}, '
                    '${applique.cible.libelle.toLowerCase()}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: AppTextStyles.chiffresTabulaires,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.entreCibles),
                Semantics(
                  button: true,
                  excludeSemantics: true,
                  onTap: onAnnuler,
                  // « Annuler » seul est ambigu à l'oreille : la sémantique
                  // nomme le raccourci qu'on défait.
                  label: AppStrings.raccourciAnnulerSemantique(
                    applique.portee.libelle,
                  ),
                  child: TextButton.icon(
                    onPressed: onAnnuler,
                    icon: const Icon(Icons.undo, size: AppTouch.icone),
                    label: const Text(AppStrings.raccourciAnnulerLabel),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, AppTouch.cible),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Pourquoi les raccourcis sont inertes, à côté des raccourcis inertes.
class _Raison extends StatelessWidget {
  const _Raison({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.lock_outline,
          size: AppTouch.iconePetite,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            texte,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
