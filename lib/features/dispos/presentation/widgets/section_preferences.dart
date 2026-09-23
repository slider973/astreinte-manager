import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../domain/disponibilite_mois.dart';
import '../../domain/preferences_mois.dart';
import '../controllers/saisie_controller.dart';
import 'champ_commentaire.dart';
import 'feuille_plafond.dart';
import 'preferences_rangees.dart';

/// **« Ce mois, je veux faire au maximum »** — la moitié du produit qui
/// manquait.
///
/// La grille dit ce que le membre **peut** faire ; cette section dit ce qu'il
/// **veut** faire. C'est elle qui autorise un pompier à cocher ses quatre
/// weekends pour laisser le choix à son chef sans se retrouver planifié
/// quatre weekends.
///
/// **Sa place a changé par rapport au brief du 011**, qui l'avait réservée
/// sous le dernier jour du mois : depuis le ticket 012, un mois se remplit en
/// deux touches sans défiler, et une section à trois écrans de défilement ne
/// serait jamais vue par la personne que ce ticket vise (`design/013 § 3`).
///
/// Elle vit donc **au-dessus de la grille**, et le prix de cette place est
/// payé par sa forme : au repos, elle tient en 80 à 140 dp — le titre, la
/// valeur, la leçon tant qu'elle n'a pas été apprise, et l'écart quand il y
/// en a un. Les contrôles et le commentaire n'apparaissent qu'au toucher. En
/// `large`, où rien n'est en concurrence avec la grille, elle est toujours
/// complète.
class SectionPreferences extends ConsumerStatefulWidget {
  const SectionPreferences({super.key, this.dansPanneau = false});

  /// Vrai dans le panneau de droite (`large`) : la place existe, la section
  /// reste toujours complète et ne se résume jamais.
  final bool dansPanneau;

  @override
  ConsumerState<SectionPreferences> createState() => _SectionPreferencesState();
}

class _SectionPreferencesState extends ConsumerState<SectionPreferences> {
  /// Le mois dont la forme d'ouverture a été décidée. Changer de mois
  /// redécide, sans attendre une interaction.
  String? _moisVu;
  bool _ouverte = true;
  bool _commentaireOuvert = false;

  /// La présence de la section, **figée le temps d'un geste**.
  ///
  /// Sans cela, la première case peinte la ferait apparaître et déplacerait
  /// la grille de quatre-vingts dp sous un doigt qui vise la suivante. C'est
  /// la même précaution que le bloc d'aide du 011, et pour la même raison.
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(saisieControllerProvider).value;
    if (etat == null) return const SizedBox.shrink();

    final preferences = etat.preferences;
    // **Tant que le mois est vierge, la section n'a rien à dire.** Il n'y a
    // rien à plafonner, la question « combien j'en veux » n'a pas d'objet, et
    // le bloc d'aide du 011 tient le haut de l'écran pour apprendre le geste.
    // Elle apparaît dès la première case posée — c'est-à-dire, pour le membre
    // que ce ticket vise, à la seconde exacte où son raccourci vient de
    // cocher tous ses weekends.
    if (!etat.enPeinture) _visible = _aQuelqueChoseADire(etat);
    if (!widget.dansPanneau && !_visible) return const SizedBox.shrink();
    if (_moisVu != etat.periode.cle) {
      _moisVu = etat.periode.cle;
      // **Jamais ouverte d'office au-dessus de la grille** : la forme
      // compacte dit déjà la valeur, la leçon et l'écart, et elle coûte deux
      // lignes de jour au lieu de six. Les contrôles arrivent au toucher.
      _ouverte = widget.dansPanneau;
      _commentaireOuvert = false;
    }

    final classe = AppWindowClass.of(context);
    final marge = widget.dansPanneau ? 0.0 : classe.margePage;
    final complete = _ouverte || widget.dansPanneau;
    // **Sur téléphone, la carte se résume à une ligne** (chantier 064d) : la
    // grille est la tâche, et tout ce qui la pousse sous le pli se paie. Le
    // commentaire, lui, descend sous la grille dans sa propre carte.
    final surUneLigne = !widget.dansPanneau && classe.estCompact;

    return Padding(
      padding: EdgeInsets.fromLTRB(marge, AppSpacing.md, marge, 0),
      child: Semantics(
        container: true,
        child: _Bloc(
          enErreur: preferences.enErreur,
          child: complete
              ? _corpsComplet(etat, preferences, horsCarte: surUneLigne)
              : _Compacte(
                  preferences: preferences,
                  compteurs: etat.compteurs,
                  surUneLigne: surUneLigne,
                  // La leçon arrive **quand elle a du sens** : sur un mois
                  // encore vierge, il n'y a rien à ne pas s'engager à faire,
                  // et le bloc d'aide du 011 apprend déjà le geste juste en
                  // dessous. Deux leçons empilées au-dessus de la grille, ce
                  // serait deux leçons non lues.
                  montrerLecon:
                      etat.modifiable &&
                      !preferences.ligneAuChargement &&
                      !etat.mois.estVierge,
                  modifiable: etat.modifiable,
                  onOuvrir: () => setState(() => _ouverte = true),
                ),
        ),
      ),
    );
  }

  /// Sur un mois **verrouillé**, la section ne montre que ce qui a été
  /// réellement déclaré : proposer « autant que nécessaire » pour un mois
  /// qu'on ne peut plus changer serait une question sans réponse possible.
  static bool _aQuelqueChoseADire(EtatSaisie etat) {
    if (!etat.modifiable) {
      return etat.preferences.ligneAuChargement ||
          !etat.preferences.valeurs.vide;
    }
    return !etat.mois.estVierge ||
        !etat.preferences.valeurs.vide ||
        etat.preferences.ligneAuChargement ||
        etat.preferences.reprise;
  }

  Widget _corpsComplet(
    EtatSaisie etat,
    EtatPreferences preferences, {
    required bool horsCarte,
  }) {
    final valeurs = preferences.valeurs;
    final compteurs = etat.compteurs;
    final modifiable = etat.modifiable;
    final theme = Theme.of(context);

    final raison = etat.periode.ouverte
        ? (etat.lectureSeule ? AppStrings.preferencesLectureSeule : null)
        : AppStrings.preferencesVerrouille;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                AppStrings.preferencesTitre,
                style: theme.textTheme.titleMedium,
              ),
              if (modifiable) ...<Widget>[
                const SizedBox(height: AppSpacing.sousTitre),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    AppStrings.preferencesLecon,
                    key: const Key('preferences-lecon'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (preferences.reprise) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                LigneMention(
                  icone: Icons.history,
                  texte: AppStrings.preferencesReprise(preferences.repriseDe!),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
        RangeePlafond(
          libelle: AppStrings.preferencesAstreintes,
          valeur: valeurs.maxAstreintes,
          detail: AppStrings.preferencesAstreintesCochees(compteurs.astreintes),
          actionnable: modifiable,
          onOuvrir: () => unawaited(_choisirAstreintes(etat)),
        ),
        RangeePlafond(
          libelle: AppStrings.preferencesWeekends,
          valeur: valeurs.maxWeekends,
          detail: AppStrings.preferencesWeekendsCoches(compteurs.weekends),
          actionnable: modifiable,
          onOuvrir: () => unawaited(_choisirWeekends(etat)),
        ),
        _Ecart(valeurs: valeurs, compteurs: compteurs),
        // Sur téléphone, le commentaire n'est plus ici : il a sa carte sous
        // la grille (`CarteCommentaire`, chantier 064d).
        if (!horsCarte)
          if (modifiable)
            ChampCommentaire(
              texte: valeurs.commentaire,
              ouvert: _commentaireOuvert,
              onOuvrir: () => setState(() => _commentaireOuvert = true),
              onChange: ref
                  .read(saisieControllerProvider.notifier)
                  .definirCommentaire,
            )
          else
            CommentaireLecture(texte: valeurs.commentaire, valeurs: valeurs),
        if (raison != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: LigneMention(icone: Icons.lock, texte: raison),
          ),
      ],
    );
  }

  Future<void> _choisirAstreintes(EtatSaisie etat) async {
    final choix = await choisirPlafond(
      context: context,
      titre: AppStrings.preferencesFeuilleAstreintes,
      valeur: etat.preferences.valeurs.maxAstreintes,
      maximum: PreferencesMois.plafondAstreintesMax,
      libelleZero: AppStrings.preferencesZeroAstreintes,
      libelleNombre: AppStrings.preferencesPlafondAstreintes,
    );
    if (choix == null) return;
    ref
        .read(saisieControllerProvider.notifier)
        .definirPlafondAstreintes(choix.valeur);
  }

  Future<void> _choisirWeekends(EtatSaisie etat) async {
    final choix = await choisirPlafond(
      context: context,
      titre: AppStrings.preferencesFeuilleWeekends,
      valeur: etat.preferences.valeurs.maxWeekends,
      // La borne vient du mois affiché : le nombre réel d'unités de weekend,
      // fériés en semaine compris. Mai 2026 en porte neuf.
      maximum: unitesWeekendDuMois(etat.periode.jours),
      libelleZero: AppStrings.preferencesZeroWeekends,
      libelleNombre: AppStrings.preferencesPlafondWeekends,
    );
    if (choix == null) return;
    ref
        .read(saisieControllerProvider.notifier)
        .definirPlafondWeekends(choix.valeur);
  }
}

/// Le bloc réglé : fond `surface`, filet 1 dp, rayon 8, **aucune ombre**.
/// Le filet passe à 2 dp `error` quand l'écriture a échoué — l'équivalent du
/// contour d'erreur d'une case, et la valeur voulue reste à l'écran.
class _Bloc extends StatelessWidget {
  const _Bloc({required this.child, required this.enErreur});

  final Widget child;
  final bool enErreur;

  /// La carte du monde du pompier (ticket 064c). Le bloc était déjà `surface`
  /// sur filet `outline-variant` : il ne change que de rayon, 8 → 20, et le
  /// filet d'erreur de 2 dp lui reste — c'est une erreur de **saisie**, celle
  /// du plafond qu'on vient de taper, pas une erreur de chargement.
  ///
  /// Sans rembourrage : les deux formes de la section, compacte et complète,
  /// portent déjà les leurs, et un commentaire replié doit pouvoir toucher
  /// les bords de sa carte.
  @override
  Widget build(BuildContext context) =>
      CarteDouce.nue(enErreur: enErreur, child: child);
}

/// **La forme compacte** — celle qu'on voit sans rien faire.
///
/// Elle ne cache pas l'information : elle énonce le titre, la valeur, la
/// leçon tant que le membre ne s'est jamais prononcé pour ce mois, et
/// l'écart quand il y en a un. Ce qu'elle range, ce sont les contrôles et le
/// commentaire, qui n'ont de sens qu'au moment où on les touche.
class _Compacte extends StatelessWidget {
  const _Compacte({
    required this.preferences,
    required this.compteurs,
    required this.montrerLecon,
    required this.modifiable,
    required this.onOuvrir,
    required this.surUneLigne,
  });

  final EtatPreferences preferences;
  final CompteursMois compteurs;
  final bool montrerLecon;
  final bool modifiable;
  final VoidCallback onOuvrir;

  /// **Sur téléphone** (chantier 064d) : le titre court et les valeurs sur une
  /// seule ligne de 56 points, et rien d'autre que les encarts qui s'appliquent.
  /// La leçon s'en va — elle reste dans la forme ouverte, à une touche —, et
  /// l'aperçu du commentaire aussi, puisque le commentaire a sa carte sous la
  /// grille.
  final bool surUneLigne;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valeurs = preferences.valeurs;
    final valeur = AppStrings.preferencesValeurs(
      valeurs.maxAstreintes,
      valeurs.maxWeekends,
    );

    return Semantics(
      button: true,
      label: '${AppStrings.preferencesTitre} : $valeur',
      hint: modifiable
          ? AppStrings.preferencesModifier
          : AppStrings.preferencesVerrouille,
      excludeSemantics: true,
      child: InkWell(
        onTap: onOuvrir,
        borderRadius: AppRadius.carteRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (surUneLigne)
                _Resume(valeur: valeur, sansLimite: valeurs.sansAucuneLimite)
              else
                _Empile(valeur: valeur, sansLimite: valeurs.sansAucuneLimite),
              // La leçon ne s'affiche que tant qu'elle a quelque chose à
              // apprendre : une fois que le membre s'est prononcé pour ce
              // mois, elle a fait son travail. Sur téléphone, elle ne
              // s'affiche plus du tout : elle est dans la forme ouverte, à
              // une touche, et la grille vaut plus que deux lignes de prose
              // au-dessus d'elle.
              if (montrerLecon && !surUneLigne) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    AppStrings.preferencesLecon,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              // La reprise n'est **jamais** silencieuse (ticket 013) : elle
              // reste, sur téléphone comme ailleurs, et ne coûte une ligne
              // que le mois où elle a lieu.
              if (preferences.reprise) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                LigneMention(
                  icone: Icons.history,
                  texte: AppStrings.preferencesReprise(preferences.repriseDe!),
                ),
              ],
              // L'aperçu du commentaire s'en va avec le commentaire : il a sa
              // carte sous la grille (chantier 064d).
              if (valeurs.commentaire.isNotEmpty && !surUneLigne) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  valeurs.commentaire,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              _Ecart(valeurs: valeurs, compteurs: compteurs, encadre: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// **Le résumé d'une ligne** : « Au maximum · 8 astreintes, 2 weekends », et
/// le chevron. Vingt-quatre points de texte entre deux rembourrages de seize :
/// la carte fait 56 points, la hauteur d'un champ.
///
/// Un seul paragraphe, deux styles : le titre en `titleMedium`, la valeur en
/// `bodyLarge`. Deux `Text` dans une `Row` n'auraient pas partagé la même
/// ligne de base, et la valeur aurait flotté sous son titre.
class _Resume extends StatelessWidget {
  const _Resume({required this.valeur, required this.sansLimite});

  final String valeur;
  final bool sansLimite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: AppStrings.preferencesTitreCourt,
                  style: theme.textTheme.titleMedium,
                ),
                TextSpan(
                  text: AppStrings.preferencesSeparateur,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextSpan(
                  text: valeur,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: sansLimite
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Icon(
          Icons.chevron_right,
          size: AppTouch.icone,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// Le titre au-dessus de sa valeur : la forme de `medium` et au-delà, là où
/// la grille n'a pas besoin des quarante points que la ligne unique gagne.
class _Empile extends StatelessWidget {
  const _Empile({required this.valeur, required this.sansLimite});

  final String valeur;
  final bool sansLimite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                AppStrings.preferencesTitre,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                valeur,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: sansLimite
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.chevron_right,
          size: AppTouch.icone,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// **Le cœur pédagogique** : l'écart entre ce qui est coché et ce qui est
/// voulu, et la phrase qui dit que cet écart est normal.
///
/// En encre d'information, **jamais en rouge ni en ocre** : dépasser son
/// maximum est ici le résultat recherché (`docs/PRD.md § 7.4`). Un
/// avertissement apprendrait au membre à décocher, c'est-à-dire exactement le
/// contraire de ce que ce ticket existe pour obtenir.
class _Ecart extends StatelessWidget {
  const _Ecart({
    required this.valeurs,
    required this.compteurs,
    this.encadre = true,
  });

  final PreferencesMois valeurs;
  final CompteursMois compteurs;

  /// Faux dans la forme compacte, qui porte déjà son propre rembourrage.
  final bool encadre;

  String? get _phrase {
    final weekends = valeurs.maxWeekends;
    if (weekends != null && compteurs.weekends > weekends) {
      return AppStrings.preferencesEcartWeekends(compteurs.weekends, weekends);
    }
    final astreintes = valeurs.maxAstreintes;
    if (astreintes != null && compteurs.astreintes > astreintes) {
      return AppStrings.preferencesEcartAstreintes(
        compteurs.astreintes,
        astreintes,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final texte = _phrase;
    if (texte == null) return const SizedBox.shrink();

    final descripteur = context.statuts.periode(PeriodeEtat.ouverte);

    return Padding(
      padding: encadre
          ? const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            )
          : const EdgeInsets.only(top: AppSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: descripteur.fond,
          borderRadius: AppRadius.caseRegistreRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.info_outline,
                size: AppTouch.icone,
                color: descripteur.encre,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  texte,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: descripteur.encre),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
