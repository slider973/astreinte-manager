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

  /// Valeur attendue mais absente. Jamais un champ vide : le vide ne se lit
  /// pas.
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

  static String periodeBientotFermee(int n, String mois) => n <= 1
      ? 'Plus qu\'un jour pour saisir $mois'
      : 'Plus que $n jours pour saisir $mois';

  // -------------------------------------------------------------------
  // Jours et repères de calendrier
  // -------------------------------------------------------------------

  /// Les douze mois, en minuscules : ils s'écrivent dans une phrase
  /// (« Expire le 4 octobre 2026 »), jamais seuls.
  static const List<String> moisLongs = <String>[
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  /// « 4 octobre 2026 ». Le premier du mois se dit « 1er ».
  static String dateLongue({
    required int jour,
    required int mois,
    required int annee,
  }) => '${jour == 1 ? '1er' : jour} ${moisLongs[mois - 1]} $annee';

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

  static String compteurSansPlafond(int valeur) => '$valeur, $compteurIllimite';

  // -------------------------------------------------------------------
  // Connexion (ticket 005)
  // -------------------------------------------------------------------

  static const String connexionTitre = 'Connexion';
  static const String connexionIntro =
      'Entre ton adresse e-mail. On t\'envoie un code à six chiffres pour te '
      'connecter, sans mot de passe.';
  static const String connexionEmailLabel = 'Adresse e-mail';
  static const String connexionEmailExemple = 'prenom.nom@exemple.fr';
  static const String connexionEnvoyer = 'Recevoir mon code';

  static const String codeTitre = 'Ton code';
  static const String codeLabel = 'Code à six chiffres';
  static const String codeValider = 'Me connecter';
  static const String codeRenvoyer = 'Renvoyer un code';
  static const String codeChangerEmail = 'Changer d\'adresse';
  static const String codeLienAlternative =
      'L\'e-mail contient aussi un lien : ouvre-le sur cet appareil au lieu de '
      'recopier le code.';
  static const String codeRenvoye = 'Nouveau code envoyé. Regarde tes e-mails.';

  static String codeIntro(String email) =>
      'Un code à six chiffres part vers $email. Il est valable une heure.';

  /// Raison affichée sous le bouton « Renvoyer un code » tant que le délai
  /// n'est pas écoulé. Un bouton désactivé dit toujours pourquoi.
  static String codeRenvoiDans(int secondes) =>
      'Nouveau code possible dans $secondes\u00a0s';

  // --- Erreurs d'authentification ------------------------------------

  static const String authEmailInvalide =
      'Adresse e-mail incomplète. Écris-la en entier, par exemple '
      'prenom.nom@exemple.fr.';
  static const String authCompteInconnu =
      'Aucun compte pour cette adresse. Demande une invitation à ton chef de '
      'centre.';

  /// Couvre le code faux **et** le code périmé : le serveur ne les distingue
  /// pas (voir `AuthErreur.codeInvalide`). La phrase nomme donc les deux
  /// causes et les deux sorties.
  static const String authCodeInvalide =
      'Code incorrect ou expiré. Vérifie les 6 chiffres ou demande un nouveau '
      'code.';
  static const String authCodeExpire =
      'Ce code a expiré. Demande un nouveau code.';
  static const String authEnvoiIndisponible =
      'L\'envoi des codes est en panne. Ce n\'est pas ton compte : réessaie '
      'dans quelques minutes.';
  static const String authDeconnexionImpossible =
      'La déconnexion n\'a pas abouti. Vérifie ta connexion, puis réessaie.';
  static const String authTropDeTentatives =
      'Trop d\'essais. Attends quelques minutes, puis redemande un code.';

  // --- Compte sans caserne -------------------------------------------

  static const String aucuneCaserneTitre = 'Aucune caserne';
  static const String aucuneCaserneTexte =
      'Ton compte existe, mais il n\'est rattaché à aucune caserne. Demande '
      'une invitation à ton chef de centre : il t\'ajoutera avec cette adresse '
      'e-mail.';
  static const String caserneDesactiveeTitre = 'Accès désactivé';

  static String caserneDesactiveeTexte(String caserne) =>
      'Ton accès à $caserne a été désactivé. Contacte ton chef de centre pour '
      'le rouvrir.';

  // --- Accueil --------------------------------------------------------

  static const String accueilTitre = 'Accueil';
  static const String accueilCaserneLabel = 'Ta caserne';
  static const String accueilRoleLabel = 'Ton rôle';
  static const String accueilAVenirTitre = 'Écran à venir';
  static const String accueilAVenirTexte =
      'Cet écran arrive dans une prochaine version. Pour l\'instant, l\'accueil '
      'te montre ta caserne et ton rôle.';
  static const String accueilRetour = 'Revenir à l\'accueil';
  static const String accueilTexte =
      'Ta connexion fonctionne. La saisie des disponibilités et le planning '
      'arrivent dans les prochaines versions.';
  static const String roleMembre = 'Membre';
  static const String roleAdmin = 'Admin de caserne';
  static const String seDeconnecter = 'Se déconnecter';
  static const String deconnexionEnCours = 'Déconnexion…';

  // --- Démarrage et configuration ------------------------------------

  static const String demarrageSemantique = 'Connexion à ton compte en cours';
  static const String configurationTitre = 'Application non configurée';
  static const String configurationTexte =
      'L\'application n\'a pas reçu l\'adresse de son serveur. Elle ne peut pas '
      'te connecter. Signale-le à la personne qui l\'a installée.';

  // -------------------------------------------------------------------
  // Membres et invitations, côté admin (ticket 006)
  // -------------------------------------------------------------------

  static const String membresTitre = 'Membres';
  static const String membresSousTitre =
      'Qui fait partie de la caserne, et qui a été invité sans avoir encore '
      'rejoint.';
  static const String membresSectionActifs = 'Membres de la caserne';
  static const String membresSectionInvitations = 'Invitations en attente';
  static const String membresInviter = 'Inviter des pompiers';
  static const String membresRafraichir = 'Relire la liste';
  static const String membresVideTitre = 'Aucun membre';
  static const String membresVideTexte =
      'Personne n\'est encore rattaché à cette caserne. Invite les pompiers '
      'du centre avec leur adresse e-mail.';
  static const String membresInvitationsVide =
      'Aucune invitation en attente. Les invitations acceptées rejoignent la '
      'liste des membres.';
  static const String membresErreurTexte =
      'Impossible de lire la liste des membres. Vérifie ta connexion, puis '
      'réessaie.';
  static const String membresReserveAdmin =
      'Cet écran est réservé aux administrateurs de la caserne.';

  static String membresCompte(int n) =>
      n <= 1 ? '$n membre actif' : '$n membres actifs';

  static String invitationsCompte(int n) =>
      n <= 1 ? '$n invitation en attente' : '$n invitations en attente';

  static const String invitationEnAttente = 'En attente';
  static const String invitationExpiree = 'Expirée';
  static const String invitationRenvoyer = 'Renvoyer';
  static const String invitationAnnuler = 'Annuler l\'invitation';
  static const String invitationRenvoyee = 'Invitation renvoyée.';
  static const String invitationAnnulee = 'Invitation annulée.';
  static const String invitationRenvoiEchec =
      'Le renvoi n\'a pas abouti. Réessaie dans un instant.';
  static const String invitationAnnulationEchec =
      'L\'annulation n\'a pas abouti. Réessaie dans un instant.';

  static String invitationExpireLe(String date) => 'Expire le $date';

  static String invitationExpireeDepuis(String date) => 'Expirée le $date';

  static String invitationAnnulerSemantique(String email) =>
      'Annuler l\'invitation de $email';

  static String invitationRenvoyerSemantique(String email) =>
      'Renvoyer l\'invitation à $email';

  // --- Formulaire d'invitation ---------------------------------------

  static const String inviterTitre = 'Inviter des pompiers';
  static const String inviterIntro =
      'Une adresse par ligne, ou séparées par des virgules. Chacune reçoit un '
      'lien personnel pour rejoindre la caserne.';
  static const String inviterEmailsLabel = 'Adresses e-mail';
  static const String inviterEmailsExemple =
      'prenom.nom@exemple.fr\nautre.pompier@exemple.fr';
  static const String inviterRoleLabel = 'Rôle dans la caserne';
  static const String inviterEnvoyer = 'Envoyer les invitations';
  static const String inviterEnvoyerUne = 'Envoyer l\'invitation';
  static const String inviterAucuneAdresse =
      'Écris au moins une adresse e-mail.';
  static const String inviterResultatsTitre = 'Résultat par adresse';
  static const String inviterTerminer = 'Revenir aux membres';
  static const String inviterReessayerEchecs =
      'Réessayer les adresses en échec';

  /// Rappel neutre, sous le formulaire : il dit la règle **avant** qu'on la
  /// franchisse. Le refus, lui, est [inviterPlafond].
  static const String inviterPlafondRappel =
      'Vingt adresses au maximum par envoi.';

  static String inviterPlafond(int max) =>
      'Vingt adresses au maximum par envoi. Tu en as $max : retire les '
      'adresses en trop, ou envoie en deux fois.';

  static String inviterAdresseInvalide(String email) =>
      'Adresse incomplète : $email.';

  /// Résumé annoncé après un envoi : toujours les deux nombres, même à zéro.
  static String inviterResume({required int envoyees, required int echecs}) {
    final partieEnvoyees = envoyees <= 1
        ? '$envoyees invitation envoyée'
        : '$envoyees invitations envoyées';
    final partieEchecs = echecs <= 1 ? '$echecs échec' : '$echecs échecs';
    return '$partieEnvoyees, $partieEchecs.';
  }

  static const String resultatInvitee = 'Invitée';
  static const String resultatRenvoyee = 'Renvoyée';
  static const String resultatEchec = 'Échec';

  static const String resultatCourrielNonParti =
      'Invitation créée, mais le courriel n\'est pas parti. Renvoie-la, ou '
      'transmets le lien toi-même.';

  // --- Motifs d'échec, adresse par adresse ---------------------------

  static const String inviteDejaMembre =
      'Déjà membre actif de la caserne : rien à envoyer.';
  static const String inviteAdresseInvalide =
      'Adresse e-mail incomplète. Corrige-la, puis renvoie.';
  static const String inviteConflit =
      'Une invitation vient d\'être créée pour cette adresse. Relis la liste.';
  static const String inviteCompteImpossible =
      'Le compte n\'a pas pu être créé pour cette adresse. Réessaie dans un '
      'instant.';
  static const String inviteErreurServeur =
      'Incident serveur sur cette adresse. Réessaie dans un instant.';

  // --- Erreurs de la requête d'invitation ----------------------------

  static const String inviteRequeteInvalide =
      'La demande a été refusée : vérifie les adresses et le rôle.';
  static const String inviteNonAdmin =
      'Seul un administrateur de la caserne peut inviter. Demande le rôle '
      'admin à ton chef de centre.';
  static const String inviteCaserneSuspendue =
      'Abonnement suspendu : la caserne est en lecture seule, les invitations '
      'sont bloquées.';
  static const String inviteCaserneInconnue =
      'Cette caserne est introuvable. Reconnecte-toi, puis réessaie.';

  // -------------------------------------------------------------------
  // Parcours de l'invité (ticket 006)
  // -------------------------------------------------------------------

  static const String invitationTitre = 'Ton invitation';
  static const String invitationRejoindre = 'Rejoindre la caserne';
  static const String invitationSeConnecter = 'Me connecter pour accepter';
  static const String invitationVerification = 'Vérification du lien…';
  static const String invitationConnexionIntro =
      'Entre l\'adresse e-mail qui a reçu cette invitation. On t\'envoie un '
      'code à six chiffres, sans mot de passe.';
  static const String invitationChangerCompte = 'Utiliser une autre adresse';
  static const String invitationAccepteeTitre = 'Bienvenue';

  static String invitationIntro(String caserne) =>
      'Tu es invité à rejoindre $caserne sur Astreinte SP.';

  static String invitationParQui(String nom) => 'Invitation envoyée par $nom.';

  static String invitationConnecteComme(String email) =>
      'Tu es connecté avec $email.';

  static String invitationRejointe(String caserne) =>
      'Tu fais maintenant partie de $caserne.';

  // --- Erreurs du lien d'invitation ----------------------------------

  static const String invitationIntrouvableTitre = 'Lien inconnu';
  static const String invitationIntrouvableTexte =
      'Ce lien d\'invitation n\'existe pas ou n\'est plus valable. Demande à '
      'ton chef de centre de t\'en envoyer un nouveau.';
  static const String invitationExpireeTitre = 'Invitation expirée';
  static const String invitationExpireeTexte =
      'Cette invitation a expiré. Demande à ton chef de centre de te la '
      'renvoyer : le nouveau lien arrivera sur la même adresse.';
  static const String invitationDejaAccepteeTitre = 'Invitation déjà utilisée';
  static const String invitationDejaAccepteeTexte =
      'Ce lien a déjà servi. Si tu es le destinataire, connecte-toi '
      'simplement : ta caserne t\'attend.';
  static const String invitationMauvaisCompteTitre = 'Autre adresse';
  static const String invitationCaserneSuspendueTitre = 'Caserne suspendue';
  static const String invitationCaserneSuspendueTexte =
      'L\'abonnement de la caserne est suspendu : impossible de la rejoindre '
      'pour l\'instant. Contacte ton chef de centre.';
  static const String invitationProfilManquantTexte =
      'Ton profil est introuvable. Déconnecte-toi, reconnecte-toi, puis '
      'rouvre le lien.';
  static const String invitationJetonManquant =
      'Ce lien est incomplet. Rouvre-le depuis ton e-mail, en entier.';
  static const String invitationEchecTexte =
      'Impossible de valider ton invitation. Vérifie ta connexion, puis '
      'réessaie.';

  static String invitationMauvaisCompteTexte({
    required String adresseInvitee,
    required String adresseCourante,
  }) =>
      'Cette invitation a été envoyée à $adresseInvitee, et tu es connecté '
      'avec $adresseCourante. Déconnecte-toi, puis rouvre le lien avec la '
      'bonne adresse.';

  static String invitationContacterAdmin(String caserne) =>
      'Écris à l\'administrateur de $caserne pour en recevoir une nouvelle.';

  // -------------------------------------------------------------------
  // Complément de profil et guide d'accueil (ticket 006)
  // -------------------------------------------------------------------

  static const String profilTitre = 'Ton profil';
  static const String profilIntro =
      'Ton nom apparaît dans le planning de la caserne. Le téléphone reste '
      'visible par les seuls administrateurs.';
  static const String profilPrenomLabel = 'Prénom';
  static const String profilNomLabel = 'Nom';
  static const String profilTelephoneLabel = 'Téléphone (facultatif)';
  static const String profilTelephoneExemple = '06 12 34 56 78';
  static const String profilEnregistrer = 'Enregistrer et continuer';
  static const String profilPrenomManquant = 'Écris ton prénom.';
  static const String profilNomManquant = 'Écris ton nom.';
  static const String profilEchec =
      'Ton profil n\'a pas pu être enregistré. Vérifie ta connexion, puis '
      'réessaie.';

  static const String guideTitre = 'Prise en main';
  static const String guidePasser = 'Passer le guide';
  static const String guideSuivant = 'Suivant';
  static const String guideTerminer = 'C\'est parti';

  static String guideEtape(int etape, int total) => 'Étape $etape sur $total';

  static const String guideDisposTitre = 'Dis quand tu es disponible';
  static const String guideDisposTexte =
      'Chaque mois, tu coches tes jours et tes nuits. Une case touchée, c\'est '
      'saisi : rien à enregistrer.';
  static const String guidePropositionsTitre = 'Réponds aux propositions';
  static const String guidePropositionsTexte =
      'Quand le chef de centre publie le planning, tes astreintes proposées '
      'arrivent ici. Tu acceptes ou tu refuses.';
  static const String guidePlanningTitre = 'Regarde le planning du centre';
  static const String guidePlanningTexte =
      'Une fois validé, le planning montre qui est d\'astreinte, jour par '
      'jour. Tu sais toujours sur qui compter.';

  // -------------------------------------------------------------------
  // Ajouter à l'écran d'accueil (ticket 006)
  // -------------------------------------------------------------------

  static const String installTitre = 'Ajoute Astreinte SP à ton écran';
  static const String installIntroIos =
      'Installée, l\'application s\'ouvre en un geste et peut t\'alerter. '
      'Sans installation, iPhone n\'envoie aucune notification : tu '
      'manquerais les propositions d\'astreinte.';
  static const String installIntroAndroid =
      'Installée, l\'application s\'ouvre en un geste, en plein écran, et '
      'peut t\'alerter d\'une proposition d\'astreinte.';
  static const String installAvertissementIos =
      'Sur iPhone, les notifications n\'existent que pour une application '
      'installée.';
  static const String installEtapesTitre = 'Trois gestes';
  static const String installIosEtape1 =
      'Touche le bouton Partager, en bas de Safari.';
  static const String installIosEtape2 =
      'Fais défiler, puis touche « Sur l\'écran d\'accueil ».';
  static const String installIosEtape3 =
      'Touche « Ajouter », en haut à droite. L\'icône rejoint ton écran.';
  static const String installAndroidEtape1 =
      'Touche le menu à trois points, en haut de Chrome.';
  static const String installAndroidEtape2 =
      'Touche « Ajouter à l\'écran d\'accueil » ou « Installer '
      'l\'application ».';
  static const String installAndroidEtape3 =
      'Confirme avec « Installer ». L\'icône rejoint ton écran.';
  static const String installPlusTard = 'Plus tard';
  static const String installTermine = 'C\'est fait';

  // -------------------------------------------------------------------
  // Écran de démonstration (build de développement)
  // -------------------------------------------------------------------

  static const String devComposantsTitre = 'Composants';
  static const String devComposantsSousTitre =
      'Catalogue du système de design. Build de développement uniquement.';
  static const String devTheme = 'Thème';
  static const String devThemeClair = 'Clair';
  static const String devThemeSombre = 'Sombre';
  static const String devThemeLesDeux = 'Les deux';
  static const String devEchelleTexte = 'Taille du texte';

  /// Libellé d'un cran d'échelle de texte : « ×1 », « ×1.3 », « ×2 ».
  static String devEchelleValeur(double facteur) =>
      '×${facteur == facteur.roundToDouble() ? facteur.toStringAsFixed(0) : facteur}';

  /// Le même cran, annoncé en entier : « Taille du texte ×1.3 ».
  static String devEchelleSemantique(double facteur) =>
      '$devEchelleTexte ${devEchelleValeur(facteur)}';
}
