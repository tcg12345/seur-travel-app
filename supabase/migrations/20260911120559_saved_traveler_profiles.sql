-- Private account profiles: contact and nationality fields are encrypted by the API.
create table public.travel_traveler_profiles (
  owner uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  private_payload text not null check (length(private_payload) between 20 and 12000),
  version integer not null default 1 check (version > 0),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(owner,id)
);
create unique index travel_traveler_one_default on public.travel_traveler_profiles(owner) where is_default;
alter table public.travel_traveler_profiles enable row level security;
revoke all on public.travel_traveler_profiles from public, anon, authenticated;
grant all on public.travel_traveler_profiles to service_role;

create function public.travel_traveler_save(actor uuid, target uuid, expected_version integer, payload text, make_default boolean)
returns setof public.travel_traveler_profiles language plpgsql security invoker set search_path='' as $$
declare existing public.travel_traveler_profiles; chosen boolean;
begin
  if actor is null or target is null or expected_version is null or expected_version < 0 or make_default is null then raise sqlstate 'PT400' using message='Invalid traveler profile.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text, 4831));
  select * into existing from public.travel_traveler_profiles where owner=actor and id=target;
  if (existing.id is null and expected_version <> 0) or (existing.id is not null and existing.version <> expected_version) then raise sqlstate 'PT409' using message='This traveler changed on another device. Reopen the profile to edit it.'; end if;
  if existing.id is null and (select count(*) from public.travel_traveler_profiles where owner=actor) >= 20 then raise sqlstate 'PT400' using message='You can save up to 20 travelers.'; end if;
  chosen := make_default or coalesce(existing.is_default,false) or not exists(select 1 from public.travel_traveler_profiles where owner=actor);
  if chosen then update public.travel_traveler_profiles set is_default=false,version=version+1,updated_at=now() where owner=actor and is_default and id<>target; end if;
  insert into public.travel_traveler_profiles(owner,id,private_payload,is_default) values(actor,target,payload,chosen)
  on conflict(owner,id) do update set private_payload=excluded.private_payload,is_default=excluded.is_default,version=travel_traveler_profiles.version+1,updated_at=now();
  return query select * from public.travel_traveler_profiles where owner=actor order by is_default desc,created_at,id;
end $$;
create function public.travel_traveler_delete(actor uuid,target uuid,expected_version integer)
returns setof public.travel_traveler_profiles language plpgsql security invoker set search_path='' as $$
declare existing public.travel_traveler_profiles;
begin
  if actor is null or target is null or expected_version is null or expected_version < 1 then raise sqlstate 'PT400' using message='Invalid traveler profile.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text,4831));
  select * into existing from public.travel_traveler_profiles where owner=actor and id=target;
  if existing.id is not null and existing.version<>expected_version then raise sqlstate 'PT409' using message='This traveler changed on another device. Reopen the profile before deleting it.'; end if;
  delete from public.travel_traveler_profiles where owner=actor and id=target;
  if existing.is_default then update public.travel_traveler_profiles set is_default=true,version=version+1,updated_at=now() where owner=actor and id=(select id from public.travel_traveler_profiles where owner=actor order by created_at,id limit 1); end if;
  return query select * from public.travel_traveler_profiles where owner=actor order by is_default desc,created_at,id;
end $$;
revoke all on function public.travel_traveler_save(uuid,uuid,integer,text,boolean) from public,anon,authenticated;
revoke all on function public.travel_traveler_delete(uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.travel_traveler_save(uuid,uuid,integer,text,boolean) to service_role;
grant execute on function public.travel_traveler_delete(uuid,uuid,integer) to service_role;
