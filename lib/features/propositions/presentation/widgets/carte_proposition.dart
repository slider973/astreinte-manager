import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../../astreintes/domain/astreinte.dart';
import '../../domain/proposition.dart';

/// Une proposition en attente, en ligne de liste (`design/064 § 2`).
///
/// Un carré de 40 à rayon 12 portant l'initiale du créneau, un titre, une
/// ligne de soutien, et à droite l'ancienneté de la proposition. Un appui
/// ouvre la réponse — **la même des deux côtés** : la feuille de bas d'écran
/// de la Boîte en `compact`, son volet latéral en `large`. La réponse ne se
/// dédouble pas.
///
/// **Le même objet sur l'accueil et dans la Boîte** (chantier 064b), d'où sa
/// place ici et non dans `features/accueil` : une seconde copie aurait
/// divergé au premier réglage, et le pompier aurait lu deux formes de la même
/// ligne à deux écrans d'intervalle.
///
/// **Ce que cette ligne ne dit pas.** Le brief y met « 1/3 pourvus » à droite.
/// L'effectif pourvu d'un créneau n'existe nulle part dans ce que le membre a
/// le droit de lire : `Proposition` porte l'attribution, son créneau et l'état
/// du planning, et la politique `assignments_select_own_published` ne rend que
/// les attributions du lecteur tant que le planning n'est pas validé
/// (`docs/SCHEMA.md § 4`). Le chiffre demanderait une requête et une politique
/// nouvelles — c'est un ticket, pas un effet de bord d'un chantier de forme.
/// La place revient à ce qui existe et qui sert : depuis quand la question est
/// posée.
class CarteProposition extends StatelessWidget {
  const CarteProposition({
    required this.proposition,
    required this.heures,
    required this.maintenant,
    required this.onOuvrir,
    super.key,
  });

  /// Côté du carré d'initiale.
  static const double carre = 40;

  final Proposition proposition;
  final HeuresAffichage heures;

  /// L'horloge, injectée : « il y a 2 h » se mesure contre elle.
  final DateTime maintenant;

  final VoidCallback onOuvrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final creneau = context.statuts.creneau(proposition.creneau);

    final titre = dateAvecJourSemaine(proposition.jour);
    final soutien =
        '${creneau.libelle} · '
        '${heures.intervalle(proposition.creneau)}';
    final proposeeLe = proposition.proposeeLe;
    final mention = proposeeLe == null
        ? null
        : formaterInstantRelatif(proposeeLe, maintenant: maintenant);

    return Semantics(
      button: true,
      label: <String>[
        titre,
        soutien,
        AppStrings.attributionProposeMembre,
        if (mention != null) AppStrings.accueilProposeeDepuis(mention),
      ].join(', '),
      child: ExcludeSemantics(
        // **Une carte de `surface` sur le papier doux de la page**
        // (`design/064 § 2`), celle que `CarteDouce` porte pour les trois
        // écrans du pompier depuis le chantier 064c.
        child: CarteDouce(
          onTap: onOuvrir,
          hauteurMin: AppTouch.cible,
          child: Row(
            children: <Widget>[
              _CarreCreneau(
                initiale: creneau.libelle.characters.first.toUpperCase(),
                icone: creneau.icone,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      titre,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      soutien,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (mention != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  mention,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Le carré d'initiale : « J » ou « N », et l'icône du créneau à côté.
///
/// L'initiale seule serait une lettre sans système — « J » et « N » ne se
/// devinent pas. L'icône du créneau la double, à la taille où elle se lit
/// encore, et la phrase annoncée de la ligne dit « Jour » ou « Nuit » en
/// toutes lettres.
class _CarreCreneau extends StatelessWidget {
  const _CarreCreneau({required this.initiale, required this.icone});

  final String initiale;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: CarteProposition.carre,
      height: CarteProposition.carre,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: AppRadius.feuilleCarreeRadius,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icone,
              size: AppTouch.iconePetite,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              initiale,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
