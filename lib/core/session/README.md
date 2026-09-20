# core/session

Qui est connecté, et dans quelle caserne. Transverse par nature : chaque fonctionnalité a
besoin du `station_id` courant et du rôle, et `lib/features/README.md` interdit à une
fonctionnalité d'en importer une autre.

| Fichier | Rôle |
|---|---|
| `session_utilisateur.dart` | L'utilisateur connecté, réduit à `userId` et `email`. Découplé du SDK. |
| `appartenance.dart` | Une ligne de `memberships` jointe au nom de sa caserne, plus les enums `RoleMembre` et `StatutMembre` (`docs/SCHEMA.md § 1, 2.1, 2.3`). |
| `etat_auth.dart` | Les quatre états qui décident de la route. |
| `auth_erreur.dart` | Les erreurs nommées et leur traduction depuis le SDK. Une phrase par erreur, avec sa sortie. |
| `auth_repository.dart` | Interface + implémentation Supabase : envoi du code, vérification, flux de sessions, déconnexion. |
| `membership_repository.dart` | Interface + implémentation Supabase : les appartenances de l'utilisateur. |
| `session_providers.dart` | Les providers Riverpod. C'est le seul point d'entrée des écrans. |

Les écrans de connexion vivent dans `lib/features/auth/presentation/` : ils sont l'interface
de cette capacité, pas sa définition.

Aucune clé de service ici, ni ailleurs dans `lib/` : toute la sécurité vient des politiques
RLS (`docs/SCHEMA.md § 4`). Un test le vérifie
(`test/core/supabase/aucune_cle_service_test.dart`).
