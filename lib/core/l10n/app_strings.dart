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

  /// **Le tableau de bord** (ticket 064) : la première destination du
  /// pompier, celle qui répond aux trois questions qu'il se pose entre deux
  /// activités.
  static const String navAccueil = 'Accueil';

  /// La saisie des disponibilités, qui s'appelait « Mon mois » tant qu'elle
  /// était le premier écran. Elle est devenue le deuxième onglet au
  /// ticket 064 : c'est un calendrier, et c'est ce que le mot dit.
  static const String navCalendrier = 'Calendrier';
  static const String navMonMois = 'Mon mois';
  static const String navPropositions = 'Propositions';

  /// Ni « Mes astreintes » ni « Planning » : le mot couvre les deux vues que
  /// cette destination portera — les miennes (ticket 027) et celles de la
  /// caserne (ticket 023), qui sont deux filtres d'une même donnée
  /// (`design/027 § 4`).
  static const String navAstreintes = 'Astreintes';

  /// La quatrième destination (ticket 064) : le journal de bord. Elle réunira
  /// les rappels et les propositions au chantier 064b.
  static const String navBoite = 'Boîte';
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

  /// Le créneau a été confié à quelqu'un d'autre (ticket 020). Distinct
  /// d'« Annulé » : la garde existe toujours, elle a changé de main.
  static const String attributionRemplace = 'Remplacé';
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

  /// « 15 h 12 ». L'espace autour du « h » est l'usage typographique français,
  /// et il est insécable : une heure ne se coupe pas en fin de ligne.
  static String heureDuJour({required int heures, required int minutes}) =>
      '$heures\u00A0h\u00A0${minutes.toString().padLeft(2, '0')}';

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

  /// Le mot écrit **à côté** de la flèche quand il n'y a pas de pile à
  /// dépiler : lien profond, URL collée, rechargement de la PWA. Une
  /// info-bulle ne le dirait pas — il n'y a pas de survol en PWA
  /// (`design/052 § 6.1`). La flèche ne bouge pas, seul le mot apparaît.
  static const String retourAccueil = 'Accueil';

  /// Ce que la même sortie annonce au lecteur d'écran, dans cet état-là. Il
  /// reste complet même quand le mot tombe faute de place.
  static const String retourAccueilSemantique = 'Aller à l\'accueil';

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
  // Caserne suspendue et fin d'essai — ticket 030
  // -------------------------------------------------------------------

  /// La première ligne de la bannière, quand la base ne connaît pas la date de
  /// bascule. Reprise mot pour mot de `DESIGN.md § AppBanner`.
  static const String lectureSeuleBanniere =
      'Caserne suspendue : lecture seule.';

  /// La même, quand la date est connue.
  ///
  /// **Le fait, et rien de plus.** La conséquence descend dans le détail : avec
  /// le bouton « Abonnement » à droite, la colonne de texte tombe à ~220 dp sur
  /// un téléphone, et une première ligne plus longue se faisait tronquer.
  static String lectureSeuleDepuis(String date) =>
      'Caserne suspendue depuis le $date.';

  /// La seconde ligne, pour un **membre**.
  ///
  /// « Rien n'a été supprimé » est obligatoire : c'est une promesse du produit
  /// (`docs/PRD.md § 6.6` et § 7.6) et la seule phrase qui compte pour
  /// quelqu'un qui découvre l'écran inerte un mardi soir.
  static const String lectureSeuleMembreDetail =
      'Tu peux consulter, pas modifier. Rien n\'a été supprimé.';

  /// La même, pour un **administrateur** : lui a une sortie, et le bouton
  /// « Abonnement » la nomme juste à côté.
  static const String lectureSeuleAdminDetail =
      'Rien n\'a été supprimé. Reprends l\'abonnement.';

  static const String lectureSeuleAction = 'Abonnement';

  static String essaiJusquAu(String date, int jours) =>
      'Essai jusqu\'au $date — il reste ${jours == 1 ? '1 jour' : '$jours jours'}.';

  static const String essaiTermine = 'Ta période d\'essai est terminée.';

  /// Le détail d'un essai **terminé** : la conséquence, qui n'est pas encore
  /// arrivée — la tâche de suspension passe une fois par jour.
  static const String essaiTermineDetail =
      'La caserne passera en lecture seule.';

  static const String essaiDetailAdmin = 'Abonne-toi pour continuer.';

  // -------------------------------------------------------------------
  // États vides et erreurs
  // -------------------------------------------------------------------

  static const String videTitreGenerique = 'Rien à afficher';
  static const String videTexteGenerique = 'Il n\'y a encore rien ici.';
  static const String videPropositionsTitre = 'Aucune proposition en attente';
  static const String videPropositionsTexte =
      'Quand ton chef de centre publiera le planning, tes astreintes '
      'proposées s\'afficheront ici.';
  static const String videAstreintesTitre = 'Aucune astreinte à venir';
  static const String videAstreintesTexte =
      'Quand ton chef de centre publiera le planning et que tu auras accepté '
      'une astreinte, elle s\'affichera ici.';

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

  // --- Invitation en attente sur « Aucune caserne » (ticket 051) -----

  /// Le titre de l'écran **tant qu'on ne sait pas** ce que la session porte.
  ///
  /// Neutre par nécessité : « Aucune caserne » est un verdict, et le rendre
  /// avant d'avoir posé la question est exactement le défaut que ce ticket
  /// répare.
  static const String aucuneCaserneTitreNeutre = 'Ton compte';
  static const String aucuneCaserneVerification =
      'Vérification de tes invitations…';

  /// Le **fait** seul, sans le conseil.
  ///
  /// [aucuneCaserneTexte] additionne un fait — le compte n'est rattaché à
  /// aucune caserne, qui vient des appartenances, déjà chargées — et un
  /// conseil — demander une invitation —, qui dépend d'une chose qu'on n'avait
  /// jamais vérifiée. Quand la vérification échoue, on garde le fait et on
  /// abandonne le conseil : c'est la seule forme qui ne peut pas se tromper.
  static const String aucuneCaserneFait =
      'Ton compte existe, mais il n\'est rattaché à aucune caserne.';

  static String invitationsRecuesTitre(int nombre) =>
      nombre <= 1 ? 'Une caserne t\'attend' : '$nombre casernes t\'attendent';

  /// L'adresse de la session est dans la phrase, et c'est délibéré : la
  /// personne vient de la taper, c'est le seul fait qui relie ce qu'elle voit
  /// à ce qu'elle a fait. C'est la sienne, elle ne révèle rien.
  static String invitationsRecuesIntro(String email, int nombre) => nombre <= 1
      ? 'Une invitation a été envoyée à $email. Rejoins-la ici, sans ouvrir '
            'ton courriel.'
      : '$nombre invitations ont été envoyées à $email. Choisis la caserne '
            'que tu rejoins.';

  static String invitationsExpireesTitre(int nombre) =>
      nombre <= 1 ? 'Ton invitation a expiré' : 'Tes invitations ont expiré';

  /// Le libellé nomme la caserne : deux boutons « Rejoindre » identiques
  /// seraient un piège, et un bouton nomme son action.
  static String invitationRejoindre(String caserne) => 'Rejoindre $caserne';

  /// La sortie d'une invitation expirée : une personne, pas un bouton.
  static String invitationExpireeDemander(String inviteur) =>
      'Demande à $inviteur de te la renvoyer.';
  static const String invitationExpireeDemanderSansNom =
      'Demande à l\'administrateur de la caserne de te la renvoyer.';

  /// Deux phrases et pas une de plus : une bannière tient **deux lignes**, et
  /// à côté de « Réessayer » il reste 218 points sur un téléphone de 390. La
  /// version longue — « Impossible de vérifier tes invitations. Tu en as
  /// peut-être une en attente. » — s'y coupait en « …Tu en as peut-être u… »,
  /// et c'est la seconde phrase qui porte tout : sans elle, la personne croit
  /// que rien ne l'attend. Le mot « Vérification » reprend celui de
  /// [aucuneCaserneVerification], que l'écran vient d'afficher.
  static const String invitationsRecuesEchec =
      'Vérification impossible. Une invitation t\'attend peut-être.';
  static const String invitationsRecuesHorsLigne =
      'Hors ligne. Impossible de vérifier tes invitations.';

  /// La ligne d'invitation, lue comme une phrase par un lecteur d'écran.
  static String invitationRecueSemantique({
    required String caserne,
    required String etat,
    required String echeance,
    String? inviteur,
  }) => <String>[
    caserne,
    if (inviteur != null) 'invitation envoyée par $inviteur',
    etat,
    echeance,
  ].join(', ');

  /// Le rappel d'un accès désactivé quand une invitation occupe le centre de
  /// l'écran : le fait, sans la consigne de [caserneDesactiveeTexte], parce
  /// que la seule chose actionnable est alors l'invitation.
  static String caserneDesactiveeRappel(String caserne) =>
      'Ton accès à $caserne a été désactivé.';
  static const String caserneDesactiveeRappelSansNom =
      'Ton accès à cette caserne a été désactivé.';

  // --- Accueil --------------------------------------------------------

  static const String accueilTitre = 'Accueil';
  static const String accueilCaserneLabel = 'Ta caserne';
  static const String accueilRoleLabel = 'Ton rôle';
  static const String accueilRetour = 'Revenir à l\'accueil';

  // --- Le tableau de bord du pompier (ticket 064) ----------------------

  /// La salutation de l'en-tête. Elle se termine par une virgule : le prénom
  /// vient à la ligne suivante, en dessous.
  static const String accueilBonjour = 'Bonjour,';
  static const String accueilBonsoir = 'Bonsoir,';

  /// La phrase annoncée d'un coup : un lecteur d'écran ne doit pas lire
  /// « Bonsoir virgule » puis « Marie » comme deux textes sans rapport.
  static String accueilSalutation(String salutation, String prenom) =>
      prenom.isEmpty ? salutation : '$salutation $prenom';

  static const String accueilMesAstreintes = 'Mes astreintes';
  static const String accueilPropositionsSection = 'Propositions';
  static const String accueilDisponibilites = 'Disponibilités';

  /// « Mes astreintes · 4 ». Le compte est une donnée : il dit combien il y en
  /// a en tout, là où la rangée n'en montre que ce qui tient.
  static String accueilSectionCompte(String titre, int compte) =>
      '$titre · $compte';

  static const String accueilToutVoir = 'Tout voir';

  /// Un lecteur d'écran annonce la destination, pas seulement « Tout voir » —
  /// deux boutons du même nom sur un écran ne se distinguent pas à l'oreille.
  static const String accueilToutVoirAstreintes = 'Voir toutes mes astreintes';
  static const String accueilToutVoirPropositions =
      'Voir toutes les propositions';

  static const String accueilAujourdhui = 'Aujourd\'hui';
  static const String accueilLibre = 'Libre';
  static const String accueilRepondre = 'Répondre';

  /// La phrase annoncée d'une carte : la date, le créneau, l'état.
  /// « mar. 24, nuit, 19:00 → 07:00, astreinte acceptée, Caserne de Meaux ».
  static String accueilCarteSemantique({
    required String date,
    required String etat,
    String? creneau,
    String? heures,
    String? caserne,
  }) => <String>[
    date,
    ?creneau,
    ?heures,
    etat,
    ?caserne,
  ].where((String part) => part.isNotEmpty).join(', ');

  static const String accueilEtatAcceptee = 'Astreinte acceptée';
  static const String accueilEtatProposition = 'Proposition à répondre';
  static const String accueilEtatLibre = 'Jour libre';

  /// La phrase annoncée d'un jour de la bande de semaine. Les points ne
  /// s'entendent pas : ce sont ces mots qui les portent.
  static String accueilJourSemantique({
    required String date,
    required bool aujourdhui,
    required bool astreinte,
    required bool proposition,
  }) => <String>[
    date,
    if (aujourdhui) accueilAujourdhui,
    if (astreinte) accueilEtatAcceptee,
    if (proposition) accueilEtatProposition,
    if (!astreinte && !proposition) accueilEtatLibre,
  ].join(', ');

  /// « Proposée il y a 2 h ».
  static String accueilProposeeDepuis(String instant) => 'Proposée $instant';

  /// « Saisir mes disponibilités d'octobre ». Trois mois s'élident — avril,
  /// août, octobre —, les neuf autres prennent « de ».
  static String accueilSaisirMois(String nomMois) =>
      'Saisir mes disponibilités ${_elision(nomMois)}';

  /// Ce qu'il reste avant la date limite. À zéro jour, ce n'est plus un
  /// décompte : c'est le dernier jour, et le mot le dit.
  static String accueilResteJours(int jours) => switch (jours) {
    <= 0 => 'Dernier jour',
    1 => 'Plus qu\'un jour',
    _ => 'Reste $jours jours',
  };

  /// « Octobre saisi : 12 jours, 4 nuits ».
  static String accueilMoisSaisi(String libelleMois, int jours, int nuits) =>
      '$libelleMois saisi : ${_pluriel(jours, 'jour', 'jours')}, '
      '${_pluriel(nuits, 'nuit', 'nuits')}';

  static const String accueilVideAstreintesTitre = 'Aucune astreinte à venir';
  static const String accueilVideAstreintesTexte =
      'Rien ne t\'attend pour l\'instant. Saisis tes disponibilités : c\'est '
      'comme ça que le chef de centre sait sur qui compter.';
  static const String accueilVideAstreintesAction =
      'Saisir mes disponibilités';

  static const String accueilVidePropositionsTitre =
      'Aucune proposition en attente';
  static const String accueilVidePropositionsTexte =
      'Tu as répondu à tout. Les prochaines arriveront par notification.';

  static const String accueilErreurTexte =
      'Impossible de lire tes astreintes et tes propositions. Vérifie ta '
      'connexion, puis réessaie.';

  /// « d'octobre » ou « de janvier ».
  static String _elision(String nomMois) =>
      RegExp('^[aeiouâàéèêîôûù]', caseSensitive: false).hasMatch(nomMois)
      ? 'd\'$nomMois'
      : 'de $nomMois';

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

  /// Ticket 030 : pourquoi « Inviter » et les actions de membre sont inertes.
  static const String membresSuspendue =
      'Abonnement suspendu : la caserne est en lecture seule, les invitations '
      'ne partent plus.';
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

  // --- L'envoi du courriel d'invitation (ticket 048) -----------------
  //
  // Trois états, et **jamais deux**. « Le courriel n'est pas parti » et « on
  // ne sait pas s'il est parti » ne se disent pas de la même façon : la
  // seconde phrase est celle des invitations créées avant la migration
  // `0035`, et leur coller la première serait exactement le mensonge que ce
  // ticket corrige (`docs/SCHEMA.md § 2.4`).
  //
  // Elles sont courtes parce qu'en production, aucun fournisseur de courriel
  // n'est configuré : toute la liste porte la première, et une phrase de
  // trois lignes répétée soixante fois rendrait l'écran illisible. Le motif
  // technique de l'échec (`email_error`) ne s'affiche nulle part : il sert au
  // diagnostic, pas au chef de centre.

  static const String invitationCourrielNonParti = 'Courriel non parti';
  static const String invitationCourrielInconnu = 'Envoi du courriel inconnu';

  static String invitationCourrielEnvoyeLe(String date) =>
      'Courriel envoyé le $date';

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

  /// Le résumé d'un envoi d'invitations, commun aux deux comptes rendus.
  ///
  /// **Le verbe suit les faits.** « envoyées » n'apparaît qu'à deux
  /// conditions : que [parties] couvre tout ce qui a été retenu, et qu'il y
  /// ait quelque chose à couvrir. La seconde n'est pas un détail — sans elle,
  /// un lot entièrement refusé s'annonçait « 0 invitation envoyée, 5
  /// échecs. », un envoi affirmé sur zéro envoi. Dès qu'un courriel manque à
  /// l'appel, la phrase ne parle plus que de ce qui existe, et l'écran
  /// affichait auparavant « 1 invitation envoyée, 0 échec. » au-dessus de
  /// « le courriel n'est pas parti » : deux phrases qui se contredisent,
  /// l'une sous l'autre (ticket 048, à l'import puis à l'invitation).
  ///
  /// **Le nom suit les faits aussi.** « créée » ne vaut que pour une ligne
  /// qui n'existait pas. Une adresse déjà invitée revient en [relancees] : la
  /// compter comme une création annonçait « 1 invitation créée » pour une
  /// invitation vieille de trois jours (ticket 048, second tour). Quand tous
  /// les courriels sont partis, la distinction ne sert plus à rien — chacun a
  /// reçu le sien —, et le résumé compte tout ensemble.
  ///
  /// Les deux écrans partagent la phrase parce qu'ils partagent la règle. Ce
  /// qu'ils ne partagent pas, c'est ce qui vient **dessous** : à l'import,
  /// [importCourrielsNonPartis] compte les invitations restées à quai, car
  /// rien d'autre n'en parlera ; à l'invitation, vingt lignes au plus, et
  /// chacune porte déjà son sort — le résumé compte, la ligne dit laquelle.
  ///
  /// Toujours le nombre d'échecs, même à zéro.
  static String invitationsResume({
    required int creees,
    required int relancees,
    required int parties,
    required int echecs,
  }) {
    final retenues = creees + relancees;
    final partieEchecs = echecs <= 1 ? '$echecs échec' : '$echecs échecs';
    if (retenues > 0 && parties >= retenues) {
      return retenues <= 1
          ? '$retenues invitation envoyée, $partieEchecs.'
          : '$retenues invitations envoyées, $partieEchecs.';
    }
    // Un courriel au moins est resté à quai : la phrase ne dit plus que ce
    // qui est certain — les lignes nouvelles, et celles qui étaient déjà là.
    // Le compte des créations reste affiché quand il n'y a rien à relancer,
    // fût-il nul : « 0 invitation créée, 5 échecs. » est la seule phrase
    // vraie d'un lot entièrement refusé.
    final morceaux = <String>[
      if (creees > 0 || relancees == 0)
        creees <= 1 ? '$creees invitation créée' : '$creees invitations créées',
      // Le nom ne se répète pas quand les créations viennent de le poser :
      // « 1 invitation créée, 1 déjà en attente » plutôt que deux fois le
      // même mot dans la même phrase.
      if (relancees > 0)
        if (creees > 0)
          '$relancees déjà en attente'
        else if (relancees <= 1)
          '$relancees invitation déjà en attente'
        else
          '$relancees invitations déjà en attente',
    ];
    return '${morceaux.join(', ')}, $partieEchecs.';
  }

  // --- Le sort d'une adresse, sur sa ligne du compte rendu -----------
  //
  // Quatre libellés pour trois statuts, parce que deux d'entre eux affirment
  // qu'on a prévenu quelqu'un et que le serveur les rend même quand aucun
  // courriel n'est sorti. [ResultatInvitation.libelle] choisit ; ici, on
  // n'écrit que des phrases vraies.
  //
  // Aucun ne contient le mot « envoyée » — pas même « Relancée », qui a
  // remplacé « Renvoyée » pour cette raison. Le garde-fou des tests
  // (`test/support/promesse_envoi.dart`) refuse ce mot partout dès qu'un
  // courriel est resté à quai : avec « Renvoyée » il fallait une exception,
  // et l'exception laissait justement passer le libellé qui mentait.

  /// Le courriel est parti vers une adresse qui n'avait pas d'invitation.
  static const String resultatInvitee = 'Invitée';

  /// Le courriel est reparti vers une adresse qui en avait déjà une.
  static const String resultatRelancee = 'Relancée';

  /// L'invitation existe désormais, mais personne n'a été prévenu.
  static const String resultatCreee = 'Créée';

  /// L'invitation existait déjà, et personne n'a été prévenu de nouveau.
  static const String resultatDejaEnAttente = 'Déjà en attente';

  static const String resultatEchec = 'Échec';

  /// Ce qui s'ajoute quand l'invitation existe mais que le courriel n'est
  /// jamais sorti : sous l'adresse, au compte rendu ; en réponse au bouton
  /// « Renvoyer », dans la liste des invitations en attente.
  ///
  /// Elle ne redit plus « Invitation créée » : au compte rendu, le résumé
  /// vient de la compter et le statut la nomme juste au-dessus ; dans la
  /// liste, l'invitation était déjà là. Remplacer la contradiction du ticket
  /// 048 par une redite aurait été la corriger à moitié. Ne reste que le fait
  /// qui manque, et le geste qui le rattrape.
  static const String resultatCourrielNonParti =
      'Le courriel n\'est pas parti. Renvoie-la, ou transmets le lien '
      'toi-même.';

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

  // --- Plafond horaire d'invitations (ticket 038) --------------------
  //
  // Ces deux phrases sont des **secours**. Le refus de débit porte le délai
  // avant de pouvoir réessayer, qui change à chaque seconde : la phrase
  // affichée est celle que le serveur compose et renvoie
  // (`supabase/functions/README.md § Le plafond de débit`). On ne s'en passe
  // qu'au cas où elle manquerait, pour ne jamais annoncer une panne à la
  // place d'une limite.

  static const String inviteDebitAtteint =
      'Limite d\'invitations atteinte pour cette caserne. Réessaie dans un '
      'moment.';

  static String inviteDebitAtteintDans(int minutes) =>
      'Limite d\'invitations atteinte pour cette caserne. Réessaie dans '
      '${minutes <= 1 ? 'une minute' : '$minutes minutes'}.';

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

  // Les deux phrases qui suivent existent parce que « Impossible de joindre
  // le serveur. Vérifie ta connexion » a été affiché le 21 septembre 2026
  // pendant que le réseau allait très bien : les Edge Functions n'étaient pas
  // déployées. On ne nomme donc une cause que lorsqu'on la connaît, et on ne
  // propose pas un geste qui ne répare rien.

  /// Le serveur a répondu, mais l'application ne sait pas lire sa réponse :
  /// fonction absente, passerelle qui refuse, corps vide. Une réponse est
  /// arrivée — la connexion n'est donc pas en cause, et le dire évite de
  /// chercher une panne là où il n'y en a pas.
  static const String inviteServeurIndisponible =
      'Les invitations sont indisponibles : le serveur a refusé la demande '
      'sans dire pourquoi. Ce n\'est pas ta connexion, et rien n\'est parti. '
      'Réessaie plus tard.';

  /// Rien n'est revenu, et le navigateur ne se dit pas hors ligne : on ne sait
  /// pas si la demande est arrivée jusqu'au serveur. Aucune cause n'est donc
  /// promise, et la sortie proposée est la seule qui apprenne quelque chose.
  static const String inviteSansReponse =
      'Le serveur n\'a pas répondu. On ne sait pas si l\'envoi est parti : '
      'vérifie les invitations en attente avant de relancer.';

  // -------------------------------------------------------------------
  // Import de membres depuis un fichier (ticket 047)
  // -------------------------------------------------------------------

  static const String membresImporter = 'Importer un fichier';

  static const String importTitre = 'Importer des membres';
  static const String importIntro =
      'Dépose la liste que tu as déjà : chaque ligne devient une invitation, '
      'avec le nom. Tu verras tout avant que quoi que ce soit ne parte.';

  static const String importFormatTitre = 'Ce que le fichier doit contenir';
  static const String importFormatEntetes = 'prenom;nom;email;role';
  static const String importFormatExplication =
      'Un fichier tableur enregistré en CSV, séparé par des virgules ou des '
      'points-virgules. Seule la colonne d\'adresse est obligatoire. Les '
      'colonnes sont reconnues par leur intitulé : peu importe leur ordre.';
  static const String importFormatVariantes =
      'Intitulés acceptés : prénom, nom, email (ou courriel, e-mail, adresse) '
      'et rôle. La colonne rôle vaut « admin » ou rien.';
  static const String importFormatLimites =
      'Limites : 512 Ko et 500 lignes par import.';

  static const String importChoisir = 'Choisir un fichier';
  static const String importChoisirAutre = 'Choisir un autre fichier';
  static const String importExemple = 'Télécharger un fichier d\'exemple';
  static const String importExempleEchec =
      'Le fichier d\'exemple n\'a pas pu être enregistré.';
  static const String importIndisponible =
      'La lecture d\'un fichier n\'est possible que depuis un navigateur. '
      'Ouvre Astreinte SP sur ton ordinateur ou ton téléphone.';

  // --- Les refus de lecture ------------------------------------------

  static String importTropGros(String taille, String limite) =>
      'Ce fichier fait $taille. La limite est de $limite. Enregistre ta liste '
      'en CSV : elle tiendra largement dessous.';

  static String importTropDeLignes(int lignes, int limite) =>
      'Ce fichier compte $lignes lignes. La limite est de $limite par import. '
      'Coupe la liste en deux, et importe-la en deux fois.';

  static const String importColonneAdresseAbsente =
      'Aucune colonne d\'adresse e-mail dans ce fichier. Nomme-la email, '
      'e-mail, courriel, mail ou adresse sur la première ligne, puis '
      'redépose-le.';
  static const String importFichierVide =
      'Ce fichier ne contient aucune ligne sous ses en-têtes.';
  static const String importFichierIllisible =
      'Ce fichier n\'a pas pu être lu. Vérifie qu\'il s\'agit bien d\'un CSV, '
      'puis réessaie.';

  // --- L'aperçu --------------------------------------------------------

  static String importApercuResume({
    required int lues,
    required int aInviter,
    required int ecartees,
  }) {
    final debut = lues <= 1 ? '$lues ligne lue' : '$lues lignes lues';
    final envoi = aInviter <= 1 ? '$aInviter à inviter' : '$aInviter à inviter';
    if (ecartees == 0) return '$debut : $envoi.';
    final reste = ecartees <= 1 ? '1 écartée' : '$ecartees écartées';
    return '$debut : $envoi, $reste.';
  }

  static const String importApercuTitre = 'Ligne par ligne';

  /// Les deux intitulés de l'aperçu quand le fichier a des fautes : ce qui ne
  /// partira pas se lit en premier. Le vocabulaire est celui du résumé juste
  /// au-dessus — « 60 à inviter, 3 écartées » — pour qu'un compte annoncé et
  /// une section portent le même mot. Sans aucune ligne écartée, ni l'un ni
  /// l'autre n'apparaît : l'aperçu reste « Ligne par ligne ».
  static const String importSectionEcartees = 'Lignes écartées';
  static const String importSectionAInviter = 'Lignes à inviter';

  static String importEnvoyer(int nombre) =>
      nombre <= 1 ? 'Envoyer l\'invitation' : 'Envoyer les $nombre invitations';

  static const String importRienAEnvoyer =
      'Aucune ligne de ce fichier ne peut être invitée. Corrige-le, puis '
      'redépose-le.';

  /// Pourquoi « Choisir un autre fichier » est inerte pendant l'envoi. La
  /// ligne d'avancement le dit déjà à l'écran : cette phrase est celle que le
  /// lecteur d'écran annonce, et non un doublon visuel.
  static const String importEnvoiEnCours =
      'Envoi en cours : attends la fin pour déposer un autre fichier.';

  /// « 15 invitations sur 40 envoyées… » — **envoyées, donc parties**.
  ///
  /// [faites] ne compte que les invitations dont le courriel est réellement
  /// sorti. Deux comptes voisins sont écartés, pour la même raison : les
  /// adresses refusées, qui reçoivent un verdict sans que personne ne soit
  /// invité, et les invitations créées dont le courriel n'est pas parti, qui
  /// existent en base sans que personne ne soit prévenu. L'un comme l'autre
  /// ferait passer pour invitée une personne qui ne recevra jamais rien, et
  /// contredirait le compte rendu affiché l'instant d'après. Les échecs ne
  /// sont pas annoncés ici : pendant l'envoi, on n'en peut rien faire ; le
  /// compte rendu, lui, les nomme.
  static String importAvancement({required int faites, required int total}) =>
      faites <= 1
      ? '$faites invitation sur $total envoyée…'
      : '$faites invitations sur $total envoyées…';

  /// Le numéro d'une ligne dépourvue d'adresse : c'est le seul repère qui
  /// permette de la retrouver dans le tableur.
  static String importLigneNumero(int numero) => 'Ligne $numero';

  static const String importSansNom =
      'Sans nom : le pompier le saisira lui-même.';
  static const String importDejaInvitee =
      'Invitation déjà en attente. Ignorée.';
  static String importDoublon(int premiere) => 'Déjà présente ligne $premiere.';
  static const String importAdresseAbsente =
      'Pas d\'adresse e-mail sur cette ligne.';

  // --- Le budget d'envoi (plafond du ticket 038) -----------------------

  static String importBudgetToutPasse(int nombre) => nombre <= 1
      ? 'L\'invitation peut partir maintenant.'
      : 'Les $nombre invitations peuvent partir maintenant.';

  static String importBudgetPartiel({
    required int maintenant,
    required int reste,
    required String heure,
  }) =>
      '$maintenant invitations peuvent partir maintenant, '
      '${reste <= 1 ? '1 à' : '$reste à'} partir de $heure. Reviens ici avec '
      'le même fichier : les personnes déjà invitées seront ignorées.';

  static String importBudgetNul(String heure) =>
      'Aucune invitation ne peut partir avant $heure. La caserne a atteint son '
      'plafond horaire d\'envois.';

  // --- Le rapport ------------------------------------------------------

  static String importEcarteesResume(int nombre, String motifs) => nombre <= 1
      ? '1 ligne du fichier n\'a rien reçu : $motifs.'
      : '$nombre lignes du fichier n\'ont rien reçu : $motifs.';

  static String importEcarteesMotif(int nombre, String motif) =>
      '$nombre $motif';

  static const String importMotifDejaMembre = 'déjà membre';
  static const String importMotifDejaInvitee = 'déjà invitée';
  static const String importMotifDoublon = 'en double';
  static const String importMotifAdresseInvalide = 'adresse invalide';
  static const String importMotifAdresseAbsente = 'sans adresse';

  /// Le titre de la seule liste que le compte rendu déroule.
  ///
  /// Ce qui est passé ne descend pas ici : [invitationsResume] l'a déjà
  /// compté, et soixante coches identiques enterrent les trois lignes qui
  /// demandent quelque chose — la règle que l'aperçu applique à sa marque.
  static const String importEchecsTitre = 'À reprendre';

  // Le résumé de l'import n'est pas ici : c'est [invitationsResume], la
  // phrase commune aux deux comptes rendus. La règle qui interdit « envoyées »
  // tant qu'un courriel n'est pas sorti est la même des deux côtés, et une
  // règle de vérité ne se recopie pas (ticket 048).

  /// Les invitations qui existent, mais dont personne n'a été prévenu.
  ///
  /// Deux tournures, parce que ce sont deux faits différents. Quand c'est
  /// tout l'import — le cas de production, aucun fournisseur de courriel
  /// configuré —, la phrase parle de l'ensemble que [invitationsResume] vient
  /// d'annoncer. Quand une partie seulement est restée à quai, elle compte
  /// sur ce même ensemble : dire « 2 invitations sont créées » sous un résumé
  /// qui en annonce 3 ferait douter de la troisième.
  ///
  /// Elles ne sont jamais énumérées : le geste utile est le renvoi, et il se
  /// pose dans la liste des invitations en attente, où chaque ligne le porte
  /// (ticket 048).
  ///
  /// [retenues] est tout ce que le serveur a accepté, créations **et**
  /// relances : c'est l'ensemble que [invitationsResume] vient d'annoncer, et
  /// le seul auquel [nonPartis] puisse se comparer.
  static String importCourrielsNonPartis({
    required int nonPartis,
    required int retenues,
  }) {
    if (nonPartis >= retenues) {
      return nonPartis <= 1
          ? 'Son courriel n\'est pas parti. Renvoie cette invitation depuis '
                'la liste des invitations en attente.'
          : 'Aucun courriel n\'est parti. Renvoie ces invitations depuis la '
                'liste des invitations en attente.';
    }
    return nonPartis <= 1
        ? '1 de ces invitations n\'a pas reçu son courriel. Renvoie-la depuis '
              'la liste des invitations en attente.'
        : '$nonPartis de ces invitations n\'ont pas reçu leur courriel. '
              'Renvoie-les depuis la liste des invitations en attente.';
  }

  static String importReprendreApres(String heure) =>
      'Reprends l\'import après $heure avec le même fichier : les personnes '
      'déjà invitées seront ignorées.';

  static const String importReprendre = 'Reprendre l\'import';

  // --- Tailles de fichier ----------------------------------------------

  static String tailleOctets(int octets) => '$octets octets';

  static String tailleKo(double ko) => '${ko.toStringAsFixed(0)} Ko';

  static String tailleMo(double mo) =>
      '${mo.toStringAsFixed(1).replaceAll('.', ',')} Mo';

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

  /// Le même refus, quand le serveur n'a pas rendu l'adresse masquée.
  ///
  /// C'est le cas de l'entrée par identifiant (ticket 051) : la masquer
  /// n'aurait pas de sens — l'identifiant n'a été donné qu'à la session qu'il
  /// concerne —, et la rendre ferait un oracle d'existence.
  static String invitationMauvaisCompteTexteSansAdresse(
    String adresseCourante,
  ) =>
      'Cette invitation ne concerne pas $adresseCourante. Déconnecte-toi, '
      'puis reconnecte-toi avec l\'adresse qui l\'a reçue.';

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
  // Page publique d'aide à l'installation — /install (ticket 032)
  // -------------------------------------------------------------------

  /// Ce qui s'affiche quand on ne connaît pas la procédure du navigateur.
  /// Pas de gestes numérotés : trois gestes faux coûtent plus qu'un aveu.
  static const String installAutreIntro =
      'Installée, Astreinte SP s\'ouvre en un geste, en plein écran, et peut '
      't\'alerter d\'une proposition d\'astreinte.';
  static const String installAutreTitre = 'Où chercher';
  static const String installAutreOu =
      'Ouvre le menu de ton navigateur, puis cherche « Installer '
      'l\'application » ou « Ajouter à l\'écran d\'accueil ».';
  static const String installAutreAveu =
      'Selon le navigateur, cette entrée n\'existe pas. Astreinte SP marche '
      'aussi dans un onglet : seules les notifications demandent une '
      'application installée.';

  /// Ouvrir la page depuis l'application déjà installée : rien à apprendre.
  static const String installDejaFaitTitre = 'C\'est déjà fait';
  static const String installDejaFaitTexte =
      'Astreinte SP est installée sur cet appareil : tu la lis en ce moment '
      'même depuis son icône.';

  static const String installOuvrir = 'Ouvrir Astreinte SP';

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
  static const String parametresSuspendue =
      'Abonnement suspendu : les réglages ne peuvent pas être enregistrés.';

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

  /// La même date sans le mot « Ouvert », que l'icône du sélecteur dit déjà.
  static String moisJusquAuCourt(String date) => 'jusqu\'au $date';

  static const String moisVerrouilleCourt = 'Verrouillé';

  /// L'état de la période, en un mot, pour l'icône du bouton sur une ligne :
  /// c'est elle qui le porte à l'œil depuis le chantier 061c, et un lecteur
  /// d'écran ne voit pas les cadenas.
  static const String moisOuvertCourt = 'Ouvert';

  /// Le mois et son état sur une seule ligne : « Octobre 2026 · Verrouillé ».
  /// Le point médian sépare deux faits de même rang, là où un tiret aurait
  /// suggéré une suite.
  static String moisEtEtat(String mois, String etat) => '$mois · $etat';

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

  static String raccourciConfirmerEffacerTitre(int n) =>
      n <= 1 ? 'Effacer 1 saisie ?' : 'Effacer $n saisies ?';
  static const String raccourciConfirmerEffacerTexte =
      'Les cases redeviennent « non saisi ». Tu pourras annuler juste après.';
  static const String raccourciConfirmerEffacerAction = 'Effacer';

  static String raccourciConfirmerCopieTitre(int n) =>
      n <= 1 ? 'Remplacer 1 saisie ?' : 'Remplacer $n saisies ?';
  static const String raccourciConfirmerCopieTexte =
      'Le mois précédent prend la place de ce que tu as saisi. Tu pourras '
      'annuler juste après.';
  static const String raccourciConfirmerCopieAction = 'Remplacer';

  // --- Résultat et annulation ---------------------------------------------

  /// « 22 cases mises à jour ». Le même compte que la peinture, parce que
  /// c'est le même geste vu de plus loin.
  static String raccourciResultat(int n) =>
      n <= 1 ? '$n case mise à jour' : '$n cases mises à jour';

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

  static String periodeVerrouillerTitre(String mois) => 'Verrouiller $mois ?';

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

  // -------------------------------------------------------------------
  // Ancienneté d'un événement (ticket 026)
  // -------------------------------------------------------------------

  static const String instantMaintenant = 'À l\'instant';
  static const String instantHier = 'Hier';

  static String instantMinutes(int n) => 'il y a $n min';
  static String instantHeures(int n) => 'il y a $n h';
  static String instantJours(int n) => 'il y a $n j';

  // -------------------------------------------------------------------
  // Centre de notifications (ticket 026)
  // -------------------------------------------------------------------

  static const String centreTitre = 'Notifications';

  /// La cloche de la barre d'application. La pastille est plafonnée à « 9+ »,
  /// mais le nombre réel est annoncé aux lecteurs d'écran.
  static const String centreOuvrir = 'Notifications';

  static String centreNonLuesBadge(int n) =>
      n <= 1 ? '$n notification non lue' : '$n notifications non lues';

  /// Le compte de l'en-tête de liste. Il dit combien de lignes suivent, et
  /// combien restent à lire.
  static String centreCompte(int total, int nonLues) {
    final lignes = total <= 1 ? '$total notification' : '$total notifications';
    if (nonLues == 0) return '$lignes, tout est lu';
    return '$lignes, $nonLues non lue${nonLues > 1 ? 's' : ''}';
  }

  /// Annoncé en tête du libellé d'une ligne : l'état ne tient jamais à la
  /// seule couleur ni à la seule marque.
  static const String centreNonLue = 'Non lue';

  static const String centreToutMarquerLu = 'Tout marquer comme lu';
  static const String centreToutMarqueLuConfirmation = 'Tout est marqué lu.';
  static const String centreRafraichir = 'Relire les notifications';

  static const String centreVideTitre = 'Rien pour l\'instant';
  static const String centreVideTexte =
      'Les propositions d\'astreinte et les infos de ta caserne arriveront '
      'ici, même si ton téléphone ne sonne pas.';

  static const String centreErreurTexte =
      'Impossible de lire tes notifications. Vérifie ta connexion.';
  static const String centreEchecLecture =
      'Notification non marquée lue. Réessaie dans un instant.';

  /// Une ligne dont la colonne `error` est renseignée : l'envoi n'a pas
  /// abouti, et le membre doit savoir qu'il ne l'a peut-être jamais reçue
  /// (`design/026 § 7`).
  static const String centreEnvoiEchoue =
      'L\'envoi a échoué, tu ne l\'as peut-être pas reçue.';

  /// Une notification dont le titre est vide. Le canal interne en garantit un,
  /// mais une ligne écrite à la main n'en aurait pas.
  static const String centreSansTitre = 'Notification';

  // -------------------------------------------------------------------
  // Matrice des disponibilités de l'admin (ticket 016)
  // -------------------------------------------------------------------

  // --- Écran et navigation ---------------------------------------------

  static const String matriceTitre = 'Planning du mois';
  static const String matriceRafraichir = 'Rafraîchir';
  static const String matriceVersMembres = 'Membres de la caserne';
  static const String matriceVersParametres = 'Réglages de la caserne';
  static const String matriceVersPeriodes = 'Mois de saisie';
  static const String matriceVersPlanning = 'Planning du mois';
  static const String matriceReserveAdmin =
      'Cet écran est réservé aux administrateurs de la caserne.';

  // --- Barre de commande ------------------------------------------------

  static const String matriceRechercheLibelle = 'Rechercher un membre';
  static const String matriceRechercheEffacer = 'Effacer la recherche';
  static const String matriceMasquerNonSaisis =
      'Masquer ceux qui n\'ont rien saisi';
  static const String matriceAfficherCommentaires = 'Commentaires';
  static const String matriceTrier = 'Trier';
  static const String matriceTriNom = 'Nom';
  static const String matriceTriAstreintes = 'Astreintes restantes';
  static const String matriceTriWeekends = 'Weekends restants';
  static const String matriceToutAfficher = 'Tout afficher';
  static const String matriceEcranLarge =
      'La matrice complète s\'ouvre sur un écran large.';

  /// « 47 membres sur 60 ». Affiché dès qu'un filtre masque quelqu'un.
  static String matriceCompteFiltre(int n, int total) =>
      '$n membre${n > 1 ? 's' : ''} sur $total';

  // --- En-têtes et légende ----------------------------------------------

  static const String matriceColonneMembre = 'Membre';
  static const String matriceColonneAstreintes = 'Astr.';
  static const String matriceColonneWeekends = 'W-E';
  static const String matriceLigneDisponibles = 'Disponibles';
  static const String matriceLegendeTitre = 'Légende';

  // --- Quotas et commentaire --------------------------------------------

  static String matriceQuotaAstreintes(int reste, int max) =>
      '$reste astreinte${reste > 1 ? 's' : ''} restante${reste > 1 ? 's' : ''} '
      'sur $max';

  static String matriceQuotaAstreintesAtteint(int max) =>
      'Quota d\'astreintes atteint : $max sur $max';

  static String matriceQuotaAstreintesDepasse(int n) =>
      '$n astreinte${n > 1 ? 's' : ''} au-delà de ce qu\'il acceptait';

  static String matriceQuotaWeekends(int reste, int max) =>
      '$reste weekend${reste > 1 ? 's' : ''} restant${reste > 1 ? 's' : ''} '
      'sur $max';

  static String matriceQuotaWeekendsAtteint(int max) =>
      'Quota de weekends atteint : $max sur $max';

  static String matriceQuotaWeekendsDepasse(int n) =>
      '$n weekend${n > 1 ? 's' : ''} au-delà de ce qu\'il acceptait';

  /// Aucun plafond déclaré : la charge se dit seule, sans barre de fraction.
  static String matriceQuotaSansPlafond(int n) =>
      '$n astreinte${n > 1 ? 's' : ''} ce mois, pas de plafond';

  static String matriceQuotaWeekendsSansPlafond(int n) =>
      '$n weekend${n > 1 ? 's' : ''} ce mois, pas de plafond';

  static String matriceChargePrecedente(int n) =>
      '$n astreinte${n > 1 ? 's' : ''} acceptée${n > 1 ? 's' : ''} sur les '
      'trois mois précédents';

  static const String matriceCommentaireVide = 'Pas de commentaire ce mois';

  // --- Saisie à la place d'un membre ------------------------------------

  static const String matriceModeSaisie = 'Saisir à la place d\'un membre';
  static const String matriceModeSaisieActif =
      'Tu saisis à la place des membres. Chaque modification est enregistrée '
      'à ton nom.';
  static const String matriceModeSaisieQuitter = 'Quitter le mode saisie';
  static const String matriceConfirmationTitre =
      'Saisir à la place d\'un membre';
  static const String matriceConfirmationTexte =
      'Tu vas modifier les disponibilités d\'un autre pompier. Chaque '
      'modification est enregistrée à ton nom dans l\'historique de la '
      'caserne. Le membre n\'est pas prévenu.';
  static const String matriceConfirmationValider = 'Saisir à sa place';
  static const String matriceConfirmationAnnuler = 'Annuler';
  static const String matriceCaseSaisieParAdmin = 'Saisi par un administrateur';
  static const String matriceSaisieIndisponibleTactile =
      'Saisie possible sur écran large avec une souris, ou depuis la vue par '
      'jour.';
  static const String matriceSaisieIndisponibleSuspendue =
      'Caserne suspendue : lecture seule.';
  static const String matriceSaisieIndisponibleHorsLigne =
      'Hors ligne : la saisie reprendra au retour du réseau.';

  // --- États vides, erreurs, faits --------------------------------------

  static const String matriceAucunePeriodeTitre = 'Aucun mois ouvert';
  static const String matriceAucunePeriodeTexte =
      'Ouvre un mois de saisie pour commencer à construire un planning.';
  static const String matriceAucunePeriodeAction = 'Ouvrir un mois';
  static const String matriceAucunMembreTitre = 'Aucun membre actif';
  static const String matriceAucunMembreTexte =
      'Invite des pompiers pour qu\'ils saisissent leurs disponibilités.';
  static const String matriceAucunMembreAction = 'Inviter un membre';
  static const String matriceAucunResultatTitre = 'Aucun membre ne correspond';
  static const String matriceErreurTexte = 'Impossible de charger la matrice.';
  static const String matriceErreurEcriture =
      'Impossible d\'enregistrer cette case.';
  static const String matriceMoisIntrouvable = 'Ce mois n\'existe plus.';

  static String matriceMoisViergeTexte(String mois) =>
      'Personne n\'a encore saisi $mois.';

  static String matriceAucunResultatTexte(String recherche) =>
      'Aucun membre ne correspond à « $recherche ».';

  /// Le verrouillage **n'inerte pas** la matrice de l'admin : le PRD § 6.3 lui
  /// donne explicitement le droit de saisir sur un mois fermé.
  static String matriceVerrouilleTexte(String date) =>
      'Saisie verrouillée depuis le $date. Tu peux encore saisir à la place '
      'd\'un membre.';

  // --- Sémantique --------------------------------------------------------

  /// « Marie Lefebvre, samedi 4 octobre, nuit, disponible ».
  static String matriceCaseSemantique({
    required String membre,
    required String jourEtDate,
    required String creneau,
    required String etat,
  }) => '$membre, $jourEtDate, ${creneau.toLowerCase()}, ${etat.toLowerCase()}';

  static String matriceCaseAction(String etatSuivant) =>
      'Appuie pour le marquer ${etatSuivant.toLowerCase()}';

  /// La case d'un membre **qui porte une astreinte** : l'attribution d'abord,
  /// puis entre parenthèses ce que le membre avait déclaré.
  ///
  /// Les deux faits comptent et ne se déduisent pas l'un de l'autre :
  /// « accepté (absent) » est la ligne qu'un chef doit entendre, et le bloc
  /// seul ne la dirait pas — il a remplacé la case de disponibilité.
  static String matriceCaseAttributionSemantique({
    required String membre,
    required String jourEtDate,
    required String creneau,
    required String etat,
    required String disponibilite,
  }) =>
      '$membre, $jourEtDate, ${creneau.toLowerCase()}, '
      '${etat.toLowerCase()} '
      '(disponibilité déclarée : ${disponibilite.toLowerCase()})';

  static String matriceDisponiblesSemantique({
    required String jourEtDate,
    required String creneau,
    required int n,
  }) =>
      '$jourEtDate, ${creneau.toLowerCase()} : $n disponible${n > 1 ? 's' : ''}';

  static String matriceDisponiblesAucun({
    required String jourEtDate,
    required String creneau,
  }) => '$jourEtDate, ${creneau.toLowerCase()} : personne de disponible';

  static String matriceLigneSemantique({
    required String nom,
    required String quotas,
    required String commentaire,
  }) => '$nom. $quotas. $commentaire';

  // -------------------------------------------------------------------
  // Construction du planning en brouillon (ticket 017)
  // -------------------------------------------------------------------

  // --- Création du planning ---------------------------------------------

  static String planningCreer(String mois) =>
      'Créer le planning ${moisAvecDe(mois)}';

  /// « d'octobre » et non « de octobre ». Trois mois commencent par une
  /// voyelle — avril, août, octobre — et une élision ratée se lit à voix haute
  /// dans la tête de celui qui lit.
  static String moisAvecDe(String mois) =>
      mois.isNotEmpty && 'aeiouyâàéèêîôû'.contains(mois[0].toLowerCase())
      ? 'd\'$mois'
      : 'de $mois';

  /// Ce que le bouton va faire, écrit avant qu'on l'actionne. Le nombre est
  /// celui du mois affiché : 56, 60 ou 62, jamais un 62 supposé.
  ///
  /// **Une ligne, pas trois** (chantier 061c) : l'explication vit sous le
  /// bouton, dans la zone du planning du bandeau, et trois lignes de texte y
  /// dépliaient le bloc. Les deux faits qui comptent restent — combien de
  /// créneaux, et d'où vient leur effectif.
  static String planningCreerDetail(int creneaux) =>
      '$creneaux créneaux, à l\'effectif requis de tes réglages.';

  static String planningCreeTexte(String mois, int creneaux) =>
      'Planning ${moisAvecDe(mois)} créé : $creneaux créneaux.';

  // -------------------------------------------------------------------
  // Le compte et le bandeau du mois (ticket 061b)
  // -------------------------------------------------------------------

  static const String compteOuvrir = 'Mon profil';

  /// « Mon profil — Marie L. » : sur un poste de caserne partagé, la première
  /// question est de savoir qui est connecté.
  static String compteOuvrirNomme(String nom) => '$compteOuvrir — $nom';

  // --- Les trois chiffres du mois ---------------------------------------

  static const String bandeauCouverts = 'Créneaux couverts';
  static const String bandeauAPourvoir = 'À pourvoir';
  static const String bandeauEnAttente = 'Réponses en attente';

  // --- La barre de répartition et sa légende ----------------------------

  /// Les quatre familles de la barre ne reprennent **pas** les mots des trois
  /// chiffres : « À pourvoir », le chiffre, compte ce qui manque de monde,
  /// d'où que cela vienne ; la barre, elle, sépare ce qui n'a jamais été
  /// pourvu de ce qu'un refus a rouvert. Deux fois le même mot dans le même
  /// bloc, pour deux comptes différents, serait un piège.
  static const String bandeauPartCouverts = 'Couverts';
  static const String bandeauPartARemplir = 'À remplir';
  static const String bandeauPartAReattribuer = 'À réattribuer';
  static const String bandeauPartNonSaisis = 'Sans astreinte requise';

  /// Ce que la légende annonce : « Couverts : 48 créneaux sur 62 ». La barre,
  /// elle, ne dit rien — une longueur n'est pas un état.
  static String bandeauPartSemantique(String libelle, int n, int total) =>
      '$libelle : $n créneau${n > 1 ? 'x' : ''} sur $total';

  // --- La ligne des créneaux --------------------------------------------

  static const String planningLigneCreneaux = 'Créneaux';
  static const String planningAPourvoir = 'À pourvoir';
  static const String planningPourvu = 'Pourvu';
  static const String planningSurPourvu = 'Sur-pourvu';

  /// « 0/1 ». Au-delà de 9 — impossible dans une caserne — le nombre est
  /// tronqué plutôt que de déborder sa case de 28 px.
  static String planningFraction(int pourvus, int requis) =>
      '${_chiffreCase(pourvus)}/${_chiffreCase(requis)}';

  static String _chiffreCase(int valeur) => valeur > 9 ? '9+' : '$valeur';

  /// « 2 attribués sur 1 requis ».
  static String planningCouvertureCompte(int pourvus, int requis) =>
      '$pourvus attribué${pourvus > 1 ? 's' : ''} sur $requis requis';

  static String planningCouvertureSemantique({
    required String jourEtDate,
    required String creneau,
    required int pourvus,
    required int requis,
    required String etat,
  }) =>
      '$jourEtDate, ${creneau.toLowerCase()} : '
      '${planningCouvertureCompte(pourvus, requis)}, ${etat.toLowerCase()}';

  static const String planningCouvertureAction =
      'Appuie pour voir les candidats';

  // --- Le panneau du créneau --------------------------------------------

  static const String planningPanneauFermer = 'Fermer le panneau du créneau';
  static const String planningEffectifRequis = 'Effectif requis';
  static const String planningEffectifDetail = 'Ne change que ce créneau.';
  static const String planningEffectifMoins = 'Diminuer l\'effectif requis';
  static const String planningEffectifPlus = 'Augmenter l\'effectif requis';
  static const String planningEffectifMinimum =
      'Zéro : aucune astreinte requise ce créneau.';
  static const String planningEffectifMaximum =
      'Cinquante au maximum, comme dans les réglages de la caserne.';

  static String planningSectionAttribues(int n) => 'Attribués ($n)';
  static String planningSectionDisponibles(int n) => 'Disponibles ($n)';
  static String planningSectionNonDisponibles(int n) => 'Non disponibles ($n)';

  static const String planningAucunAttribue = 'Personne pour l\'instant.';
  static const String planningAttribuer = 'Attribuer';
  static const String planningAttribuerQuandMeme = 'Attribuer quand même';
  static const String planningRetirer = 'Retirer';
  static const String planningRetireeTexte = 'Attribution retirée';
  static const String planningAnnulerRetrait = 'Annuler';
  static const String planningQuotaAtteint = 'Quota atteint';
  static const String planningQuotaDepasse = 'Quota dépassé';

  /// La ligne de mesures d'un candidat : « 2/3 astr. · 1/1 w-e · 4 sur 3 mois ».
  /// L'absence de barre de fraction dit l'illimité, comme dans la matrice.
  static String planningCandidatMesures({
    required int? astreintesRestantes,
    required int? maxAstreintes,
    required int astreintes,
    required int? weekendsRestants,
    required int? maxWeekends,
    required int unitesWeekend,
    required int accepteesPrecedentes,
  }) => <String>[
    maxAstreintes == null
        ? '$astreintes astr.'
        : '${astreintesRestantes ?? 0}/$maxAstreintes astr.',
    maxWeekends == null
        ? '$unitesWeekend w-e'
        : '${weekendsRestants ?? 0}/$maxWeekends w-e',
    '$accepteesPrecedentes sur 3 mois',
  ].join(' · ');

  static const String planningAucunDisponibleTitre =
      'Personne n\'est disponible';
  static const String planningAucunDisponibleTexte =
      'Aucun pompier ne s\'est déclaré disponible sur ce créneau.';
  static const String planningVoirNonDisponibles = 'Voir les non disponibles';

  // --- Attribuer hors disponibilité --------------------------------------

  static const String planningHorsDispoTitre =
      'Attribuer hors des disponibilités';

  /// Ne pas avoir répondu n'est pas avoir dit non : les deux phrases ne se
  /// confondent jamais. C'est le mécanisme central du produit.
  static String planningHorsDispoTexte({
    required String membre,
    required String jourEtDate,
    required String creneau,
    required bool absent,
  }) =>
      '$membre ${absent ? 's\'est déclaré absent' : 'n\'a pas saisi ses '
                'disponibilités'} '
      '$jourEtDate, ${creneau.toLowerCase()}. La proposition lui parviendra '
      'comme aux autres, et pourra être refusée. Cette attribution est '
      'enregistrée à ton nom dans l\'historique de la caserne.';

  static const String planningHorsDispoValider = 'Attribuer quand même';
  static const String planningHorsDispoAnnuler = 'Annuler';

  // --- Le temps réel ------------------------------------------------------

  static const String planningDirect = 'Direct';
  static const String planningDirectDetail =
      'Les modifications des autres administrateurs arrivent à l\'écran.';
  static const String planningDirectInterrompu = 'Direct interrompu';
  static const String planningDirectInterrompuDetail =
      'Les modifications des autres administrateurs n\'arrivent plus. '
      'Rafraîchis pour voir l\'état réel.';

  /// « Modifié à l'instant par Marie L. » — sans second point : un nom
  /// affiché finit souvent par une initiale abrégée.
  static String planningModifieDistant(String qui) =>
      'Modifié à l\'instant par ${qui.endsWith('.') ? qui : '$qui.'}';
  static const String planningModifieDistantAnonyme =
      'Modifié à l\'instant par un autre administrateur.';

  // --- Erreurs et raisons -------------------------------------------------

  static const String planningErreurTexte =
      'Impossible de charger le planning.';
  static const String planningDejaAttribue =
      'Ce membre est déjà attribué à ce créneau.';
  static const String planningPublieDetail =
      'Planning publié : la modification d\'un créneau publié arrive avec la '
      'publication.';
  static const String planningSaisieHorsLigne =
      'Hors ligne : l\'attribution reprendra au retour du réseau.';
  static const String planningSaisieTactile =
      'Ouvre un créneau depuis la vue par jour pour l\'attribuer.';

  // -------------------------------------------------------------------
  // Proposition automatique de remplissage (ticket 018)
  // -------------------------------------------------------------------

  static const String proposerAction = 'Proposer automatiquement';

  static String proposerTitre(String mois) =>
      'Proposition pour ${moisAvecDe(mois)}';

  static const String proposerFermer = 'Fermer la proposition';
  static const String proposerAnnuler = 'Annuler';

  /// Le bouton porte le compte : appliquer 48 attributions n'est pas en
  /// appliquer 3.
  static String proposerConfirmer(int attributions) => attributions == 1
      ? 'Appliquer 1 attribution'
      : 'Appliquer $attributions attributions';

  static const String proposerCreneauxRemplis = 'créneaux remplis';
  static const String proposerAstreintes = 'astreintes posées';
  static const String proposerDecouverts = 'sans candidat';

  /// Ce que la machine s'interdit, dit une fois, à l'endroit où on le croit.
  static const String proposerPromesse =
      'Les créneaux que tu as remplis toi-même ne sont pas touchés. Personne '
      'n\'est désigné hors de ses disponibilités, et personne ne dépasse le '
      'nombre d\'astreintes qu\'il a accepté.';

  static String proposerSansCandidat(int n) => n == 1
      ? '1 créneau reste sans candidat'
      : '$n créneaux restent sans candidat';

  /// Ce n'est pas une panne : c'est l'état des disponibilités de la caserne.
  static const String proposerSansCandidatDetail =
      'Personne ne s\'est déclaré disponible, ou tous ceux qui l\'étaient ont '
      'fait leur compte d\'astreintes. Ces créneaux se remplissent à la main.';

  static const String proposerRienATrouver =
      'Aucun créneau à pourvoir ne trouve de candidat disponible.';

  /// Ce qui s'est réellement passé, pas ce qui était prévu.
  static String proposerFait(int posees, int decouverts) {
    final creneaux = decouverts == 0
        ? ''
        : decouverts == 1
        ? ', 1 créneau reste sans candidat'
        : ', $decouverts créneaux restent sans candidat';
    return posees == 1
        ? '1 astreinte posée$creneaux.'
        : '$posees astreintes posées$creneaux.';
  }

  /// Des lignes ont été écartées par la base : l'autre administrateur est passé
  /// avant. Le dire vaut mieux que d'annoncer un chiffre faux.
  static String proposerFaitPartiel(int posees, int ecartees) =>
      '$posees astreintes posées. '
      '${ecartees == 1 ? '1 créneau a été pris' : '$ecartees créneaux ont été pris'} '
      'entre-temps.';

  static const String proposerRienFait =
      'Aucune attribution n\'a été posée : tout avait déjà été repris.';

  static const String proposerErreur =
      'La proposition n\'a pas abouti. Le planning n\'a pas bougé.';

  static const String proposerHorsLigne =
      'Hors ligne : la proposition a besoin du réseau pour s\'appliquer.';

  // -------------------------------------------------------------------
  // Publication et suivi des réponses (ticket 019)
  // -------------------------------------------------------------------

  // --- Le bouton « Publier » et son récapitulatif -----------------------

  static const String publierAction = 'Publier le planning';

  /// Ce que le bouton va faire, avant qu'on l'actionne. Le nombre compte les
  /// **membres** : c'est le nombre de téléphones qui vont sonner.
  /// **Une ligne, à côté du bouton** (chantier 061c) : l'explication vit
  /// désormais dans une rangée de 48 points, où trois lignes de texte
  /// dépliaient la barre. Le nombre de téléphones reste ; la phrase qui
  /// l'enrobait est partie.
  static String publierDetail(int membres) => switch (membres) {
    0 => 'Personne n\'est attribué : aucune notification.',
    1 => '1 pompier sera prévenu.',
    _ => '$membres pompiers seront prévenus.',
  };

  static String publierTitre(String mois) =>
      'Publier le planning ${moisAvecDe(mois)}';

  static const String publierConfirmer = 'Publier et notifier';
  static const String publierAnnuler = 'Annuler';
  static const String publierFermer = 'Fermer le récapitulatif';

  static const String publierCreneaux = 'créneaux';
  static const String publierPompiers = 'pompiers';
  static const String publierAstreintes = 'astreintes';

  /// La promesse du ticket, écrite avant qu'on la croie.
  static const String publierPromesse =
      'Chaque pompier recevra une seule notification listant tous ses '
      'créneaux.';

  static const String publierAVerifier = 'À vérifier avant d\'envoyer';

  static const String publierSansReserve =
      'Tous les créneaux sont pourvus, aucun quota dépassé, aucune '
      'attribution forcée.';

  static String publierNonPourvus(int n) => n == 1
      ? '1 créneau n\'est pourvu par personne'
      : '$n créneaux ne sont pourvus par personne';

  static String publierHorsQuota(int n) => n == 1
      ? '1 pompier au-delà de son quota'
      : '$n pompiers au-delà de leur quota';

  static String publierHorsDispo(int n) => n == 1
      ? '1 pompier attribué hors disponibilité'
      : '$n pompiers attribués hors disponibilité';

  /// « Marie L. — 5 astreintes pour un plafond de 4 ».
  static String publierQuotaLigne({
    required String membre,
    required int astreintes,
    required int plafond,
  }) => '$membre — $astreintes astreintes pour un plafond de $plafond';

  /// « Marie L. — sam. 11 nuit, mar. 14 jour ».
  static String publierMembreEtCreneaux(String membre, String creneaux) =>
      '$membre — $creneaux';

  /// Au-delà de six, la liste s'arrête et dit combien elle tait.
  static String publierEtAutres(int n) =>
      n == 1 ? 'et 1 autre' : 'et $n autres';

  static const String publierEnCours = 'Publication…';

  static String publiePourMois(String mois, int membres) => membres == 0
      ? 'Planning ${moisAvecDe(mois)} publié.'
      : 'Planning ${moisAvecDe(mois)} publié : '
            '$membres pompier${membres > 1 ? 's' : ''} '
            'notifié${membres > 1 ? 's' : ''}.';

  /// **L'envoi a échoué, la publication non.** Le planning est parti en base,
  /// mais les téléphones n'ont pas sonné : le dire est la seule chose à faire,
  /// parce qu'un chef qui croit avoir prévenu tout le monde n'ira pas relancer.
  static String publiePourMoisSansEnvoi(String mois) =>
      'Planning ${moisAvecDe(mois)} publié, mais les notifications ne sont '
      'pas parties. Personne n\'a été prévenu.';

  static const String publierDejaFait = 'Ce planning a déjà été publié.';
  static const String publierErreur =
      'La publication n\'a pas abouti. Le planning n\'a pas bougé.';
  static const String publierHorsLigne =
      'Hors ligne : la publication part des pompiers, elle a besoin du '
      'réseau.';
  static const String publierReserveAdmin =
      'Il faut être administrateur de la caserne pour publier son planning.';

  // --- L'écran de suivi ---------------------------------------------------

  static const String suiviTitre = 'Suivi du planning';
  static const String suiviVersSuivi = 'Suivi du planning';
  static const String suiviVersConstruction = 'Ouvrir la construction';

  static const String suiviProgressionTitre = 'Progression';

  /// « 42 réponses sur 70 attendues ». La barre ne dit rien de plus.
  static String suiviReponses(int reponses, int attendues) =>
      '$reponses réponse${reponses > 1 ? 's' : ''} sur $attendues '
      'attendue${attendues > 1 ? 's' : ''}';

  static const String suiviAucuneAttribution =
      'Aucune attribution : il n\'y a rien à attendre.';

  static const String suiviEnAttente = 'en attente';
  static const String suiviAcceptees = 'acceptées';
  static const String suiviRefusees = 'refusées';
  static const String suiviCreneauxPourvus = 'créneaux pourvus';

  static String suiviRetardatairesTitre(int n) => 'Retardataires ($n)';

  static String suiviRetardatairesDetail(int heures) =>
      'Sans réponse depuis plus de $heures h.';

  /// « 2 créneaux · proposé il y a 4 jours ».
  static String suiviRetardataireLigne({
    required int creneaux,
    required String depuis,
  }) => '$creneaux créneau${creneaux > 1 ? 'x' : ''} · proposé $depuis';

  static String suiviRelanceLe(String depuis) => 'relancé $depuis';

  static const String suiviRelancer = 'Relancer maintenant';

  /// Ticket 030 : pourquoi les gestes du suivi sont inertes.
  static const String suiviSuspendue =
      'Abonnement suspendu : la caserne est en lecture seule, le planning ne '
      'bouge plus.';
  static const String suiviPrevenir = 'Prévenir maintenant';

  /// La bannière qui reste tant que l'envoi manqué n'est pas rattrapé.
  static const String suiviEnvoiManque =
      'Les notifications de publication ne sont pas parties : les pompiers '
      'attribués n\'ont pas été prévenus.';

  static String suiviRattrapageFait(int membres) => membres == 0
      ? 'Plus personne n\'attend de notification.'
      : '$membres pompier${membres > 1 ? 's' : ''} '
            'prévenu${membres > 1 ? 's' : ''}.';
  static const String suiviRelanceEnCours = 'Relance…';

  static String suiviRelanceFaite(int membres) => membres == 0
      ? 'Personne à relancer.'
      : '$membres pompier${membres > 1 ? 's' : ''} '
            'relancé${membres > 1 ? 's' : ''}.';

  static const String suiviRelanceDejaFaite =
      'Ces pompiers ont déjà été relancés dans l\'heure.';
  static const String suiviRelanceErreur =
      'La relance n\'a pas abouti. Réessaie dans un instant.';
  static const String suiviRelanceHorsLigne =
      'Hors ligne : la relance a besoin du réseau.';
  static const String suiviRelanceArchive =
      'Ce planning est archivé : plus personne n\'a de réponse à donner.';

  // --- Les filtres et la liste des créneaux -------------------------------

  static const String suiviFiltreTous = 'Tous';
  static const String suiviFiltreAttente = 'En attente';
  static const String suiviFiltreAcceptes = 'Acceptés';
  static const String suiviFiltreRefuses = 'Refusés';
  static const String suiviFiltreNonPourvus = 'Non pourvus';

  static String suiviFiltreVide(String filtre) =>
      'Aucun créneau dans « $filtre » pour ce mois.';
  static const String suiviToutAfficher = 'Tout afficher';
  static String suiviFiltreDesactive(String filtre) =>
      'Aucun créneau « ${filtre.toLowerCase()} » ce mois-ci.';

  static const String suiviPersonne = 'personne';

  /// « en attente depuis 3 j », « accepté hier », « refusé il y a 2 h ».
  static String suiviEtatDepuis(String etat, String depuis) => '$etat $depuis';

  /// Le motif d'un refus, entre guillemets français.
  static String suiviMotifRefus(String motif) => '« $motif »';

  static String suiviLigneSemantique({
    required String jourEtDate,
    required String creneau,
    required int pourvus,
    required int requis,
    required String detail,
  }) =>
      '$jourEtDate, ${creneau.toLowerCase()} : '
      '${planningCouvertureCompte(pourvus, requis)}. $detail';

  // --- Les états de l'écran ----------------------------------------------

  static String suiviValideLe(String date) =>
      'Planning validé le $date. Tout le monde peut le voir.';

  static const String suiviBrouillonTitre =
      'Le planning est encore en '
      'brouillon';
  static const String suiviBrouillonTexte =
      'Rien n\'est parti : il n\'y a pas encore de réponse à suivre.';

  static const String suiviAbsentTitre = 'Rien à suivre pour ce mois';
  static const String suiviAbsentTexte =
      'Le planning de ce mois n\'a pas encore été construit.';
  static const String suiviAbsentAction = 'Construire le planning';

  static const String suiviErreurTexte =
      'Impossible de charger le suivi du planning.';
  static const String suiviReserveAdmin =
      'Le suivi du planning est réservé aux administrateurs de la caserne.';

  // -------------------------------------------------------------------
  // Réattribution d'un créneau refusé (ticket 020)
  // -------------------------------------------------------------------

  // --- L'action sur la ligne du suivi -----------------------------------

  static const String reattribuerAction = 'Réattribuer';
  static const String pourvoirAction = 'Pourvoir';

  /// L'étiquette annoncée au lecteur d'écran : **la personne et le créneau**,
  /// jamais « Réattribuer » seul. Une liste de douze boutons homonymes est
  /// inutilisable.
  static String reattribuerSemantique({
    required String jourEtDate,
    required String creneau,
  }) => 'Réattribuer le créneau $creneau du $jourEtDate';

  static String pourvoirSemantique({
    required String jourEtDate,
    required String creneau,
  }) => 'Pourvoir le créneau $creneau du $jourEtDate';

  /// « remplacé par Chloé C. » — l'historique montre la sortie **et** l'entrée.
  static String suiviRemplacePar(String qui) => 'remplacé par $qui';

  // --- Le bandeau du panneau -------------------------------------------

  static const String reattributionBandeau =
      'Planning publié : la personne choisie sera notifiée tout de suite.';

  static String reattributionBandeauRefus(String qui) =>
      '$qui a refusé ce créneau. La personne choisie sera notifiée tout de '
      'suite.';

  /// Une annulation n'est pas un refus : c'est la caserne qui a retiré la
  /// garde, et le dire autrement serait mettre un refus sur le dos de
  /// quelqu'un qui n'a rien refusé.
  static String reattributionBandeauAnnulation(String qui) =>
      'L\'astreinte de $qui a été annulée. La personne choisie sera notifiée '
      'tout de suite.';

  // --- La confirmation --------------------------------------------------

  static const String reattribuerTitre = 'Réattribuer ce créneau';

  static String reattribuerTexte({
    required String membre,
    required String jourEtDate,
    required String creneau,
  }) =>
      '$membre recevra une notification pour le $jourEtDate, $creneau. '
      'Personne d\'autre n\'est prévenu.';

  /// L'avertissement de disponibilité, dans la **même** feuille : une
  /// confirmation par sujet apprendrait à cliquer sans lire.
  static String reattribuerHorsDispo(String membre) =>
      '$membre s\'est déclaré indisponible ce jour-là.';

  static String reattribuerRemplace(String qui) =>
      'L\'astreinte de $qui est annulée et $qui en est prévenu.';

  static const String reattribuerConfirmer = 'Réattribuer et notifier';
  static const String reattribuerAnnuler = 'Annuler';

  static String reattribuerFaite(String membre) => '$membre est prévenu.';

  static String reattribuerFaiteEtAncien(String membre, String ancien) =>
      '$membre est prévenu, $ancien aussi.';

  // --- L'annulation d'une astreinte -------------------------------------

  static const String annulerAstreinteAction = 'Annuler';

  static String annulerAstreinteSemantique(String membre) =>
      'Annuler l\'astreinte de $membre';

  static const String annulerAstreinteTitre = 'Annuler cette astreinte';

  static String annulerAstreinteTexte({
    required String membre,
    required String jourEtDate,
    required String creneau,
  }) =>
      '$membre sera prévenu que son astreinte du $jourEtDate, $creneau, est '
      'annulée.';

  /// La proposition n'avait pas encore de réponse : rien n'était acquis, donc
  /// personne n'est prévenu. L'écran le dit plutôt que de le taire.
  static String annulerPropositionTexte({
    required String membre,
    required String jourEtDate,
    required String creneau,
  }) =>
      'La proposition faite à $membre pour le $jourEtDate, $creneau, sera '
      'retirée. $membre n\'a pas encore répondu : il n\'est pas prévenu.';

  static const String annulerMotifLibelle = 'Motif (facultatif)';
  static const String annulerMotifAide =
      'Il part avec la notification. « Annulée » sans raison, c\'est un coup '
      'de téléphone de plus.';
  static const String annulerMotifExemple = 'Manœuvre annulée';

  static const String annulerConfirmer = 'Annuler l\'astreinte';
  static const String annulerRenoncer = 'Revenir';

  static String annulerFaite(String membre) =>
      'Astreinte annulée. $membre est prévenu.';

  static String annulerFaiteSansEnvoi(String membre) =>
      'Proposition retirée. $membre n\'avait pas répondu : rien n\'est parti.';

  // --- Le panneau chargé depuis le suivi --------------------------------

  static const String reattributionChargement = 'Chargement des candidats';

  // --- Les refus ---------------------------------------------------------

  static const String reattribuerHorsLigne =
      'Sans réseau, impossible de réattribuer : la notification partirait trop '
      'tard, pour un créneau peut-être déjà pourvu.';

  static const String reattribuerBrouillon =
      'Ce planning est encore en brouillon : les attributions s\'y posent et '
      's\'y retirent directement.';

  static const String reattribuerArchive =
      'Ce planning est archivé : le mois est passé.';

  static const String reattribuerDejaAttribue =
      'Ce pompier tient déjà ce créneau.';

  /// **Une réattribution remplace, elle n'ajoute pas.** Renforcer un créneau
  /// publié se dit en clair : on augmente son effectif requis, et le panneau le
  /// propose juste au-dessus de la liste des candidats.
  static const String reattribuerCreneauPourvu =
      'Ce créneau est déjà pourvu. Augmente son effectif requis pour y ajouter '
      'quelqu\'un.';

  static const String reattribuerDejaRemplacee =
      'Cette attribution a déjà été remplacée. L\'écran se remet à jour.';

  static const String reattribuerMembreInactif =
      'Ce pompier n\'est plus membre actif de la caserne.';

  static const String reattribuerErreur =
      'La réattribution n\'a pas abouti. Le planning n\'a pas bougé.';

  static const String annulerErreur =
      'L\'annulation n\'a pas abouti. L\'astreinte n\'a pas bougé.';

  // -------------------------------------------------------------------
  // Les propositions du membre (ticket 021)
  // -------------------------------------------------------------------

  static const String propositionsTitre = 'Propositions';
  static const String propositionsRafraichir = 'Rafraîchir la liste';

  /// Le sous-titre d'un en-tête de mois : « 3 propositions ».
  static String propositionsCompte(int n) =>
      n <= 1 ? '$n proposition' : '$n propositions';

  // --- La ligne -----------------------------------------------------------

  static const String propositionsAccepter = 'Accepter';
  static const String propositionsRefuser = 'Refuser';

  /// Chaque bouton nomme **son** créneau : un écran qui annonce quatre fois
  /// « Accepter » est un écran inutilisable au lecteur d'écran.
  static String propositionsAccepterCreneau(String creneau) =>
      'Accepter $creneau';
  static String propositionsRefuserCreneau(String creneau) =>
      'Refuser $creneau';

  /// « proposé il y a 2 h », « proposé hier ».
  ///
  /// L'ancienneté arrive avec une capitale quand elle vaut « Hier » : elle est
  /// écrite pour commencer une phrase, pas pour la continuer.
  static String propositionsProposeeDepuis(String depuis) =>
      'proposé ${_enMinuscule(depuis)}';

  /// Abaisse la première lettre d'un fragment qui entre dans une phrase.
  /// Les dates courtes (« 15 sept. ») n'en sont pas affectées.
  static String _enMinuscule(String texte) =>
      texte.isEmpty ? texte : '${texte[0].toLowerCase()}${texte.substring(1)}';

  /// « relancé hier », ajouté après le précédent quand la base a compté une
  /// relance. Le séparateur est un point médian, comme partout ailleurs.
  static String propositionsRelanceDepuis(String depuis) =>
      'relancé ${_enMinuscule(depuis)}';

  /// La phrase complète d'une ligne : « Samedi 12 octobre, nuit. Proposé il y
  /// a 2 h. »
  static String propositionsLigneSemantique({
    required String jourEtDate,
    required String creneau,
    required String detail,
  }) {
    final debut = '$jourEtDate, ${creneau.toLowerCase()}.';
    return detail.isEmpty
        ? debut
        : '$debut ${detail[0].toUpperCase()}${detail.substring(1)}.';
  }

  // --- Les réponses -------------------------------------------------------

  /// « Samedi 12 octobre, nuit : acceptée. »
  static String propositionsAcceptee(String creneau) => '$creneau : acceptée.';

  static String propositionsRefusee(String creneau) =>
      '$creneau : refusée. Ton chef de centre est prévenu.';

  /// Le créneau n'est plus proposé : annulé ou confié à quelqu'un d'autre
  /// pendant que le pompier lisait sa notification. **Un fait, pas une
  /// panne** : bannière d'information, jamais de rouge.
  static const String propositionsDisparue =
      'Ce créneau ne t\'est plus proposé.';

  /// La seconde ligne de la bannière. Deux lignes au plus : le créneau
  /// d'abord — c'est ce qu'on cherche — puis la raison en trois mots.
  static String propositionsDisparueDetail(String creneau) {
    final debut = '${creneau[0].toUpperCase()}${creneau.substring(1)}';
    return '$debut : ton chef de centre l\'a repris ou confié à '
        'quelqu\'un d\'autre.';
  }

  static const String propositionsDisparueFermer = 'Masquer ce message';

  static const String propositionsEchecTitre = 'Ta réponse n\'est pas partie.';

  /// Le mois s'est validé sur cette réponse : c'était la dernière qu'il
  /// attendait. Le seul endroit où cet écran parle du planning entier.
  static String propositionsPlanningValide(String mois) =>
      'Planning ${moisAvecDe(mois)} validé : tout le monde peut le voir '
      'maintenant.';
  static const String propositionsPlanningValideFermer = 'Masquer ce message';

  // --- Les empêchements ---------------------------------------------------

  static const String propositionsHorsLigneRaison =
      'Une réponse a besoin du réseau. Elle repartira dès qu\'il revient.';
  static const String propositionsLectureSeuleRaison =
      'Caserne suspendue : les réponses sont bloquées. Contacte ton chef de '
      'centre.';
  static const String propositionsErreurTexte =
      'Impossible de charger tes propositions.';
  static const String propositionsVideAction = 'Voir mon mois';

  // --- La feuille de refus ------------------------------------------------

  /// Le titre dit ce que la feuille va faire, jamais « Êtes-vous sûr ? ».
  static String refusTitre(String creneau) => 'Refuser $creneau';

  static const String refusMotifLibelle = 'Motif (facultatif)';
  static const String refusMotifInvite = 'ex. en formation ce week-end';
  static const String refusMotifAide =
      'Ton chef de centre le verra en cherchant quelqu\'un d\'autre.';

  /// Le bouton qui recule **nomme l'action**, il ne dit pas « Annuler ».
  static const String refusGarder = 'Garder le créneau';
  static const String refusConfirmer = 'Refuser le créneau';

  /// Un refus ne se reprend pas : `declined` est terminal
  /// (`docs/WORKFLOWS.md § 3`). Le dire avant vaut mieux que de proposer une
  /// annulation qui échouerait.
  static const String refusDefinitif =
      'Un refus ne se reprend pas. Ton chef de centre proposera le créneau à '
      'quelqu\'un d\'autre.';

  /// La limite du motif : court par construction, parce qu'il se lit dans une
  /// liste de trente lignes.
  static const int refusMotifLongueurMax = 120;

  // -------------------------------------------------------------------
  // Mes astreintes (ticket 027)
  // -------------------------------------------------------------------

  static const String astreintesTitre = 'Mes astreintes';
  static const String astreintesRafraichir = 'Rafraîchir mes astreintes';

  /// Le sous-titre d'un en-tête de mois : « 2 astreintes ».
  static String astreintesCompte(int n) =>
      n <= 1 ? '$n astreinte' : '$n astreintes';

  // --- La bascule de vue --------------------------------------------------

  static const String astreintesVueLabel = 'Vue de mes astreintes';
  static const String astreintesVueListe = 'Liste';

  /// **« Mois » et non « Calendrier » depuis le ticket 064** : la deuxième
  /// destination de la barre s'appelle « Calendrier », et deux fois le même
  /// mot sur un même écran pour deux gestes différents — changer de vue, ou
  /// changer d'écran — est un piège, avec des gants et au soleil. La forme,
  /// elle, ne change pas : c'est bien la grille du mois.
  static const String astreintesVueCalendrier = 'Mois';

  /// Au-delà de ×1,6, le calendrier **change de forme** plutôt que de rogner
  /// son texte (`DESIGN.md § Typography — Named Rules`). Un bouton désactivé
  /// qui dit pourquoi vaut mieux qu'un bouton sélectionné qui montre autre
  /// chose que ce qu'il nomme.
  static const String astreintesCalendrierTropGrand =
      'Le calendrier ne tient pas à cette taille de texte. La liste dit la '
      'même chose.';

  // --- La ligne et le créneau ---------------------------------------------

  /// « 19:00 → 07:00 ». Les heures viennent des paramètres de la caserne
  /// (`docs/SCHEMA.md § 2.1`), jamais d'un 7 h – 19 h écrit en dur.
  static String astreintesIntervalle(String debut, String fin) =>
      '$debut → $fin';

  /// La même chose, dite : la flèche ne se lit pas à voix haute.
  static String astreintesIntervalleDit(String debut, String fin) =>
      'de $debut à $fin';

  /// La phrase complète d'une ligne : « Samedi 12 octobre, nuit, de 19:00 à
  /// 07:00. Voir le détail. »
  static String astreintesLigneSemantique({
    required String jourEtDate,
    required String creneau,
    required String heures,
  }) => '$jourEtDate, ${creneau.toLowerCase()}, $heures. $astreintesVoirDetail';

  static const String astreintesVoirDetail = 'Voir le détail.';

  // --- Le repli des passées -----------------------------------------------

  static String astreintesPassees(int n) => 'Astreintes passées ($n)';
  static const String astreintesPasseesAfficher =
      'Afficher les astreintes passées';
  static const String astreintesPasseesMasquer =
      'Masquer les astreintes passées';

  // --- Le calendrier ------------------------------------------------------

  static const String astreintesMoisPrecedent = 'Mois précédent';
  static const String astreintesMoisSuivant = 'Mois suivant';
  static const String astreintesMoisAvantDebut =
      'Tu n\'as pas d\'astreinte avant ce mois.';
  static const String astreintesMoisApresFin =
      'Tu n\'as pas d\'astreinte après ce mois.';

  /// « jour », « nuit », ou « jour et nuit » — ce que porte une case du
  /// calendrier.
  static String astreintesCreneauxDuJour(List<String> creneaux) =>
      creneaux.map(_enMinuscule).join(' et ');

  /// La phrase d'une case marquée : « Samedi 12 octobre, jour et nuit. Voir le
  /// détail. »
  static String astreintesJourSemantique({
    required String jourEtDate,
    required String creneaux,
  }) => '$jourEtDate, $creneaux. $astreintesVoirDetail';

  /// La phrase d'une case sans astreinte. Elle n'est pas actionnable, mais
  /// elle reste lue : un calendrier où les jours vides sont muets ne se
  /// parcourt pas au lecteur d'écran.
  static String astreintesJourLibre(String jourEtDate) =>
      '$jourEtDate, pas d\'astreinte';

  // --- Le détail ----------------------------------------------------------

  /// « Samedi 12 octobre 2026 ». Avec l'année : la feuille s'ouvre depuis un
  /// calendrier où l'année n'est plus à l'écran.
  static String astreintesDetailTitre(String jourEtDate, int annee) =>
      '${jourEtDate[0].toUpperCase()}${jourEtDate.substring(1)} $annee';

  static const String astreintesEquipiersTitre = 'Avec toi sur ce créneau';

  /// La RLS ne rend les attributions des autres qu'une fois le planning
  /// validé (`docs/SCHEMA.md § 4`). L'écran dit pourquoi, au lieu de montrer
  /// une liste vide qui se lirait « personne d'autre n'est de garde ».
  static const String astreintesEquipiersAttente =
      'Les autres noms s\'afficheront quand ton chef de centre aura validé le '
      'planning.';

  /// Une information, pas une absence.
  static const String astreintesSeul = 'Tu es seul sur ce créneau.';

  static const String astreintesFermer = 'Fermer';

  // --- Fraîcheur, hors ligne, erreurs -------------------------------------

  /// « Dernière mise à jour : il y a 2 h. » Le deux-points tient aussi bien un
  /// relatif qu'une date (« 15 sept. »), là où « mise à jour 15 sept. » ne se
  /// lirait pas.
  static String astreintesFraicheur(String depuis) =>
      'Dernière mise à jour : ${_enMinuscule(depuis)}.';

  /// Hors ligne, cet écran ne promet **pas** d'envoyer des modifications : il
  /// ne fait que lire. Ce qu'il doit dire, c'est l'âge de ce qu'on lit.
  static const String astreintesHorsLigne = 'Hors ligne.';

  static const String astreintesNonActualisees =
      'Ces astreintes n\'ont pas pu être actualisées.';

  static const String astreintesErreurTexte =
      'Impossible de charger tes astreintes.';

  static const String astreintesVideAction = 'Voir mes propositions';

  // -------------------------------------------------------------------
  // Le planning de la caserne (ticket 023)
  // -------------------------------------------------------------------

  /// Le titre suit la portée : la barre d'application est ce qu'un lecteur
  /// d'écran annonce en arrivant, et « Mes astreintes » serait faux de ce
  /// côté-ci du sélecteur.
  static const String planningCaserneTitre = 'Planning de la caserne';

  static const String planningCaserneRafraichir =
      'Rafraîchir le planning de la caserne';

  // --- Le sélecteur de portée ---------------------------------------------

  static const String porteeLabel = 'Astreintes affichées';
  static const String porteeMoi = 'Moi';
  static const String porteeCaserne = 'La caserne';

  // --- Le sélecteur de mois -----------------------------------------------

  /// Les flèches parcourent les **plannings**, pas les mois : un mois sans
  /// planning n'est pas une destination (`design/023 § 5`).
  static const String planningCaserneMoisAvantDebut =
      'Aucun planning publié avant ce mois.';
  static const String planningCaserneMoisApresFin =
      'Aucun planning publié après ce mois.';

  // --- La règle de visibilité ---------------------------------------------

  /// Le titre du bloc d'attente. « Publié » est un état nommé du produit, que
  /// le pompier a vu passer dans sa notification. Ni « accès restreint » ni
  /// « données partielles » : rien n'est cassé et personne n'est puni.
  static const String planningCaserneAttenteTitre =
      'Planning publié, pas encore validé';

  /// Pourquoi la vue est partielle. **La phrase est obligatoire** : sans elle,
  /// une liste courte se lirait « le planning est presque vide », ce qui est
  /// faux (`design/023 § 4`).
  static const String planningCaserneAttenteTexte =
      'Tu ne vois que tes propres créneaux. Les autres noms s\'afficheront '
      'quand ton chef de centre aura validé le planning.';

  // --- Le registre --------------------------------------------------------

  /// Les noms d'un créneau, séparés par un point médian : « Marie L. · Thomas
  /// M. ». Le séparateur ne se lit pas à voix haute — la phrase annoncée est
  /// construite à part par [planningCaserneCreneauSemantique].
  static const String planningCaserneSeparateurNoms = ' · ';

  /// Comment le lecteur se nomme lui-même dans la liste des noms. En tête,
  /// marqué d'une icône pleine : trois signaux, jamais la couleur seule.
  static const String planningCaserneToi = 'Toi';

  /// Un créneau que personne ne couvre. C'est un **trou du planning**, donc une
  /// information : il ne se tait pas.
  static const String planningCaserneCreneauVide =
      'Personne n\'est d\'astreinte.';

  /// Les membres acceptés dont le nom n'a pas pu être lu — quelqu'un qui a
  /// quitté la caserne. Comptés, jamais affichés sous forme d'identifiant.
  static String planningCaserneAutres(int n) =>
      n <= 1 ? 'et 1 autre' : 'et $n autres';

  /// La phrase complète d'un créneau : « Samedi 24 octobre, nuit, de 19:00 à
  /// 07:00, avec toi et Marie L. »
  static String planningCaserneCreneauSemantique({
    required String jourEtDate,
    required String creneau,
    required String heures,
    required String personnes,
  }) => '$jourEtDate, ${creneau.toLowerCase()}, $heures, $personnes';

  /// « avec toi et Marie L. », « personne n'est d'astreinte ».
  static String planningCaserneAvec(List<String> personnes) {
    if (personnes.isEmpty) return 'personne n\'est d\'astreinte';
    if (personnes.length == 1) return 'avec ${personnes.single}';
    final debut = personnes.sublist(0, personnes.length - 1).join(', ');
    return 'avec $debut et ${personnes.last}';
  }

  // --- États vides et erreurs ---------------------------------------------

  static const String planningCaserneAucunTitre = 'Aucun planning publié';
  static const String planningCaserneAucunTexte =
      'Quand ton chef de centre publiera le planning du mois, tu le verras '
      'ici.';
  static const String planningCaserneAucunAction = 'Voir mes astreintes';

  /// Le mois listé n'a plus de planning lisible : archivé ou supprimé entre la
  /// lecture de la liste et celle du mois.
  static const String planningCaserneIntrouvableTitre =
      'Ce mois n\'a plus de planning';
  static const String planningCaserneIntrouvableTexte =
      'Il a été archivé ou retiré depuis la dernière lecture.';

  /// Planning publié, et ce pompier n'y a aucun créneau. Le bloc d'attente
  /// reste au-dessus : c'est lui qui distingue « personne n'est de garde » de
  /// « je n'ai pas le droit de voir ».
  static String planningCaserneSansMoiTitre(String mois) =>
      'Tu n\'as pas d\'astreinte en ${_enMinuscule(mois)}';
  static const String planningCaserneSansMoiTexte =
      'Les créneaux des autres apparaîtront ici dès la validation du '
      'planning.';

  /// Planning validé et pas un seul créneau demandé. Rare, mais possible : une
  /// caserne peut n'avoir besoin de personne un mois donné.
  static const String planningCaserneMoisVideTitre =
      'Aucun créneau à pourvoir ce mois-ci';
  static const String planningCaserneMoisVideTexte =
      'Le planning est validé, et la caserne ne demande personne.';

  static const String planningCaserneErreurTexte =
      'Impossible de charger le planning de la caserne.';

  static const String planningCaserneNonActualise =
      'Ce planning n\'a pas pu être actualisé.';

  // -------------------------------------------------------------------
  // Abonnement de la caserne (ticket 029)
  // -------------------------------------------------------------------

  static const String abonnementTitre = 'Abonnement';
  static const String abonnementDepuisAdmin = 'Abonnement de la caserne';
  static const String abonnementRafraichir = 'Relire l\'abonnement';
  static const String abonnementReserveAdmin =
      'Seuls les administrateurs de la caserne voient et gèrent l\'abonnement.';

  // --- Le bloc d'état -----------------------------------------------------

  static const String abonnementSectionEtat = 'État';

  static const String abonnementEtatEssai = 'Période d\'essai';
  static const String abonnementEtatActif = 'Abonnement actif';
  static const String abonnementEtatRetard = 'Paiement en retard';
  static const String abonnementEtatSuspendu = 'Caserne suspendue';
  static const String abonnementEtatResilie = 'Abonnement résilié';

  /// « Gratuite jusqu'au 20 novembre 2026 — 60 jours. »
  static String abonnementEssaiJusquau(String date, int jours) =>
      'Gratuite jusqu\'au $date — ${abonnementJours(jours)}.';

  static String abonnementJours(int n) =>
      n <= 1 ? '$n jour restant' : '$n jours restants';

  /// L'essai est passé, la tâche de suspension n'a pas encore tourné.
  static String abonnementEssaiTermine(String date) => 'Terminée le $date.';

  static String abonnementProchainPaiement(String date) =>
      'Prochain paiement le $date.';

  /// Le seul état rouge de l'écran : il y a une action à faire et une échéance
  /// réelle. Il nomme la conséquence **et** la sortie.
  static String abonnementRetardEcheance(String date) =>
      'Mets ta carte à jour avant le $date, sinon la caserne passera en '
      'lecture seule.';

  static const String abonnementRetardSansDate =
      'Mets ta carte à jour pour éviter le passage en lecture seule.';

  /// Suspendu et résilié disent la même chose, parce que c'est la même chose
  /// pour la caserne : lecture seule, et rien de perdu (`docs/PRD.md § 6.6`).
  static String abonnementLectureSeuleDepuis(String date) =>
      'Lecture seule depuis le $date. Rien n\'a été supprimé.';

  static const String abonnementLectureSeule =
      'Lecture seule. Rien n\'a été supprimé.';

  /// Le badge annoncé en une phrase complète, jamais « trialing ».
  static String abonnementEtatSemantique(String statut, String detail) =>
      detail.isEmpty ? statut : '$statut. $detail';

  // --- Le bloc des formules -----------------------------------------------

  static const String abonnementSectionFormules = 'Formules';

  static const String abonnementFormuleMensuelle = 'Mensuel';
  static const String abonnementFormuleAnnuelle = 'Annuel';

  static const String abonnementPeriodeMensuelle = 'par mois';
  static const String abonnementPeriodeAnnuelle = 'par an';

  static const String abonnementSouscrire = 'S\'abonner';

  /// « S'abonner à la formule mensuelle » — le libellé annoncé, qui nomme
  /// laquelle des deux on choisit.
  static String abonnementSouscrireSemantique(String formule) =>
      'S\'abonner à la formule ${_enMinuscule(formule)}';

  /// « Deux mois offerts. » — calculée, jamais écrite en dur.
  static String abonnementEconomie(String montant) => '$montant offerts.';

  /// Un montant en euros, sans centimes quand ils sont nuls : « 12 € »,
  /// « 12,50 € ». Les chiffres prennent le cut Mono dans l'écran.
  static String abonnementMontant(int centimes, {String devise = 'eur'}) {
    final unites = centimes ~/ 100;
    final reste = centimes % 100;
    final symbole = _symboleDevise(devise);
    return reste == 0
        ? '$unites $symbole'
        : '$unites,${reste.toString().padLeft(2, '0')} $symbole';
  }

  static String _symboleDevise(String devise) => switch (devise.toLowerCase()) {
    'eur' => '€',
    'chf' => 'CHF',
    'usd' => '\$',
    _ => devise.toUpperCase(),
  };

  // --- Le bloc de gestion --------------------------------------------------

  static const String abonnementSectionGestion = 'Gérer';
  static const String abonnementGerer = 'Gérer mon abonnement';
  static const String abonnementGererDetail =
      'Carte bancaire, factures et résiliation se règlent sur la page '
      'sécurisée de Stripe.';

  // --- Les états de bord ---------------------------------------------------

  /// Le cas d'aujourd'hui : aucun compte n'est configuré. Bannière
  /// `information`, jamais `erreur` — rien n'est cassé.
  static const String abonnementNonConfigureTexte =
      'L\'abonnement n\'est pas encore ouvert. Ta caserne fonctionne '
      'normalement pendant l\'essai.';

  static const String abonnementBientotDisponible = 'Bientôt disponible.';

  /// Nomme la sortie, et la bonne : une carte qui a expiré se change dans le
  /// portail. Ré-souscrire ferait payer deux fois la même caserne.
  static const String abonnementDejaAbonne =
      'Cette caserne a déjà un abonnement. Passe par « Gérer mon abonnement » '
      'pour changer de carte ou de formule.';

  static const String abonnementSansClient =
      'Cette caserne n\'a pas encore d\'abonnement à gérer.';

  static const String abonnementEssaiExpireTexte =
      'Ta période d\'essai est terminée. Abonne-toi pour continuer à publier '
      'des plannings.';

  // --- Le retour du prestataire -------------------------------------------

  static const String abonnementPaiementEnregistre = 'Paiement enregistré.';

  /// Le webhook n'est pas encore passé : on le dit au lieu de faire tourner un
  /// sablier.
  static const String abonnementPaiementEnAttente =
      'Paiement enregistré. Le statut se met à jour dans un instant.';

  static const String abonnementRedirection =
      'Ouverture de la page de paiement…';

  static const String abonnementOngletBloque =
      'Ton navigateur a bloqué l\'ouverture. Autorise les fenêtres pour ce '
      'site, puis réessaie.';

  // --- Les refus -----------------------------------------------------------

  static const String abonnementRefusDroits =
      'Il faut être administrateur de cette caserne pour gérer son abonnement.';

  static const String abonnementEchecPrestataire =
      'Le paiement n\'a pas pu s\'ouvrir. Réessaie dans un instant.';

  static const String abonnementEchecGenerique =
      'Impossible de lire l\'abonnement.';

  static const String abonnementErreurTexte =
      'Impossible de charger l\'abonnement de la caserne.';

  // -------------------------------------------------------------------
  // Interface de l'éditeur du produit (ticket 031)
  // -------------------------------------------------------------------
  //
  // L'écran de l'éditeur, pas celui d'un client : le vouvoiement n'y est pas
  // plus de mise qu'ailleurs, mais le ton est descriptif — on énonce des faits
  // d'exploitation, on ne guide personne.

  static const String superAdminTitre = 'Casernes';
  static const String superAdminSousTitre =
      'Toutes les casernes du service, leur état et leur abonnement.';

  static const String superAdminRelire = 'Relire la liste';

  /// L'écran s'ouvre le temps que le droit revienne, puis le routeur reprend
  /// la main. Se tromper d'URL n'est pas une faute : pas de message d'erreur.
  static const String superAdminReserveTitre = 'Écran réservé';
  static const String superAdminReserveTexte =
      'Cet écran est réservé à l\'éditeur de l\'application.';

  static const String superAdminVideTitre = 'Aucune caserne';
  static const String superAdminVideTexte =
      'Rien n\'est encore ouvert. Crée une première caserne et nomme son '
      'administrateur.';

  static const String superAdminErreurTexte =
      'Impossible de lire la liste des casernes.';

  // --- La ligne d'une caserne ---------------------------------------------

  /// « 9 membres actifs · 1 administrateur ».
  static String superAdminEffectif(int membres, int admins) =>
      '${_pluriel(membres, 'membre actif', 'membres actifs')} · '
      '${_pluriel(admins, 'administrateur', 'administrateurs')}';

  /// Le seul défaut d'une ligne qui appelle une action.
  static const String superAdminSansAdmin =
      'Aucun administrateur : personne ne peut gérer cette caserne.';

  static String superAdminInvitationsEnAttente(int n) => n <= 1
      ? 'Une invitation d\'administrateur est en attente.'
      : '$n invitations d\'administrateur sont en attente.';

  static String superAdminCreeeLe(String date) => 'Créée le $date.';

  static String superAdminDernierPlanning(String mois) =>
      'Dernier planning publié : ${_enMinuscule(mois)}.';

  static const String superAdminAucunPlanning = 'Aucun planning publié.';

  // --- Les actions ---------------------------------------------------------

  static const String superAdminCreer = 'Créer une caserne';
  static const String superAdminInviterAdmin = 'Inviter un administrateur';
  static const String superAdminSuspendre = 'Suspendre';
  static const String superAdminReactiver = 'Réactiver';
  static const String superAdminConsulter = 'Consulter les plannings';

  /// Quatre boutons « Suspendre » ne se distinguent pas à l'oreille.
  static String superAdminActionSemantique(String action, String caserne) =>
      '$action ${caserne.isEmpty ? 'cette caserne' : caserne}';

  // --- La création ---------------------------------------------------------

  static const String superAdminCreerTitre = 'Nouvelle caserne';
  static const String superAdminCreerAide =
      'L\'adresse d\'URL est dérivée du nom. L\'essai de 60 jours démarre '
      'tout de suite.';
  static const String superAdminChampNom = 'Nom de la caserne';
  static const String superAdminChampNomExemple = 'CIS Saint-Martin';
  static const String superAdminChampFuseau = 'Fuseau horaire';
  static const String superAdminCreerValider = 'Créer la caserne';

  static String superAdminCaserneCreee(String nom) => '$nom créée.';

  // --- L'invitation du premier administrateur ------------------------------

  static const String superAdminInviterTitre = 'Premier administrateur';
  static String superAdminInviterAide(String caserne) =>
      'L\'invitation part par courriel. La personne deviendra administratrice '
      'de $caserne dès qu\'elle l\'aura acceptée.';
  static const String superAdminChampEmail = 'Adresse e-mail';
  static const String superAdminChampEmailExemple = 'chef@caserne.fr';
  static const String superAdminInviterValider = 'Envoyer l\'invitation';

  /// Le compte rendu d'une invitation de l'éditeur, en une phrase.
  ///
  /// **Elle ne décide de rien.** [libelle] vient de
  /// [ResultatInvitation.libelle] et [detail] de [ResultatInvitation.detail] :
  /// la règle qui interdit d'annoncer un envoi tant que le courriel n'est pas
  /// sorti vit là-bas, une seule fois, pour les trois écrans qui invitent
  /// (ticket 048, puis 050). Écrire ici « envoyée si … » en serait une
  /// quatrième copie, et c'est leur duplication tacite qui a fait dire trois
  /// fois le même mensonge.
  ///
  /// Une seule adresse, donc le compte rendu de la caserne ne convient pas :
  /// « 1 invitation envoyée, 0 échec. » compte ce qu'on voit déjà. Il reste
  /// l'ordre de la ligne du compte rendu — le sort, puis l'adresse, puis ce
  /// qui manque —, et les quatre sorts possibles s'y disent tels quels :
  /// « Invitée », « Relancée », « Créée », « Déjà en attente ».
  static String superAdminResultatInvitation({
    required String email,
    required String libelle,
    String? detail,
  }) => detail == null ? '$libelle : $email.' : '$libelle : $email. $detail';

  static const String superAdminEchecInvitation =
      'L\'invitation n\'est pas partie. Réessaie dans un instant.';

  // --- La suspension -------------------------------------------------------

  static String superAdminSuspendreTitre(String caserne) =>
      'Suspendre $caserne ?';

  /// La promesse du produit, et elle est due ici comme au 030.
  static const String superAdminSuspendreAide =
      'Rien n\'est supprimé. La caserne passe en lecture seule : ses membres '
      'consultent, personne ne modifie.';

  static const String superAdminChampRaisonSuspension =
      'Impayé constaté hors Stripe, demande du trésorier';

  static const String superAdminSuspendreValider = 'Suspendre la caserne';

  /// Réactiver ne détruit rien et se refait d'un geste : l'écran ne demande pas
  /// de raison. La fonction en exige une — c'est elle qui part dans le journal
  /// d'audit de la caserne, et « réactivation manuelle » y est exact.
  static const String superAdminReactivationRaison =
      'Réactivation manuelle par l\'éditeur de l\'application';

  static String superAdminSuspendue(String nom) =>
      nom.isEmpty ? 'Caserne suspendue.' : '$nom suspendue.';

  static String superAdminReactivee(String nom) =>
      nom.isEmpty ? 'Caserne réactivée.' : '$nom réactivée.';

  // --- La consultation de support ------------------------------------------

  static String superAdminSupportTitre(String caserne) =>
      'Consulter les plannings de $caserne';

  /// Dit avant l'action, jamais après : la caserne verra qu'on l'a regardée.
  static const String superAdminSupportAide =
      'Cette consultation est inscrite au journal d\'audit de la caserne. '
      'Ses administrateurs la verront.';

  static const String superAdminSupportPortee =
      'Seuls l\'avancement et les dates sont rendus : aucun nom, aucune '
      'disponibilité.';

  static const String superAdminChampRaison = 'Raison';
  static const String superAdminChampRaisonExemple =
      'Ticket support 42 : le planning de mars ne se valide pas';
  static const String superAdminSupportValider = 'Ouvrir la consultation';

  static const String superAdminSupportVideTitre = 'Aucun planning';
  static const String superAdminSupportVideTexte =
      'Cette caserne n\'a construit aucun planning. Il n\'y a rien à '
      'diagnostiquer de ce côté.';

  /// « 31 créneaux · 28 acceptées, 3 en attente ».
  static String superAdminSupportCreneaux(int n) =>
      _pluriel(n, 'créneau', 'créneaux');

  static String superAdminSupportAttributions(int n) =>
      _pluriel(n, 'attribution', 'attributions');

  static String superAdminSupportPublieLe(String date) => 'Publié le $date.';
  static String superAdminSupportValideLe(String date) => 'Validé le $date.';

  // --- Les refus -----------------------------------------------------------

  static const String superAdminRefusDroits =
      'Cette action est réservée à l\'éditeur de l\'application.';

  static const String superAdminRefusNom =
      'Donne un nom de caserne, de 80 caractères au plus.';

  static const String superAdminRefusFuseau =
      'Ce fuseau horaire n\'existe pas. Exemple : Europe/Paris.';

  static const String superAdminRefusRaison =
      'Écris la raison en une phrase : elle part dans le journal d\'audit de '
      'la caserne.';

  static const String superAdminRefusCaserne =
      'Cette caserne n\'existe plus. Relis la liste.';

  static const String superAdminEchecGenerique =
      'L\'action n\'a pas abouti. Réessaie dans un instant.';

  /// « 1 membre actif », « 9 membres actifs » — l'accord fait le pluriel, pas
  /// un « (s) » entre parenthèses.
  static String _pluriel(int n, String singulier, String pluriel) =>
      '$n ${n <= 1 ? singulier : pluriel}';

  // ===================================================================
  // Profil (ticket 007)
  // ===================================================================

  static const String profilEcranTitre = 'Profil';
  static const String profilEcranIntro =
      'Ce que la caserne voit de toi, et comment l\'application te joint.';

  // --- Identité ------------------------------------------------------

  static const String profilIdentiteTitre = 'Ton identité';
  static const String profilIdentiteAide =
      'Ce nom est celui qui apparaît dans le planning de ta caserne.';
  static const String profilEmailLabel = 'Adresse de connexion';

  /// Le courriel ne se change pas ici : c'est l'identifiant du compte, pas une
  /// donnée de profil. La raison est écrite à côté du champ inerte
  /// (`DESIGN.md § Do's`).
  static const String profilEmailRaison =
      'C\'est ton identifiant de connexion. Pour en changer, demande à ton '
      'chef de centre.';
  static const String profilEnregistrerIdentite =
      'Enregistrer mes informations';
  static const String profilEnregistre = 'Informations enregistrées.';
  static const String profilLectureEchec =
      'Ton profil n\'a pas pu être lu. Vérifie ta connexion, puis réessaie.';

  // --- Caserne -------------------------------------------------------

  static const String profilCaserneTitre = 'Ta caserne';

  /// N'apparaît qu'à partir de deux appartenances actives : un contrôle à un
  /// seul choix est un contrôle de trop (`design/007-profil.md § 5.2`).
  static const String profilCaserneChoixTitre = 'Choisis ta caserne';
  static const String profilCaserneChoixAide =
      'Tout ce que l\'application affiche — ton mois, tes astreintes, le '
      'planning — suit ce choix.';

  static String profilCaserneNombre(int n) =>
      'Tu appartiens à ${_pluriel(n, 'caserne', 'casernes')}.';

  static String profilCaserneRole(String role) => 'Ton rôle : $role.';

  // --- Langue --------------------------------------------------------

  static const String profilLangueTitre = 'Langue';
  static const String profilLangueFrancais = 'Français';

  /// La raison du contrôle inerte, à côté du contrôle. Le jour où une
  /// deuxième langue arrive, la ligne devient un choix sans bouger de place.
  static const String profilLangueRaison =
      'L\'application n\'existe qu\'en français pour le moment.';

  // --- Compte --------------------------------------------------------

  static const String profilCompteTitre = 'Ton compte';

  static const String profilSupprimerCompte = 'Supprimer mon compte';

  // --- La feuille de suppression -------------------------------------

  static const String suppressionTitre = 'Supprimer ton compte';
  static const String suppressionDefinitif =
      'C\'est définitif : personne ne peut annuler cette suppression, pas même '
      'ton chef de centre.';
  static const String suppressionCeQuiPartTitre = 'Ce qui est effacé';
  static const String suppressionCeQuiPart =
      'Ton nom, ton téléphone, ton adresse, tes disponibilités saisies, tes '
      'notifications et les appareils qui les reçoivent.';
  static const String suppressionCeQuiResteTitre = 'Ce qui reste à la caserne';
  static const String suppressionCeQuiReste =
      'Tes astreintes passées, sous la mention « Membre supprimé ». La caserne '
      'en a besoin pour ses statistiques ; elles ne portent plus ton nom.';
  static const String suppressionConfirmer = 'Supprimer définitivement';
  static const String suppressionAnnuler = 'Annuler';
  static const String suppressionEnCours = 'Suppression en cours…';

  // --- Les refus -----------------------------------------------------

  static const String suppressionDernierAdmin =
      'Tu es le seul administrateur actif de ta caserne. Nomme quelqu\'un '
      'd\'autre avant de supprimer ton compte.';

  static String suppressionDernierAdminCaserne(String caserne) =>
      'Tu es le seul administrateur actif de $caserne. Nomme quelqu\'un '
      'd\'autre avant de supprimer ton compte.';

  static const String suppressionProfilIntrouvable =
      'Ton profil est introuvable. Déconnecte-toi, reconnecte-toi, puis '
      'réessaie.';

  /// Le pire des cas, et il faut le dire tel qu'il est : les données sont
  /// parties, l'accès non.
  static const String suppressionAccesNonFerme =
      'Tes données ont été effacées, mais ton accès n\'a pas pu être fermé. '
      'Préviens ton chef de centre.';

  static const String suppressionNonAuthentifie =
      'Ta session a expiré. Reconnecte-toi, puis réessaie.';

  static const String suppressionReseau =
      'Pas de connexion. Rien n\'a été supprimé : réessaie quand le réseau '
      'revient.';

  static const String suppressionEchec =
      'La suppression n\'a pas abouti. Réessaie dans un instant.';

  // ===================================================================
  // Export des données personnelles et pages légales (ticket 034)
  // ===================================================================

  static const String exportBouton = 'Exporter mes données';

  /// La phrase sous le bouton, toujours visible : elle dit ce que contient le
  /// fichier avant qu'on le demande, pas après.
  static const String exportAide =
      'Un fichier JSON contenant tout ce que l\'application sait de toi : ton '
      'profil, tes disponibilités, tes astreintes, tes notifications. Les '
      'autres membres de ta caserne n\'y figurent pas.';

  /// Dans la feuille de suppression : la dernière sortie avant le point de
  /// non-retour (`design/034-rgpd-export.md § 5.2`).
  static const String exportAvantSuppressionTitre =
      'Récupère d\'abord tes données';
  static const String exportAvantSuppression =
      'Une fois le compte supprimé, plus personne ne peut te les rendre.';

  static const String exportEnCours = 'Préparation de ton fichier…';

  /// Le fichier est nommé : dans une PWA installée, il n'y a pas de barre de
  /// téléchargement pour le dire à la place de l'écran.
  static String exportEnregistre(String nomFichier) =>
      'Fichier enregistré : $nomFichier';

  static const String exportPartage =
      'Fichier envoyé au partage. Choisis « Enregistrer dans Fichiers » pour le '
      'garder sur ton téléphone.';

  // --- Les refus -----------------------------------------------------

  static const String exportProfilIntrouvable =
      'Ton profil est introuvable. Déconnecte-toi, reconnecte-toi, puis '
      'réessaie.';

  static const String exportNonAuthentifie =
      'Ta session a expiré. Reconnecte-toi, puis réessaie.';

  static const String exportReseau =
      'Pas de connexion. Réessaie quand le réseau revient.';

  /// Le serveur a répondu, c'est l'appareil qui n'a pas su ranger le fichier.
  /// Le message le dit : réessayer a un sens, se reconnecter n'en a aucun.
  static const String exportFichierImpossible =
      'Tes données sont prêtes, mais ton navigateur n\'a pas pu enregistrer le '
      'fichier. Réessaie, ou ouvre l\'application dans un onglet ordinaire.';

  static const String exportEchec =
      'L\'export n\'a pas abouti. Réessaie dans un instant.';

  // --- Les deux pages légales ----------------------------------------

  static const String legalConfidentialiteLien = 'Confidentialité';
  static const String legalMentionsLien = 'Mentions légales';

  /// Le pied de page qui mène aux deux documents, sur le profil comme sur
  /// l'écran de connexion — c'est le seul écran qu'un visiteur non connecté
  /// voit, et une politique de confidentialité joignable seulement une fois
  /// connecté ne remplit pas son office.
  static const String legalPiedTitre = 'Tes données et la loi';

  static const String legalRetour = 'Retour';

  /// La marque de ce qui reste à décider par le propriétaire du produit. Elle
  /// est **visible**, jamais remplacée par un texte plausible : une mention
  /// légale fausse se croit, une mention légale trouée se corrige.
  static const String legalACompleterTitre =
      'À compléter avant mise en service';

  // ===================================================================
  // Export calendrier (ticket 028)
  // ===================================================================

  // --- Le bloc du profil ---------------------------------------------

  static const String calendrierTitre = 'Ajouter à mon calendrier';

  /// Ce que l'abonnement fait, et la seule chose qui compte : il se met à jour
  /// tout seul. Sans cette phrase, le geste ressemble à un export figé.
  static const String calendrierIntro =
      'Colle cette adresse dans ton agenda : tes astreintes acceptées y '
      'apparaîtront, et chaque nouvelle garde s\'y ajoutera toute seule.';

  static const String calendrierAdresseLabel = 'Adresse d\'abonnement';

  static const String calendrierCopier = 'Copier le lien';
  static const String calendrierCopie = 'Lien copié.';

  /// Le presse-papiers peut refuser — contexte non sécurisé, geste non reconnu.
  /// L'adresse est à l'écran, sélectionnable : le message dit quoi faire.
  static const String calendrierCopieImpossible =
      'Ton navigateur n\'a pas laissé copier. Sélectionne l\'adresse '
      'ci-dessus et copie-la à la main.';

  /// L'avertissement. Il est court et il est au-dessus du mode d'emploi : un
  /// lien qui vaut mot de passe se dit avant qu'on le distribue.
  static const String calendrierAvertissement =
      'Ce lien vaut mot de passe : il donne accès à tes astreintes. Ne le '
      'partage pas.';

  // --- Le mode d'emploi, replié --------------------------------------

  static const String calendrierModeEmploi = 'Comment l\'ajouter ?';

  static const String calendrierGoogleTitre = 'Google Agenda';
  static const String calendrierGoogle =
      'Sur ordinateur : Autres agendas, le +, « À partir de l\'URL », colle '
      'l\'adresse, « Ajouter l\'agenda ». L\'agenda apparaît ensuite dans '
      'l\'application Google Agenda du téléphone.';

  static const String calendrierAppleTitre = 'Apple Calendrier';
  static const String calendrierApple =
      'Sur iPhone : Réglages, Applications, Calendrier, Comptes, Ajouter un '
      'compte, Autre, « Ajouter un abonnement à un calendrier », colle '
      'l\'adresse.';

  static const String calendrierOutlookTitre = 'Outlook';
  static const String calendrierOutlook =
      'Sur outlook.com : Calendrier, « Ajouter un calendrier », « S\'abonner '
      'à partir du web », colle l\'adresse, donne-lui un nom, « Importer ».';

  /// Le délai de rafraîchissement n'est pas à nous : chaque agenda décide.
  /// Le dire évite la question « pourquoi ma garde d\'hier n\'est pas là ».
  static const String calendrierDelai =
      'Les agendas rechargent l\'adresse quelques fois par jour : une astreinte '
      'acceptée à l\'instant peut mettre un moment à apparaître.';

  // --- La régénération -----------------------------------------------

  static const String calendrierRegenerer = 'Régénérer le lien';
  static const String calendrierRegenereTitre = 'Régénérer ton lien ?';
  static const String calendrierRegenereCorps =
      'L\'adresse actuelle cessera de fonctionner immédiatement. Les agendas '
      'où tu l\'as déjà collée ne se mettront plus à jour : il faudra y coller '
      'la nouvelle.';
  static const String calendrierRegenereConfirmer = 'Régénérer';
  static const String calendrierRegenereAnnuler = 'Annuler';
  static const String calendrierRegenereFait =
      'Nouveau lien en place. L\'ancien ne répond plus : recolle celui-ci dans '
      'ton agenda.';

  // --- Les refus ------------------------------------------------------

  static const String calendrierNonAuthentifie =
      'Ta session a expiré. Reconnecte-toi, puis réessaie.';

  static const String calendrierReseau =
      'Pas de connexion. Réessaie quand le réseau revient.';

  /// Le bouton de reprise du bloc. **Pas « Réessayer »** : la bannière de
  /// l'écran de profil en porte déjà un, et deux boutons au même libellé sur un
  /// même écran ne se distinguent pas à l'oreille. Celui-ci nomme son objet.
  static const String calendrierRelire = 'Relire mon lien';

  static const String calendrierEchec =
      'Ton lien d\'abonnement n\'a pas pu être lu. Réessaie dans un instant.';

  // --- Le bouton du détail d'une astreinte ----------------------------

  static const String calendrierAjouterUne = 'Ajouter à mon agenda';

  /// Deux boutons au même libellé se suivent dans la feuille d'une journée à
  /// deux créneaux : l'annoncé porte la phrase entière.
  static String calendrierAjouterUneDit(String jourEtDate, String creneau) =>
      'Ajouter $jourEtDate, ${creneau.toLowerCase()}, à mon agenda';

  static const String calendrierAjoutEnCours = 'Préparation du fichier…';

  static String calendrierAjoutEnregistre(String nomFichier) =>
      'Fichier enregistré : $nomFichier. Ouvre-le pour l\'ajouter à ton agenda.';

  static const String calendrierAjoutPartage =
      'Fichier envoyé au partage. Choisis ton application d\'agenda pour '
      'ajouter l\'astreinte.';

  static const String calendrierAjoutImpossible =
      'Ton navigateur n\'a pas pu enregistrer le fichier. Réessaie, ou abonne '
      'ton agenda depuis ton profil.';

  // --- Le contenu du fichier iCalendar --------------------------------
  // Ces trois-là ne s'affichent pas dans l'application : elles s'affichent dans
  // l'agenda de la personne. C'est du texte de produit malgré tout, et il vit
  // ici comme le reste (`design/028-export-ics.md § 4`).

  /// « Astreinte nuit — CIS Saint-Martin ». Sans caserne lisible, l'intitulé ne
  /// finit pas par un tiret orphelin.
  static String icsIntitule({required bool nuit, required String caserne}) {
    final creneau = nuit ? 'nuit' : 'jour';
    return caserne.isEmpty
        ? 'Astreinte $creneau'
        : 'Astreinte $creneau — $caserne';
  }

  /// Un intitulé se tronque dans une vue mensuelle ; la description survit.
  /// C'est elle qui doit porter le mot *jour* ou *nuit* et les heures.
  static String icsDescription({
    required bool nuit,
    required String debut,
    required String fin,
  }) =>
      'Créneau de ${nuit ? 'nuit' : 'jour'}, de $debut à $fin. '
      'Astreinte acceptée.';

  /// `astreinte-2026-11-14-nuit.ics`. La date en ISO et en tête : dans un
  /// dossier de téléchargements, c'est le seul ordre qui range les fichiers
  /// dans l'ordre des gardes.
  static String icsNomFichier({required String jourIso, required bool nuit}) =>
      'astreinte-$jourIso-${nuit ? 'nuit' : 'jour'}.ics';
}
