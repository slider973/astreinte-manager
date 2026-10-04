import '../../../core/theme/app_status.dart';
import '../../astreintes/domain/astreinte.dart';
import 'echange.dart';

/// L'étape du parcours de demande, **dans l'adresse** (`design/073 § 6.2`) :
/// le retour du navigateur et le geste retour reculent d'une étape, jamais de
/// tout le parcours.
enum EtapeDemande {
  qui('qui'),
  quoi('quoi'),
  verifier('verifier');

  const EtapeDemande(this.valeurUrl);

  final String valeurUrl;

  static EtapeDemande depuisUrl(String? valeur) {
    for (final etape in values) {
      if (etape.valeurUrl == valeur) return etape;
    }
    return qui;
  }
}

/// La valeur de `?cible=` pour une demande « à la caserne ».
const String cibleCaserne = 'caserne';

/// La valeur de `?forme=` pour un échange (sinon : cession).
const String formeEchanger = 'echanger';

/// Pourquoi une astreinte ne peut pas être proposée, quand le bouton doit
/// rester visible mais grisé (`design/073 § 5.2`).
enum BlocageProposition { tropTard, horsLigne, lectureSeule }

/// Vrai quand l'astreinte est **proposable** : acceptée (elle l'est, puisque
/// « Mes astreintes » ne rend que celles-là), d'un planning publié ou validé,
/// sur un créneau futur. Sur les autres, le bouton est **absent** : une
/// astreinte passée n'a rien à proposer.
bool proposable(Astreinte astreinte, DateTime aujourdhui) =>
    (astreinte.planningEtat == PlanningEtat.publie ||
        astreinte.planningEtat == PlanningEtat.valide) &&
    !astreinte.passee(aujourdhui);

/// La garde d'une astreinte, pour une demande.
GardeEchange gardeDe(Astreinte astreinte) => GardeEchange(
  jour: astreinte.jour,
  creneau: astreinte.creneau,
  attributionId: astreinte.id,
  creneauId: astreinte.creneauId,
);

/// La raison qui grise « Proposer un échange », ou `null`. L'ordre est celui
/// du système : la caserne d'abord, puis le réseau, puis l'échéance.
BlocageProposition? blocageProposition({
  required Astreinte astreinte,
  required ReglagesEchange reglages,
  required DateTime maintenant,
  required bool enLigne,
  required bool lectureSeule,
}) {
  if (lectureSeule) return BlocageProposition.lectureSeule;
  if (!enLigne) return BlocageProposition.horsLigne;
  if (!maintenant.isBefore(reglages.echeance(<GardeEchange>[gardeDe(astreinte)]))) {
    return BlocageProposition.tropTard;
  }
  return null;
}
