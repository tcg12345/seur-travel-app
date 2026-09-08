-- Recaps are immutable, independently revocable projections of local trips.
-- A recap never publishes or changes the audience of the source document.
create table public.travel_recaps (
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
 owner_id uuid not null references public.travel_profiles(id) on delete cascade,
 document_id uuid not null,
 visibility text not null check(visibility in ('private','friends','public')),
 body jsonb not null,
 created timestamptz not null default now()
);
create index travel_recaps_owner_document on public.travel_recaps(owner_id,document_id);
create table public.travel_recap_media (
 token_hash text not null references public.travel_recaps(token_hash) on delete cascade,
 image_id text not null,
 jpeg text not null check(length(jpeg) <= 2000000),
 primary key(token_hash,image_id)
);
alter table public.travel_recaps enable row level security;
alter table public.travel_recap_media enable row level security;
revoke all on public.travel_recaps, public.travel_recap_media from public, anon, authenticated;
grant all on public.travel_recaps, public.travel_recap_media to service_role;
comment on table public.travel_recaps is 'Service-only. Edge validates the account or a high-entropy recap capability. No direct client access.';
comment on table public.travel_recap_media is 'Only selected, re-encoded photos; media inherits snapshot lifetime through cascade.';
create function public.travel_save_recap(actor uuid, hash text, doc uuid, audience text, snapshot jsonb, images jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
begin
 if not exists(select 1 from public.travel_profiles where id=actor) then raise sqlstate 'PT401' using message='Sign in first.'; end if;
 if exists(select 1 from public.travel_documents where id=doc and owner_id<>actor) then raise sqlstate 'PT403' using message='Make your own private copy before sharing this trip.'; end if;
 if (select count(*) from public.travel_recaps where owner_id=actor and document_id=doc)>=20 then raise sqlstate 'PT400' using message='Revoke older recap links before creating more.'; end if;
 insert into public.travel_recaps(token_hash,owner_id,document_id,visibility,body) values(hash,actor,doc,audience,snapshot);
 insert into public.travel_recap_media(token_hash,image_id,jpeg) select hash,i->>'id',i->>'jpeg' from jsonb_array_elements(images) i;
end $$;
revoke all on function public.travel_save_recap(uuid,text,uuid,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.travel_save_recap(uuid,text,uuid,text,jsonb,jsonb) to service_role;
create function public.travel_recap_source_cleanup() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
 if TG_OP='DELETE' or (new.visibility='private' and old.visibility<>'private') then
   delete from public.travel_recaps where owner_id=old.owner_id and document_id=old.id;
 end if;
 return null;
end $$;
revoke all on function public.travel_recap_source_cleanup() from public,anon,authenticated;
create trigger travel_recap_source_cleanup after delete or update of visibility on public.travel_documents for each row execute function public.travel_recap_source_cleanup();
