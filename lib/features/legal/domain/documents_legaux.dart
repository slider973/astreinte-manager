import 'document_legal.dart';

/// Les deux documents juridiques du produit.
///
/// **Ils décrivent ce que le logiciel fait réellement**, vérifié contre
/// `docs/SCHEMA.md` table par table et contre `docs/RGPD.md`, qui en est le
/// registre détaillé. Aucune phrase n'est un remplissage : chacune répond à une
/// question qu'un pompier volontaire ou un chef de centre peut réellement
/// poser.
///
/// Ce qui n'est pas décidé porte une marque `aCompleter`, visible à l'écran.
/// C'est un choix, pas un oubli — une raison sociale inventée ou une durée de
/// conservation plausible se croirait, et la première mairie qui poserait la
/// question obtiendrait une réponse fausse.
///
/// **Chaque paragraphe est une constante nommée**, et les sections ne font que
/// les assembler : `no_adjacent_strings_in_list` interdit d'écrire une phrase
/// sur plusieurs lignes à l'intérieur d'une liste, et c'est une bonne chose ici
/// — la liste se lit comme un sommaire, et un diff sur un paragraphe nomme le
/// paragraphe qui change.
abstract final class DocumentsLegaux {
  /// Date de la version en vigueur des deux documents. Une seule, parce qu'ils
  /// se répondent et qu'ils sont relus ensemble.
  static const String _version = 'Version 1 — 21 septembre 2026';

  // =====================================================================
  // Politique de confidentialité — les paragraphes
  // =====================================================================

  static const String _confChapeau =
      'Astreinte SP sert à organiser les gardes d\'un centre de secours. Cette '
      'page dit quelles données l\'application détient sur toi, pourquoi, '
      'combien de temps, qui les voit, et comment tu en reprends la main. Elle '
      'est écrite pour être lue par un pompier volontaire, pas seulement par un '
      'juriste.';

  // --- Qui est responsable ---

  static const String _respCaserne =
      'Ta caserne est responsable des données qu\'elle traite sur toi : ton '
      'identité, tes coordonnées, tes disponibilités et tes astreintes. C\'est '
      'elle qui décide de t\'inscrire, de te désactiver et de te proposer des '
      'gardes.';

  static const String _respEditeur =
      'L\'éditeur d\'Astreinte SP héberge et traite ces données pour le compte '
      'de ta caserne, en qualité de sous-traitant au sens de l\'article 28 du '
      'RGPD. Il est en revanche responsable de ses propres données de gestion : '
      'ton compte d\'accès et la facturation de l\'abonnement de la caserne.';

  // --- Ce que l'application sait ---

  static const String _donneesCompte =
      'Ton compte : ton adresse électronique, qui est ton identifiant de '
      'connexion, ton prénom, ton nom, ton téléphone si tu l\'as renseigné, le '
      'surnom affiché dans ta caserne, ton rôle et ton statut, ainsi que les '
      'dates de création du compte et de dernière connexion.';

  static const String _donneesGardes =
      'Tes gardes : les cases que tu coches ou décoches pour chaque date et '
      'chaque créneau, les quotas que tu souhaites pour un mois donné et le '
      'commentaire que tu y ajoutes, les astreintes qui te sont proposées, '
      'celles que tu acceptes, celles que tu refuses et le motif que tu donnes.';

  static const String _donneesNotifications =
      'Tes notifications : le titre et le texte de chaque message qui t\'est '
      'envoyé, le canal utilisé — interne, notification sur ton téléphone, '
      'courriel —, la date d\'envoi et la date de lecture. S\'y ajoute, pour '
      'chaque appareil sur lequel tu as autorisé les notifications, un '
      'identifiant d\'installation fourni par Google, son type et un libellé '
      'lisible comme « iPhone · Safari ».';

  static const String _donneesAudit =
      'Les actes d\'administration qui te concernent : quand un chef de centre '
      'saisit une disponibilité à ta place, t\'attribue une garde alors que tu '
      'ne t\'étais pas déclaré disponible, ou annule une de tes astreintes, '
      'l\'application en garde la trace. C\'est une protection pour toi autant '
      'qu\'une obligation pour lui.';

  static const String _donneesAbsentes =
      'L\'application ne collecte aucune donnée de localisation, aucune donnée '
      'de santé, aucun identifiant publicitaire, et n\'installe aucun traceur '
      'de mesure d\'audience.';

  // --- Le commentaire libre ---

  static const String _commentaireRole =
      'Quand tu indiques tes quotas pour un mois, tu peux ajouter un '
      'commentaire que ton chef de centre lira. Il est prévu pour dire « pas '
      'plus d\'un week-end » ou « nuits de préférence ».';

  static const String _commentaireAvertissement =
      'N\'y écris pas de motif médical ni de situation familiale précise : ce '
      'champ n\'est pas conçu pour recevoir une donnée de santé, et ce qui y '
      'est écrit est lisible par tous les administrateurs de ta caserne. '
      '« Indisponible ce week-end » suffit toujours.';

  // --- Qui voit quoi ---

  static const String _voitCloisonnement =
      'Chaque caserne est cloisonnée des autres au niveau de la base de données '
      'elle-même, et pas seulement dans l\'affichage : une requête émise depuis '
      'une caserne ne peut pas atteindre les lignes d\'une autre.';

  static const String _voitMembres =
      'Les autres membres actifs de ta caserne voient ton prénom, ton nom et '
      'ton surnom, ainsi que les astreintes des plannings publiés ou validés. '
      'Ils ne voient ni ton téléphone, ni ton adresse, ni tes disponibilités.';

  static const String _voitAdmins =
      'Les administrateurs de ta caserne voient en plus ton téléphone, ton '
      'adresse, toutes tes disponibilités et tes préférences. C\'est ce qui '
      'leur permet de construire un planning.';

  static const String _voitNotifications =
      'Personne ne lit tes notifications à part toi.';

  static const String _voitEditeur =
      'L\'éditeur du produit accède à la base pour l\'exploiter et la dépanner. '
      'Chacune de ses interventions sur les données d\'une caserne laisse une '
      'trace lisible par les administrateurs de cette caserne.';

  // --- Combien de temps ---

  static const String _dureeActif =
      'Ton compte et tes données de garde sont conservés tant que tu es membre '
      'd\'une caserne.';

  static const String _dureeSuppression =
      'Quand tu supprimes ton compte, tes disponibilités, tes préférences, tes '
      'notifications, tes appareils et les invitations en attente à ton adresse '
      'sont effacés. Ton profil est anonymisé : ton nom devient « Membre '
      'supprimé », ton adresse est remplacée par une adresse non routable, ton '
      'téléphone est effacé.';

  static const String _dureeAstreintes =
      'Tes astreintes passées, elles, sont conservées sans limite de durée. '
      'Elles décrivent des gardes tenues, c\'est-à-dire l\'activité du centre, '
      'et elles ne portent plus ton nom. C\'est le seul point où l\'effacement '
      's\'arrête, et il est assumé.';

  static const String _dureeDernierAdmin =
      'Si tu es le seul administrateur actif de ta caserne, la suppression est '
      'refusée tant qu\'un autre n\'a pas été nommé : sans cela, ta caserne se '
      'retrouverait sans personne pour publier un planning.';

  // --- Les droits ---

  static const String _droitAcces =
      'Accès et portabilité : le bouton « Exporter mes données » de ton profil '
      'te remet un fichier contenant tout ce que l\'application sait de toi, '
      'dans un format réutilisable. Les autres membres de ta caserne n\'y '
      'figurent pas : quand un acte les implique, seul le fait est conservé, '
      'jamais leur identité.';

  static const String _droitRectification =
      'Rectification : ton prénom, ton nom et ton téléphone se corrigent '
      'directement dans ton profil. Ton adresse de connexion est l\'identifiant '
      'de ton compte : pour en changer, passe par ton chef de centre.';

  static const String _droitEffacement =
      'Effacement : le bouton « Supprimer mon compte » de ton profil. L\'écran '
      'te dit exactement ce qui part et ce qui reste avant que tu confirmes.';

  static const String _droitOpposition =
      'Opposition : les notifications non essentielles — rappels de saisie, '
      'rapports — se coupent depuis ton profil. Les propositions d\'astreinte, '
      'elles, partent toujours : sans elles, l\'application ne rend pas son '
      'service.';

  static const String _droitReclamation =
      'Si une demande reste sans réponse, tu peux saisir la CNIL, 3 place de '
      'Fontenoy, 75007 Paris, ou déposer une plainte sur cnil.fr.';

  // --- Où sont les données ---

  static const String _hebergementBase =
      'La base de données, l\'authentification et les traitements serveur sont '
      'hébergés chez Supabase, dans une région européenne.';

  static const String _hebergementFirebase =
      'Les notifications envoyées sur ton téléphone passent par Firebase Cloud '
      'Messaging, un service de Google situé aux États-Unis. C\'est le seul '
      'transfert hors de l\'Union européenne du produit, et il porte le titre et '
      'le texte de la notification — donc, parfois, une date de garde. Il est '
      'encadré par les clauses contractuelles types de la Commission '
      'européenne. Tu peux le supprimer en refusant les notifications sur ton '
      'appareil : tu continueras à les recevoir par courriel et dans '
      'l\'application.';

  static const String _hebergementAutres =
      'Les courriels sont envoyés par Resend. Les paiements de l\'abonnement de '
      'la caserne sont traités par Stripe, qui ne reçoit aucune donnée te '
      'concernant.';

  // --- Sécurité ---

  static const String _securiteSansMotDePasse =
      'La connexion se fait par un code à usage unique envoyé par courriel : '
      'aucun mot de passe n\'est stocké, donc aucun ne peut fuir.';

  static const String _securiteCloisonnement =
      'Le cloisonnement entre casernes est appliqué par la base de données '
      'elle-même, table par table, et vérifié automatiquement à chaque '
      'modification du logiciel.';

  static const String _securiteCles =
      'Les clés qui donnent un accès complet au serveur ne quittent jamais le '
      'serveur : elles ne sont ni dans l\'application, ni dans une réponse, ni '
      'dans un journal.';

  static const String _modifications =
      'Toute modification de fond est datée par un changement de version en '
      'haut de cette page, et annoncée aux administrateurs des casernes avant '
      'son entrée en vigueur.';

  // =====================================================================
  // Mentions légales — les paragraphes
  // =====================================================================

  static const String _mentionsChapeau =
      'Qui édite Astreinte SP, qui l\'héberge, et à qui s\'adresser. Ces '
      'mentions sont exigées par l\'article 6 de la loi pour la confiance dans '
      'l\'économie numérique.';

  static const String _editeurRole =
      'Astreinte SP est une application de gestion des astreintes destinée aux '
      'centres de secours.';

  static const String _hebergeurDonnees =
      'Les données de l\'application — base de données, authentification et '
      'traitements serveur — sont hébergées par Supabase, dans une région '
      'européenne.';

  static const String _proprieteIntellectuelle =
      'Le logiciel, son interface et ses textes sont protégés par le droit '
      'd\'auteur. Les données saisies par une caserne — ses membres, ses '
      'disponibilités, ses plannings — restent la propriété de cette caserne, '
      'qui peut les récupérer à tout moment.';

  static const String _renvoiConfidentialite =
      'Le détail des données traitées, de leur finalité, de leur durée de '
      'conservation et des droits dont tu disposes se trouve dans la politique '
      'de confidentialité.';

  static const String _cookies =
      'L\'application n\'utilise aucun cookie publicitaire et aucun outil de '
      'mesure d\'audience. Elle conserve sur ton appareil ce qui lui est '
      'strictement nécessaire pour fonctionner : ta session, ta caserne '
      'sélectionnée et le dernier état connu de tes écrans, afin de rester '
      'consultable sans réseau. Ces éléments sont effacés quand tu te '
      'déconnectes ou que tu supprimes ton compte, et ils ne requièrent pas de '
      'consentement préalable.';

  static const String _signalement =
      'Pour signaler une anomalie, un contenu inapproprié ou une difficulté '
      'd\'accessibilité, écris à l\'adresse de contact de l\'éditeur. Pour une '
      'question qui concerne ta caserne — ton inscription, tes gardes —, '
      'adresse-toi d\'abord à ton chef de centre : c\'est lui qui en est '
      'responsable.';

  // =====================================================================
  // Ce qui reste à décider par le propriétaire
  // =====================================================================

  static const String _aCompleterIdentiteEditeur =
      'Raison sociale, forme juridique, numéro SIREN et adresse du siège de '
      'l\'éditeur.';

  static const String _aCompleterContact =
      'Adresse électronique de contact pour l\'exercice des droits.';

  static const String _aCompleterDpo =
      'Désignation ou non d\'un délégué à la protection des données.';

  static const String _aCompleterDureeAudit =
      'Durée de conservation du journal d\'audit et des notifications lues.';

  static const String _aCompleterDureeFacturation =
      'Durée de conservation des pièces de facturation de l\'abonnement.';

  static const String _aCompleterRegions =
      'Région exacte du projet Supabase et de l\'envoi de courriels.';

  static const String _aCompleterHebergeurWeb =
      'Hébergeur retenu pour l\'application web, et sa localisation.';

  static const String _aCompleterListeSousTraitants =
      'Liste publique et tenue à jour des sous-traitants.';

  static const String _aCompleterViolation =
      'Procédure de notification en cas de violation de données : qui prévient '
      'les casernes, dans quel délai, par quel canal.';

  static const String _aCompleterFormeJuridique =
      'Raison sociale, forme juridique et capital social.';

  static const String _aCompleterSiege = 'Adresse du siège social.';

  static const String _aCompleterSiren =
      'Numéro SIREN ou SIRET, et numéro de TVA intracommunautaire le cas '
      'échéant.';

  static const String _aCompleterDirecteur =
      'Nom du directeur de la publication.';

  static const String _aCompleterContactPublic =
      'Adresse électronique et numéro de téléphone de contact.';

  static const String _aCompleterSupabaseEntite =
      'Raison sociale et adresse de l\'entité Supabase contractante.';

  static const String _aCompleterHebergeurApp =
      'Hébergeur de l\'application web elle-même, avec sa raison sociale et son '
      'adresse.';

  static const String _aCompleterLicence =
      'Régime de licence du logiciel, et marques éventuellement déposées.';

  static const String _aCompleterSignalement =
      'Adresse de signalement, et délai de réponse annoncé.';

  // =====================================================================
  // Les documents
  // =====================================================================

  static const DocumentLegal confidentialite = DocumentLegal(
    titre: 'Politique de confidentialité',
    version: _version,
    chapeau: _confChapeau,
    sections: <SectionLegale>[
      SectionLegale(
        titre: 'Qui est responsable de tes données',
        paragraphes: <String>[_respCaserne, _respEditeur],
        aCompleter: <String>[
          _aCompleterIdentiteEditeur,
          _aCompleterContact,
          _aCompleterDpo,
        ],
      ),
      SectionLegale(
        titre: 'Ce que l\'application sait de toi',
        paragraphes: <String>[
          _donneesCompte,
          _donneesGardes,
          _donneesNotifications,
          _donneesAudit,
          _donneesAbsentes,
        ],
      ),
      SectionLegale(
        titre: 'Le commentaire libre de tes préférences',
        paragraphes: <String>[_commentaireRole, _commentaireAvertissement],
      ),
      SectionLegale(
        titre: 'Qui voit quoi',
        paragraphes: <String>[
          _voitCloisonnement,
          _voitMembres,
          _voitAdmins,
          _voitNotifications,
          _voitEditeur,
        ],
      ),
      SectionLegale(
        titre: 'Combien de temps',
        paragraphes: <String>[
          _dureeActif,
          _dureeSuppression,
          _dureeAstreintes,
          _dureeDernierAdmin,
        ],
        aCompleter: <String>[
          _aCompleterDureeAudit,
          _aCompleterDureeFacturation,
        ],
      ),
      SectionLegale(
        titre: 'Tes droits, et où ils s\'exercent',
        paragraphes: <String>[
          _droitAcces,
          _droitRectification,
          _droitEffacement,
          _droitOpposition,
          _droitReclamation,
        ],
      ),
      SectionLegale(
        titre: 'Où sont tes données, et qui les traite pour nous',
        paragraphes: <String>[
          _hebergementBase,
          _hebergementFirebase,
          _hebergementAutres,
        ],
        aCompleter: <String>[
          _aCompleterRegions,
          _aCompleterHebergeurWeb,
          _aCompleterListeSousTraitants,
        ],
      ),
      SectionLegale(
        titre: 'Sécurité',
        paragraphes: <String>[
          _securiteSansMotDePasse,
          _securiteCloisonnement,
          _securiteCles,
        ],
        aCompleter: <String>[_aCompleterViolation],
      ),
      SectionLegale(
        titre: 'Modifications de cette page',
        paragraphes: <String>[_modifications],
      ),
    ],
  );

  static const DocumentLegal mentions = DocumentLegal(
    titre: 'Mentions légales',
    version: _version,
    chapeau: _mentionsChapeau,
    sections: <SectionLegale>[
      SectionLegale(
        titre: 'Éditeur',
        paragraphes: <String>[_editeurRole],
        aCompleter: <String>[
          _aCompleterFormeJuridique,
          _aCompleterSiege,
          _aCompleterSiren,
          _aCompleterDirecteur,
          _aCompleterContactPublic,
        ],
      ),
      SectionLegale(
        titre: 'Hébergement',
        paragraphes: <String>[_hebergeurDonnees],
        aCompleter: <String>[
          _aCompleterSupabaseEntite,
          _aCompleterHebergeurApp,
        ],
      ),
      SectionLegale(
        titre: 'Propriété intellectuelle',
        paragraphes: <String>[_proprieteIntellectuelle],
        aCompleter: <String>[_aCompleterLicence],
      ),
      SectionLegale(
        titre: 'Données personnelles',
        paragraphes: <String>[_renvoiConfidentialite],
      ),
      SectionLegale(
        titre: 'Cookies et traceurs',
        paragraphes: <String>[_cookies],
      ),
      SectionLegale(
        titre: 'Signaler un problème',
        paragraphes: <String>[_signalement],
        aCompleter: <String>[_aCompleterSignalement],
      ),
    ],
  );
}
