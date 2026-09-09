-- Actor is derived from the Seur session by the Edge Function. This RPC is
-- never directly executable by anonymous or authenticated client roles.
create function public.travel_social_feed(actor uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select coalesce(jsonb_agg(public.travel_remote(d, actor) order by d.updated desc), '[]'::jsonb)
  from (
    select doc.* from public.travel_documents doc
    where doc.owner_id <> actor and (
      (doc.visibility in ('friends', 'public') and public.travel_friends(doc.owner_id, actor))
      or exists(select 1 from public.travel_grants g where g.document_id=doc.id and g.user_id=actor)
    )
    order by doc.updated desc limit 200
  ) d;
$$;
revoke all on function public.travel_social_feed(uuid) from public, anon, authenticated;
grant execute on function public.travel_social_feed(uuid) to service_role;
