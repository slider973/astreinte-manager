-- 0037 — Le jeton d'appareil passe au compte qui tient l'appareil. Ticket 057.
-- Référence : docs/SCHEMA.md § 2.11 et § 3 (« Jetons push ») ; docs/WORKFLOWS.md § 8.
--
-- Le défaut corrigé : un téléphone de caserne est prêté. À la déconnexion, la PWA
-- comme l'app iOS suppriment la ligne `push_tokens` de l'appareil **avant** de
-- fermer la session (après, `push_tokens_delete_self` ne le permet plus). Mais une
-- déconnexion hors ligne ne supprime rien : la ligne reste au nom du compte sorti.
--
-- Le compte suivant se connecte sur le même appareil, FCM lui rend **le même
-- jeton**, et l'`upsert` direct sur `token` (colonne `unique`) est refusé par la
-- RLS : la ligne existante appartient à quelqu'un d'autre, `push_tokens_update_self`
-- ne la laisse pas modifier, `push_tokens_insert_self` ne peut pas en créer une
-- seconde. Résultat : les push du compte sorti continuent d'arriver sur
-- l'appareil, et le compte qui le tient n'en reçoit aucun.
--
-- La réponse : `register_push_token`, **seul chemin d'enregistrement** des
-- clients (PWA et app iOS), qui réattribue le jeton au compte de la session.
--
-- Pourquoi c'est légitime : un jeton FCM **identifie un appareil**, pas un compte.
-- FCM ne le remet qu'à l'application installée sur cet appareil ; le présenter,
-- c'est prouver qu'on tient l'appareil. Or un push va là où est l'appareil : le
-- compte qui le tient est le seul à qui ses push doivent arriver. Retirer la ligne
-- de l'ancien propriétaire ne lui retire rien qu'il puisse encore recevoir — ses
-- autres appareils ont leurs propres jetons, et ne sont pas touchés.
--
-- Ce que la fonction ne fait pas : rendre la ligne de l'autre, ni dire qu'elle
-- existait (elle ne rend rien) ; toucher à un autre jeton que celui passé ;
-- accepter un `user_id` en paramètre — c'est `auth.uid()`, jamais l'appelant, qui
-- dit à qui va la ligne. La RLS de `push_tokens` n'est **pas** élargie : un
-- `upsert` direct sur la ligne d'un autre reste refusé.

create function register_push_token(
  p_token        text,
  p_platform     push_platform,
  p_device_label text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_user  uuid := auth.uid();
  v_token text := nullif(btrim(coalesce(p_token, '')), '');
  v_label text := nullif(btrim(coalesce(p_device_label, '')), '');
begin
  -- Pas de session, pas d'enregistrement. `anon` n'a de toute façon pas le droit
  -- d'exécution ; ceci couvre un JWT `authenticated` sans `sub`.
  if v_user is null then
    raise exception 'register_push_token : session requise'
      using errcode = '42501';
  end if;

  if v_token is null then
    raise exception 'register_push_token : jeton vide'
      using errcode = '22023';
  end if;

  if p_platform is null then
    raise exception 'register_push_token : plateforme requise'
      using errcode = '22023';
  end if;

  -- 1. Le jeton quitte le compte qui ne tient plus l'appareil.
  delete from push_tokens
   where token = v_token
     and user_id <> v_user;

  -- 2. Puis il est inscrit, ou rafraîchi, au nom de la session. `user_id` est
  -- repris dans la mise à jour : si un autre appel concurrent a réinséré la
  -- ligne entre les deux instructions, c'est quand même la session qui la garde.
  insert into push_tokens (user_id, token, platform, device_label, last_seen_at)
  values (v_user, v_token, p_platform, v_label, now())
  on conflict (token) do update
     set user_id      = excluded.user_id,
         platform     = excluded.platform,
         device_label = excluded.device_label,
         last_seen_at = excluded.last_seen_at;
end $$;

comment on function register_push_token(text, push_platform, text) is
  'Inscrit ou rafraîchit le jeton push de l''appareil au nom de la session, et le retire à tout autre compte : le jeton identifie l''appareil, le présenter prouve qu''on le tient (ticket 057).';

-- `revoke ... from public` ne suffit pas : `api.auto_expose_new_tables` pose des
-- privilèges par défaut qui accordent `execute` à `anon` et `authenticated` sur
-- toute fonction créée dans `public` (voir 0036). Les deux rôles sont donc
-- révoqués nommément avant le seul `grant`.
revoke all on function register_push_token(text, push_platform, text) from public, anon, authenticated;
grant execute on function register_push_token(text, push_platform, text) to authenticated;
