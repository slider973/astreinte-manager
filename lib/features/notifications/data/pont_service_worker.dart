import '../domain/message_push.dart';
import 'pont_stub.dart' if (dart.library.js_interop) 'pont_web.dart';

/// Les destinations envoyées par le service worker quand on touche une
/// notification **alors que l'application est déjà ouverte**.
///
/// Trois chemins mènent à une destination, et ils sont distincts :
///
/// 1. l'application est au premier plan → `messagesPremierPlan` et la
///    bannière ;
/// 2. l'application est fermée → le service worker ouvre une fenêtre sur le
///    lien, et c'est `DestinationInitiale` qui le rattrape au démarrage à
///    froid (`core/router/destination_initiale.dart`) ;
/// 3. l'application est ouverte mais cachée (onglet en arrière-plan, PWA
///    minimisée) → le service worker la ramène au premier plan et lui poste la
///    destination. **C'est ce flux-ci**, et sans lui on reviendrait sur
///    l'écran quitté au lieu de la proposition.
///
/// Depuis le ticket 072, la caserne de la notification voyage avec le lien.
Stream<OuverturePush> routesDepuisServiceWorker() => ecouterServiceWorker();

/// Range les service workers de l'origine, **sans réseau** (voir
/// `nettoyerEnregistrements`).
///
/// [garderPush] : vrai au lancement, où l'abonnement de la portée `push/` est
/// celui qu'on veut garder ; faux à la déconnexion, où tout part.
Future<void> nettoyerServiceWorkers({required bool garderPush}) =>
    nettoyerEnregistrements(garderPush: garderPush);

/// Un avertissement dans la console du navigateur, **en production aussi**.
///
/// Réservé aux échecs qui, sinon, ne laissent aucune trace : un jeton push
/// refusé, une ligne `push_tokens` non écrite (ticket 074). Jamais de jeton
/// dans le message.
void avertirConsole(String message) => avertir(message);
