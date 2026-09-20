import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les six familles d'états, avec leurs valeurs et leur résolveur.
///
/// Un état ajouté à une énumération sans descripteur fait échouer ce fichier
/// avant d'arriver à l'écran.
Map<String, List<StatusDescriptor>> _familles(AppStatusColors statuts) {
  return <String, List<StatusDescriptor>>{
    'disponibilité': <StatusDescriptor>[
      for (final etat in DisponibiliteEtat.values) statuts.disponibilite(etat),
    ],
    'créneau': <StatusDescriptor>[
      for (final type in CreneauType.values) statuts.creneau(type),
    ],
    'attribution': <StatusDescriptor>[
      for (final etat in AttributionEtat.values) statuts.attribution(etat),
    ],
    'planning': <StatusDescriptor>[
      for (final etat in PlanningEtat.values) statuts.planning(etat),
    ],
    'période': <StatusDescriptor>[
      for (final etat in PeriodeEtat.values) statuts.periode(etat),
    ],
    'synchronisation': <StatusDescriptor>[
      for (final etat in SyncEtat.values) statuts.sync(etat),
    ],
  };
}

const Map<String, AppStatusColors> _themes = <String, AppStatusColors>{
  'clair': AppStatusColors.clair,
  'sombre': AppStatusColors.sombre,
};

void main() {
  group('StatusDescriptor', () {
    test('un libellé vide est refusé à la construction', () {
      expect(
        () => StatusDescriptor(
          icone: Icons.check,
          libelle: '',
          encre: const Color(0xFF000000),
          fond: const Color(0xFFFFFFFF),
        ),
        throwsAssertionError,
      );
    });

    test('iconeCase retombe sur icone quand il n\'y a pas de variante', () {
      const descripteur = StatusDescriptor(
        icone: Icons.lock,
        libelle: 'Mois verrouillé',
        encre: Color(0xFF000000),
        fond: Color(0xFFFFFFFF),
      );
      expect(descripteur.iconeCase, Icons.lock);
    });

    test(
      'lerp bascule l\'icône et le libellé à mi-course, jamais à moitié',
      () {
        const a = StatusDescriptor(
          icone: Icons.check_box,
          libelle: 'Disponible',
          encre: Color(0xFF000000),
          fond: Color(0xFFFFFFFF),
        );
        const b = StatusDescriptor(
          icone: Icons.close,
          libelle: 'Absent',
          encre: Color(0xFFFFFFFF),
          fond: Color(0xFF000000),
        );

        expect(StatusDescriptor.lerp(a, b, 0.2).libelle, 'Disponible');
        expect(StatusDescriptor.lerp(a, b, 0.8).libelle, 'Absent');
        expect(StatusDescriptor.lerp(a, b, 0.8).icone, Icons.close);
      },
    );
  });

  group('AppStatusColors', () {
    for (final entree in _themes.entries) {
      final nomTheme = entree.key;
      final familles = _familles(entree.value);

      test('$nomTheme : chaque état a une icône et un libellé non vide', () {
        for (final famille in familles.entries) {
          expect(
            famille.value,
            isNotEmpty,
            reason: 'La famille « ${famille.key} » n\'a aucun descripteur.',
          );
          for (final descripteur in famille.value) {
            expect(
              descripteur.libelle.trim(),
              isNotEmpty,
              reason:
                  'Un état de « ${famille.key} » n\'a pas de libellé : '
                  'la règle « jamais la couleur seule » est cassée.',
            );
            expect(
              descripteur.icone.codePoint,
              isNot(0),
              reason:
                  'Un état de « ${famille.key} » n\'a pas d\'icône : '
                  'la règle « jamais la couleur seule » est cassée.',
            );
          }
        }
      });

      test('$nomTheme : deux états d\'une même famille n\'ont jamais la même '
          'icône', () {
        for (final famille in familles.entries) {
          final vues = <int, String>{};
          for (final descripteur in famille.value) {
            final code = descripteur.icone.codePoint;
            expect(
              vues.containsKey(code),
              isFalse,
              reason:
                  'Dans « ${famille.key} », « ${descripteur.libelle} » et '
                  '« ${vues[code]} » partagent la même icône. Une icône est '
                  'un signal d\'état : deux états ne peuvent pas la '
                  'partager.',
            );
            vues[code] = descripteur.libelle;
          }
        }
      });

      test('$nomTheme : deux états d\'une même famille n\'ont jamais le même '
          'libellé', () {
        for (final famille in familles.entries) {
          final libelles = famille.value
              .map((descripteur) => descripteur.libelle)
              .toList();
          expect(
            libelles.toSet().length,
            libelles.length,
            reason:
                'Deux états de « ${famille.key} » portent le même libellé : '
                '$libelles.',
          );
        }
      });
    }

    test(
      'les familles qui partagent une teinte ne partagent jamais l\'icône',
      () {
        // `accepté` et `disponible` sont tous deux verts ; `refusé` et
        // `absent` tous deux vermillon. C'est l'icône qui les sépare
        // (`DESIGN.md § Attribution`).
        const statuts = AppStatusColors.clair;
        expect(
          statuts.attribution(AttributionEtat.accepte).icone,
          isNot(statuts.disponibilite(DisponibiliteEtat.disponible).icone),
        );
        expect(
          statuts.attribution(AttributionEtat.refuse).icone,
          isNot(statuts.disponibilite(DisponibiliteEtat.absent).icone),
        );
      },
    );

    test('la case du registre a ses trois glyphes propres', () {
      const statuts = AppStatusColors.clair;
      final glyphes = <IconData>[
        for (final etat in DisponibiliteEtat.values)
          statuts.disponibilite(etat).iconeCase,
      ];
      expect(glyphes, <IconData>[Icons.check, Icons.close, Icons.remove]);
      expect(glyphes.map((g) => g.codePoint).toSet().length, 3);
    });

    test('« absent » et « non saisi » ne se ressemblent jamais', () {
      // C'est le mécanisme qui sépare ce produit de l'intranet remplacé :
      // si ces deux cases se ressemblent, le système a échoué (brief § 2).
      for (final statuts in _themes.values) {
        final absent = statuts.disponibilite(DisponibiliteEtat.absent);
        final nonSaisi = statuts.disponibilite(DisponibiliteEtat.nonSaisi);

        expect(absent.icone, isNot(nonSaisi.icone));
        expect(absent.iconeCase, isNot(nonSaisi.iconeCase));
        expect(absent.libelle, isNot(nonSaisi.libelle));
        expect(absent.fond, isNot(nonSaisi.fond));
        // La marque avant la teinte : l'un est hachuré, l'autre pas.
        expect(absent.hachure, isTrue);
        expect(nonSaisi.hachure, isFalse);
      }
    });

    test('lerp d\'extension conserve toutes les familles', () {
      final melange = AppStatusColors.clair.lerp(AppStatusColors.sombre, 0.5);
      expect(melange.tous.length, AppStatusColors.clair.tous.length);
      expect(melange.disponibilites.length, DisponibiliteEtat.values.length);
      expect(melange.syncs.length, SyncEtat.values.length);
    });

    test('copyWith ne perd aucune famille', () {
      final copie = AppStatusColors.clair.copyWith(
        filetEtat: const Color(0xFF123456),
      );
      expect(copie.filetEtat, const Color(0xFF123456));
      expect(copie.tous.length, AppStatusColors.clair.tous.length);
    });
  });
}
