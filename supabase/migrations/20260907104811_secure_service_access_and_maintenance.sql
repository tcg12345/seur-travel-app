-- Explicit deny policies document the server-only API boundary.
do $$ declare t text; begin
 foreach t in array array['travel_profiles','travel_sessions','travel_friendships','travel_documents','travel_links','travel_conversations','travel_members','travel_messages','travel_grants','travel_limits','travel_provider_cache'] loop
 execute format('create policy server_only on public.%I for all to anon, authenticated using (false) with check (false)',t);
 end loop;
 if to_regprocedure('public.rls_auto_enable()') is not null then
  execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
 end if;
end $$;
create function public.travel_maintenance() returns void language sql security invoker set search_path='' as $$
 delete from public.travel_sessions where expires<now();
 delete from public.travel_provider_cache where expires<now();
 delete from public.travel_limits where started<now()-interval '2 hours';
$$;
create function public.travel_orphan_photos() returns setof text language sql stable security invoker set search_path='' as $$
 select o.name from storage.objects o where o.bucket_id='journey-photos' and o.created_at<now()-interval '1 day'
 and o.name ~ '^[a-f0-9-]{36}/[a-f0-9-]{36}/[a-f0-9-]{36}/[a-f0-9-]{36}\.jpg$'
 and not exists(select 1 from public.travel_documents d where d.id::text=split_part(o.name,'/',2)
 and d.body @> jsonb_build_object('places',jsonb_build_array(jsonb_build_object('photos',jsonb_build_array(jsonb_build_object('storagePath',o.name))))))
 order by o.created_at limit 100;
$$;
revoke all on function public.travel_maintenance(),public.travel_orphan_photos() from public,anon,authenticated;
grant execute on function public.travel_maintenance(),public.travel_orphan_photos() to service_role;
