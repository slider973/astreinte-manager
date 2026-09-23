import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/entete_section.dart';
import '../../../astreintes/domain/astreinte.dart';
import '../../../notifications/domain/notification_interne.dart';
import '../../../notifications/presentation/widgets/ligne_notification.dart';
import '../../../propositions/domain/proposition.dart';
import '../../../propositions/presentation/widgets/carte_proposition.dart';
import '../../domain/composition_boite.dart';

/// Ce que les trois listes de la Boîte ont en commun : une colonne bornée,
/// la marge de page de la classe de fenêtre, le geste de tirage, et une
/// position de défilement qui survit au changement d'onglet.
///
/// Les trois sont **virtualisées** : deux cents rappels et soixante-deux
/// propositions sont légaux, et un `Column` dans un `SingleChildScrollView`
/// les construirait tous à chaque image.
class _Colonne extends StatelessWidget {
  const _Colonne({
    required this.cle,
    required this.compte,
    required this.constructeur,
    required this.onRelire,
    this.separateur,
  });

  /// La clé de défilement de l'onglet. `PageStorage` rend sa position quand on
  /// y revient : changer d'onglet n'est pas repartir du haut.
  final String cle;

  final int compte;
  final NullableIndexedWidgetBuilder constructeur;
  final IndexedWidgetBuilder? separateur;
  final Future<void> Function() onRelire;

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return RefreshIndicator(
      onRefresh: onRelire,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child: ListView.separated(
            key: PageStorageKey<String>(cle),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              marge,
              AppSpacing.md,
              marge,
              AppSpacing.xl,
            ),
            itemCount: compte,
            itemBuilder: (BuildContext context, int index) =>
                constructeur(context, index) ?? const SizedBox.shrink(),
            separatorBuilder:
                separateur ??
                (BuildContext context, int index) =>
                    const SizedBox(height: AppSpacing.sm),
          ),
        ),
      ),
    );
  }
}

/// **L'onglet « Tout »** : les propositions et les rappels, fusionnés par date
/// décroissante.
///
/// Une proposition y ouvre la réponse, un rappel ouvre sa cible. Les deux
/// gardent leur forme propre : la carte de proposition dit une question à
/// laquelle on répond, la ligne de rappel dit un fait qu'on a lu ou pas.
class ListeTout extends StatelessWidget {
  const ListeTout({
    required this.etat,
    required this.heures,
    required this.maintenant,
    required this.onProposition,
    required this.onRappel,
    required this.onRelire,
    super.key,
  });

  final EtatBoite etat;
  final HeuresAffichage heures;
  final DateTime maintenant;
  final ValueChanged<Proposition> onProposition;
  final ValueChanged<NotificationInterne> onRappel;
  final VoidCallback onRelire;

  @override
  Widget build(BuildContext context) {
    // **Une lecture en panne ne devient jamais un état vide.** Affirmer « Rien
    // pour l'instant » alors qu'on n'a rien pu lire est le pire des deux
    // mondes : c'est faux, et ça se croit. Chaque source dit son échec là où
    // son contenu manque, sans effacer l'autre — la condition porte sur le
    // contenu, jamais sur `hasValue` (leçon du 064a).
    final echecs = <Widget>[
      if (etat.echecPropositions)
        EmptyState.erreur(
          texte: AppStrings.propositionsErreurTexte,
          onAction: onRelire,
        ),
      if (etat.echecRappels)
        EmptyState.erreur(
          texte: AppStrings.centreErreurTexte,
          onAction: onRelire,
        ),
    ];

    if (etat.toutVide && echecs.isEmpty) {
      return const EmptyState(
        titre: AppStrings.centreVideTitre,
        texte: AppStrings.centreVideTexte,
      );
    }

    return _Colonne(
      cle: 'boite-tout',
      compte: echecs.length + etat.tout.length,
      onRelire: () async => onRelire(),
      constructeur: (BuildContext context, int index) {
        if (index < echecs.length) return echecs[index];
        final element = etat.tout[index - echecs.length];
        return switch (element) {
          PropositionBoite(:final proposition) => CarteProposition(
            key: ValueKey<String>(proposition.id),
            proposition: proposition,
            heures: heures,
            maintenant: maintenant,
            onOuvrir: () => onProposition(proposition),
          ),
          RappelBoite(:final notification) => _CarteRappel(
            key: ValueKey<String>(notification.id),
            notification: notification,
            maintenant: maintenant,
            onTouche: () => onRappel(notification),
          ),
        };
      },
    );
  }
}

/// **L'onglet « Propositions »** : les propositions en attente, groupées par
/// mois, dans l'ordre du calendrier.
///
/// Le groupement par mois est celui du ticket 021 : les en-têtes défilent avec
/// le contenu, ils ne sont pas collants. À trois propositions typiques, un
/// en-tête épinglé volerait 44 points pour ne rien dire de plus que la ligne
/// qu'il surplombe.
class ListePropositions extends StatelessWidget {
  const ListePropositions({
    required this.elements,
    required this.heures,
    required this.maintenant,
    required this.onOuvrir,
    required this.onRelire,
    super.key,
  });

  final List<ElementListe> elements;
  final HeuresAffichage heures;
  final DateTime maintenant;
  final ValueChanged<Proposition> onOuvrir;
  final VoidCallback onRelire;

  @override
  Widget build(BuildContext context) => _Colonne(
    cle: 'boite-propositions',
    compte: elements.length,
    onRelire: () async => onRelire(),
    // Les en-têtes portent déjà leur propre écart au-dessus d'eux
    // (`EnteteSection`) : un séparateur de plus creuserait un trou entre le
    // dernier mois et le suivant.
    separateur: (BuildContext context, int index) =>
        elements[index + 1] is EnteteMois
        ? const SizedBox.shrink()
        : const SizedBox(height: AppSpacing.sm),
    constructeur: (BuildContext context, int index) {
      final element = elements[index];
      return switch (element) {
        EnteteMois() => EnteteSection(
          titre: element.libelle,
          compte: AppStrings.propositionsCompte(element.compte),
          premiere: element.premier,
        ),
        LigneProposition(:final proposition) => CarteProposition(
          key: ValueKey<String>(proposition.id),
          proposition: proposition,
          heures: heures,
          maintenant: maintenant,
          onOuvrir: () => onOuvrir(proposition),
        ),
      };
    },
  );
}

/// **L'onglet « Rappels »** : les notifications qui ne sont pas des
/// propositions, la plus récente en premier.
class ListeRappels extends StatelessWidget {
  const ListeRappels({
    required this.rappels,
    required this.maintenant,
    required this.onOuvrir,
    required this.onRelire,
    super.key,
  });

  final List<NotificationInterne> rappels;
  final DateTime maintenant;
  final ValueChanged<NotificationInterne> onOuvrir;
  final VoidCallback onRelire;

  @override
  Widget build(BuildContext context) => _Colonne(
    cle: 'boite-rappels',
    compte: rappels.length,
    onRelire: () async => onRelire(),
    constructeur: (BuildContext context, int index) {
      final rappel = rappels[index];
      return _CarteRappel(
        key: ValueKey<String>(rappel.id),
        notification: rappel,
        maintenant: maintenant,
        onTouche: () => onOuvrir(rappel),
      );
    },
  );
}

/// Un rappel, **posé sur le papier doux de la Boîte**.
///
/// La ligne elle-même est celle du ticket 026, inchangée : la marque carrée de
/// non-lue, la graisse du titre, le fond plus dense, et « Non lue » en tête de
/// sa phrase annoncée. Ce qui change est ce qui la porte — une carte `surface`
/// à filet et à rayon 20, comme la carte de proposition qui la côtoie dans
/// « Tout » (`design/064 § 2`). Sans elle, les deux formes se seraient
/// contredites dans la même liste.
class _CarteRappel extends StatelessWidget {
  const _CarteRappel({
    required this.notification,
    required this.maintenant,
    required this.onTouche,
    super.key,
  });

  final NotificationInterne notification;
  final DateTime maintenant;
  final VoidCallback onTouche;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.carteRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: LigneNotification(
        notification: notification,
        maintenant: maintenant,
        onTouche: onTouche,
      ),
    );
  }
}
