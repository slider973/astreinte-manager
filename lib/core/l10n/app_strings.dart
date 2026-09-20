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

  /// Les douze mois abrégés, pour une ligne d'état qui n'a pas la place d'un
  /// mois entier (« Ouvert jusqu'au 15 sept. »). Mai, juin et juillet ne
  /// s'abrègent pas : ils sont déjà courts.
  static const List<String> moisCourts = <String>[
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  /// « 4 octobre 2026 ». Le premier du mois se dit « 1er ».
  static String dateLongue({
    required int jour,
    required int mois,
    required int annee,
  }) => '${jour == 1 ? '1er' : jour} ${moisLongs[mois - 1]} $annee';

  /// « 15 sept. ». Sans l'année : elle est déjà dans le sélecteur de mois.
  static String dateCourte({required int jour, required int mois}) =>
      '${jour == 1 ? '1er' : jour} ${moisCourts[mois - 1]}';

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

  /// Le même message quand le nom de la caserne n'est pas lisible.
  ///
  /// Ce n'est pas un cas d'école : la politique de `stations` n'ouvre la
  /// lecture qu'aux membres **actifs** (`is_member`), donc un compte
  /// fraîchement désactivé n'a plus le nom de sa caserne. Mieux vaut une
  /// phrase sans nom qu'une phrase avec un trou.
  static const String caserneDesactiveeTexteSansNom =
      'Ton accès à cette caserne a été désactivé. Contacte ton chef de centre '
      'pour le rouvrir.';

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
  // Administration d'un membre (ticket 009)
  // -------------------------------------------------------------------

  // --- Liste et recherche ---------------------------------------------

  static const String membresRecherche = 'Rechercher un membre';
  static const String membresRechercheInvite = 'Nom ou adresse e-mail';
  static const String membresRechercheEffacer = 'Effacer la recherche';
  static const String membresRechercheVideTexte =
      'Vérifie l\'orthographe, ou efface la recherche pour revoir toute la '
      'caserne.';

  static String membresRechercheVideTitre(String requete) =>
      'Aucun membre ne correspond à « $requete ».';

  /// « 2 membres sur 9 » : le compte de la section pendant une recherche.
  static String membresCompteFiltre(int trouves, int total) =>
      '$trouves membre${trouves > 1 ? 's' : ''} sur $total';

  /// « 9 membres actifs · 1 désactivé ». Le second nombre n'apparaît que
  /// lorsqu'il y a quelque chose à dire : un badge sur chaque ligne serait du
  /// bruit sur quatre-vingt-dix-neuf lignes.
  static String membresCompteAvecDesactives(int actifs, int desactives) =>
      desactives == 0
      ? membresCompte(actifs)
      : '${membresCompte(actifs)} · $desactives '
            '${desactives > 1 ? 'désactivés' : 'désactivé'}';

  static const String membreStatutDesactive = 'Désactivé';
  static const String membreStatutActif = 'Actif';
  static const String membreAucuneSaisie = 'Aucune saisie de disponibilités';

  static String membreDerniereSaisie(String date) => 'Dispos saisies le $date';

  static String membreActions(String nom) => 'Actions pour $nom';

  // --- Feuille d'actions ----------------------------------------------

  static const String membreRole = 'Rôle';
  static const String membreStatut = 'Statut';
  static const String membreDispos = 'Dernière saisie';
  static const String membreActionRenommer = 'Modifier le nom affiché';
  static const String membreActionPromouvoir = 'Nommer administrateur';
  static const String membreActionRetrograder =
      'Retirer le rôle d\'administrateur';
  static const String membreActionDesactiver = 'Désactiver l\'accès';
  static const String membreActionReactiver = 'Réactiver l\'accès';

  // --- Garde-fous ------------------------------------------------------

  static const String membreRefusDernierAdmin =
      'C\'est le dernier administrateur actif de la caserne. Nomme un autre '
      'administrateur avant de retirer celui-ci.';
  static const String membreRefusSoiMeme =
      'Tu ne peux pas modifier ton propre rôle ni désactiver ton accès. '
      'Demande-le à un autre administrateur de la caserne.';

  // --- Renommer --------------------------------------------------------

  static const String membreRenommerTitre = 'Nom affiché';
  static const String membreRenommerAide =
      'Ce nom remplace le prénom et le nom dans les plannings de la caserne. '
      'Laisse le champ vide pour revenir au nom du profil.';
  static const String membreRenommerEnregistrer = 'Enregistrer le nom';

  // --- Confirmation de désactivation ------------------------------------

  /// L'espace avant le « ? » est **insécable** (`\u00A0`) : la typographie
  /// française l'exige, et sans lui le point d'interrogation part seul à la
  /// ligne suivante quand le nom est long. Vu en vrai sur « Lucas Bernard ».
  static String membreDesactiverTitre(String nom) =>
      'Désactiver l\'accès de $nom\u00A0?';
  static const String membreDesactiverTexte =
      'La personne ne verra plus la caserne à sa prochaine connexion. Son '
      'historique d\'astreintes est conservé, et tu peux la réactiver quand '
      'tu veux.';

  // --- Verdicts ---------------------------------------------------------

  static String membreVerdictPromu(String nom) =>
      '$nom administre maintenant la caserne.';

  static String membreVerdictRetrograde(String nom) =>
      '$nom n\'administre plus la caserne.';

  static String membreVerdictDesactive(String nom) =>
      'L\'accès de $nom est désactivé.';

  static String membreVerdictReactive(String nom) =>
      'L\'accès de $nom est réactivé.';

  static const String membreVerdictRenomme = 'Nom affiché enregistré.';

  static const String membreEchecRefus =
      'Modification refusée par la caserne. Tu n\'es peut-être plus '
      'administrateur, ou l\'abonnement est suspendu. Relis la liste.';
  static const String membreEchecGenerique =
      'La modification n\'a pas abouti. Vérifie ta connexion, puis réessaie.';

  // -------------------------------------------------------------------
  // Parcours de l'invité (ticket 006)
  // -------------------------------------------------------------------

  static const String invitationTitre = 'Ton invitation';
  static const String invitationSeConnecter = 'Me connecter pour accepter';
  static const String invitationVerification = 'Vérification du lien…';
  static const String invitationConnexionIntro =
      'Entre l\'adresse e-mail qui a reçu cette invitation. On t\'envoie un '
      'code à six chiffres, sans mot de passe.';
  static const String invitationChangerCompte = 'Utiliser une autre adresse';
  static const String invitationAccepteeTitre = 'Bienvenue';

  static String invitationParQui(String nom) => 'Invitation envoyée par $nom.';

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
  // Paramètres de la caserne (ticket 010)
  // -------------------------------------------------------------------

  static const String parametresTitre = 'Paramètres';
  static const String parametresSousTitre =
      'Les réglages de ta caserne. Ils s\'appliquent aux plannings créés '
      'ensuite.';
  static const String parametresReserveAdmin =
      'Les réglages de la caserne appartiennent à ses administrateurs.';
  static const String parametresErreurTexte =
      'Les paramètres de la caserne n\'ont pas pu être lus.';
  static const String parametresRafraichir = 'Relire les paramètres';
  static const String parametresVersMembres = 'Membres de la caserne';
  static const String parametresDepuisMembres = 'Paramètres de la caserne';

  /// Le troisième écran de la destination Admin, atteint par la barre
  /// d'application depuis les deux autres.
  static const String periodesDepuisAdmin = 'Mois de saisie';

  /// Les neuf fuseaux d'une caserne française, métropole et outre-mer. Un
  /// champ libre n'a rien à faire ici : un fuseau inventé casse le calcul des
  /// dates limites, et la base le refuse (`stations_check_timezone`).
  static const Map<String, String> fuseauxCaserne = <String, String>{
    'Europe/Paris': 'France métropolitaine',
    'America/Guadeloupe': 'Guadeloupe',
    'America/Martinique': 'Martinique',
    'America/Cayenne': 'Guyane',
    'Indian/Reunion': 'La Réunion',
    'Indian/Mayotte': 'Mayotte',
    'America/Miquelon': 'Saint-Pierre-et-Miquelon',
    'Pacific/Noumea': 'Nouvelle-Calédonie',
    'Pacific/Tahiti': 'Polynésie française',
  };

  /// « France métropolitaine (Europe/Paris) » : le nom du lieu d'abord, son
  /// identifiant ensuite — c'est lui qui voyage dans la base.
  static String fuseauLibelle(String identifiant) {
    final lieu = fuseauxCaserne[identifiant];
    return lieu == null ? identifiant : '$lieu ($identifiant)';
  }

  static const List<String> joursSemaineLongs = <String>[
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  static const String parametresSectionCaserne = 'La caserne';
  static const String parametresSectionCaserneNote =
      'Le nom que voient les membres, et le fuseau qui date les échéances.';
  static const String parametresNom = 'Nom de la caserne';
  static const String parametresNomInvite = 'CIS Saint-Martin';
  static const String parametresFuseau = 'Fuseau horaire';

  static const String parametresSectionCreneaux = 'Créneaux';
  static const String parametresSectionCreneauxNote =
      'Des heures d\'affichage. Elles ne découpent pas l\'astreinte : un '
      'créneau reste « le 12 octobre, nuit ».';
  static const String parametresDebutJour = 'Début du créneau de jour';
  static const String parametresFinJour = 'Fin du créneau de jour';
  static const String parametresHeureInvite = '07:00';

  static String parametresNuitDeduite(String debut, String fin) =>
      'La nuit couvre le reste : de $fin à $debut.';

  static const String parametresSectionEffectif = 'Effectif requis';
  static const String parametresSectionEffectifNote =
      'Le nombre de pompiers attendus sur chaque créneau.';
  static const String parametresEffectifJour = 'Requis en journée';
  static const String parametresEffectifNuit = 'Requis la nuit';
  static const String parametresEffectifConsequence =
      'Les plannings déjà créés gardent leur effectif. Ce réglage s\'applique '
      'aux plannings créés ensuite.';

  static const String parametresSectionSurcharges = 'Surcharges';
  static const String parametresSectionSurchargesNote =
      'Les exceptions à l\'effectif requis : un samedi chargé, un 31 décembre.';
  static const String parametresSurchargesSemaine = 'Par jour de semaine';
  static const String parametresSurchargesDates = 'Par date';
  static const String parametresSurchargeAucune = 'Par défaut';
  static const String parametresSurchargesDatesVide =
      'Aucune date particulière.';
  static const String parametresSurchargeAjouterDate = 'Ajouter une date';
  static const String parametresSurchargeRevenirDefaut =
      'Revenir à l\'effectif par défaut';
  static const String parametresSurchargeAppliquer = 'Appliquer';
  static const String parametresSurchargeDate = 'Date';
  static const String parametresSurchargeDateInvite = '31/12/2026';
  static const String parametresSurchargeDateExistante =
      'Cette date a déjà une surcharge.';

  /// L'état d'une surcharge, en toutes lettres : « 2 en journée · 3 la nuit ».
  static String parametresSurchargeValeur(int? jour, int? nuit) {
    final morceaux = <String>[
      if (jour != null) '$jour en journée',
      if (nuit != null) '$nuit la nuit',
    ];
    return morceaux.isEmpty ? parametresSurchargeAucune : morceaux.join(' · ');
  }

  static String parametresSurchargeModifier(String quoi) =>
      'Modifier la surcharge : $quoi';
  static String parametresSurchargeRetirer(String quoi) =>
      'Retirer la surcharge : $quoi';
  static String parametresSurchargeTitre(String quoi) => 'Surcharge — $quoi';
  static String parametresSurchargeDefautRappel(int jour, int nuit) =>
      'Par défaut : $jour en journée, $nuit la nuit.';

  static const String parametresCreneauJourLibelle = 'En journée';
  static const String parametresCreneauNuitLibelle = 'La nuit';
  static const String parametresSurchargeFixerJour =
      'Fixer l\'effectif en journée';
  static const String parametresSurchargeFixerNuit =
      'Fixer l\'effectif la nuit';

  static const String parametresSectionSaisie = 'Saisie des disponibilités';
  static const String parametresSectionSaisieNote =
      'Le jour du mois précédent où la saisie se ferme.';
  static const String parametresJourLimite = 'Jour limite de saisie';
  static const String parametresJourLimiteConsequence =
      'La date limite des mois encore ouverts sera recalculée.';

  static String parametresJourLimiteExemple(String mois, String date) =>
      'Les disponibilités de $mois se ferment le $date à 23:59.';

  static const String parametresSectionRelances = 'Relances';
  static const String parametresSectionRelancesNote =
      'Le délai après la publication d\'un planning, en heures.';
  static const String parametresRelancePush = 'Rappel poussé, sans réponse';
  static const String parametresRelanceEmail = 'Relance par courriel';
  static const String parametresRapportRetard = 'Rapport des retardataires';

  static String parametresHeures(int n) => n <= 1 ? '$n heure' : '$n heures';

  static const String parametresEnregistrer = 'Enregistrer les paramètres';
  static const String parametresAucuneModification =
      'Aucune modification à enregistrer.';
  static const String parametresEnregistres = 'Paramètres enregistrés.';

  static String parametresACorriger(int n) =>
      n <= 1 ? 'Un réglage est à corriger.' : '$n réglages sont à corriger.';

  static String parametresDiminuer(String quoi) => 'Diminuer : $quoi';
  static String parametresAugmenter(String quoi) => 'Augmenter : $quoi';

  // Validation — les mêmes phrases que les bornes de la contrainte SQL
  // `stations_settings_valide` (migration 0011).
  static const String parametresNomVide = 'Donne un nom à la caserne.';
  static const String parametresNomLong = '80 caractères au maximum.';
  static const String parametresFuseauInconnu =
      'Choisis un fuseau horaire dans la liste.';
  static const String parametresHeureInvalide = 'Écris une heure comme 07:00.';
  static const String parametresHeuresIdentiques =
      'Le jour ne peut pas commencer et finir à la même heure.';
  static const String parametresEffectifBorne = 'Un effectif va de 0 à 50.';
  static const String parametresJourLimiteBorne =
      'Le jour limite va du 1 au 28 : le 29, le 30 et le 31 n\'existent pas '
      'tous les mois.';
  static const String parametresDelaiBorne =
      'Un délai va de 1 à 336 heures (deux semaines).';
  static const String parametresSurchargeIncomplete =
      'Une surcharge fixe l\'effectif du jour, celui de la nuit, ou les deux.';
  static const String parametresDateInvalide =
      'Écris une date comme 31/12/2026.';

  // Refus venus du serveur.
  static const String parametresRefusDroits =
      'Seul un administrateur de la caserne modifie ses paramètres.';
  static const String parametresRefusDocument =
      'Le serveur a refusé ces réglages. Vérifie les valeurs saisies.';
  static const String parametresRefusFuseau =
      'Ce fuseau horaire est inconnu du serveur.';
  static const String parametresEchecGenerique =
      'Les paramètres n\'ont pas été enregistrés. Vérifie ta connexion, puis '
      'réessaie.';

  // -------------------------------------------------------------------
  // Mon mois — saisie des disponibilités (ticket 011)
  // -------------------------------------------------------------------

  // --- Sélecteur de mois -----------------------------------------------

  static const String moisSelecteurLabel = 'Mois à saisir';

  /// « Octobre 2026 » : capitale initiale, contrairement à [moisLongs], parce
  /// que le bouton du sélecteur **est** le titre de l'écran.
  static String moisNomEtAnnee(int mois, int annee) {
    final nom = moisLongs[mois - 1];
    return '${nom[0].toUpperCase()}${nom.substring(1)} $annee';
  }

  static String moisOuvertJusquAuCourt(String date) => 'Ouvert jusqu\'au $date';

  static const String moisVerrouilleCourt = 'Verrouillé';

  static String moisSelectionSemantique(String mois) =>
      'Mois sélectionné : $mois';

  // --- En-tête de colonnes ----------------------------------------------

  static const String grilleColonneDate = 'Date';

  static const List<String> grilleJoursCourts = <String>[
    'lun.',
    'mar.',
    'mer.',
    'jeu.',
    'ven.',
    'sam.',
    'dim.',
  ];

  /// Initiales de la vue calendaire. Deux « M » et deux « J » : c'est l'usage
  /// français, et la position en colonne lève l'ambiguïté.
  static const List<String> grilleJoursInitiales = <String>[
    'L',
    'M',
    'M',
    'J',
    'V',
    'S',
    'D',
  ];

  static const List<String> grilleJoursLongs = <String>[
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];

  // --- Peinture au glissement -------------------------------------------

  static String peintureEnCours(String etat) => 'Tu peins : $etat';

  static const String peintureAnnulee = 'Peinture annulée';

  static String peintureResultat(int n, String etat) => n <= 1
      ? '$n case mise à jour, ${etat.toLowerCase()}'
      : '$n cases mises à jour, ${etat.toLowerCase()}';

  static const String peintureIndiceSemantique =
      'Appui long puis glissement pour cocher plusieurs cases';

  // --- Bloc d'aide -------------------------------------------------------

  static const String astuceSaisieTouche =
      'Appuie sur une case pour te déclarer disponible. Appuie encore pour '
      't\'absenter.';
  static const String astuceSaisieGlissement =
      'Astuce : appui long puis glisse pour cocher plusieurs cases d\'un coup.';

  // --- Compteurs ---------------------------------------------------------

  /// Le résumé annoncé de la barre du bas. Les trois nombres, toujours.
  static String compteursResume(int jours, int nuits, int weekends) =>
      'Total du mois : $jours ${jours <= 1 ? 'jour' : 'jours'}, '
      '$nuits ${nuits <= 1 ? 'nuit' : 'nuits'}, '
      '$weekends ${weekends <= 1 ? 'weekend' : 'weekends'} disponibles';

  // --- Enregistrement, réseau, verrouillage ------------------------------

  static const String moisErreurEnregistrementBanniere =
      'Impossible d\'enregistrer tes disponibilités. Elles sont conservées sur '
      'ton téléphone.';

  /// Des écritures gardées sur l'appareil visaient un mois qui s'est
  /// verrouillé avant qu'elles ne partent. Nomme le problème **et** la
  /// sortie : il n'y a plus qu'à passer par le chef de centre.
  static const String moisFilePerimeeBanniere =
      'Des disponibilités en attente visaient un mois désormais verrouillé. '
      'Elles n\'ont pas été enregistrées : contacte ton chef de centre.';
  static const String moisErreurVerrouilleEnCours =
      'Le mois vient d\'être verrouillé. Tes dernières modifications n\'ont pas '
      'été enregistrées.';
  static const String moisErreurSuspendueEnCours =
      'Ta caserne est passée en lecture seule. Tes dernières modifications '
      'n\'ont pas été enregistrées.';
  static const String actionRecharger = 'Recharger';

  /// **La réponse à un appui sur une case verrouillée** (ticket 014).
  ///
  /// La grille du ticket 011 rendait les cases inertes : l'appui ne faisait
  /// rien du tout, et un doigt qui n'obtient rien recommence. La case reste
  /// non modifiable, mais elle répond — le problème, puis la sortie.
  static String moisRefusVerrouille(String mois) =>
      '$mois est verrouillé : la saisie est fermée. Demande à ton chef de '
      'centre de rouvrir le mois.';

  static const String moisRefusLectureSeule =
      'Caserne suspendue : la saisie est fermée. Tu peux consulter tes '
      'disponibilités, pas les changer.';

  // --- États vides -------------------------------------------------------

  static const String moisAucunePeriodeTitre = 'Aucun mois à saisir';
  static const String moisAucunePeriodeTexte =
      'Ton chef de centre n\'a pas encore ouvert de mois. Tu recevras une '
      'notification dès que la saisie sera possible.';
  static const String moisChargementImpossibleTexte =
      'Impossible de lire tes disponibilités. Vérifie ta connexion, puis '
      'réessaie.';

  // -------------------------------------------------------------------
  // Raccourcis de sélection (ticket 012)
  // -------------------------------------------------------------------

  static const String raccourcisTitre = 'Remplir vite';

  /// Le libellé lu par un lecteur d'écran avant d'entrer dans la bande.
  static const String raccourcisSemantique =
      'Raccourcis de remplissage du mois';

  /// La raison affichée à côté des raccourcis inertes. `DESIGN.md § Do` :
  /// un contrôle désactivé dit pourquoi, à côté du contrôle.
  static const String raccourcisVerrouilles =
      'Mois verrouillé : les raccourcis ne s\'appliquent plus.';
  static const String raccourcisLectureSeule =
      'Caserne en lecture seule : les raccourcis ne s\'appliquent plus.';

  // --- Les cinq portées ---------------------------------------------------

  static const String raccourciWeekends = 'Les weekends';
  static const String raccourciWeekendsDetail =
      'Tous les samedis et dimanches du mois. Les jours fériés en semaine ne '
      'sont pas concernés.';

  static const String raccourciSemaine = 'La semaine';
  static const String raccourciSemaineDetail =
      'Du lundi au vendredi, jours fériés compris.';

  static const String raccourciMois = 'Tout le mois';
  static const String raccourciMoisDetail =
      'Tous les jours du mois, weekends compris.';

  static const String raccourciCopie = 'Copier le mois précédent';
  static const String raccourciCopieDetail =
      'Reprend le mois précédent en alignant les jours de la semaine : un '
      'samedi reste un samedi. Remplace ce qui est déjà saisi.';

  static const String raccourciEffacer = 'Tout effacer';
  static const String raccourciEffacerDetail =
      'Remet le mois à zéro. Les cases redeviennent « non saisi ».';

  // --- Le créneau visé ----------------------------------------------------

  static const String raccourciCibleJour = 'Jour';
  static const String raccourciCibleNuit = 'Nuit';
  static const String raccourciCibleLesDeux = 'Jour et nuit';

  /// Le nombre de cases qu'un choix de la feuille va changer.
  static String raccourciCasesConcernees(int n) =>
      n <= 1 ? '$n case' : '$n cases';

  static const String raccourciAucunChangement =
      'Rien à changer : ces cases sont déjà comme ça.';

  // --- Confirmation -------------------------------------------------------

  static String raccourciConfirmerEffacerTitre(int n) => n <= 1
      ? 'Effacer 1 saisie ?'
      : 'Effacer $n saisies ?';
  static const String raccourciConfirmerEffacerTexte =
      'Les cases redeviennent « non saisi ». Tu pourras annuler juste après.';
  static const String raccourciConfirmerEffacerAction = 'Effacer';

  static String raccourciConfirmerCopieTitre(int n) => n <= 1
      ? 'Remplacer 1 saisie ?'
      : 'Remplacer $n saisies ?';
  static const String raccourciConfirmerCopieTexte =
      'Le mois précédent prend la place de ce que tu as saisi. Tu pourras '
      'annuler juste après.';
  static const String raccourciConfirmerCopieAction = 'Remplacer';

  // --- Résultat et annulation ---------------------------------------------

  /// « 22 cases mises à jour ». Le même compte que la peinture, parce que
  /// c'est le même geste vu de plus loin.
  static String raccourciResultat(int n) => n <= 1
      ? '$n case mise à jour'
      : '$n cases mises à jour';

  /// L'annonce complète, pour le lecteur d'écran : le compte, le raccourci,
  /// et la sortie.
  static String raccourciResultatSemantique(String raccourci, int n) =>
      '${raccourciResultat(n)} : $raccourci. Annulation possible.';

  static const String raccourciAnnulerLabel = 'Annuler';
  static String raccourciAnnulerSemantique(String raccourci) =>
      'Annuler le raccourci $raccourci';
  static const String raccourciAnnule = 'Raccourci annulé';

  static const String raccourciCopieIllisible =
      'Impossible de lire le mois précédent. Vérifie ta connexion, puis '
      'réessaie.';

  // --- Jours fériés ------------------------------------------------------

  static const String feriePremierJanvier = 'Jour de l\'an';
  static const String feriePaques = 'Lundi de Pâques';
  static const String ferieFeteTravail = 'Fête du Travail';
  static const String ferieVictoire1945 = 'Victoire 1945';
  static const String ferieAscension = 'Ascension';
  static const String feriePentecote = 'Lundi de Pentecôte';
  static const String ferieFeteNationale = 'Fête nationale';
  static const String ferieAssomption = 'Assomption';
  static const String ferieToussaint = 'Toussaint';
  static const String ferieArmistice = 'Armistice';
  static const String ferieNoel = 'Noël';

  // -------------------------------------------------------------------
  // Préférences de charge (ticket 013)
  // -------------------------------------------------------------------

  static const String preferencesTitre = 'Ce mois, je veux faire au maximum';

  /// **La leçon.** C'est elle qui apprend au membre que l'outil a changé de
  /// logique : cocher, c'est dire ce qu'on peut, pas ce qu'on veut. Un
  /// pompier qui la lit coche ses quatre weekends ; un pompier qui ne la lit
  /// pas continue d'en cocher un seul.
  static const String preferencesLecon =
      'Cocher tous tes weekends ne t\'engage pas à tous les faire. Dis ici '
      'combien tu en veux vraiment.';

  static const String preferencesAstreintes = 'Astreintes';
  static const String preferencesWeekends = 'Weekends';

  /// Écrit en toutes lettres, jamais un `∞` : le symbole n'est pas lisible
  /// pour tout le monde.
  static const String preferencesSansLimite = 'autant que nécessaire';

  static String preferencesAstreintesCochees(int nombre) =>
      '$nombre ${nombre <= 1 ? 'cochée' : 'cochées'} ce mois';

  static String preferencesWeekendsCoches(int nombre) =>
      '$nombre ${nombre <= 1 ? 'coché' : 'cochés'} ce mois';

  static const String preferencesZeroAstreintes = 'Aucune astreinte ce mois';
  static const String preferencesZeroWeekends = 'Aucun weekend ce mois';

  /// Les valeurs seules : « 4 astreintes, 1 weekend ». Sous le titre, qui
  /// dit déjà « au maximum », le préfixe serait un doublon.
  static String preferencesValeurs(int? astreintes, int? weekends) {
    if (astreintes == null && weekends == null) return preferencesSansLimite;
    return <String>[
      if (astreintes != null)
        '$astreintes ${astreintes <= 1 ? 'astreinte' : 'astreintes'}',
      if (weekends != null)
        '$weekends ${weekends <= 1 ? 'weekend' : 'weekends'}',
    ].join(', ');
  }

  /// Une rangée de la feuille de choix : « 4 astreintes au maximum ».
  static String preferencesPlafondAstreintes(int n) =>
      '$n ${n <= 1 ? 'astreinte' : 'astreintes'} au maximum';

  /// Une rangée de la feuille de choix : « 2 weekends au maximum ».
  static String preferencesPlafondWeekends(int n) =>
      '$n ${n <= 1 ? 'weekend' : 'weekends'} au maximum';

  /// La même chose en phrase, pour une annonce ou un résumé isolé.
  static String preferencesResume(int? astreintes, int? weekends) =>
      astreintes == null && weekends == null
      ? preferencesResumeSansLimite
      : 'Au maximum : ${preferencesValeurs(astreintes, weekends)}';

  static const String preferencesResumeSansLimite =
      'Au maximum : autant que nécessaire';

  static const String preferencesModifier = 'Modifier mes maximums';

  /// **L'écart, et sa raison.** Jamais un avertissement : dépasser son
  /// maximum est ici le résultat recherché, pas une faute
  /// (`docs/PRD.md § 7.4`).
  static String preferencesEcartAstreintes(int cochees, int maximum) =>
      'Tu as coché $cochees ${cochees <= 1 ? 'astreinte' : 'astreintes'} pour '
      '$maximum ${maximum <= 1 ? 'voulue' : 'voulues'}. C\'est normal : tu '
      'laisses le choix à ton chef.';

  static String preferencesEcartWeekends(int coches, int maximum) =>
      'Tu as coché $coches ${coches <= 1 ? 'weekend' : 'weekends'} pour '
      '$maximum ${maximum <= 1 ? 'voulu' : 'voulus'}. C\'est normal : tu '
      'laisses le choix à ton chef.';

  /// La reprise n'est jamais silencieuse.
  static String preferencesReprise(int mois) =>
      'Repris de ${moisLongs[mois - 1]}. Change-le si ce n\'est plus vrai.';

  static const String preferencesCommentaireRangee = 'Un mot pour ton chef';
  static const String preferencesCommentaireInvite =
      'Ex. : pas plus d\'un weekend, garde des enfants.';

  static String preferencesCommentaireRestants(int nombre) =>
      '$nombre ${nombre <= 1 ? 'caractère restant' : 'caractères restants'}';

  static const String preferencesVerrouille =
      'Mois verrouillé : tu ne peux plus changer tes maximums.';
  static const String preferencesLectureSeule =
      'Caserne en lecture seule : tu ne peux plus changer tes maximums.';
  static const String preferencesAucuneVerrouille =
      'Aucun maximum indiqué pour ce mois.';

  static const String preferencesFeuilleAstreintes =
      'Au maximum, combien d\'astreintes ?';
  static const String preferencesFeuilleWeekends =
      'Au maximum, combien de weekends ?';

  /// Le rappel des maximums dans le résumé annoncé de la barre du bas : un
  /// utilisateur de lecteur d'écran a l'écart complet sans entrer dans la
  /// section.
  static String compteursResumeMaximums(int? astreintes, int? weekends) {
    if (astreintes == null && weekends == null) return '';
    return '. ${preferencesResume(astreintes, weekends)}';
  }

  // -------------------------------------------------------------------
  // Écran « Périodes » — administration (ticket 014)
  // -------------------------------------------------------------------

  static const String periodesTitre = 'Périodes';
  static const String periodesSousTitre =
      'Un mois se verrouille tout seul à sa date limite. Tu peux le fermer '
      'plus tôt, ou le rouvrir en repoussant sa date limite.';
  static const String periodesReserveAdmin =
      'Les mois de saisie appartiennent aux administrateurs de la caserne.';
  static const String periodesRafraichir = 'Relire les mois';
  static const String periodesErreurTexte =
      'Impossible de lire les mois de la caserne. Vérifie ta connexion, puis '
      'réessaie.';
  static const String periodesSectionAVenir = 'Mois à venir';
  static const String periodesSectionEcoules = 'Mois écoulés';
  static const String periodesVideTitre = 'Aucun mois ouvert';
  static const String periodesVideTexte =
      'Ouvre le mois prochain pour que les pompiers puissent saisir leurs '
      'disponibilités.';
  static const String periodesAucunAVenir =
      'Aucun mois à venir. Ouvre le mois prochain dès maintenant.';
  static const String periodesAucunEcoule = 'Aucun mois écoulé.';

  /// « 2 mois » : le mot est invariable, le compte ne l'est pas.
  static String periodesCompte(int n) => '$n mois';

  /// La ligne de faits d'un mois verrouillé : quand, et jusqu'à quand il
  /// était ouvert.
  static String periodeLigneVerrouillee(String verrouilleLe, String limite) =>
      'Verrouillé le $verrouilleLe · date limite du $limite';

  // --- Le taux de saisie -------------------------------------------------

  static String periodeTauxSaisie(int saisis, int effectif) =>
      '$saisis ${saisis <= 1 ? 'membre' : 'membres'} sur $effectif '
      '${saisis <= 1 ? 'a' : 'ont'} saisi';

  static const String periodeTauxAucunMembre =
      'Aucun membre actif dans la caserne.';
  static const String periodeTauxIndisponible = 'Comptage indisponible.';

  /// Le pourcentage, annoncé avec son unité : la jauge n'est qu'un rappel.
  static String periodeTauxPourcentage(int pourcentage) => '$pourcentage %';

  // --- Verrouiller maintenant -------------------------------------------

  static const String periodeActionVerrouiller = 'Verrouiller';

  static String periodeVerrouillerTitre(String mois) =>
      'Verrouiller $mois ?';

  static const String periodeVerrouillerTexte =
      'Les membres ne pourront plus modifier leurs disponibilités. Toi, tu '
      'peux toujours saisir pour eux, et rouvrir le mois plus tard.';
  static const String periodeVerrouillerConfirmer = 'Verrouiller maintenant';

  static String periodeVerrouilleeConfirmation(String mois) =>
      '$mois est verrouillé.';

  // --- Rouvrir ------------------------------------------------------------

  static const String periodeActionRouvrir = 'Rouvrir';

  static String periodeRouvrirTitre(String mois) => 'Rouvrir $mois';

  static const String periodeRouvrirRegle =
      'Le verrouillage automatique passe toutes les heures. Sans nouvelle '
      'date limite, le mois se refermerait dans l\'heure.';
  static const String periodeRouvrirLibelleDate = 'Nouvelle date limite';
  static const String periodeRouvrirJourPlusTot = 'Un jour plus tôt';
  static const String periodeRouvrirJourPlusTard = 'Un jour plus tard';
  static const String periodeRouvrirConfirmer = 'Rouvrir le mois';
  static const String periodeRouvrirRefusDatePassee =
      'Choisis une date future : sinon le verrouillage automatique refermera '
      'le mois dans l\'heure.';

  /// La date limite en toutes lettres : « mercredi 23 septembre, 23 h 59 ».
  /// L'heure est écrite parce qu'une date limite « le 23 » ne dit pas si le
  /// 23 compte.
  static String periodeDateLimiteHeure(String dateLongue) =>
      '$dateLongue, 23 h 59';

  static String periodeRouverteConfirmation(String mois, String date) =>
      '$mois est rouvert jusqu\'au $date.';

  // --- Ouvrir un mois -----------------------------------------------------

  static const String periodesOuvrirUnMois = 'Ouvrir un mois';
  static const String periodeCreerTitre = 'Ouvrir un mois à la saisie';
  static const String periodeCreerAide =
      'La date limite est calculée depuis les paramètres de la caserne : le '
      'jour limite du mois précédent, à 23 h 59.';
  static const String periodeCreerDejaOuvert = 'Déjà ouvert';
  static const String periodeCreerDejaVerrouille = 'Déjà verrouillé';

  static String periodeCreeeConfirmation(String mois) =>
      '$mois est ouvert à la saisie.';

  static String periodeDejaOuverteConfirmation(String mois) =>
      '$mois était déjà ouvert.';

  // --- Refus du serveur ---------------------------------------------------

  static const String periodeRefusDroits =
      'Seul un administrateur de la caserne ouvre, verrouille ou rouvre un '
      'mois.';
  static const String periodeRefusSuspendue =
      'Abonnement suspendu : la caserne est en lecture seule, les mois ne '
      'bougent plus.';
  static const String periodeRefusMoisPasse =
      'Un mois déjà écoulé ne peut plus être ouvert à la saisie.';
  static const String periodeRefusMoisInvalide =
      'Ce mois n\'existe pas. Choisis un mois de la liste.';
  static const String periodeRefusDeadlinePassee =
      'Rouvrir un mois demande de repousser sa date limite : sinon la tâche '
      'horaire le reverrouille dans l\'heure.';
  static const String periodeRefusDeadlineDansLePasse =
      'La date limite d\'un mois ouvert doit rester dans le futur. Pour fermer '
      'ce mois, verrouille-le.';
  static const String periodeEchecGenerique =
      'Impossible de modifier ce mois. Réessaie dans un instant.';

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

  // -------------------------------------------------------------------
  // Notifications push (ticket 024)
  // -------------------------------------------------------------------

  // --- Accueil d'un nouveau membre : la demande d'autorisation ---------

  static const String notifAccueilTitre = 'Reçois les propositions';
  static const String notifAccueilIntro =
      'Quand un chef te propose une astreinte, ton téléphone te prévient. '
      'Sans ça, il faut ouvrir l\'application pour le savoir.';
  static const String notifAccueilListeTitre = 'Ce que tu recevras';
  static const String notifAccueilItemProposition =
      'Une astreinte t\'est proposée';
  static const String notifAccueilItemPlanning =
      'Le planning de ton mois est validé';
  static const String notifAccueilItemRappel =
      'Un rappel avant la date limite de saisie';

  /// Annoncé une ligne avant que la fenêtre du navigateur s'ouvre : elle
  /// arrive sans prévenir et un refus ne se rattrape pas.
  static const String notifAccueilAvantDemande =
      'Le navigateur va te demander l\'autorisation.';

  static const String notifActiver = 'Activer les notifications';
  static const String notifPlusTard = 'Plus tard';
  static const String notifContinuer = 'Continuer';

  // --- Les cas où les notifications sont impossibles -------------------

  static const String notifIosBanniere =
      'Sur iPhone, les notifications n\'arrivent que si l\'application est sur '
      'ton écran d\'accueil.';
  static const String notifIosTexte =
      'Ajoute-la à ton écran d\'accueil, puis reviens activer les '
      'notifications depuis ton profil.';
  static const String notifIosAction = 'Comment l\'installer';

  static const String notifNonSupporteBanniere =
      'Ton navigateur ne sait pas recevoir de notifications.';
  static const String notifNonConfigureBanniere =
      'Les notifications ne sont pas disponibles sur cette installation.';

  /// La suite, dans les deux cas : rien n'est perdu, c'est juste moins
  /// confortable.
  static const String notifSansPushTexte =
      'Tu verras tes propositions en ouvrant l\'application. Pense à la '
      'regarder avant chaque début de mois.';

  // --- Réglage dans le profil ------------------------------------------

  static const String notifReglageTitre = 'Notifications';
  static const String notifReglageBascule = 'Rappels et infos';
  static const String notifReglageBasculeAide =
      'Rappels de saisie, planning validé, changement de créneau.';

  /// Exigence produit (`docs/PRD.md § 6.5`) : les propositions d'astreinte ne
  /// sont jamais désactivables, et le produit le dit au lieu de le cacher.
  static const String notifReglageToujours =
      'Les propositions d\'astreinte arrivent toujours. Elles ne se coupent '
      'pas.';
  static const String notifReglageRaisonInactive =
      'Active d\'abord les notifications sur cet appareil.';
  static const String notifReglageEchec =
      'Réglage non enregistré. Réessaie dans un instant.';

  static const String notifEtatActive = 'Activées sur cet appareil';
  static const String notifEtatADemander = 'Pas encore activées';
  static const String notifEtatRefusee = 'Refusées dans ton navigateur';
  static const String notifEtatRefuseeSortie =
      'Rouvre l\'autorisation dans les réglages de ton navigateur, puis '
      'reviens ici.';
  static const String notifEtatInstallation =
      'Ajoute l\'application à ton écran d\'accueil pour les recevoir';
  static const String notifEtatNonSupporte =
      'Ton navigateur ne sait pas les recevoir';
  static const String notifEtatNonConfigure =
      'Indisponibles sur cette installation';
  static const String notifEtatHorsWeb =
      'Indisponibles dans cette version de l\'application';

  // --- Bannière d'un message reçu au premier plan -----------------------

  static const String notifBanniereVoir = 'Voir';
  static const String notifBanniereFermer = 'Fermer la notification';

  /// Une notification sans titre : le canal a au moins un corps, sinon rien
  /// ne s'affiche.
  static const String notifBanniereSansTitre = 'Nouvelle notification';
}
