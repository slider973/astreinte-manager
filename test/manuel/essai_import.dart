// Essai manuel de l'import de membres contre la pile locale (ticket 047).
//
// Il ne remplace pas les tests du ticket : il rejoue le parcours contre de
// vraies données, avec de vrais courriels, sur un fichier qu'on fabrique. Il se
// saute tout seul quand on ne lui donne rien.
//
//   supabase start && supabase functions serve
//   # Les trois valeurs viennent de l'environnement : ni jeton ni mot de passe,
//   # même d'un jeu d'essai, ne se range dans un fichier versionné.
//   ANON_KEY=$(jq -r .SUPABASE_ANON_KEY env/dev.json)
//   COMPTE=admin@caserne-a.test MOTDEPASSE=<le mot de passe du seed>
//   JETON=$(curl -s -X POST \
//     'http://127.0.0.1:54321/auth/v1/token?grant_type=password' \
//     -H "apikey: $ANON_KEY" -H 'content-type: application/json' \
//     -d "{\"email\":\"$COMPTE\",\"password\":\"$MOTDEPASSE\"}" \
//     | jq -r .access_token)
//   FICHIER=pompiers.csv JETON=$JETON flutter test test/manuel/essai_import.dart
//
// Rejoue exactement ce que fait l'écran : décodage, aperçu, lecture du budget,
// découpage en lots de vingt, envoi, arrêt au plafond. Ce fichier n'est pas
// livré — il sert à voir le parcours en vrai, avec de vrais courriels.
// Un outil de ligne de commande : il **rend compte sur la sortie standard**,
// c'est tout son objet. La règle vaut pour le code livré, pas pour lui.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:astreinte_sp/features/membres/domain/fichier_membres.dart';
import 'package:astreinte_sp/features/membres/domain/import_membres.dart';
import 'package:astreinte_sp/features/membres/domain/invitation.dart';
import 'package:astreinte_sp/features/membres/domain/membre_caserne.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const String api = 'http://127.0.0.1:54321';
const String station = 'aaaaaaaa-0000-4000-8000-000000000001';
// La clé publique vient de l'environnement, jamais du dépôt : même la clé de
// démonstration locale est un jeton, et l'analyse de secrets la refuse à juste
// titre. `ANON_KEY=$(jq -r .SUPABASE_ANON_KEY env/dev.json)` avant de lancer.
const String anon = String.fromEnvironment('ANON_KEY');

void main() {
  // **Se saute tout seul** quand les deux variables manquent : ce fichier a
  // besoin d'une pile locale, de `supabase functions serve` et d'un jeton
  // d'administrateur. `flutter test` doit rester vert sans rien de tout ça.
  final fichier = Platform.environment['FICHIER'];
  final jeton = Platform.environment['JETON'];

  test(
    'import de bout en bout contre la pile locale',
    _essai,
    skip: fichier == null || jeton == null
        ? 'Manuel : FICHIER=… JETON=… flutter test test/manuel/essai_import.dart'
        : null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _essai() async {
  // `flutter test` détourne HttpClient vers un faux qui rend 400 : ici on veut
  // de vraies requêtes vers la pile locale.
  HttpOverrides.global = null;

  final args = <String>[
    Platform.environment['FICHIER']!,
    Platform.environment['JETON']!,
  ];
  final octets = File(args[0]).readAsBytesSync();
  final jeton = args[1];
  final entetes = <String, String>{
    'apikey': anon,
    'Authorization': 'Bearer $jeton',
    'content-type': 'application/json',
  };

  final lecture = lireFichierMembres(nomFichier: args[0], octets: octets);
  print('--- Lecture');
  print('lisible : ${lecture.lisible}  erreur : ${lecture.erreur}');
  print('lignes  : ${lecture.lignes.length}');
  print(
    'ligne 1 : ${lecture.lignes.first.prenom} '
    '${lecture.lignes.first.nom} <${lecture.lignes.first.email}> '
    '${lecture.lignes.first.role.name}',
  );
  print('ligne 2 : ${lecture.lignes[1].prenom} ${lecture.lignes[1].nom}');

  // Les deux lectures que fait l'écran avant de juger.
  final membres = await _lire(
    '$api/rest/v1/memberships?station_id=eq.$station'
    '&status=in.(active,disabled)'
    '&select=id,user_id,role,status,display_name,profiles!inner(first_name,last_name,email)',
    entetes,
  );
  final invitations = await _lire(
    '$api/rest/v1/invitations?station_id=eq.$station&accepted_at=is.null'
    '&select=id,email,role,first_name,last_name,expires_at,created_at',
    entetes,
  );
  final evenements = await _lire(
    '$api/rest/v1/invitation_rate_events?station_id=eq.$station'
    '&created_at=gt.${DateTime.now().toUtc().subtract(fenetrePlafond).toIso8601String()}'
    '&select=created_at&order=created_at',
    entetes,
  );

  final budget = BudgetInvitations(
    plafond: 60,
    envoisRecents: <DateTime>[
      for (final Map<String, dynamic> e in evenements)
        DateTime.parse(e['created_at']! as String).toLocal(),
    ],
  );

  final apercu = preparerApercu(
    lecture: lecture,
    membres: membres.map(MembreCaserne.depuisJson).toList(),
    invitations: invitations.map(Invitation.depuisJson).toList(),
    budget: budget,
  );

  print('\n--- Aperçu');
  print(
    'à inviter : ${apercu.nombreAInviter}  écartées : ${apercu.nombreEcartees}',
  );
  print('par motif : ${apercu.ecarteesParMotif}');
  print(
    'budget    : ${budget.restantes} places sur ${budget.plafond} '
    '(${budget.envoisRecents.length} envois dans l\'heure)',
  );
  print('partira maintenant : ${apercu.partiraMaintenant(budget)}');
  print(
    'le reste à partir de : '
    '${budget.ouvertureApresEpuisement(DateTime.now())}',
  );
  for (final ligne in apercu.lignes.where((l) => !l.partira).take(6)) {
    print('  ligne ${ligne.ligne.numero} — ${ligne.titre} : ${ligne.detail}');
  }

  print('\n--- Envoi, par lots de vingt');
  final lots = decouperEnLots(
    apercu.aInviter.map((l) => PersonneAInviter.depuisLigne(l.ligne)).toList(),
  );
  var envoyees = 0;
  for (var i = 0; i < lots.length; i++) {
    final reponse = await http.post(
      Uri.parse('$api/functions/v1/invite-member'),
      headers: entetes,
      body: jsonEncode(<String, dynamic>{
        'station_id': station,
        'people': lots[i].map((p) => p.versJson()).toList(),
      }),
    );
    final corps = jsonDecode(reponse.body) as Map<String, dynamic>;
    print('lot ${i + 1} — HTTP ${reponse.statusCode}');

    if (reponse.statusCode != 200) {
      final erreur = corps['error'] as Map<String, dynamic>;
      print('  refus global : ${erreur['code']}');
      print('  message      : ${erreur['message']}');
      print('  retry_at     : ${erreur['retry_at']}');
      print(
        '  ARRÊT : ${apercu.nombreAInviter - envoyees} personnes restent à inviter.',
      );
      break;
    }

    final rapport = RapportInvitations.depuisJson(corps);
    envoyees += rapport.resultats.length;
    print(
      '  créées ${rapport.creees}, courriels partis '
      '${rapport.courrielsPartis}, échecs ${rapport.echecs} '
      '(cumul $envoyees/${apercu.nombreAInviter})',
    );
    final coupe = rapport.resultats.where(
      (r) => r.motif == MotifEchecInvitation.debitAtteint,
    );
    if (coupe.isNotEmpty) {
      print('  plafond atteint dans le lot : ${coupe.first.detail}');
      print('  reprise possible à : ${coupe.first.plafond?.reessayerLe}');
      print('  ARRÊT : les lots suivants ne sont pas tentés.');
      break;
    }
  }
}

Future<List<Map<String, dynamic>>> _lire(
  String url,
  Map<String, String> entetes,
) async {
  final reponse = await http.get(Uri.parse(url), headers: entetes);
  if (reponse.statusCode != 200) {
    throw StateError('${reponse.statusCode} sur $url : ${reponse.body}');
  }
  return (jsonDecode(reponse.body) as List<dynamic>)
      .cast<Map<String, dynamic>>();
}
