import 'package:flutter/foundation.dart';

import '../caserne/etat_caserne.dart';
import '../l10n/app_strings.dart';
import '../l10n/format_date.dart';
import 'app_banner.dart';

/// Le fait « caserne » qu'un écran doit annoncer, s'il y en a un.
///
/// Deux champs et pas un widget tout fait : chaque écran a déjà sa propre liste
/// de variantes à arbitrer — erreur d'enregistrement, hors ligne, mois
/// verrouillé — et la règle « une seule bannière à la fois » se joue chez lui.
/// Il verse donc [variante] dans son arbitrage, et ne construit [banniere] que
/// si elle gagne.
@immutable
class FaitCaserne {
  const FaitCaserne({required this.variante, required this.banniere});

  final AppBannerVariante variante;
  final AppBanner banniere;
}

/// La bannière d'abonnement d'un écran qui écrit, ou `null`.
///
/// Trois faits possibles, dans cet ordre :
///
/// 1. **la caserne est en lecture seule** — pour tout le monde, membre compris,
///    parce que c'est ce qui explique une grille inerte ;
/// 2. **l'essai est terminé, la tâche de suspension n'a pas encore tourné** —
///    pour les administrateurs ; elle passe une fois par jour, cette fenêtre
///    existe et l'écran ne ment pas ;
/// 3. **l'essai se termine bientôt** — pour les administrateurs, à deux paliers
///    d'escalade : `information` à J-14, `attention` à J-3.
///
/// Au-delà de quatorze jours, **rien**. Une bannière permanente pendant soixante
/// jours coûterait 48 dp de grille chaque jour pour redire une chose sans
/// échéance ; c'est la même décision qu'au ticket 011 pour la fermeture d'un
/// mois, qui n'apparaît qu'à J-3.
///
/// Un membre ordinaire ne voit **jamais** les faits d'essai : il n'a rien à y
/// faire, et lui annoncer une échéance qu'il ne peut pas tenir est du bruit.
FaitCaserne? faitCaserne({
  required EtatCaserne? etat,
  required bool admin,
  required DateTime maintenant,
  VoidCallback? versAbonnement,
}) {
  if (etat == null) return null;

  if (etat.lectureSeule) {
    final depuis = etat.suspendueLe;
    return FaitCaserne(
      variante: AppBannerVariante.lectureSeule,
      banniere: AppBanner(
        variante: AppBannerVariante.lectureSeule,
        texte: depuis == null
            ? AppStrings.lectureSeuleBanniere
            : AppStrings.lectureSeuleDepuis(formaterDateLongue(depuis)),
        detail: admin
            ? AppStrings.lectureSeuleAdminDetail
            : AppStrings.lectureSeuleMembreDetail,
        // Un membre n'a pas de destination : lui donner un bouton qui mène à un
        // écran fermé par le routeur serait une impasse de plus.
        libelleAction: admin && versAbonnement != null
            ? AppStrings.lectureSeuleAction
            : null,
        onAction: admin ? versAbonnement : null,
      ),
    );
  }

  if (!admin) return null;

  if (etat.essaiExpire(maintenant: maintenant)) {
    return FaitCaserne(
      variante: AppBannerVariante.attention,
      banniere: AppBanner(
        variante: AppBannerVariante.attention,
        texte: AppStrings.essaiTermine,
        detail: AppStrings.essaiTermineDetail,
        libelleAction: versAbonnement == null
            ? null
            : AppStrings.lectureSeuleAction,
        onAction: versAbonnement,
      ),
    );
  }

  final jours = etat.joursEssaiRestants(maintenant: maintenant);
  final fin = etat.finEssai;
  if (jours == null || fin == null || jours > seuilRappelEssai) return null;

  final urgent = jours <= seuilAlerteEssai;
  final variante = urgent
      ? AppBannerVariante.attention
      : AppBannerVariante.information;

  return FaitCaserne(
    variante: variante,
    banniere: AppBanner(
      variante: variante,
      texte: AppStrings.essaiJusquAu(formaterDateLongue(fin), jours),
      detail: AppStrings.essaiDetailAdmin,
      libelleAction: versAbonnement == null
          ? null
          : AppStrings.lectureSeuleAction,
      onAction: versAbonnement,
    ),
  );
}

/// Le premier palier : la bannière d'essai apparaît à quatorze jours.
const int seuilRappelEssai = 14;

/// Le second : elle passe à l'ocre à trois jours.
const int seuilAlerteEssai = 3;
