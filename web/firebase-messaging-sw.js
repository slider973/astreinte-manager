/*
 * Ancien emplacement du service worker des notifications — à retirer à la
 * version suivante (ticket 074).
 *
 * Le vrai vit désormais dans `push/firebase-messaging-sw.js`, sur une portée à
 * lui. Ce fichier-ci ne reste que pour **nettoyer les navigateurs déjà
 * passés**, qui gardent deux sortes d'enregistrements pointant ici :
 *
 *   - sur la portée `/`, derrière `flutter_service_worker.js`, avec la
 *     configuration dans l'URL (le défaut que corrige le ticket 074) ;
 *   - sur `/firebase-cloud-messaging-push-scope`, **sans** configuration : ce
 *     que le SDK Firebase enregistre de lui-même quand `deleteToken()` est
 *     appelé sans `getToken()` préalable (la déconnexion d'avant le 074).
 *
 * Quand le navigateur revérifie l'un d'eux, il trouve ce script-ci : il
 * s'active sans attendre, oublie l'abonnement push de son enregistrement,
 * puis se désinscrit. Aucun `importScripts`, aucune requête vers Google.
 *
 * **Sauf sur la portée `/`, où il ne fait rien du tout.** Cet enregistrement
 * est celui de Flutter : s'y activer puis se désinscrire emporterait le worker
 * de Flutter, donc le hors-ligne. Là, il reste en attente et le chargeur de
 * Flutter (`flutter_bootstrap.js`) le remplace au lancement suivant ;
 * l'abonnement push qu'il y avait laissé est oublié par l'application
 * (`nettoyerEnregistrements`, `lib/features/notifications/data/pont_web.dart`).
 */

const SUR_LA_RACINE =
  self.registration.scope === new URL('./', self.location).href;

if (!SUR_LA_RACINE) {
  self.addEventListener('install', () => {
    self.skipWaiting();
  });

  self.addEventListener('activate', (evenement) => {
    evenement.waitUntil(
      (async () => {
        try {
          const abonnement =
            await self.registration.pushManager.getSubscription();
          if (abonnement) await abonnement.unsubscribe();
        } catch (erreur) {
          // Sans abonnement lisible, il reste à se désinscrire : c'est ce qui
          // coupe le chemin des push, abonnement compris.
        }
        await self.registration.unregister();
      })(),
    );
  });
}
