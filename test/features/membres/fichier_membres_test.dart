import 'dart:convert';

import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/membres/domain/fichier_membres.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le fichier d'un chef de centre, tel qu'il sort d'un tableur.
Uint8List _utf8(String texte) => Uint8List.fromList(utf8.encode(texte));

/// Le même fichier tel qu'Excel en français l'écrit : Windows-1252.
///
/// Encodé à la main, octet par octet, pour éprouver le décodage sur de la
/// vraie matière plutôt que sur ce que Dart sait produire.
Uint8List _windows1252(String texte) {
  const hauts = <String, int>{
    'è': 0xE8,
    'é': 0xE9,
    'ê': 0xEA,
    'ï': 0xEF,
    'ô': 0xF4,
    'ç': 0xE7,
    'û': 0xFB,
    'à': 0xE0,
    'É': 0xC9,
    '’': 0x92,
    'œ': 0x9C,
    '€': 0x80,
  };
  return Uint8List.fromList(<int>[
    for (final rune in texte.runes)
      hauts[String.fromCharCode(rune)] ??
          (rune < 0x100 ? rune : 0x3F /* '?' */),
  ]);
}

const String _pointVirgule =
    'prenom;nom;email;role\n'
    'Marie;Lefèbvre;marie.lefebvre@exemple.fr;admin\n'
    'Thomas;Nguyen;thomas.nguyen@exemple.fr;\n';

const String _virgule =
    'prenom,nom,email,role\n'
    'Marie,Lefèbvre,marie.lefebvre@exemple.fr,admin\n'
    'Thomas,Nguyen,thomas.nguyen@exemple.fr,\n';

void main() {
  group('Séparateurs', () {
    test('le point-virgule et la virgule donnent la même lecture', () {
      final avecPointVirgule = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8(_pointVirgule),
      );
      final avecVirgule = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8(_virgule),
      );

      expect(avecPointVirgule.lisible, isTrue);
      expect(avecVirgule.lisible, isTrue);
      expect(avecPointVirgule.lignes, avecVirgule.lignes);
      expect(avecVirgule.lignes.first.nomComplet, 'Marie Lefèbvre');
      expect(avecVirgule.lignes.first.role, RoleMembre.admin);
      expect(avecVirgule.lignes.last.role, RoleMembre.membre);
    });

    test('le point-virgule gagne à égalité : c\'est celui d\'Excel', () {
      // Un en-tête sans séparateur du tout ne doit pas partir sur la virgule :
      // un fichier à une colonne est plus souvent français qu'anglais.
      expect(separateurDe('email'), ';');
      expect(separateurDe('prenom;nom;email'), ';');
      expect(separateurDe('prenom,nom,email'), ',');
      expect(separateurDe('prenom\tnom\temail'), '\t');
    });

    test('les virgules entre guillemets ne séparent rien', () {
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8(
          'nom,email\n'
          '"Dupont, dit ""Le Grand""",jean@exemple.fr\n',
        ),
      );

      expect(lecture.lisible, isTrue);
      expect(lecture.lignes.single.nom, 'Dupont, dit "Le Grand"');
      expect(lecture.lignes.single.email, 'jean@exemple.fr');
    });

    test('les trois fins de ligne sont acceptées', () {
      for (final fin in <String>['\r\n', '\n', '\r']) {
        final lecture = lireFichierMembres(
          nomFichier: 'a.csv',
          octets: _utf8('email${fin}a@x.fr${fin}b@x.fr$fin'),
        );
        expect(lecture.lignes.length, 2, reason: 'fin de ligne ${fin.codeUnits}');
      }
    });
  });

  group('Encodages', () {
    test('UTF-8 et Windows-1252 donnent les mêmes accents', () {
      final enUtf8 = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8(_pointVirgule),
      );
      final en1252 = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _windows1252(_pointVirgule),
      );

      expect(en1252.lisible, isTrue);
      expect(en1252.lignes.first.nom, 'Lefèbvre');
      expect(en1252.lignes, enUtf8.lignes);
    });

    test('le BOM d\'Excel ne colle pas au premier intitulé', () {
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8('﻿email;prenom\nmarie@x.fr;Marie\n'),
      );

      expect(lecture.lisible, isTrue);
      expect(lecture.lignes.single.email, 'marie@x.fr');
      expect(lecture.lignes.single.prenom, 'Marie');
    });

    test('la plage 80–9F de Windows-1252 est celle de Windows', () {
      // Latin-1 y met des caractères de contrôle ; Windows y a mis des signes
      // de ponctuation, dont l'apostrophe courbe des noms copiés depuis un
      // traitement de texte.
      expect(decoderWindows1252(Uint8List.fromList(<int>[0x92])), '’');
      expect(decoderWindows1252(Uint8List.fromList(<int>[0x80])), '€');
      expect(decoderWindows1252(Uint8List.fromList(<int>[0x9C])), 'œ');
    });

    test('un fichier UTF-8 valide n\'est jamais pris pour du 1252', () {
      // Le seul des deux décodages qui sache dire « ce n'est pas moi » passe
      // en premier : sans ça, « Lefèbvre » deviendrait « LefÃ¨bvre ».
      expect(decoderTableur(_utf8('Lefèbvre')), 'Lefèbvre');
    });
  });

  group('En-têtes', () {
    test('les colonnes sont reconnues dans n\'importe quel ordre', () {
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8(
          'Rôle;ADRESSE E-MAIL;Nom de famille;Prénom\n'
          'chef de centre;marie@x.fr;Lefèbvre;Marie\n',
        ),
      );

      expect(lecture.lisible, isTrue);
      final ligne = lecture.lignes.single;
      expect(ligne.prenom, 'Marie');
      expect(ligne.nom, 'Lefèbvre');
      expect(ligne.email, 'marie@x.fr');
      expect(ligne.role, RoleMembre.admin);
    });

    test('les intitulés courants d\'adresse sont tous reconnus', () {
      for (final intitule in <String>[
        'email',
        'e-mail',
        'E-Mail',
        'courriel',
        'mail',
        'adresse',
        'Adresse e-mail',
      ]) {
        final lecture = lireFichierMembres(
          nomFichier: 'a.csv',
          octets: _utf8('$intitule\nmarie@x.fr\n'),
        );
        expect(lecture.lisible, isTrue, reason: intitule);
        expect(lecture.lignes.single.email, 'marie@x.fr', reason: intitule);
      }
    });

    test('sans colonne d\'adresse, rien ne se lit', () {
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8('prenom;nom\nMarie;Lefèbvre\n'),
      );

      expect(lecture.lisible, isFalse);
      expect(lecture.erreur, ErreurFichier.colonneAdresseAbsente);
    });

    test('les colonnes en trop sont ignorées, pas refusées', () {
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8(
          'matricule;prenom;grade;email;telephone\n'
          '4211;Marie;Sergent;marie@x.fr;0600000000\n',
        ),
      );

      expect(lecture.lisible, isTrue);
      expect(lecture.lignes.single.prenom, 'Marie');
      expect(lecture.lignes.single.email, 'marie@x.fr');
    });

    test('un rôle inconnu vaut membre, et ne refuse pas la ligne', () {
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8(
          'email;role\n'
          'a@x.fr;Caporal\n'
          'b@x.fr;ADMINISTRATRICE\n'
          'c@x.fr;\n',
        ),
      );

      expect(
        lecture.lignes.map((LigneFichier l) => l.role),
        <RoleMembre>[RoleMembre.membre, RoleMembre.admin, RoleMembre.membre],
      );
    });
  });

  group('Numéros de ligne et lignes vides', () {
    test('le numéro est celui du tableur, en-tête compris', () {
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8('email\na@x.fr\nb@x.fr\n'),
      );

      expect(lecture.lignes.map((LigneFichier l) => l.numero), <int>[2, 3]);
    });

    test('la ligne vide du bas n\'est pas une ligne', () {
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8('email;prenom\na@x.fr;Marie\n;\n\n'),
      );

      expect(lecture.lignes.length, 1);
    });

    test('un fichier sans aucune ligne de données le dit', () {
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8('prenom;nom;email\n'),
      );

      expect(lecture.erreur, ErreurFichier.vide);
    });
  });

  group('Limites', () {
    test('au-delà de 512 Ko, le fichier est refusé sans être lu', () {
      final trop = Uint8List(maxOctetsFichier + 1);
      final lecture = lireFichierMembres(nomFichier: 'a.csv', octets: trop);

      expect(lecture.erreur, ErreurFichier.tropGros);
    });

    test('au-delà de 500 lignes, le fichier est refusé', () {
      final corps = StringBuffer('email\n');
      for (var i = 0; i <= maxLignesFichier; i++) {
        corps.writeln('pompier$i@exemple.fr');
      }
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8(corps.toString()),
      );

      expect(lecture.erreur, ErreurFichier.tropDeLignes);
    });

    test('exactement 500 lignes passent', () {
      final corps = StringBuffer('email\n');
      for (var i = 0; i < maxLignesFichier; i++) {
        corps.writeln('pompier$i@exemple.fr');
      }
      final lecture = lireFichierMembres(
        nomFichier: 'a.csv',
        octets: _utf8(corps.toString()),
      );

      expect(lecture.lisible, isTrue);
      expect(lecture.lignes.length, maxLignesFichier);
    });
  });

  group('Fichier d\'exemple', () {
    test('il se relit lui-même, et porte les intitulés reconnus', () {
      // La garantie qui justifie de le produire sur place plutôt que de
      // l'embarquer : il ne peut pas diverger du code qui le relit.
      final lecture = lireFichierMembres(
        nomFichier: nomFichierExemple,
        octets: _utf8(fichierExempleMembres()),
      );

      expect(lecture.lisible, isTrue);
      expect(lecture.lignes.length, 3);
      expect(lecture.lignes.first.nomComplet, 'Marie Lefèbvre');
      expect(lecture.lignes.first.role, RoleMembre.admin);
      expect(lecture.lignes.last.role, RoleMembre.membre);
    });
  });

  group('Tailles lisibles', () {
    test('les trois ordres de grandeur se disent en français', () {
      expect(tailleLisible(512), '512 octets');
      expect(tailleLisible(512 * 1024), '512 Ko');
      expect(tailleLisible(1468006), '1,4 Mo');
    });
  });
}
