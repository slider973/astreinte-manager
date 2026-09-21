import 'dart:convert';

import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/membres/domain/fichier_membres.dart';
import 'package:astreinte_sp/features/membres/domain/import_membres.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_invitations.dart';

LectureFichier _lire(String contenu) => lireFichierMembres(
  nomFichier: 'pompiers.csv',
  octets: Uint8List.fromList(utf8.encode(contenu)),
);

const MembreCaserne _membreMarie = MembreCaserne(
  id: 'm-1',
  userId: 'u-1',
  role: RoleMembre.membre,
  statut: StatutMembre.actif,
  prenom: 'Marie',
  nom: 'Lefebvre',
  email: 'marie@exemple.fr',
);

const MembreCaserne _membreParti = MembreCaserne(
  id: 'm-2',
  userId: 'u-2',
  role: RoleMembre.membre,
  statut: StatutMembre.desactive,
  prenom: 'Luc',
  nom: 'Parti',
  email: 'luc@exemple.fr',
);

ApercuImport _apercu(
  String contenu, {
  List<MembreCaserne> membres = const <MembreCaserne>[],
  List<Invitation> invitations = const <Invitation>[],
  BudgetInvitations? budget,
}) => preparerApercu(
  lecture: _lire(contenu),
  membres: membres,
  invitations: invitations,
  budget: budget,
);

void main() {
  group('Verdicts de l\'aperçu', () {
    test('une ligne complète et inconnue part, sans rien à dire', () {
      final apercu = _apercu('prenom;nom;email\nMarie;Lefèbvre;m@x.fr\n');

      expect(apercu.lignes.single.verdict, VerdictApercu.aInviter);
      expect(apercu.lignes.single.detail, isNull);
      expect(apercu.nombreAInviter, 1);
      expect(apercu.nombreEcartees, 0);
    });

    test('une ligne sans nom part quand même, et le dit en gris', () {
      final apercu = _apercu('prenom;nom;email\n;;m@x.fr\n');
      final ligne = apercu.lignes.single;

      // L'adresse fait entrer quelqu'un dans la caserne, pas le nom : refuser
      // la ligne priverait le chef de centre d'une personne pour une case vide.
      expect(ligne.verdict, VerdictApercu.aInviterSansNom);
      expect(ligne.partira, isTrue);
      expect(ligne.verdict.estUneFaute, isFalse);
      expect(ligne.titre, 'm@x.fr');
      expect(apercu.nombreEcartees, 0);
    });

    test('un membre déjà actif est écarté, avec le mot du ticket 006', () {
      final apercu = _apercu(
        'prenom;email\nMarie;marie@exemple.fr\n',
        membres: const <MembreCaserne>[_membreMarie],
      );

      expect(apercu.lignes.single.verdict, VerdictApercu.dejaMembre);
      expect(apercu.nombreAInviter, 0);
    });

    test('un membre désactivé peut être réinvité', () {
      // `create_invitation` le permet : `accept_invitation` réactivera sa
      // ligne. L'aperçu ne doit pas être plus restrictif que la base.
      final apercu = _apercu(
        'prenom;email\nLuc;luc@exemple.fr\n',
        membres: const <MembreCaserne>[_membreParti],
      );

      expect(apercu.lignes.single.verdict, VerdictApercu.aInviter);
    });

    test('une invitation déjà en attente est ignorée', () {
      // C'est ce qui rend l'import rejouable : redéposer le même fichier après
      // un refus de débit n'envoie que ce qui manquait.
      final apercu = _apercu(
        'prenom;email\nRecrue;recrue@exemple.fr\n',
        invitations: <Invitation>[invitationEnAttente()],
      );

      expect(apercu.lignes.single.verdict, VerdictApercu.dejaInvitee);
      expect(apercu.nombreAInviter, 0);
    });

    test('un doublon nomme la ligne qui portait déjà l\'adresse', () {
      final apercu = _apercu(
        'prenom;email\n'
        'Marie;m@x.fr\n'
        'Thomas;t@x.fr\n'
        'Marion;M@X.FR\n',
      );

      expect(apercu.lignes[2].verdict, VerdictApercu.doublon);
      expect(apercu.lignes[2].premiereApparition, 2);
      expect(apercu.lignes[2].detail, contains('ligne 2'));
      expect(apercu.nombreAInviter, 2);
    });

    test('une adresse illisible et une adresse absente sont des fautes', () {
      final apercu = _apercu(
        'prenom;email\n'
        'Marie;marie.exemple.fr\n'
        'Thomas;\n',
      );

      expect(apercu.lignes[0].verdict, VerdictApercu.adresseInvalide);
      expect(apercu.lignes[1].verdict, VerdictApercu.adresseAbsente);
      expect(apercu.lignes[0].verdict.estUneFaute, isTrue);
      expect(apercu.lignes[1].verdict.estUneFaute, isTrue);
      // Sans adresse, le numéro de ligne est le seul repère pour corriger.
      expect(apercu.lignes[1].titre, 'Thomas');
      expect(apercu.lignes[1].sousTitre, 'Ligne 3');
      expect(apercu.envoyable, isFalse);
    });

    test('le fichier passe avant la caserne dans l\'ordre des contrôles', () {
      // Une ligne illisible n'a pas à être comparée à quoi que ce soit, et un
      // doublon interne se dit mieux que « déjà invitée ».
      final apercu = _apercu(
        'email\nmarie@exemple.fr\nMarie@Exemple.fr\n',
        membres: const <MembreCaserne>[_membreMarie],
      );

      expect(apercu.lignes[0].verdict, VerdictApercu.dejaMembre);
      expect(apercu.lignes[1].verdict, VerdictApercu.doublon);
    });

    test('un fichier mêlé compte juste, par motif', () {
      final apercu = _apercu(
        'prenom;email\n'
        'Marie;marie@exemple.fr\n'
        'Recrue;recrue@exemple.fr\n'
        'Anne;anne@x.fr\n'
        'Anne;ANNE@x.fr\n'
        'Paul;paul.x.fr\n',
        membres: const <MembreCaserne>[_membreMarie],
        invitations: <Invitation>[invitationEnAttente()],
      );

      expect(apercu.nombreAInviter, 1);
      expect(apercu.nombreEcartees, 4);
      expect(apercu.ecarteesParMotif, <VerdictApercu, int>{
        VerdictApercu.dejaMembre: 1,
        VerdictApercu.dejaInvitee: 1,
        VerdictApercu.doublon: 1,
        VerdictApercu.adresseInvalide: 1,
      });
    });
  });

  group('Ce qui part dans la requête', () {
    test('seuls l\'adresse, les deux noms et le rôle quittent le navigateur', () {
      final apercu = _apercu(
        'matricule;prenom;nom;email;role;telephone\n'
        '4211;Marie;Lefèbvre;M.Lefebvre@Exemple.FR;admin;0600000000\n',
      );
      final personne = PersonneAInviter.depuisLigne(apercu.lignes.single.ligne);

      expect(personne.versJson(), <String, dynamic>{
        'email': 'm.lefebvre@exemple.fr',
        'role': 'admin',
        'first_name': 'Marie',
        'last_name': 'Lefèbvre',
      });
    });

    test('un nom absent n\'est pas envoyé comme chaîne vide', () {
      final apercu = _apercu('prenom;nom;email\n;;m@x.fr\n');
      final personne = PersonneAInviter.depuisLigne(apercu.lignes.single.ligne);

      expect(personne.versJson().containsKey('first_name'), isFalse);
      expect(personne.versJson().containsKey('last_name'), isFalse);
    });

    test('soixante personnes font trois lots de vingt', () {
      final personnes = <PersonneAInviter>[
        for (var i = 0; i < 60; i++)
          PersonneAInviter(email: 'p$i@x.fr', role: RoleMembre.membre),
      ];
      final lots = decouperEnLots(personnes);

      expect(lots.length, 3);
      expect(lots.map((List<PersonneAInviter> l) => l.length), <int>[20, 20, 20]);
      expect(lots.first.first.email, 'p0@x.fr');
      expect(lots.last.last.email, 'p59@x.fr');
    });

    test('un lot incomplet reste un lot', () {
      final personnes = <PersonneAInviter>[
        for (var i = 0; i < 21; i++)
          PersonneAInviter(email: 'p$i@x.fr', role: RoleMembre.membre),
      ];

      expect(
        decouperEnLots(personnes).map((List<PersonneAInviter> l) => l.length),
        <int>[20, 1],
      );
    });
  });

  group('Budget d\'envoi (plafond du ticket 038)', () {
    final maintenant = DateTime(2026, 9, 21, 15);

    test('un compteur vierge laisse passer tout le plafond', () {
      const budget = BudgetInvitations(
        plafond: 60,
        envoisRecents: <DateTime>[],
      );

      expect(budget.restantes, 60);
    });

    test('la place restante est le plafond moins ce qui est parti', () {
      final budget = BudgetInvitations(
        plafond: 60,
        envoisRecents: <DateTime>[
          for (var i = 0; i < 18; i++)
            maintenant.subtract(Duration(minutes: 50 - i)),
        ],
      );

      expect(budget.restantes, 42);
    });

    test('le plafond atteint rouvre à l\'heure exacte, pas « dans une heure »', () {
      // Même calcul que `invitation_rate_limit()` : le plus ancien des
      // `plafond` derniers envois sort de la fenêtre. Ici il est parti à
      // 14 h 12, donc la place revient à 15 h 12 — pas à 16 h.
      final budget = BudgetInvitations(
        plafond: 3,
        envoisRecents: <DateTime>[
          DateTime(2026, 9, 21, 14, 12),
          DateTime(2026, 9, 21, 14, 30),
          DateTime(2026, 9, 21, 14, 45),
        ],
      );

      expect(budget.restantes, 0);
      expect(
        budget.ouvertureApresEpuisement(maintenant),
        DateTime(2026, 9, 21, 15, 12),
      );
    });

    test('un plafond abaissé après coup ne fait pas mentir l\'heure', () {
      // Cinq envois pour un plafond ramené à trois : ce sont les trois
      // derniers qui comptent, donc la place revient une heure après le
      // premier des trois.
      final budget = BudgetInvitations(
        plafond: 3,
        envoisRecents: <DateTime>[
          DateTime(2026, 9, 21, 14),
          DateTime(2026, 9, 21, 14, 5),
          DateTime(2026, 9, 21, 14, 12),
          DateTime(2026, 9, 21, 14, 30),
          DateTime(2026, 9, 21, 14, 45),
        ],
      );

      expect(budget.restantes, 0);
      expect(
        budget.ouvertureApresEpuisement(maintenant),
        DateTime(2026, 9, 21, 15, 12),
      );
    });

    test('sans rien dans la fenêtre, la place suivante est dans une heure', () {
      const budget = BudgetInvitations(plafond: 2, envoisRecents: <DateTime>[]);

      expect(
        budget.ouvertureApresEpuisement(maintenant),
        maintenant.add(const Duration(hours: 1)),
      );
    });

    test('un import de soixante sur un budget de quarante se coupe en deux', () {
      final budget = BudgetInvitations(
        plafond: 60,
        envoisRecents: <DateTime>[
          for (var i = 0; i < 20; i++) DateTime(2026, 9, 21, 14, 12 + i),
        ],
      );
      final fichier = StringBuffer('email\n');
      for (var i = 0; i < 60; i++) {
        fichier.writeln('p$i@x.fr');
      }
      final apercu = _apercu(fichier.toString(), budget: budget);

      expect(apercu.nombreAInviter, 60);
      expect(apercu.partiraMaintenant(budget), 40);
    });
  });
}
