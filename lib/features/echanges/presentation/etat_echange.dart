import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/theme/app_status.dart';
import '../../astreintes/domain/astreinte.dart';
import '../domain/cause_echange.dart';
import '../domain/echange.dart';

/// La grammaire des sept états d'une demande (`design/073 § 5.3`).
///
/// **Aucune encre nouvelle** : chaque état prend les couleurs et la marque
/// d'un descripteur existant du thème — l'attente des propositions, le
/// « Validé » du planning, le « Refusé » et l'« Annulé » des attributions,
/// l'« Archivé » du planning — et ne change que l'icône et le libellé. Deux
/// états d'une même famille diffèrent toujours par les deux.
StatusDescriptor descripteurEchange(BuildContext context, Echange echange) {
  final statuts = context.statuts;
  final scheme = Theme.of(context).colorScheme;
  final attente = statuts.attribution(AttributionEtat.propose);
  final refuse = statuts.attribution(AttributionEtat.refuse);
  final annule = statuts.attribution(AttributionEtat.annule);
  final valide = statuts.planning(PlanningEtat.valide);
  final archive = statuts.planning(PlanningEtat.archive);

  StatusDescriptor comme(
    StatusDescriptor base, {
    required IconData icone,
    required String libelle,
    Color? filet,
  }) => StatusDescriptor(
    icone: icone,
    libelle: libelle,
    encre: base.encre,
    fond: base.fond,
    filet: filet ?? base.filet,
    barre: base.barre,
  );

  return switch (echange.statut) {
    StatutEchange.ouvert when echange.aLaCaserne => comme(
      attente,
      icone: Icons.person_search,
      libelle: AppStrings.echangeEtatCherche,
    ),
    StatutEchange.ouvert => comme(
      attente,
      icone: Icons.hourglass_top,
      libelle: AppStrings.echangeEtatAttenteDe(_nom(echange.cibleNom)),
    ),
    StatutEchange.accepteParPair => comme(
      attente,
      icone: Icons.how_to_reg,
      libelle: AppStrings.echangeEtatAValider,
    ),
    StatutEchange.valide => comme(
      valide,
      icone: Icons.verified,
      libelle: AppStrings.echangeEtatValide,
    ),
    StatutEchange.refuse => comme(
      refuse,
      icone: Icons.cancel,
      libelle: AppStrings.echangeEtatRefuse,
    ),
    StatutEchange.annule => comme(
      annule,
      icone: Icons.block,
      libelle: AppStrings.echangeEtatAnnule,
    ),
    StatutEchange.expire => comme(
      archive,
      icone: Icons.timer_off,
      libelle: AppStrings.echangeEtatExpire,
    ),
    StatutEchange.echoue => comme(
      refuse,
      icone: Icons.error_outline,
      libelle: AppStrings.echangeEtatEchec,
      filet: scheme.error,
    ),
  };
}

/// « nuit du samedi 12 octobre ».
String phraseGarde(GardeEchange garde) => AppStrings.echangeCreneauPhrase(
  nuit: garde.creneau == CreneauType.nuit,
  jourEtDate: dateAvecJourSemaine(garde.jour),
);

/// « sam. 12 oct. · Nuit ».
String gardeCourte(BuildContext context, GardeEchange garde) =>
    AppStrings.echangeGardeCourte(
      jourCourt: nomJourCourt(garde.jour),
      jour: garde.jour.day,
      mois: garde.jour.month,
      creneau: context.statuts.creneau(garde.creneau).libelle,
    );

/// « Samedi 12 octobre · Nuit ».
String gardeTitre(BuildContext context, GardeEchange garde) =>
    AppStrings.echangeGardeTitre(
      dateAvecJourSemaine(garde.jour),
      context.statuts.creneau(garde.creneau).libelle,
    );

/// Les deux bornes d'une garde : (« 19:00 », « 07:00 ») pour la nuit.
(String, String) bornes(HeuresAffichage heures, CreneauType creneau) =>
    creneau == CreneauType.jour
    ? (heures.debutJour, heures.finJour)
    : (heures.finJour, heures.debutJour);

/// « Échange de la nuit du samedi 12 octobre » ou « Cession de… ».
String titreEchange(Echange echange) => echange.estEchange
    ? AppStrings.echangeDetailTitreEchange(phraseGarde(echange.garde))
    : AppStrings.echangeDetailTitreCession(phraseGarde(echange.garde));

/// La ligne de détail sous le badge : le qui, le quand, et pour un état
/// terminal le pourquoi — **écrite pour son lecteur** (`design/073 § 5.3`).
String ligneDetail(
  Echange echange, {
  required String moi,
  required DateTime maintenant,
}) {
  final lecteur = echange.lecteur(moi);
  final pair = _nom(echange.pairNom);
  final demandeur = _nom(echange.demandeurNom);
  String depuis(DateTime instant) =>
      formaterInstantRelatif(instant, maintenant: maintenant);
  String date(DateTime? instant) =>
      instant == null ? '' : formaterDateCourte(instant);
  String decideur() => echange.decideurId == moi
      ? AppStrings.echangeToi
      : _nom(echange.decideurNom);
  final cause = causeEchange(
    echange.codeMotif,
    nomDemandeur: demandeur,
    nomPair: pair,
  );
  final expire = formaterDateCourte(echange.expireLe);
  final heure = heureMinute(echange.expireLe);

  switch (echange.statut) {
    case StatutEchange.ouvert:
      return switch (lecteur) {
        LecteurEchange.demandeur when echange.aLaCaserne =>
          AppStrings.echangeDetailVisibleDispos(expire, heure),
        LecteurEchange.demandeur => AppStrings.echangeDetailEnvoyee(
          depuis(echange.creeLe),
          expire,
          heure,
        ),
        LecteurEchange.admin when echange.aLaCaserne =>
          AppStrings.echangeDetailEnvoyeeDispos(depuis(echange.creeLe)),
        LecteurEchange.admin => AppStrings.echangeDetailEnvoyeeAdmin(
          depuis(echange.creeLe),
          pair,
        ),
        _ => AppStrings.echangeDetailCherchePourB(demandeur),
      };
    case StatutEchange.accepteParPair:
      final accepte = depuis(echange.accepteLe ?? echange.creeLe);
      return switch (lecteur) {
        LecteurEchange.demandeur => AppStrings.echangeDetailAccepteParPourA(
          pair,
          accepte,
        ),
        LecteurEchange.pair => AppStrings.echangeDetailTuAsAccepte(accepte),
        _ => AppStrings.echangeDetailAccepteAdmin(pair, accepte),
      };
    case StatutEchange.valide:
      final quand = date(echange.decideLe ?? echange.closLe);
      if (echange.autoValide) return AppStrings.echangeDetailValideAuto(quand);
      return switch (lecteur) {
        LecteurEchange.demandeur => AppStrings.echangeDetailValidePourA(
          decideur(),
          quand,
          pair,
        ),
        LecteurEchange.pair => AppStrings.echangeDetailValidePourB(
          decideur(),
          quand,
        ),
        _ => AppStrings.echangeDetailValideAdmin(decideur(), quand),
      };
    case StatutEchange.refuse:
      if (echange.refuseParPair) {
        return lecteur == LecteurEchange.pair
            ? AppStrings.echangeDetailTuAsRefuse
            : AppStrings.echangeDetailRefusePair(pair);
      }
      final motif = echange.motif;
      return motif == null || motif.isEmpty
          ? AppStrings.echangeDetailRefuseChef(decideur())
          : AppStrings.echangeDetailRefuseChefMotif(decideur(), motif);
    case StatutEchange.annule:
      return switch (lecteur) {
        LecteurEchange.demandeur => AppStrings.echangeDetailAnnuleParA,
        LecteurEchange.pair => AppStrings.echangeDetailAnnulePourB(demandeur),
        _ => AppStrings.echangeDetailAnnuleAdmin(demandeur),
      };
    case StatutEchange.expire:
      return switch (lecteur) {
        LecteurEchange.demandeur => AppStrings.echangeDetailExpirePourA,
        LecteurEchange.admin => AppStrings.echangeDetailExpireAdmin,
        _ => AppStrings.echangeDetailExpire,
      };
    case StatutEchange.echoue:
      return switch (lecteur) {
        LecteurEchange.demandeur => AppStrings.echangeDetailEchecPourA(cause),
        LecteurEchange.admin => AppStrings.echangeDetailEchecAdmin(cause),
        _ => AppStrings.echangeDetailEchec(cause),
      };
  }
}

/// Le fil d'une demande : trois lignes au plus, horodatées.
List<String> filEchange(Echange echange, {required String moi}) {
  String instant(DateTime t) =>
      AppStrings.echangeInstant(formaterDateCourte(t), heureMinute(t));
  final fil = <String>[AppStrings.echangeFilDemandee(instant(echange.creeLe))];
  final accepte = echange.accepteLe;
  if (accepte != null) {
    fil.add(
      AppStrings.echangeFilAcceptee(_nom(echange.pairNom), instant(accepte)),
    );
  }
  final fin = echange.decideLe ?? echange.closLe;
  if (fin == null) return fil;
  final decideur = echange.decideurId == moi
      ? AppStrings.echangeToi
      : _nom(echange.decideurNom);
  switch (echange.statut) {
    case StatutEchange.valide:
      fil.add(
        echange.autoValide
            ? AppStrings.echangeFilValideeAuto(instant(fin))
            : AppStrings.echangeFilValidee(decideur, instant(fin)),
      );
    case StatutEchange.refuse:
      fil.add(AppStrings.echangeFilRefusee(decideur, instant(fin)));
    case StatutEchange.annule:
      fil.add(AppStrings.echangeFilAnnulee(instant(fin)));
    case StatutEchange.expire:
      fil.add(AppStrings.echangeFilExpiree(instant(fin)));
    case StatutEchange.echoue:
      fil.add(AppStrings.echangeFilEchec(instant(fin)));
    case StatutEchange.ouvert:
    case StatutEchange.accepteParPair:
      break;
  }
  return fil;
}

String _nom(String? nom) =>
    (nom ?? '').trim().isEmpty ? AppStrings.echangeMembreInconnu : nom!.trim();
