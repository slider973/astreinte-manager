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
Stream<String> routesDepuisServiceWorker() => ecouterServiceWorker();

/// Oublie l'abonnement push de ce navigateur, **sans réseau**
/// (voir `desabonnerPushLocal`).
Future<void> oublierAbonnementPush() => desabonnerPushLocal();
