/// Textes de l'application, centralisés et en français.
///
/// Aucune chaîne visible ne doit être écrite en dur dans un widget. Si le
/// projet passe à des fichiers ARB, cette classe sera remplacée par les
/// accesseurs générés sans changer les appelants.
///
/// Règles de ton (`PRODUCT.md`) : tutoiement du membre, phrases courtes,
/// vocabulaire des pompiers sans jargon logiciel. Un contrôle nomme son
/// action, une erreur nomme le problème **et** la sortie.
abstract final class AppStrings {
  static const String appTitle = 'Astreinte SP';

  // -------------------------------------------------------------------
  // Écran Hello (ticket 001)
  // -------------------------------------------------------------------

  static const String helloTitle = 'Bonjour';
  static const String helloSubtitle =
      'Le socle Flutter est en place. Cet écran lit la configuration '
      'fournie à la compilation.';
  static const String appEnvLabel = 'Environnement';
  static const String supabaseUrlLabel = 'URL Supabase';
  static const String valueUndefined = 'Non définie';

  // -------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------

  static const String navMonMois = 'Mon mois';
  static const String navPropositions = 'Propositions';
  static const String navPlanning = 'Planning';
  static const String navProfil = 'Profil';
  static const String navAdmin = 'Admin';
  static const String navOuvrirMenu = 'Ouvrir le menu';

  /// Double la pastille chiffrée d'un libellé annoncé. Plafonné à « 9+ »
  /// visuellement, mais le nombre réel est annoncé aux lecteurs d'écran.
  static String navPropositionsBadge(int n) =>
      n <= 1 ? '$n proposition en attente' : '$n propositions en attente';

  // -------------------------------------------------------------------
  // États de disponibilité
  // -------------------------------------------------------------------

  static const String etatDisponible = 'Disponible';
  static const String etatAbsent = 'Absent';
  static const String etatNonSaisi = 'Non saisi';
  static const String creneauJour = 'Jour';
  static const String creneauNuit = 'Nuit';

  /// Phrase complète annoncée par un `SlotChip` : jamais un code.
  /// Exemple : « Samedi 4 octobre, nuit, disponible ».
  ///
  /// [jourEtDate] arrive déjà composé (« Samedi 4 octobre ») : le formatage
  /// des dates appartient à la grille mensuelle (ticket 011), pas au socle.
  static String slotSemantique({
    required String jourEtDate,
    required String creneau,
    required String etat,
  }) => '$jourEtDate, ${creneau.toLowerCase()}, ${etat.toLowerCase()}';

  static const String slotActionMarquerDisponible =
      'Appuie pour te marquer disponible';
  static const String slotActionMarquerAbsent = 'Appuie pour te marquer absent';
  static const String slotActionEffacer = 'Appuie pour effacer';
  static const String slotVerrouille = 'Créneau verrouillé';

  // -------------------------------------------------------------------
  // États d'attribution
  // -------------------------------------------------------------------

  static const String attributionPropose = 'En attente';
  static const String attributionProposeMembre = 'En attente de ta réponse';
  static const String attributionAccepte = 'Accepté';
  static const String attributionRefuse = 'Refusé';
  static const String attributionAnnule = 'Annulé';

  // -------------------------------------------------------------------
  // États de planning et de période
  // -------------------------------------------------------------------

  static const String planningBrouillon = 'Brouillon';
  static const String planningPublie = 'Publié';
  static const String planningValide = 'Validé';
  static const String planningArchive = 'Archivé';

  static const String periodeOuverte = 'Saisie ouverte';
  static const String periodeVerrouillee = 'Mois verrouillé';

  static String periodeOuverteJusquAu(String date) =>
      'Saisie ouverte jusqu\'au $date';

  static String periodeVerrouilleeDetail(String date) =>
      'Mois verrouillé depuis le $date. Contacte ton chef de centre pour une '
      'modification.';

  static String periodeBientotFermee(int n, String mois) =>
      n <= 1
          ? 'Plus qu\'un jour pour saisir $mois'
          : 'Plus que $n jours pour saisir $mois';

  // -------------------------------------------------------------------
  // Jours et repères de calendrier
  // -------------------------------------------------------------------

  static const String jourAujourdhui = 'Aujourd\'hui';
  static const String jourWeekend = 'Weekend';
  static const String jourFerie = 'Jour férié';
  static const String jourHorsMois = 'Hors du mois';

  static String jourFerieNomme(String nom) => 'Jour férié : $nom';

  // -------------------------------------------------------------------
  // Actions génériques
  // -------------------------------------------------------------------

  static const String actionEnregistrer = 'Enregistrer';
  static const String actionAnnuler = 'Annuler';
  static const String actionReessayer = 'Réessayer';
  static const String actionFermer = 'Fermer';
  static const String actionContinuer = 'Continuer';
  static const String actionRetour = 'Retour';
  static const String actionChargement = 'Chargement…';

  // -------------------------------------------------------------------
  // Sauvegarde et réseau
  // -------------------------------------------------------------------

  static const String saveAuRepos = 'À jour';
  static const String saveEnCours = 'Enregistrement…';
  static const String saveTermine = 'Enregistré';
  static const String saveEchec = 'Non enregistré';
  static const String saveEchecDetail =
      'Impossible d\'enregistrer. Vérifie ta connexion.';

  static const String horsLigne = 'Hors ligne';
  static const String horsLigneDetail =
      'Hors ligne. Tes modifications partiront au retour du réseau.';
  static const String lectureSeule = 'Lecture seule';
  static const String lectureSeuleDetail =
      'Caserne suspendue : tu peux consulter, pas modifier.';

  // -------------------------------------------------------------------
  // États vides et erreurs
  // -------------------------------------------------------------------

  static const String videTitreGenerique = 'Rien à afficher';
  static const String videTexteGenerique = 'Il n\'y a encore rien ici.';
  static const String videPropositionsTitre = 'Aucune proposition';
  static const String videPropositionsTexte =
      'Quand ton chef de centre publiera le planning, tes astreintes '
      'proposées s\'afficheront ici.';

  static const String erreurTitre = 'Ça n\'a pas marché';
  static const String erreurTexteGenerique =
      'Une erreur est survenue. Réessaie dans un instant.';
  static const String erreurReseauTitre = 'Pas de connexion';
  static const String erreurReseauTexte =
      'Impossible de joindre le serveur. Vérifie ta connexion, puis réessaie.';

  static const String chargementSemantique = 'Contenu en cours de chargement';

  // -------------------------------------------------------------------
  // Compteurs
  // -------------------------------------------------------------------

  static const String compteurJours = 'Jours';
  static const String compteurNuits = 'Nuits';
  static const String compteurWeekends = 'Weekends';
  static const String compteurIllimite = 'illimité';

  static String compteurSurPlafond(int valeur, int plafond) =>
      '$valeur sur $plafond';

  static String compteurSansPlafond(int valeur) =>
      '$valeur, $compteurIllimite';

  // -------------------------------------------------------------------
  // Écran de démonstration (build de développement)
  // -------------------------------------------------------------------

  static const String devComposantsTitre = 'Composants';
  static const String devComposantsSousTitre =
      'Catalogue du système de design. Build de développement uniquement.';
  static const String devTheme = 'Thème';
  static const String devThemeClair = 'Clair';
  static const String devThemeSombre = 'Sombre';
  static const String devEchelleTexte = 'Taille du texte';
}
