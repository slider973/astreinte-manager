import '../../../core/l10n/app_strings.dart';
import 'parametres_caserne.dart';

/// Les champs de l'écran qui peuvent porter une erreur.
///
/// Un seul message par champ : l'erreur est affichée **sous le contrôle
/// fautif**, jamais rassemblée ailleurs sans l'être aussi à sa place.
enum ChampParametre {
  nom,
  fuseau,
  debutJour,
  finJour,
  effectifJour,
  effectifNuit,
  jourLimite,
  relancePush,
  relanceEmail,
  rapportRetard,
  surcharges,
}

/// Les bornes du document `settings`.
///
/// **Elles sont le miroir exact de la contrainte SQL `stations_settings_valide`
/// (migration `0011`).** Toute modification ici se fait en même temps que
/// là-bas, sinon l'écran promet ce que la base refuse — ou l'inverse, ce qui
/// est pire : un réglage impossible à poser sans explication.
abstract final class LimitesParametres {
  static const int nomMax = 80;

  static const int effectifMin = 0;
  static const int effectifMax = 50;

  /// 28 : le jour limite doit exister dans tous les mois, février compris.
  static const int jourLimiteMin = 1;
  static const int jourLimiteMax = 28;

  /// 336 heures = deux semaines. Au-delà, une relance ne relance plus.
  static const int delaiMin = 1;
  static const int delaiMax = 336;
}

final RegExp _heure = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
final RegExp _dateCourte = RegExp(r'^([0-9]{2})/([0-9]{2})/([0-9]{4})$');

/// Vrai pour « HH:MM », de 00:00 à 23:59.
bool heureValide(String valeur) => _heure.hasMatch(valeur);

/// Lit « 31/12/2026 ». Rend `null` si la date n'existe pas — le 31 février
/// s'écrit sans peine, et `DateTime` le déplacerait au 3 mars sans rien dire.
DateTime? lireDateCourte(String valeur) {
  final trouve = _dateCourte.firstMatch(valeur.trim());
  if (trouve == null) return null;

  final jour = int.parse(trouve.group(1)!);
  final mois = int.parse(trouve.group(2)!);
  final annee = int.parse(trouve.group(3)!);
  if (mois < 1 || mois > 12 || jour < 1) return null;

  final date = DateTime(annee, mois, jour);
  if (date.year != annee || date.month != mois || date.day != jour) return null;
  return date;
}

/// Tout ce qui ne va pas dans ces réglages, un message par champ.
///
/// Vide : le document passera la contrainte de la base. C'est la promesse de
/// cette fonction, et c'est ce que vérifie `test/features/parametres/`.
Map<ChampParametre, String> validerParametres(ParametresCaserne parametres) {
  final erreurs = <ChampParametre, String>{};

  final nom = parametres.nom.trim();
  if (nom.isEmpty) {
    erreurs[ChampParametre.nom] = AppStrings.parametresNomVide;
  } else if (nom.length > LimitesParametres.nomMax) {
    erreurs[ChampParametre.nom] = AppStrings.parametresNomLong;
  }

  if (!AppStrings.fuseauxCaserne.containsKey(parametres.fuseau)) {
    erreurs[ChampParametre.fuseau] = AppStrings.parametresFuseauInconnu;
  }

  if (!heureValide(parametres.debutJour)) {
    erreurs[ChampParametre.debutJour] = AppStrings.parametresHeureInvalide;
  }
  if (!heureValide(parametres.finJour)) {
    erreurs[ChampParametre.finJour] = AppStrings.parametresHeureInvalide;
  } else if (parametres.finJour == parametres.debutJour) {
    // L'erreur est posée sur la fin : c'est le champ qu'on vient de quitter
    // quand les deux se rejoignent.
    erreurs[ChampParametre.finJour] = AppStrings.parametresHeuresIdentiques;
  }

  _borne(
    erreurs,
    ChampParametre.effectifJour,
    parametres.effectifJour,
    LimitesParametres.effectifMin,
    LimitesParametres.effectifMax,
    AppStrings.parametresEffectifBorne,
  );
  _borne(
    erreurs,
    ChampParametre.effectifNuit,
    parametres.effectifNuit,
    LimitesParametres.effectifMin,
    LimitesParametres.effectifMax,
    AppStrings.parametresEffectifBorne,
  );
  _borne(
    erreurs,
    ChampParametre.jourLimite,
    parametres.jourLimite,
    LimitesParametres.jourLimiteMin,
    LimitesParametres.jourLimiteMax,
    AppStrings.parametresJourLimiteBorne,
  );
  _borne(
    erreurs,
    ChampParametre.relancePush,
    parametres.relancePushHeures,
    LimitesParametres.delaiMin,
    LimitesParametres.delaiMax,
    AppStrings.parametresDelaiBorne,
  );
  _borne(
    erreurs,
    ChampParametre.relanceEmail,
    parametres.relanceEmailHeures,
    LimitesParametres.delaiMin,
    LimitesParametres.delaiMax,
    AppStrings.parametresDelaiBorne,
  );
  _borne(
    erreurs,
    ChampParametre.rapportRetard,
    parametres.rapportRetardHeures,
    LimitesParametres.delaiMin,
    LimitesParametres.delaiMax,
    AppStrings.parametresDelaiBorne,
  );

  for (final surcharge in parametres.surcharges) {
    if (surcharge.estVide) {
      erreurs[ChampParametre.surcharges] =
          AppStrings.parametresSurchargeIncomplete;
      break;
    }
    if (!cleSurchargeValide(surcharge.cle)) {
      erreurs[ChampParametre.surcharges] = AppStrings.parametresDateInvalide;
      break;
    }
    if (!_effectifValide(surcharge.effectifJour) ||
        !_effectifValide(surcharge.effectifNuit)) {
      erreurs[ChampParametre.surcharges] = AppStrings.parametresEffectifBorne;
      break;
    }
  }

  return erreurs;
}

/// Vrai pour `mon`…`sun` ou pour une date ISO réelle — la règle de
/// `station_settings_cle_surcharge_valide` (migration `0011`).
bool cleSurchargeValide(String cle) {
  if (JourSemaine.depuisCle(cle) != null) return true;
  if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(cle)) return false;

  final date = DateTime.tryParse(cle);
  return date != null && cleDate(date) == cle;
}

bool _effectifValide(int? valeur) =>
    valeur == null ||
    (valeur >= LimitesParametres.effectifMin &&
        valeur <= LimitesParametres.effectifMax);

void _borne(
  Map<ChampParametre, String> erreurs,
  ChampParametre champ,
  int valeur,
  int min,
  int max,
  String message,
) {
  if (valeur < min || valeur > max) erreurs[champ] = message;
}
