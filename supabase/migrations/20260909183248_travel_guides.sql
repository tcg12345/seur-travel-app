-- Published guides are separate from private itineraries. Only travel-api can access these tables.
create table public.travel_guides (
 id uuid primary key,
 owner_id uuid not null references public.travel_profiles(id) on delete cascade,
 body jsonb not null check (jsonb_typeof(body)='object' and octet_length(body::text)<=6000000),
 revision integer not null default 1 check(revision>0),
 published boolean not null default true,
 hidden boolean not null default false,
 created timestamptz not null default now(),
 updated timestamptz not null default now()
);
create index travel_guides_owner on public.travel_guides(owner_id, updated desc);
create index travel_guides_public on public.travel_guides(updated desc, id) where published and not hidden;
create table public.travel_guide_reports (
 guide_id uuid not null references public.travel_guides(id) on delete cascade,
 reporter_id uuid not null references public.travel_profiles(id) on delete cascade,
 reason text not null check(reason in ('Spam','Inappropriate content','Inaccurate information','Copyright concern')),
 created timestamptz not null default now(), primary key(guide_id,reporter_id)
);
create index travel_guide_reports_reporter on public.travel_guide_reports(reporter_id);
create table public.travel_guide_blocks (
 actor_id uuid not null references public.travel_profiles(id) on delete cascade,
 author_id uuid not null references public.travel_profiles(id) on delete cascade,
 primary key(actor_id,author_id), check(actor_id<>author_id)
);
create index travel_guide_blocks_author on public.travel_guide_blocks(author_id);
alter table public.travel_guides enable row level security;
alter table public.travel_guide_reports enable row level security;
alter table public.travel_guide_blocks enable row level security;
revoke all on public.travel_guides,public.travel_guide_reports,public.travel_guide_blocks from public,anon,authenticated;
grant all on public.travel_guides,public.travel_guide_reports,public.travel_guide_blocks to service_role;

create function public.travel_guide_remote(g public.travel_guides, summary boolean default false) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('guide',case when summary then (g.body-'coverJPEG'-'sections') || jsonb_build_object('sections','[]'::jsonb,'coverJPEG',g.body->'thumbnailJPEG') else g.body end,
  'author',public.travel_user(g.owner_id),'revision',g.revision,'isPublished',g.published,'isSummary',summary,
  'updatedAt',extract(epoch from g.updated),'placeCount',(select coalesce(sum(jsonb_array_length(s->'places')),0) from jsonb_array_elements(g.body->'sections') s))
$$;
create function public.travel_guides_read(actor uuid default null, target uuid default null, own boolean default false, search text default '', tag text default '', skip integer default 0) returns jsonb
language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(public.travel_guide_remote(g,target is null) order by g.updated desc,g.id),'[]'::jsonb) from (
  select d.* from public.travel_guides d
  where ((own and actor is not null and d.owner_id=actor) or (not own and d.published and not d.hidden))
   and (target is null or d.id=target)
   and (own or actor is null or not exists(select 1 from public.travel_guide_blocks b where b.actor_id=actor and b.author_id=d.owner_id))
   and (search='' or position(lower(search) in lower((d.body->>'title') || ' ' || (d.body->>'destination')))>0)
   and (tag='' or (d.body->'tags') ? tag)
  order by d.updated desc,d.id limit 20 offset greatest(0,least(skip,10000))
 ) g
$$;
create function public.travel_guide_publish(actor uuid, doc jsonb, expected integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare old public.travel_guides; saved public.travel_guides; target uuid := (doc->>'id')::uuid;
begin
 if actor is null or not exists(select 1 from public.travel_profiles where id=actor) then raise sqlstate 'PT401' using message='Sign in to publish your guide.'; end if;
 select * into old from public.travel_guides where id=target for update;
 if found then
  if old.owner_id<>actor then raise sqlstate 'PT403' using message='This guide belongs to another traveler.'; end if;
  if old.hidden then raise sqlstate 'PT403' using message='This guide is under review and cannot be republished.'; end if;
  if expected<>old.revision or expected is null then raise sqlstate 'PT409' using message='This guide changed on another device. Reload the published version before updating.'; end if;
  update public.travel_guides set body=doc,published=true,revision=revision+1,updated=now() where id=target returning * into saved;
 else
  if expected<>0 or expected is null then raise sqlstate 'PT409' using message='The published version is no longer available. Create a new guide to publish again.'; end if;
  insert into public.travel_guides(id,owner_id,body) values(target,actor,doc) returning * into saved;
 end if;
 return public.travel_guide_remote(saved);
end $$;
create function public.travel_guide_unpublish(actor uuid, target uuid, expected integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare old public.travel_guides; saved public.travel_guides;
begin
 select * into old from public.travel_guides where id=target for update;
 if not found or actor is null or old.owner_id<>actor then raise sqlstate 'PT404' using message='Guide unavailable.'; end if;
 if expected<>old.revision or expected is null then raise sqlstate 'PT409' using message='This guide changed. Reload it before unpublishing.'; end if;
 update public.travel_guides set published=false,revision=revision+1,updated=now() where id=target returning * into saved;
 return public.travel_guide_remote(saved);
end $$;
create function public.travel_guide_report(actor uuid, target uuid, reason text) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 if actor is null or not exists(select 1 from public.travel_profiles where id=actor) then raise sqlstate 'PT401' using message='Sign in to report a guide.'; end if;
 if not exists(select 1 from public.travel_guides where id=target and published and not hidden) then raise sqlstate 'PT404' using message='Guide unavailable.'; end if;
 insert into public.travel_guide_reports(guide_id,reporter_id,reason) values(target,actor,reason)
 on conflict(guide_id,reporter_id) do update set reason=excluded.reason;
 return '{"ok":true}'::jsonb;
end $$;
create function public.travel_guide_block(actor uuid, author uuid, blocked boolean) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 if actor is null or actor=author or not exists(select 1 from public.travel_profiles where id=actor) then raise sqlstate 'PT400' using message='Choose another traveler.'; end if;
 if blocked then insert into public.travel_guide_blocks values(actor,author) on conflict do nothing;
 else delete from public.travel_guide_blocks where actor_id=actor and author_id=author; end if;
 return '{"ok":true}'::jsonb;
end $$;
revoke all on function public.travel_guide_remote(public.travel_guides,boolean),public.travel_guides_read(uuid,uuid,boolean,text,text,integer),public.travel_guide_publish(uuid,jsonb,integer),public.travel_guide_unpublish(uuid,uuid,integer),public.travel_guide_report(uuid,uuid,text),public.travel_guide_block(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.travel_guide_remote(public.travel_guides,boolean),public.travel_guides_read(uuid,uuid,boolean,text,text,integer),public.travel_guide_publish(uuid,jsonb,integer),public.travel_guide_unpublish(uuid,uuid,integer),public.travel_guide_report(uuid,uuid,text),public.travel_guide_block(uuid,uuid,boolean) to service_role;
