import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';
import 'membre_caserne.dart' show normaliserRecherche;

/// La taille maximale d'un fichier accepté : **512 Kio**.
///
/// Une ligne de pompier pèse une cinquantaine d'octets ; la limite laisse donc
/// passer dix mille personnes, largement au-delà de [maxLignesFichier]. Elle
/// n'est pas là pour borner le métier mais pour que l'onglet ne tombe pas sur
/// un fichier déposé par erreur — une photo, un classeur, une sauvegarde.
const int maxOctetsFichier = 512 * 1024;

/// Le nombre maximal de lignes de données lues dans un fichier.
///
/// La plus grosse caserne de France compte quelques centaines de sapeurs ;
/// cinq cents est confortable et borne l'aperçu à quelque chose qui se relit.
const int maxLignesFichier = 500;

/// Les types proposés par le sélecteur du système. Un filtre d'affichage, pas
/// une garantie : le contenu est jugé après lecture, jamais sur l'extension.
const String typesFichierAcceptes = '.csv,.txt,text/csv,text/plain';

/// Ce qui empêche de lire un fichier, avant même de regarder ses lignes.
enum ErreurFichier {
  /// Pas une ligne exploitable après l'en-tête.
  vide,

  /// Aucune colonne d'adresse reconnue. Le seul en-tête obligatoire.
  colonneAdresseAbsente,

  /// Plus de [maxLignesFichier] lignes de données.
  tropDeLignes,

  /// Plus de [maxOctetsFichier] octets.
  tropGros,

  /// Ni le sélecteur ni la lecture n'ont abouti.
  illisible,
}

/// Une ligne du fichier, telle qu'elle a été lue. Rien n'est encore jugé ici :
/// c'est la matière brute, à l'ordre et au numéro près.
@immutable
class LigneFichier {
  const LigneFichier({
    required this.numero,
    required this.prenom,
    required this.nom,
    required this.email,
    required this.role,
  });

  /// Le numéro de ligne **dans le fichier**, en-tête compris : c'est celui que
  /// la personne lit dans son tableur, et le seul qui l'aide à corriger.
  final int numero;

  final String prenom;
  final String nom;

  /// Normalisée : sans espaces, en minuscules. Peut être vide.
  final String email;

  /// Le rôle lu dans la colonne facultative. `membre` par défaut.
  final RoleMembre role;

  /// « Marie Lefèbvre », ou une chaîne vide quand les deux colonnes manquent.
  String get nomComplet =>
      <String>[prenom, nom].where((String p) => p.isNotEmpty).join(' ');

  @override
  bool operator ==(Object other) =>
      other is LigneFichier &&
      other.numero == numero &&
      other.prenom == prenom &&
      other.nom == nom &&
      other.email == email &&
      other.role == role;

  @override
  int get hashCode => Object.hash(numero, prenom, nom, email, role);
}

/// Le résultat de la lecture d'un fichier : des lignes, ou une raison de ne pas
/// continuer.
@immutable
class LectureFichier {
  const LectureFichier._({
    required this.nomFichier,
    required this.lignes,
    required this.erreur,
  });

  const LectureFichier.echec(String nomFichier, ErreurFichier erreur)
    : this._(
        nomFichier: nomFichier,
        lignes: const <LigneFichier>[],
        erreur: erreur,
      );

  final String nomFichier;
  final List<LigneFichier> lignes;
  final ErreurFichier? erreur;

  bool get lisible => erreur == null;
}

/// Lit un fichier tableur séparé par des virgules ou des points-virgules.
///
/// **Trois devinettes, aucune question.** Personne ne doit savoir ce qu'est un
/// encodage, un séparateur ou un ordre de colonnes pour importer ses pompiers :
///
/// 1. l'encodage, par [decoderTableur] ;
/// 2. le séparateur, par [separateurDe], compté sur la ligne d'en-têtes ;
/// 3. les colonnes, par leur intitulé et non par leur position.
LectureFichier lireFichierMembres({
  required String nomFichier,
  required Uint8List octets,
}) {
  if (octets.length > maxOctetsFichier) {
    return LectureFichier.echec(nomFichier, ErreurFichier.tropGros);
  }

  final String texte;
  try {
    texte = decoderTableur(octets);
  } on Object {
    return LectureFichier.echec(nomFichier, ErreurFichier.illisible);
  }

  final rangees = decouperTableur(texte);
  if (rangees.isEmpty) {
    return LectureFichier.echec(nomFichier, ErreurFichier.vide);
  }

  final colonnes = _ColonnesReconnues.depuisEntetes(rangees.first);
  if (colonnes.email == null) {
    return LectureFichier.echec(nomFichier, ErreurFichier.colonneAdresseAbsente);
  }

  final corps = rangees.skip(1).toList(growable: false);
  if (corps.length > maxLignesFichier) {
    return LectureFichier.echec(nomFichier, ErreurFichier.tropDeLignes);
  }

  final lignes = <LigneFichier>[];
  for (var i = 0; i < corps.length; i++) {
    final cellules = corps[i];
    // Une rangée entièrement vide est un artefact du tableur — la ligne de
    // trop en bas du fichier —, pas une ligne à signaler.
    if (cellules.every((String c) => c.trim().isEmpty)) continue;

    lignes.add(
      LigneFichier(
        // +2 : la ligne 1 est l'en-tête, et les humains comptent depuis 1.
        numero: i + 2,
        prenom: colonnes.valeur(cellules, colonnes.prenom),
        nom: colonnes.valeur(cellules, colonnes.nom),
        email: colonnes.valeur(cellules, colonnes.email).toLowerCase(),
        role: _roleDepuis(colonnes.valeur(cellules, colonnes.role)),
      ),
    );
  }

  if (lignes.isEmpty) {
    return LectureFichier.echec(nomFichier, ErreurFichier.vide);
  }
  return LectureFichier._(
    nomFichier: nomFichier,
    lignes: List<LigneFichier>.unmodifiable(lignes),
    erreur: null,
  );
}

// ---------------------------------------------------------------------------
// L'encodage
// ---------------------------------------------------------------------------

/// Décode le contenu brut d'un fichier tableur.
///
/// **UTF-8 d'abord, en mode strict ; Windows-1252 en repli.** Un fichier
/// enregistré en CSV par un tableur français est presque toujours en
/// Windows-1252 — c'est le défaut d'Excel sous Windows — et le lire en UTF-8
/// donne « Lef?bvre » quand il ne fait pas échouer la lecture. Dans l'autre
/// sens, un fichier UTF-8 lu en Windows-1252 donne « LefÃ¨bvre », ce qui est
/// tout aussi faux mais **ne lève pas**, puisque les 256 octets ont tous une
/// signification.
///
/// L'ordre n'est donc pas un goût : le seul des deux décodages qui sache dire
/// « ce n'est pas moi » doit passer en premier. Un fichier UTF-8 valide n'est
/// jamais pris pour du Windows-1252 ; un fichier Windows-1252 portant un accent
/// est presque toujours refusé par UTF-8, parce que ses octets hauts ne forment
/// pas de séquence valide.
///
/// Le BOM est retiré dans les deux cas : Excel l'écrit, et il apparaîtrait
/// sinon collé au premier intitulé de colonne, qui ne serait plus reconnu.
String decoderTableur(Uint8List octets) {
  final sansBom = _retirerBom(octets);
  try {
    return const Utf8Decoder().convert(sansBom);
  } on FormatException {
    return decoderWindows1252(sansBom);
  }
}

/// Retire la marque d'ordre des octets, UTF-8 (`EF BB BF`) comme UTF-16.
Uint8List _retirerBom(Uint8List octets) {
  if (octets.length >= 3 &&
      octets[0] == 0xEF &&
      octets[1] == 0xBB &&
      octets[2] == 0xBF) {
    return Uint8List.sublistView(octets, 3);
  }
  return octets;
}

/// Décode du Windows-1252 (CP1252). Ne peut pas échouer : les 256 octets ont
/// tous une signification.
///
/// Latin-1 sauf la plage `80`–`9F`, que Windows a remplie de signes de
/// ponctuation — dont les guillemets français et l'apostrophe courbe, qui
/// arrivent tous les jours dans un nom de famille copié depuis un traitement
/// de texte. Les cinq octets sans affectation deviennent le caractère de
/// remplacement plutôt que de faire échouer un import entier.
String decoderWindows1252(Uint8List octets) {
  final tampon = StringBuffer();
  for (final octet in octets) {
    if (octet < 0x80 || octet > 0x9F) {
      tampon.writeCharCode(octet);
    } else {
      tampon.write(_hautDeWindows1252[octet - 0x80]);
    }
  }
  return tampon.toString();
}

/// La plage `80`–`9F` de Windows-1252. `�` pour les cinq trous.
const List<String> _hautDeWindows1252 = <String>[
  '€', '�', '‚', 'ƒ', '„', '…', '†', //
  '‡', 'ˆ', '‰', 'Š', '‹', 'Œ', '�',
  'Ž', '�', '�', '‘', '’', '“', '”',
  '•', '–', '—', '˜', '™', 'š', '›',
  'œ', '�', 'ž', 'Ÿ',
];

// ---------------------------------------------------------------------------
// Le découpage
// ---------------------------------------------------------------------------

/// Le séparateur de [premiereLigne] : point-virgule ou virgule.
///
/// Compté sur la ligne d'en-têtes, **hors guillemets**. Le point-virgule gagne
/// à égalité : c'est le séparateur qu'un Excel en français écrit par défaut, et
/// un en-tête français n'a aucune raison de porter des virgules.
String separateurDe(String premiereLigne) {
  var virgules = 0;
  var pointsVirgules = 0;
  var tabulations = 0;
  var dansGuillemets = false;

  for (final unite in premiereLigne.codeUnits) {
    if (unite == 0x22) {
      dansGuillemets = !dansGuillemets;
      continue;
    }
    if (dansGuillemets) continue;
    if (unite == 0x2C) virgules++;
    if (unite == 0x3B) pointsVirgules++;
    if (unite == 0x09) tabulations++;
  }

  if (tabulations > pointsVirgules && tabulations > virgules) return '\t';
  return virgules > pointsVirgules ? ',' : ';';
}

/// Découpe un fichier tableur en rangées de cellules.
///
/// RFC 4180 pour l'essentiel : guillemets autour d'un champ, guillemet doublé
/// à l'intérieur, séparateur et retour à la ligne neutralisés entre guillemets.
/// Les trois fins de ligne (`\r\n`, `\n`, `\r`) sont acceptées : un fichier
/// produit sous Windows et relu sous macOS ne doit pas devenir une seule ligne.
List<List<String>> decouperTableur(String texte) {
  if (texte.trim().isEmpty) return const <List<String>>[];

  final finPremiereLigne = texte.indexOf(RegExp('[\r\n]'));
  final separateur = separateurDe(
    finPremiereLigne < 0 ? texte : texte.substring(0, finPremiereLigne),
  ).codeUnitAt(0);

  final rangees = <List<String>>[];
  var rangee = <String>[];
  final cellule = StringBuffer();
  var dansGuillemets = false;

  void finirCellule() {
    rangee.add(cellule.toString());
    cellule.clear();
  }

  void finirRangee() {
    finirCellule();
    rangees.add(rangee);
    rangee = <String>[];
  }

  final unites = texte.codeUnits;
  for (var i = 0; i < unites.length; i++) {
    final unite = unites[i];

    if (dansGuillemets) {
      if (unite == 0x22) {
        // Un guillemet doublé est un guillemet littéral, pas une fermeture.
        if (i + 1 < unites.length && unites[i + 1] == 0x22) {
          cellule.writeCharCode(0x22);
          i++;
        } else {
          dansGuillemets = false;
        }
      } else {
        cellule.writeCharCode(unite);
      }
      continue;
    }

    if (unite == 0x22 && cellule.isEmpty) {
      dansGuillemets = true;
    } else if (unite == separateur) {
      finirCellule();
    } else if (unite == 0x0A) {
      finirRangee();
    } else if (unite == 0x0D) {
      // `\r\n` compte pour une seule fin de ligne.
      if (i + 1 < unites.length && unites[i + 1] == 0x0A) i++;
      finirRangee();
    } else {
      cellule.writeCharCode(unite);
    }
  }

  if (cellule.isNotEmpty || rangee.isNotEmpty) finirRangee();

  // La dernière rangée d'un fichier qui finit par un retour à la ligne est
  // vide : elle n'existe que pour le tableur qui l'a écrite.
  while (rangees.isNotEmpty &&
      rangees.last.every((String c) => c.trim().isEmpty)) {
    rangees.removeLast();
  }
  return rangees;
}

// ---------------------------------------------------------------------------
// Les colonnes
// ---------------------------------------------------------------------------

/// Où sont le prénom, le nom, l'adresse et le rôle dans les rangées.
@immutable
class _ColonnesReconnues {
  const _ColonnesReconnues({
    required this.prenom,
    required this.nom,
    required this.email,
    required this.role,
  });

  /// Reconnaît les colonnes par leur intitulé, **jamais par leur position**.
  ///
  /// Un fichier tenu par un chef de centre a les colonnes qu'il a voulues,
  /// dans l'ordre où il les a voulues. Imposer « prénom, nom, e-mail » ferait
  /// échouer la moitié des imports sur une permutation.
  factory _ColonnesReconnues.depuisEntetes(List<String> entetes) {
    int? prenom;
    int? nom;
    int? email;
    int? role;

    for (var i = 0; i < entetes.length; i++) {
      final intitule = _normaliserEntete(entetes[i]);
      if (intitule.isEmpty) continue;
      if (prenom == null && _entetesPrenom.contains(intitule)) {
        prenom = i;
      } else if (nom == null && _entetesNom.contains(intitule)) {
        nom = i;
      } else if (email == null && _entetesEmail.contains(intitule)) {
        email = i;
      } else if (role == null && _entetesRole.contains(intitule)) {
        role = i;
      }
    }

    return _ColonnesReconnues(
      prenom: prenom,
      nom: nom,
      email: email,
      role: role,
    );
  }

  final int? prenom;
  final int? nom;
  final int? email;
  final int? role;

  /// La cellule d'une colonne, resserrée. Chaîne vide si la colonne n'existe
  /// pas ou si la rangée est plus courte que l'en-tête.
  String valeur(List<String> cellules, int? index) {
    if (index == null || index >= cellules.length) return '';
    return cellules[index].replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// Minuscules, sans accent, sans ponctuation : « Prénom », « PRENOM » et
/// « prenom_ » sont le même intitulé.
String _normaliserEntete(String brut) => normaliserRecherche(
  brut,
).replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

const Set<String> _entetesPrenom = <String>{
  'prenom',
  'prenoms',
  'first name',
  'firstname',
  'given name',
};

const Set<String> _entetesNom = <String>{
  'nom',
  'nom de famille',
  'last name',
  'lastname',
  'surname',
  'famille',
  'patronyme',
};

const Set<String> _entetesEmail = <String>{
  'email',
  'e mail',
  'mail',
  'courriel',
  'adresse',
  'adresse email',
  'adresse e mail',
  'adresse mail',
  'adresse courriel',
  'mel',
};

const Set<String> _entetesRole = <String>{
  'role',
  'roles',
  'fonction',
  'droits',
  'statut',
  'profil',
};

/// Les intitulés d'adresse reconnus, pour le dire quand aucun n'est trouvé.
const String entetesAdresseReconnus = 'email, e-mail, courriel, mail, adresse';

/// Le rôle lu dans la colonne facultative.
///
/// Tout ce qui n'est pas explicitement un rôle d'administration donne
/// « membre ». On ne refuse **jamais** une ligne pour un rôle qu'on ne
/// comprend pas : le rôle se change en deux gestes dans la feuille d'actions du
/// ticket 009, l'invitation, elle, ne se rattrape pas.
RoleMembre _roleDepuis(String brut) {
  final propre = normaliserRecherche(brut);
  return _rolesAdmin.contains(propre) ? RoleMembre.admin : RoleMembre.membre;
}

const Set<String> _rolesAdmin = <String>{
  'admin',
  'admins',
  'administrateur',
  'administratrice',
  'administrateur de caserne',
  'admin de caserne',
  'chef',
  'chef de centre',
  'chef de caserne',
  'responsable',
};

/// Le fichier d'exemple, produit par l'écran plutôt qu'embarqué en `assets/`.
///
/// **Point-virgule et BOM UTF-8**, les deux réglages qu'Excel en français relit
/// sans rien demander. Trois lignes fictives : assez pour montrer la forme, pas
/// assez pour qu'on soit tenté de les garder. Il est produit sur place et non
/// livré comme fichier, ce qui garantit qu'il porte les intitulés que le code
/// reconnaît vraiment.
String fichierExempleMembres() =>
    '﻿'
    'prenom;nom;email;role\r\n'
    'Marie;Lefèbvre;marie.lefebvre@exemple.fr;admin\r\n'
    'Thomas;Nguyen;thomas.nguyen@exemple.fr;membre\r\n'
    'Camille;Roux;camille.roux@exemple.fr;\r\n';

/// Le nom du fichier d'exemple, et l'extension attendue à l'import.
const String nomFichierExemple = 'pompiers-exemple.csv';

/// Ce qu'on affiche pour une taille d'octets : « 1,4 Mo », « 512 Ko ».
String tailleLisible(int octets) {
  if (octets < 1024) return AppStrings.tailleOctets(octets);
  if (octets < 1024 * 1024) return AppStrings.tailleKo(octets / 1024);
  return AppStrings.tailleMo(octets / (1024 * 1024));
}
