import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'app_colors.dart';

/// Disponibilité d'un créneau — la grammaire de la case du registre.
///
/// La distinction entre [absent] et [nonSaisi] est **le** mécanisme qui
/// sépare ce produit de l'intranet remplacé (brief § 2). Si ces deux cases se
/// ressemblent, le système a échoué.
enum DisponibiliteEtat { disponible, absent, nonSaisi }

/// Créneau d'une journée. Ne porte **aucune teinte** : il est signé par
/// l'icône et par la position, le fond ne fait que confirmer.
enum CreneauType { jour, nuit }

/// Cycle de vie d'une proposition d'astreinte.
///
/// **L'ordre est celui de la lecture du suivi** : ce qui reste à faire d'abord,
/// puis ce qui est acquis, puis ce qui a cassé, puis ce qui a été réparé. Le
/// tri des réponses d'un créneau s'appuie dessus (`SuiviPlanning`).
///
/// [remplace] et [annule] disent tous deux « cette attribution ne compte
/// plus » ; ils se distinguent par l'icône et le libellé, jamais par une
/// cinquième couleur (`DESIGN.md § Écarts, ticket 020`).
enum AttributionEtat { propose, accepte, refuse, remplace, annule }

/// Cycle de vie d'un planning mensuel.
enum PlanningEtat { brouillon, publie, valide, archive }

/// État de la période de saisie d'un mois.
enum PeriodeEtat { ouverte, verrouillee }

/// État de l'enregistrement automatique et du réseau.
enum SyncEtat { repos, enregistrement, enregistre, echec, horsLigne }

/// Tout ce qu'il faut pour afficher un état, indissociable.
///
/// **C'est ici que vit la règle « jamais la couleur seule ».** Un
/// [StatusDescriptor] ne peut pas être construit sans [icone] ni [libelle] :
/// aucun écran ne peut donc rendre un état par une teinte seule, ni par une
/// pastille muette. L'assertion sur un libellé vide ferme la dernière porte.
///
/// Ordre des signaux, du plus robuste au moins robuste (`DESIGN.md`) :
/// la **marque** ([hachure], [barre], [filet], remplissage), puis l'**icône**,
/// puis le **libellé**, et la couleur seulement en quatrième.
@immutable
class StatusDescriptor {
  const StatusDescriptor({
    required this.icone,
    required this.libelle,
    required this.encre,
    required this.fond,
    this.filet,
    this.hachure = false,
    this.barre = false,
    IconData? iconeCase,
  }) : assert(libelle != '', 'Un état sans libellé est interdit.'),
       _iconeCase = iconeCase;

  /// Glyphe accompagnant le libellé. Toujours une icône Material, jamais un
  /// emoji ni un glyphe Unicode.
  final IconData icone;

  /// Libellé français, affiché **et** annoncé. Jamais vide.
  final String libelle;

  /// Couleur du texte et du glyphe. Contraste ≥ 4.5:1 sur [fond], vérifié
  /// par `test/core/theme/contraste_test.dart`.
  final Color encre;

  /// Fond de la marque.
  final Color fond;

  /// Contour **porteur d'état**, 2 dp. `null` quand l'état n'en porte pas.
  final Color? filet;

  /// Marque hachurée à 45° : « absent » et « mois verrouillé », nulle part
  /// ailleurs.
  final bool hachure;

  /// Marque barrée : « refusé » et « annulé ». Ce qui est annulé ne se
  /// supprime pas, il se barre et reste lisible (principe produit 5).
  final bool barre;

  final IconData? _iconeCase;

  /// Glyphe employé **dans la case du registre**, où l'encombrement d'une
  /// icône de case à cocher nuit à la lecture à 28 px : `check`, `close` et
  /// `remove` au lieu de `check_box`, `disabled_by_default` et
  /// `check_box_outline_blank` (`DESIGN.md § Disponibilité`).
  ///
  /// Vaut [icone] quand l'état n'a pas de variante de grille.
  IconData get iconeCase => _iconeCase ?? icone;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatusDescriptor &&
          other.icone == icone &&
          other.libelle == libelle &&
          other.encre == encre &&
          other.fond == fond &&
          other.filet == filet &&
          other.hachure == hachure &&
          other.barre == barre &&
          other.iconeCase == iconeCase;

  @override
  int get hashCode => Object.hash(
    icone,
    libelle,
    encre,
    fond,
    filet,
    hachure,
    barre,
    iconeCase,
  );

  /// Interpolation entre deux descripteurs, pour le passage clair/sombre.
  /// Les couleurs se mélangent ; l'icône, le libellé et les marques
  /// basculent à mi-course — un demi-glyphe ne veut rien dire.
  static StatusDescriptor lerp(
    StatusDescriptor a,
    StatusDescriptor b,
    double t,
  ) {
    final versB = t >= 0.5;
    return StatusDescriptor(
      icone: versB ? b.icone : a.icone,
      iconeCase: versB ? b.iconeCase : a.iconeCase,
      libelle: versB ? b.libelle : a.libelle,
      encre: Color.lerp(a.encre, b.encre, t)!,
      fond: Color.lerp(a.fond, b.fond, t)!,
      filet: Color.lerp(a.filet, b.filet, t),
      hachure: versB ? b.hachure : a.hachure,
      barre: versB ? b.barre : a.barre,
    );
  }
}

/// Extension de thème qui résout un [StatusDescriptor] pour chaque valeur
/// d'énumération, en clair et en sombre.
///
/// Un widget n'écrit jamais une couleur d'état : il demande
/// `Theme.of(context).extension<AppStatusColors>()!.disponibilite(etat)` et
/// reçoit d'un seul coup la couleur, l'icône et le libellé.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.disponibilites,
    required this.creneaux,
    required this.attributions,
    required this.plannings,
    required this.periodes,
    required this.syncs,
    required this.filetEtat,
    required this.filetDecoratif,
    required this.accentTexte,
  });

  final Map<DisponibiliteEtat, StatusDescriptor> disponibilites;
  final Map<CreneauType, StatusDescriptor> creneaux;
  final Map<AttributionEtat, StatusDescriptor> attributions;
  final Map<PlanningEtat, StatusDescriptor> plannings;
  final Map<PeriodeEtat, StatusDescriptor> periodes;
  final Map<SyncEtat, StatusDescriptor> syncs;

  /// Filet **porteur d'information** (≥ 3:1) : case non saisie, sélection.
  final Color filetEtat;

  /// Réglure décorative du registre. Ne porte jamais d'information.
  final Color filetDecoratif;

  /// L'indigo **en texte** : lien, libellé d'accent, « toi » dans une liste.
  ///
  /// Ce n'est pas `colorScheme.primary`. Depuis le ticket 061, `primary` est
  /// l'indigo vif, fait pour remplir un bloc sous du blanc (4.72:1) ; posé en
  /// texte il tombe à 3.96:1 sur le fond de grille. L'indigo lisible partout
  /// est celui-ci — 5.86:1 au pire cran de surface en clair. En sombre les
  /// deux coïncident, le fond ayant changé de côté.
  final Color accentTexte;

  StatusDescriptor disponibilite(DisponibiliteEtat etat) =>
      disponibilites[etat]!;

  StatusDescriptor creneau(CreneauType type) => creneaux[type]!;

  StatusDescriptor attribution(AttributionEtat etat) => attributions[etat]!;

  StatusDescriptor planning(PlanningEtat etat) => plannings[etat]!;

  StatusDescriptor periode(PeriodeEtat etat) => periodes[etat]!;

  StatusDescriptor sync(SyncEtat etat) => syncs[etat]!;

  /// Tous les descripteurs du thème, dans l'ordre des familles. Sert au
  /// catalogue `/dev/components` et aux tests de couverture.
  List<StatusDescriptor> get tous => <StatusDescriptor>[
    ...disponibilites.values,
    ...creneaux.values,
    ...attributions.values,
    ...plannings.values,
    ...periodes.values,
    ...syncs.values,
  ];

  // -------------------------------------------------------------------
  // Thème clair
  // -------------------------------------------------------------------

  static const AppStatusColors clair = AppStatusColors(
    filetEtat: AppColors.etatNonSaisiFilet,
    filetDecoratif: AppColors.outlineVariant,
    accentTexte: AppColors.accentTexte,
    disponibilites: <DisponibiliteEtat, StatusDescriptor>{
      // Case pleine : le triplet du registre commence par « cochée ».
      DisponibiliteEtat.disponible: StatusDescriptor(
        icone: Icons.check_box,
        iconeCase: Icons.check,
        libelle: AppStrings.etatDisponible,
        encre: AppColors.onPrimary,
        fond: AppColors.etatDisponiblePlein,
      ),
      // Case hachurée à 45°, bord 2 dp : « barrée ».
      DisponibiliteEtat.absent: StatusDescriptor(
        icone: Icons.disabled_by_default,
        iconeCase: Icons.close,
        libelle: AppStrings.etatAbsent,
        encre: AppColors.etatAbsentSurFond,
        fond: AppColors.etatAbsentFond,
        filet: AppColors.etatAbsent,
        hachure: true,
      ),
      // Case vide, filet tireté : « vide ».
      DisponibiliteEtat.nonSaisi: StatusDescriptor(
        icone: Icons.check_box_outline_blank,
        iconeCase: Icons.remove,
        libelle: AppStrings.etatNonSaisi,
        encre: AppColors.etatNonSaisi,
        fond: AppColors.surface,
        filet: AppColors.etatNonSaisiFilet,
      ),
    },
    creneaux: <CreneauType, StatusDescriptor>{
      CreneauType.jour: StatusDescriptor(
        icone: Icons.light_mode,
        libelle: AppStrings.creneauJour,
        encre: AppColors.onSurfaceVariant,
        fond: AppColors.surface,
      ),
      CreneauType.nuit: StatusDescriptor(
        icone: Icons.bedtime,
        libelle: AppStrings.creneauNuit,
        encre: AppColors.onSurfaceVariant,
        fond: AppColors.surfaceContainerHigh,
      ),
    },
    attributions: <AttributionEtat, StatusDescriptor>{
      // L'encre du bloc orange est celle du registre, pas l'orange :
      // `etatAttente` sur `etatAttenteFond` ne fait que 4.22:1 depuis le
      // ticket 061. Il reste le filet, où 3:1 suffit.
      AttributionEtat.propose: StatusDescriptor(
        icone: Icons.hourglass_top,
        libelle: AppStrings.attributionPropose,
        encre: AppColors.etatAttenteSurFond,
        fond: AppColors.etatAttenteFond,
        filet: AppColors.etatAttente,
      ),
      AttributionEtat.accepte: StatusDescriptor(
        icone: Icons.task_alt,
        libelle: AppStrings.attributionAccepte,
        encre: AppColors.etatDisponibleSurFond,
        fond: AppColors.etatDisponibleFond,
      ),
      AttributionEtat.refuse: StatusDescriptor(
        icone: Icons.cancel,
        libelle: AppStrings.attributionRefuse,
        encre: AppColors.etatAbsentSurFond,
        fond: AppColors.etatAbsentFond,
        barre: true,
      ),
      AttributionEtat.remplace: StatusDescriptor(
        icone: Icons.swap_horiz,
        libelle: AppStrings.attributionRemplace,
        encre: AppColors.etatAnnule,
        fond: AppColors.etatNeutreFond,
        barre: true,
      ),
      AttributionEtat.annule: StatusDescriptor(
        icone: Icons.block,
        libelle: AppStrings.attributionAnnule,
        encre: AppColors.etatAnnule,
        fond: AppColors.etatNeutreFond,
        barre: true,
      ),
    },
    plannings: <PlanningEtat, StatusDescriptor>{
      PlanningEtat.brouillon: StatusDescriptor(
        icone: Icons.edit_note,
        libelle: AppStrings.planningBrouillon,
        encre: AppColors.etatNeutre,
        fond: AppColors.etatNeutreFond,
        filet: AppColors.etatNeutre,
      ),
      PlanningEtat.publie: StatusDescriptor(
        icone: Icons.campaign,
        libelle: AppStrings.planningPublie,
        encre: AppColors.onSecondaryContainer,
        fond: AppColors.etatInfoFond,
      ),
      PlanningEtat.valide: StatusDescriptor(
        icone: Icons.verified,
        libelle: AppStrings.planningValide,
        encre: AppColors.etatDisponibleSurFond,
        fond: AppColors.etatDisponibleFond,
      ),
      PlanningEtat.archive: StatusDescriptor(
        icone: Icons.inventory_2,
        libelle: AppStrings.planningArchive,
        encre: AppColors.etatArchive,
        fond: AppColors.etatArchiveFond,
      ),
    },
    periodes: <PeriodeEtat, StatusDescriptor>{
      PeriodeEtat.ouverte: StatusDescriptor(
        icone: Icons.lock_open,
        libelle: AppStrings.periodeOuverte,
        encre: AppColors.onSecondaryContainer,
        fond: AppColors.etatInfoFond,
        filet: AppColors.etatInfo,
      ),
      // Le verrouillage n'est pas une erreur : gris-encre, jamais rose.
      PeriodeEtat.verrouillee: StatusDescriptor(
        icone: Icons.lock,
        libelle: AppStrings.periodeVerrouillee,
        encre: AppColors.etatVerrouille,
        fond: AppColors.etatVerrouilleFond,
        hachure: true,
      ),
    },
    syncs: <SyncEtat, StatusDescriptor>{
      SyncEtat.repos: StatusDescriptor(
        icone: Icons.cloud_done_outlined,
        libelle: AppStrings.saveAuRepos,
        encre: AppColors.onSurfaceVariant,
        fond: AppColors.surface,
      ),
      SyncEtat.enregistrement: StatusDescriptor(
        icone: Icons.sync,
        libelle: AppStrings.saveEnCours,
        encre: AppColors.onSurfaceVariant,
        fond: AppColors.surface,
      ),
      SyncEtat.enregistre: StatusDescriptor(
        icone: Icons.cloud_done,
        libelle: AppStrings.saveTermine,
        encre: AppColors.etatDisponible,
        fond: AppColors.surface,
      ),
      SyncEtat.echec: StatusDescriptor(
        icone: Icons.error_outline,
        libelle: AppStrings.saveEchec,
        encre: AppColors.error,
        fond: AppColors.surface,
      ),
      SyncEtat.horsLigne: StatusDescriptor(
        icone: Icons.cloud_off,
        libelle: AppStrings.horsLigne,
        encre: AppColors.etatAttenteSurFond,
        fond: AppColors.etatAttenteFond,
      ),
    },
  );

  // -------------------------------------------------------------------
  // Thème sombre
  // -------------------------------------------------------------------

  static const AppStatusColors sombre = AppStatusColors(
    filetEtat: AppColors.darkEtatNonSaisiFilet,
    filetDecoratif: AppColors.darkOutlineVariant,
    accentTexte: AppColors.darkAccentTexte,
    disponibilites: <DisponibiliteEtat, StatusDescriptor>{
      DisponibiliteEtat.disponible: StatusDescriptor(
        icone: Icons.check_box,
        iconeCase: Icons.check,
        libelle: AppStrings.etatDisponible,
        encre: AppColors.onPrimary,
        fond: AppColors.darkEtatDisponiblePlein,
      ),
      DisponibiliteEtat.absent: StatusDescriptor(
        icone: Icons.disabled_by_default,
        iconeCase: Icons.close,
        libelle: AppStrings.etatAbsent,
        encre: AppColors.darkEtatAbsentSurFond,
        fond: AppColors.darkEtatAbsentFond,
        filet: AppColors.darkEtatAbsentFilet,
        hachure: true,
      ),
      DisponibiliteEtat.nonSaisi: StatusDescriptor(
        icone: Icons.check_box_outline_blank,
        iconeCase: Icons.remove,
        libelle: AppStrings.etatNonSaisi,
        encre: AppColors.darkEtatNonSaisi,
        fond: AppColors.darkSurface,
        filet: AppColors.darkEtatNonSaisiFilet,
      ),
    },
    creneaux: <CreneauType, StatusDescriptor>{
      CreneauType.jour: StatusDescriptor(
        icone: Icons.light_mode,
        libelle: AppStrings.creneauJour,
        encre: AppColors.darkOnSurfaceVariant,
        fond: AppColors.darkSurface,
      ),
      CreneauType.nuit: StatusDescriptor(
        icone: Icons.bedtime,
        libelle: AppStrings.creneauNuit,
        encre: AppColors.darkOnSurfaceVariant,
        fond: AppColors.darkSurfaceContainerHigh,
      ),
    },
    attributions: <AttributionEtat, StatusDescriptor>{
      AttributionEtat.propose: StatusDescriptor(
        icone: Icons.hourglass_top,
        libelle: AppStrings.attributionPropose,
        encre: AppColors.darkEtatAttenteSurFond,
        fond: AppColors.darkEtatAttenteFond,
        filet: AppColors.darkEtatAttente,
      ),
      AttributionEtat.accepte: StatusDescriptor(
        icone: Icons.task_alt,
        libelle: AppStrings.attributionAccepte,
        encre: AppColors.darkEtatDisponibleSurFond,
        fond: AppColors.darkEtatDisponibleFond,
      ),
      AttributionEtat.refuse: StatusDescriptor(
        icone: Icons.cancel,
        libelle: AppStrings.attributionRefuse,
        encre: AppColors.darkOnErrorContainer,
        fond: AppColors.darkErrorContainer,
        barre: true,
      ),
      AttributionEtat.remplace: StatusDescriptor(
        icone: Icons.swap_horiz,
        libelle: AppStrings.attributionRemplace,
        encre: AppColors.darkEtatNeutre,
        fond: AppColors.darkEtatNeutreFond,
        barre: true,
      ),
      AttributionEtat.annule: StatusDescriptor(
        icone: Icons.block,
        libelle: AppStrings.attributionAnnule,
        encre: AppColors.darkEtatNeutre,
        fond: AppColors.darkEtatNeutreFond,
        barre: true,
      ),
    },
    plannings: <PlanningEtat, StatusDescriptor>{
      PlanningEtat.brouillon: StatusDescriptor(
        icone: Icons.edit_note,
        libelle: AppStrings.planningBrouillon,
        encre: AppColors.darkEtatNeutre,
        fond: AppColors.darkEtatNeutreFond,
        filet: AppColors.darkEtatNeutre,
      ),
      PlanningEtat.publie: StatusDescriptor(
        icone: Icons.campaign,
        libelle: AppStrings.planningPublie,
        encre: AppColors.darkEtatInfoSurFond,
        fond: AppColors.darkEtatInfoFond,
      ),
      PlanningEtat.valide: StatusDescriptor(
        icone: Icons.verified,
        libelle: AppStrings.planningValide,
        encre: AppColors.darkEtatDisponibleSurFond,
        fond: AppColors.darkEtatDisponibleFond,
      ),
      PlanningEtat.archive: StatusDescriptor(
        icone: Icons.inventory_2,
        libelle: AppStrings.planningArchive,
        encre: AppColors.darkEtatArchive,
        fond: AppColors.darkEtatArchiveFond,
      ),
    },
    periodes: <PeriodeEtat, StatusDescriptor>{
      PeriodeEtat.ouverte: StatusDescriptor(
        icone: Icons.lock_open,
        libelle: AppStrings.periodeOuverte,
        encre: AppColors.darkEtatInfoSurFond,
        fond: AppColors.darkEtatInfoFond,
        filet: AppColors.darkEtatInfo,
      ),
      PeriodeEtat.verrouillee: StatusDescriptor(
        icone: Icons.lock,
        libelle: AppStrings.periodeVerrouillee,
        encre: AppColors.darkEtatVerrouille,
        fond: AppColors.darkEtatVerrouilleFond,
        hachure: true,
      ),
    },
    syncs: <SyncEtat, StatusDescriptor>{
      SyncEtat.repos: StatusDescriptor(
        icone: Icons.cloud_done_outlined,
        libelle: AppStrings.saveAuRepos,
        encre: AppColors.darkOnSurfaceVariant,
        fond: AppColors.darkSurface,
      ),
      SyncEtat.enregistrement: StatusDescriptor(
        icone: Icons.sync,
        libelle: AppStrings.saveEnCours,
        encre: AppColors.darkOnSurfaceVariant,
        fond: AppColors.darkSurface,
      ),
      SyncEtat.enregistre: StatusDescriptor(
        icone: Icons.cloud_done,
        libelle: AppStrings.saveTermine,
        encre: AppColors.darkEtatDisponible,
        fond: AppColors.darkSurface,
      ),
      SyncEtat.echec: StatusDescriptor(
        icone: Icons.error_outline,
        libelle: AppStrings.saveEchec,
        encre: AppColors.darkEtatAbsent,
        fond: AppColors.darkSurface,
      ),
      SyncEtat.horsLigne: StatusDescriptor(
        icone: Icons.cloud_off,
        libelle: AppStrings.horsLigne,
        encre: AppColors.darkEtatAttenteSurFond,
        fond: AppColors.darkEtatAttenteFond,
      ),
    },
  );

  @override
  AppStatusColors copyWith({
    Map<DisponibiliteEtat, StatusDescriptor>? disponibilites,
    Map<CreneauType, StatusDescriptor>? creneaux,
    Map<AttributionEtat, StatusDescriptor>? attributions,
    Map<PlanningEtat, StatusDescriptor>? plannings,
    Map<PeriodeEtat, StatusDescriptor>? periodes,
    Map<SyncEtat, StatusDescriptor>? syncs,
    Color? filetEtat,
    Color? filetDecoratif,
    Color? accentTexte,
  }) {
    return AppStatusColors(
      disponibilites: disponibilites ?? this.disponibilites,
      creneaux: creneaux ?? this.creneaux,
      attributions: attributions ?? this.attributions,
      plannings: plannings ?? this.plannings,
      periodes: periodes ?? this.periodes,
      syncs: syncs ?? this.syncs,
      filetEtat: filetEtat ?? this.filetEtat,
      filetDecoratif: filetDecoratif ?? this.filetDecoratif,
      accentTexte: accentTexte ?? this.accentTexte,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      disponibilites: _lerpMap(disponibilites, other.disponibilites, t),
      creneaux: _lerpMap(creneaux, other.creneaux, t),
      attributions: _lerpMap(attributions, other.attributions, t),
      plannings: _lerpMap(plannings, other.plannings, t),
      periodes: _lerpMap(periodes, other.periodes, t),
      syncs: _lerpMap(syncs, other.syncs, t),
      filetEtat: Color.lerp(filetEtat, other.filetEtat, t)!,
      filetDecoratif: Color.lerp(filetDecoratif, other.filetDecoratif, t)!,
      accentTexte: Color.lerp(accentTexte, other.accentTexte, t)!,
    );
  }

  static Map<K, StatusDescriptor> _lerpMap<K>(
    Map<K, StatusDescriptor> a,
    Map<K, StatusDescriptor> b,
    double t,
  ) {
    return <K, StatusDescriptor>{
      for (final entry in a.entries)
        entry.key: StatusDescriptor.lerp(
          entry.value,
          b[entry.key] ?? entry.value,
          t,
        ),
    };
  }
}

/// Raccourci de lecture de l'extension depuis un widget.
extension AppStatusColorsContext on BuildContext {
  /// Les couleurs, icônes et libellés d'état du thème courant.
  ///
  /// Lève si l'extension est absente : un widget de ce système ne doit jamais
  /// être monté sous un `ThemeData` étranger, et un échec silencieux (couleur
  /// par défaut, état sans icône) serait pire qu'une exception en test.
  AppStatusColors get statuts {
    final extension = Theme.of(this).extension<AppStatusColors>();
    assert(
      extension != null,
      'AppStatusColors absent du thème : monte le widget sous AppTheme.clair '
      'ou AppTheme.sombre.',
    );
    return extension ?? AppStatusColors.clair;
  }
}
