import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';

/// Un jour de semaine, tel qu'il s'écrit dans une clé de surcharge.
///
/// Les trois lettres viennent de `docs/SCHEMA.md § 2.1` — `{"sat": {"day": 2}}`
/// — et ne sont jamais affichées : le libellé français est à côté.
enum JourSemaine {
  lundi('mon', 0),
  mardi('tue', 1),
  mercredi('wed', 2),
  jeudi('thu', 3),
  vendredi('fri', 4),
  samedi('sat', 5),
  dimanche('sun', 6);

  const JourSemaine(this.cle, this._index);

  final String cle;
  final int _index;

  String get libelle => AppStrings.joursSemaineLongs[_index];

  static JourSemaine? depuisCle(String cle) {
    for (final jour in values) {
      if (jour.cle == cle) return jour;
    }
    return null;
  }
}

/// Une exception à l'effectif requis, pour un jour de semaine ou pour une date.
///
/// `{"sat": {"day": 2}}` : une surcharge peut ne fixer qu'un seul créneau. Le
/// créneau laissé à `null` garde l'effectif par défaut de la caserne.
@immutable
class SurchargeEffectif {
  const SurchargeEffectif({
    required this.cle,
    this.effectifJour,
    this.effectifNuit,
  });

  /// `mon`…`sun`, ou une date ISO `AAAA-MM-JJ`.
  final String cle;

  final int? effectifJour;
  final int? effectifNuit;

  /// Une surcharge qui ne surcharge rien n'a pas lieu d'être : elle laisse
  /// croire à une règle. La base la refuse aussi.
  bool get estVide => effectifJour == null && effectifNuit == null;

  JourSemaine? get jourSemaine => JourSemaine.depuisCle(cle);

  /// La date de la surcharge, ou `null` si la clé est un jour de semaine ou
  /// une chaîne illisible.
  DateTime? get date =>
      jourSemaine != null ? null : DateTime.tryParse(cle)?.toLocal();

  /// Ce que la surcharge désigne, en français : « Samedi », « 31/12/2026 ».
  String get libelle {
    final jour = jourSemaine;
    if (jour != null) return jour.libelle;
    final quand = date;
    return quand == null ? cle : formaterDateCourte(quand);
  }

  /// La valeur en toutes lettres : « 2 en journée · 3 la nuit ».
  String get valeurLibelle =>
      AppStrings.parametresSurchargeValeur(effectifJour, effectifNuit);

  Map<String, dynamic> get versJson => <String, dynamic>{
    if (effectifJour != null) 'day': effectifJour,
    if (effectifNuit != null) 'night': effectifNuit,
  };

  SurchargeEffectif copyWith({
    int? Function()? effectifJour,
    int? Function()? effectifNuit,
  }) => SurchargeEffectif(
    cle: cle,
    effectifJour: effectifJour == null ? this.effectifJour : effectifJour(),
    effectifNuit: effectifNuit == null ? this.effectifNuit : effectifNuit(),
  );

  @override
  bool operator ==(Object other) =>
      other is SurchargeEffectif &&
      other.cle == cle &&
      other.effectifJour == effectifJour &&
      other.effectifNuit == effectifNuit;

  @override
  int get hashCode => Object.hash(cle, effectifJour, effectifNuit);
}

/// « 31/12/2026 ». Le format que l'écran lit et écrit pour une date de
/// surcharge : la base, elle, ne connaît que l'ISO.
String formaterDateCourte(DateTime date) {
  final locale = date.toLocal();
  final jour = locale.day.toString().padLeft(2, '0');
  final mois = locale.month.toString().padLeft(2, '0');
  return '$jour/$mois/${locale.year}';
}

/// La clé ISO d'une date de surcharge : `2026-12-31`.
String cleDate(DateTime date) {
  final locale = date.toLocal();
  final mois = locale.month.toString().padLeft(2, '0');
  final jour = locale.day.toString().padLeft(2, '0');
  return '${locale.year}-$mois-$jour';
}

/// Les réglages d'une caserne : la ligne `stations` et son document `settings`
/// (`docs/SCHEMA.md § 2.1`), à plat.
///
/// La lecture est **tolérante** — une clé absente reprend la valeur par défaut
/// plutôt que de faire échouer l'écran —, l'écriture est stricte : ce qui part
/// vers la base a déjà été validé par `validerParametres`, et la contrainte
/// `stations_settings_valide` reste l'autorité.
@immutable
class ParametresCaserne {
  const ParametresCaserne({
    required this.stationId,
    required this.nom,
    required this.fuseau,
    required this.debutJour,
    required this.finJour,
    required this.effectifJour,
    required this.effectifNuit,
    required this.jourLimite,
    required this.relancePushHeures,
    required this.relanceEmailHeures,
    required this.rapportRetardHeures,
    this.surcharges = const <SurchargeEffectif>[],
  });

  /// Les valeurs du `default` de la colonne `settings` (migration `0001`).
  static const ParametresCaserne defauts = ParametresCaserne(
    stationId: '',
    nom: '',
    fuseau: 'Europe/Paris',
    debutJour: '07:00',
    finJour: '19:00',
    effectifJour: 1,
    effectifNuit: 1,
    jourLimite: 15,
    relancePushHeures: 24,
    relanceEmailHeures: 48,
    rapportRetardHeures: 72,
  );

  /// Construit depuis la réponse PostgREST : `id, name, timezone, settings`.
  factory ParametresCaserne.depuisJson(Map<String, dynamic> ligne) {
    final settings = ligne['settings'];
    final reglages = settings is Map
        ? Map<String, dynamic>.from(settings)
        : <String, dynamic>{};

    return ParametresCaserne(
      stationId: ligne['id'] as String? ?? '',
      nom: ligne['name'] as String? ?? '',
      fuseau: ligne['timezone'] as String? ?? defauts.fuseau,
      debutJour: _texte(reglages['day_start'], defauts.debutJour),
      finJour: _texte(reglages['day_end'], defauts.finJour),
      effectifJour: _entier(reglages['required_day'], defauts.effectifJour),
      effectifNuit: _entier(reglages['required_night'], defauts.effectifNuit),
      jourLimite: _entier(
        reglages['availability_deadline_day'],
        defauts.jourLimite,
      ),
      relancePushHeures: _entier(
        reglages['response_reminder_hours'],
        defauts.relancePushHeures,
      ),
      relanceEmailHeures: _entier(
        reglages['response_email_hours'],
        defauts.relanceEmailHeures,
      ),
      rapportRetardHeures: _entier(
        reglages['late_report_hours'],
        defauts.rapportRetardHeures,
      ),
      surcharges: _surcharges(reglages['required_overrides']),
    );
  }

  final String stationId;
  final String nom;
  final String fuseau;

  /// « HH:MM ». Affichage seulement : rien n'est découpé par ces heures.
  final String debutJour;
  final String finJour;

  final int effectifJour;
  final int effectifNuit;

  /// Jour du mois **précédent** où la saisie se ferme.
  final int jourLimite;

  final int relancePushHeures;
  final int relanceEmailHeures;
  final int rapportRetardHeures;

  /// Les surcharges, triées : les jours de semaine dans l'ordre de la semaine,
  /// puis les dates dans l'ordre chronologique. L'ordre est une donnée de
  /// l'écran, pas un hasard de la sérialisation JSON.
  final List<SurchargeEffectif> surcharges;

  List<SurchargeEffectif> get surchargesDatees => surcharges
      .where((SurchargeEffectif s) => s.jourSemaine == null)
      .toList(growable: false);

  SurchargeEffectif? surchargeDe(JourSemaine jour) {
    for (final surcharge in surcharges) {
      if (surcharge.cle == jour.cle) return surcharge;
    }
    return null;
  }

  /// Le document `settings` tel qu'il part vers la base.
  ///
  /// `required_overrides` est **omis** quand il n'y a aucune surcharge : une
  /// clé vide n'apporte rien, et le défaut de la colonne ne la porte pas.
  Map<String, dynamic> get settingsJson => <String, dynamic>{
    'day_start': debutJour,
    'day_end': finJour,
    'required_day': effectifJour,
    'required_night': effectifNuit,
    'availability_deadline_day': jourLimite,
    'response_reminder_hours': relancePushHeures,
    'response_email_hours': relanceEmailHeures,
    'late_report_hours': rapportRetardHeures,
    if (surcharges.isNotEmpty)
      'required_overrides': <String, dynamic>{
        for (final SurchargeEffectif surcharge in surcharges)
          surcharge.cle: surcharge.versJson,
      },
  };

  /// Pose ou remplace une surcharge, et retire celles qui ne surchargent plus
  /// rien : une ligne vide dans le document serait refusée par la base.
  ParametresCaserne avecSurcharge(SurchargeEffectif surcharge) {
    final restantes = surcharges
        .where((SurchargeEffectif s) => s.cle != surcharge.cle)
        .toList();
    if (!surcharge.estVide) restantes.add(surcharge);
    return copyWith(surcharges: _trier(restantes));
  }

  ParametresCaserne sansSurcharge(String cle) => copyWith(
    surcharges: surcharges
        .where((SurchargeEffectif s) => s.cle != cle)
        .toList(growable: false),
  );

  ParametresCaserne copyWith({
    String? nom,
    String? fuseau,
    String? debutJour,
    String? finJour,
    int? effectifJour,
    int? effectifNuit,
    int? jourLimite,
    int? relancePushHeures,
    int? relanceEmailHeures,
    int? rapportRetardHeures,
    List<SurchargeEffectif>? surcharges,
  }) => ParametresCaserne(
    stationId: stationId,
    nom: nom ?? this.nom,
    fuseau: fuseau ?? this.fuseau,
    debutJour: debutJour ?? this.debutJour,
    finJour: finJour ?? this.finJour,
    effectifJour: effectifJour ?? this.effectifJour,
    effectifNuit: effectifNuit ?? this.effectifNuit,
    jourLimite: jourLimite ?? this.jourLimite,
    relancePushHeures: relancePushHeures ?? this.relancePushHeures,
    relanceEmailHeures: relanceEmailHeures ?? this.relanceEmailHeures,
    rapportRetardHeures: rapportRetardHeures ?? this.rapportRetardHeures,
    surcharges: surcharges ?? this.surcharges,
  );

  @override
  bool operator ==(Object other) =>
      other is ParametresCaserne &&
      other.stationId == stationId &&
      other.nom == nom &&
      other.fuseau == fuseau &&
      other.debutJour == debutJour &&
      other.finJour == finJour &&
      other.effectifJour == effectifJour &&
      other.effectifNuit == effectifNuit &&
      other.jourLimite == jourLimite &&
      other.relancePushHeures == relancePushHeures &&
      other.relanceEmailHeures == relanceEmailHeures &&
      other.rapportRetardHeures == rapportRetardHeures &&
      listEquals(other.surcharges, surcharges);

  @override
  int get hashCode => Object.hash(
    stationId,
    nom,
    fuseau,
    debutJour,
    finJour,
    effectifJour,
    effectifNuit,
    jourLimite,
    relancePushHeures,
    relanceEmailHeures,
    rapportRetardHeures,
    Object.hashAll(surcharges),
  );

  static String _texte(Object? valeur, String defaut) =>
      valeur is String && valeur.isNotEmpty ? valeur : defaut;

  /// Un entier lu sans confiance : la base garantit le type depuis la
  /// migration `0011`, mais une caserne créée avant elle peut porter n'importe
  /// quoi, et un écran qui refuse de s'ouvrir ne se répare pas.
  static int _entier(Object? valeur, int defaut) {
    if (valeur is int) return valeur;
    if (valeur is num) return valeur.round();
    if (valeur is String) return int.tryParse(valeur) ?? defaut;
    return defaut;
  }

  static List<SurchargeEffectif> _surcharges(Object? valeur) {
    if (valeur is! Map) return const <SurchargeEffectif>[];

    final lues = <SurchargeEffectif>[];
    valeur.forEach((Object? cle, Object? contenu) {
      if (cle is! String || contenu is! Map) return;
      final jour = contenu['day'];
      final nuit = contenu['night'];
      final surcharge = SurchargeEffectif(
        cle: cle,
        effectifJour: jour == null ? null : _entier(jour, 0),
        effectifNuit: nuit == null ? null : _entier(nuit, 0),
      );
      if (!surcharge.estVide) lues.add(surcharge);
    });
    return _trier(lues);
  }

  /// Les jours de semaine d'abord, dans l'ordre de la semaine ; les dates
  /// ensuite, de la plus proche à la plus lointaine.
  static List<SurchargeEffectif> _trier(List<SurchargeEffectif> surcharges) {
    final triees = surcharges.toList()
      ..sort((SurchargeEffectif a, SurchargeEffectif b) {
        final jourA = a.jourSemaine;
        final jourB = b.jourSemaine;
        if (jourA != null && jourB != null) {
          return jourA.index.compareTo(jourB.index);
        }
        if (jourA != null) return -1;
        if (jourB != null) return 1;
        return a.cle.compareTo(b.cle);
      });
    return List<SurchargeEffectif>.unmodifiable(triees);
  }
}
