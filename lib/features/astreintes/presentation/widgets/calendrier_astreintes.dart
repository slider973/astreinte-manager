import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../domain/astreinte.dart';
import 'barre_mois.dart';

/// **La vue calendrier** : sept colonnes, du lundi au dimanche, un mois à la
/// fois.
///
/// Le ticket 011 a refusé le calendrier en compact parce que ses soixante-deux
/// cases se touchent toutes : `7 × 48 + 6 × 8 = 384 dp` contre 328 disponibles
/// sur un téléphone de 360. Ici la contrainte est plus douce — **seuls les
/// jours marqués sont actionnables**, trois ou quatre par mois. En ramenant la
/// marge de la grille à 8 et l'écart à 4, une case fait 45,7 dp sur un
/// téléphone de 360 et 49,9 sur un 390 : au-dessus du plancher
/// (`design/027 § 7.5`).
class CalendrierAstreintes extends StatelessWidget {
  const CalendrierAstreintes({
    required this.mois,
    required this.donnees,
    required this.aujourdhui,
    required this.onMois,
    required this.onOuvrir,
    super.key,
  });

  /// Le mois affiché, au premier du mois.
  final DateTime mois;

  final MesAstreintes donnees;
  final DateTime aujourdhui;

  /// Change de mois. `null` sur une borne : la flèche est alors désactivée
  /// avec sa raison, jamais cachée.
  final ValueChanged<DateTime> onMois;

  /// Ouvre le détail d'une journée.
  final ValueChanged<List<Astreinte>> onOuvrir;

  /// Écart entre deux cases. 4 en compact (`DESIGN.md § Espacement`), 6 dès
  /// que la largeur le paie.
  static double ecartDe(AppWindowClass classe) =>
      classe.estCompact ? AppSpacing.xs : 6;

  /// Marge horizontale de la seule grille. Écart assumé à la marge de page de
  /// 16 : à 16, une case tombe à 43,4 dp sur un téléphone de 360.
  static double margeDe(AppWindowClass classe) =>
      classe.estCompact ? AppSpacing.sm : AppSpacing.pageMedium;

  @override
  Widget build(BuildContext context) {
    final classe = AppWindowClass.of(context);
    final ecart = ecartDe(classe);
    final marge = margeDe(classe);

    final parJour = donnees.parJourDuMois(mois.year, mois.month);
    final (DateTime premier, DateTime dernier) = donnees.etendue(aujourdhui);

    // Bornée comme la liste : sur un portable, sept colonnes étalées sur
    // 1 200 dp donnent des cases de 165 dp pour deux chiffres.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
        child: _grille(
          context,
          ecart: ecart,
          marge: marge,
          parJour: parJour,
          premier: premier,
          dernier: dernier,
        ),
      ),
    );
  }

  Widget _grille(
    BuildContext context, {
    required double ecart,
    required double marge,
    required Map<int, List<Astreinte>> parJour,
    required DateTime premier,
    required DateTime dernier,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BarreMois(
          libelle: AppStrings.moisNomEtAnnee(mois.month, mois.year),
          onPrecedent: mois.isAfter(premier)
              ? () => onMois(DateTime(mois.year, mois.month - 1))
              : null,
          onSuivant: mois.isBefore(dernier)
              ? () => onMois(DateTime(mois.year, mois.month + 1))
              : null,
          libellePrecedent: AppStrings.astreintesMoisPrecedent,
          libelleSuivant: AppStrings.astreintesMoisSuivant,
          raisonPrecedent: AppStrings.astreintesMoisAvantDebut,
          raisonSuivant: AppStrings.astreintesMoisApresFin,
        ),
        // **La grille dans sa carte** (`design/064 § 3.2`, chantier 064c).
        // Sa marge extérieure est celle que la grille portait, et ses cases
        // touchent le filet : les rentrer d'un rembourrage de plus ferait
        // tomber une case sous le plancher de 44 dp sur un téléphone de 360,
        // ce que le calcul du ticket 027 interdit.
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.md),
            child: CarteDouce.nue(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: _EnteteJours(ecart: ecart),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Column(
                        children: <Widget>[
                          for (final semaine in _semaines(mois))
                            Padding(
                              padding: EdgeInsets.only(top: ecart),
                              // Les sept blocs d'une semaine s'alignent sur le plus
                              // haut : sans cela, une semaine sans astreinte serait
                              // deux fois plus basse que la suivante.
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    for (final date in semaine) ...<Widget>[
                                      Expanded(
                                        child: _Case(
                                          date: date,
                                          horsMois: date.month != mois.month,
                                          aujourdhui: _memeJour(
                                            date,
                                            aujourdhui,
                                          ),
                                          astreintes: date.month == mois.month
                                              ? parJour[date.day] ??
                                                    const <Astreinte>[]
                                              : const <Astreinte>[],
                                          onOuvrir: onOuvrir,
                                        ),
                                      ),
                                      if (date != semaine.last)
                                        SizedBox(width: ecart),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Les semaines du mois, chacune de sept jours, du lundi au dimanche.
  static List<List<DateTime>> _semaines(DateTime mois) {
    final premier = DateTime(mois.year, mois.month);
    // `weekday` vaut 1 le lundi : le décalage est direct.
    final debut = premier.subtract(Duration(days: premier.weekday - 1));
    final dernier = DateTime(mois.year, mois.month + 1, 0);
    final fin = dernier.add(Duration(days: 7 - dernier.weekday));

    final total = fin.difference(debut).inDays + 1;
    return <List<DateTime>>[
      for (var semaine = 0; semaine * 7 < total; semaine++)
        <DateTime>[
          for (var jour = 0; jour < 7; jour++)
            DateTime(debut.year, debut.month, debut.day + semaine * 7 + jour),
        ],
    ];
  }
}

bool _memeJour(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Les initiales des sept jours. Décoratives : la sémantique de chaque case
/// dit le jour en toutes lettres.
class _EnteteJours extends StatelessWidget {
  const _EnteteJours({required this.ecart});

  final double ecart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExcludeSemantics(
      child: Row(
        children: <Widget>[
          for (var jour = 0; jour < 7; jour++) ...<Widget>[
            Expanded(
              child: Text(
                AppStrings.grilleJoursInitiales[jour],
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (jour < 6) SizedBox(width: ecart),
          ],
        ],
      ),
    );
  }
}

/// Un jour du calendrier : un **bloc réglé**, jamais une carte.
class _Case extends StatelessWidget {
  const _Case({
    required this.date,
    required this.horsMois,
    required this.aujourdhui,
    required this.astreintes,
    required this.onOuvrir,
  });

  /// Hauteur de la marque d'un créneau.
  static const double hauteurMarque = 18;

  final DateTime date;
  final bool horsMois;
  final bool aujourdhui;
  final List<Astreinte> astreintes;
  final ValueChanged<List<Astreinte>> onOuvrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;
    final marquee = astreintes.isNotEmpty;
    final weekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

    final contenu = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${date.day}',
            textAlign: TextAlign.center,
            style: AppTextStyles.nombrePetit.copyWith(
              color: horsMois
                  ? theme.colorScheme.outline
                  : theme.colorScheme.onSurface,
            ),
          ),
          for (final astreinte in astreintes) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            _Marque(creneau: astreinte.creneau),
          ],
        ],
      ),
    );

    final bloc = DecoratedBox(
      decoration: BoxDecoration(
        color: horsMois
            ? Colors.transparent
            : weekend
            ? theme.colorScheme.surfaceDim
            : theme.colorScheme.surface,
        borderRadius: AppRadius.caseRegistreRadius,
        border: Border.all(color: statuts.filetDecoratif),
      ),
      child: Stack(
        children: <Widget>[
          // Le jour courant porte un filet `primary` de 2 dp sur son bord
          // gauche, comme `DayCell` au ticket 011 — posé par-dessus le bloc et
          // non dans sa bordure : un `Border` non uniforme et un rayon de coin
          // ne cohabitent pas.
          if (aujourdhui)
            PositionedDirectional(
              top: 0,
              bottom: 0,
              start: 0,
              child: ColoredBox(
                color: theme.colorScheme.primary,
                child: const SizedBox(width: AppStroke.etat),
              ),
            ),
          contenu,
        ],
      ),
    );

    final jourEtDate = dateAvecJourSemaine(date);
    final ferie = nomJourFerie(date);

    if (!marquee) {
      // Un jour vide n'a rien à montrer : le rendre cliquable pour afficher
      // « rien » serait un faux affordance. Il reste lu, sinon le calendrier
      // ne se parcourt pas au lecteur d'écran.
      return Semantics(
        label: horsMois
            ? AppStrings.jourHorsMois
            : AppStrings.astreintesJourLibre(jourEtDate),
        excludeSemantics: true,
        child: bloc,
      );
    }

    return Semantics(
      button: true,
      label: AppStrings.astreintesJourSemantique(
        jourEtDate: aujourdhui
            ? '${AppStrings.jourAujourdhui}, $jourEtDate'
            : jourEtDate,
        creneaux: AppStrings.astreintesCreneauxDuJour(<String>[
          for (final astreinte in astreintes)
            statuts.creneau(astreinte.creneau).libelle,
        ]),
      ),
      hint: ferie == null ? null : AppStrings.jourFerieNomme(ferie),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onOuvrir(astreintes),
          borderRadius: AppRadius.caseRegistreRadius,
          child: bloc,
        ),
      ),
    );
  }
}

/// La marque d'un créneau d'astreinte : une **case pleine** portant l'icône du
/// créneau.
///
/// Quatre signaux : la case est pleine (marque), elle porte un glyphe (icône),
/// la sémantique de la case le dit en toutes lettres (libellé), et elle est
/// verte (couleur, en quatrième).
///
/// L'encre est celle de `etat-disponible-plein`, lue à travers le thème. Elle
/// est prise pour sa **valeur** — une case pleine sombre contre une case vide
/// blanche reste lisible en niveaux de gris, là où le vert pâle d'« accepté »
/// ne le serait pas — et non pour son sens : le sens est porté par l'icône du
/// créneau et par la phrase annoncée. Sur cet écran, « accepté » est universel
/// et ne distingue rien (`design/027 § 5`).
class _Marque extends StatelessWidget {
  const _Marque({required this.creneau});

  final CreneauType creneau;

  @override
  Widget build(BuildContext context) {
    final statuts = context.statuts;
    final plein = statuts.disponibilite(DisponibiliteEtat.disponible);

    return Container(
      height: _Case.hauteurMarque,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: plein.fond,
        borderRadius: AppRadius.caseRegistreRadius,
      ),
      child: Icon(
        statuts.creneau(creneau).icone,
        size: AppTouch.iconePetite,
        color: plein.encre,
      ),
    );
  }
}
