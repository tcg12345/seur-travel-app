-- All application access is through the authenticated travel-api Edge Function.
-- These tables have RLS and no client grants; the service role is server-only.
create table public.travel_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 handle text unique not null check (handle ~ '^[a-z0-9_]{3,32}$'),
 name text not null check (length(name) between 1 and 100), created timestamptz not null default now()
);
create table public.travel_sessions (
 token_hash text primary key, user_id uuid not null references public.travel_profiles(id) on delete cascade,
 expires timestamptz not null, created timestamptz not null default now()
);
create index travel_sessions_user on public.travel_sessions(user_id);
create index travel_sessions_expiry on public.travel_sessions(expires);
create table public.travel_friendships (
 a uuid not null references public.travel_profiles(id) on delete cascade,
 b uuid not null references public.travel_profiles(id) on delete cascade,
 requester uuid not null references public.travel_profiles(id) on delete cascade,
 status text not null check(status in ('pending','accepted')), primary key(a,b), check(a < b), check(requester in (a,b))
);
create index travel_friendships_b on public.travel_friendships(b);
create index travel_friendships_requester on public.travel_friendships(requester);
create table public.travel_documents (
 id uuid primary key, owner_id uuid not null references public.travel_profiles(id) on delete cascade,
 body jsonb not null, visibility text not null check(visibility in ('private','friends','public')),
 revision integer not null default 1, updated timestamptz not null default now(),
 check(lower(body->>'id')=id::text), check(body->>'visibility'=visibility)
);
create index travel_documents_owner on public.travel_documents(owner_id,updated desc);
create index travel_documents_feed on public.travel_documents(updated desc) where visibility in ('friends','public');
create table public.travel_links (
 token_hash text primary key, document_id uuid not null references public.travel_documents(id) on delete cascade,
 created timestamptz not null default now()
);
create index travel_links_document on public.travel_links(document_id);
create table public.travel_conversations (
 id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 1 and 100),
 creator_id uuid not null references public.travel_profiles(id) on delete cascade, created timestamptz not null default now()
);
create index travel_conversations_creator on public.travel_conversations(creator_id);
create table public.travel_members (
 conversation_id uuid not null references public.travel_conversations(id) on delete cascade,
 user_id uuid not null references public.travel_profiles(id) on delete cascade, primary key(conversation_id,user_id)
);
create index travel_members_user on public.travel_members(user_id);
create table public.travel_messages (
 id uuid primary key default gen_random_uuid(), conversation_id uuid not null references public.travel_conversations(id) on delete cascade,
 sender_id uuid not null references public.travel_profiles(id) on delete cascade, text text not null check(length(text)<=5000),
 document_id uuid references public.travel_documents(id) on delete set null, created timestamptz not null default now()
);
create index travel_messages_conversation on public.travel_messages(conversation_id,created);
create index travel_messages_sender on public.travel_messages(sender_id);
create index travel_messages_document on public.travel_messages(document_id);
create table public.travel_grants (
 document_id uuid not null references public.travel_documents(id) on delete cascade,
 user_id uuid not null references public.travel_profiles(id) on delete cascade, primary key(document_id,user_id)
);
create index travel_grants_user on public.travel_grants(user_id);
create table public.travel_limits (key text primary key, started timestamptz not null, count integer not null);
create index travel_limits_started on public.travel_limits(started);
create table public.travel_provider_cache (key text primary key, value jsonb not null, expires timestamptz not null);
create index travel_cache_expires on public.travel_provider_cache(expires);

do $$ declare t text; begin
 foreach t in array array['travel_profiles','travel_sessions','travel_friendships','travel_documents','travel_links','travel_conversations','travel_members','travel_messages','travel_grants','travel_limits','travel_provider_cache'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public, anon, authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('journey-photos','journey-photos',false,1500000,array['image/jpeg'])
on conflict(id) do nothing;
-- No client storage policies: the Edge Function checks document access before reads.

create function public.travel_limit(k text, maximum integer, seconds integer) returns boolean
language plpgsql security invoker set search_path='' as $$
declare n integer; begin
 delete from public.travel_limits where started < now()-interval '2 hours';
 insert into public.travel_limits(key,started,count) values(k,now(),1)
 on conflict(key) do update set
 count=case when travel_limits.started < now()-make_interval(secs=>seconds) then 1 else travel_limits.count+1 end,
 started=case when travel_limits.started < now()-make_interval(secs=>seconds) then now() else travel_limits.started end
 returning count into n;
 return n<=maximum;
end $$;
create function public.travel_friends(x uuid,y uuid) returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.travel_friendships where a=least(x,y) and b=greatest(x,y) and status='accepted');
$$;
create function public.travel_user(x uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',id,'handle',handle,'name',name) from public.travel_profiles where id=x;
$$;
create function public.travel_readable(d public.travel_documents, actor uuid) returns boolean language sql stable security invoker set search_path='' as $$
 select d.owner_id=actor or d.visibility='public' or (d.visibility='friends' and public.travel_friends(d.owner_id,actor)) or exists(select 1 from public.travel_grants where document_id=d.id and user_id=actor);
$$;
create function public.travel_remote(d public.travel_documents,actor uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare b jsonb:=d.body; begin
 if actor is distinct from d.owner_id then
 b=jsonb_set(b,'{hotels}',coalesce((select jsonb_agg(h || '{"confirmation":"","notes":""}'::jsonb) from jsonb_array_elements(b->'hotels') h),'[]'::jsonb));
 b=jsonb_set(b,'{flights}',coalesce((select jsonb_agg(f || '{"notes":""}'::jsonb) from jsonb_array_elements(b->'flights') f),'[]'::jsonb));
 end if;
 return jsonb_build_object('id',d.id,'owner',public.travel_user(d.owner_id),'document',b,'revision',d.revision);
end $$;
create function public.travel_conversation(cid uuid,actor uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.travel_members where conversation_id=cid and user_id=actor) then raise sqlstate 'PT403' using message='You are not a member of this conversation.'; end if;
 return (select jsonb_build_object('id',c.id,'name',c.name,'members',(select jsonb_agg(public.travel_user(m.user_id) order by p.name) from public.travel_members m join public.travel_profiles p on p.id=m.user_id where m.conversation_id=cid)) from public.travel_conversations c where c.id=cid);
end $$;
create function public.travel_message(m public.travel_messages) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',m.id,'sender',public.travel_user(m.sender_id),'text',m.text,'documentID',m.document_id,'createdAt',extract(epoch from m.created));
$$;
create function public.travel_dispatch(actor uuid,method text,path text,body jsonb default '{}'::jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare other uuid; x uuid; y uuid; ident uuid; action text; d public.travel_documents; f public.travel_friendships; cid uuid; mid uuid; ids uuid[]; v uuid; result jsonb;
begin
 if actor is null or not exists(select 1 from public.travel_profiles where id=actor) then raise sqlstate 'PT401' using message='Sign in to your travel account first.'; end if;
 if path='/v1/me' and method='GET' then return public.travel_user(actor); end if;
 if path='/v1/friends' then
  if method='GET' then return coalesce((select jsonb_agg(public.travel_user(case when a=actor then b else a end)||jsonb_build_object('status',status,'incoming',requester<>actor)) from public.travel_friendships where a=actor or b=actor),'[]'::jsonb); end if;
  if method='POST' then
   select id into other from public.travel_profiles where handle=lower(trim(body->>'handle'));
   if other is null then raise sqlstate 'PT404' using message='No account has that username.'; end if;
   if other=actor then raise sqlstate 'PT400' using message='Choose another traveler.'; end if;
   insert into public.travel_friendships values(least(actor,other),greatest(actor,other),actor,'pending') on conflict do nothing;
   if not found then raise sqlstate 'PT409' using message='A friendship or request already exists.'; end if;
   return '{"ok":true}';
  end if;
 end if;
 if path ~ '^/v1/friends/[a-fA-F0-9-]{36}$' and method in ('PUT','DELETE') then
  other=split_part(path,'/',4)::uuid; x=least(actor,other); y=greatest(actor,other);
  select * into f from public.travel_friendships where a=x and b=y for update;
  if not found then raise sqlstate 'PT404' using message='Friend request not found.'; end if;
  if method='PUT' then
   if f.requester=actor or f.status<>'pending' then raise sqlstate 'PT403' using message='Only the recipient can accept a pending request.'; end if;
   update public.travel_friendships set status='accepted' where a=x and b=y;
  else
   delete from public.travel_friendships where a=x and b=y;
   delete from public.travel_grants g using public.travel_documents doc where g.document_id=doc.id and ((g.user_id=actor and doc.owner_id=other) or (g.user_id=other and doc.owner_id=actor));
  end if;
  return '{"ok":true}';
 end if;
 if method='GET' and path in ('/v1/documents','/v1/feed') then
  return coalesce((select jsonb_agg(public.travel_remote(z,actor) order by z.updated desc) from
   (select dd.* from public.travel_documents dd where (path='/v1/documents' and owner_id=actor) or (path='/v1/feed' and owner_id<>actor and visibility in ('friends','public') and public.travel_friends(owner_id,actor)) order by updated desc limit 200) z),'[]'::jsonb);
 end if;
 if path ~ '^/v1/documents/[a-fA-F0-9-]{36}(/(link|revoke))?$' then
  ident=split_part(path,'/',4)::uuid; action=split_part(path,'/',5);
  -- Serialize creation and updates, including the previously absent-row case.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(ident::text,0));
  select * into d from public.travel_documents where id=ident for update;
  if method='PUT' and action='' then
   if d.id is not null and d.owner_id<>actor then raise sqlstate 'PT403' using message='Only the owner can edit this journey.'; end if;
   if d.id is not null and (body->>'updatedAt')::numeric < (d.body->>'updatedAt')::numeric then raise sqlstate 'PT409' using message='A newer cloud copy exists. Download it before updating.'; end if;
   if d.id is not null and body->>'visibility'='private' and d.visibility<>'private' then delete from public.travel_links where document_id=ident; delete from public.travel_grants where document_id=ident; end if;
   insert into public.travel_documents(id,owner_id,body,visibility) values(ident,actor,body,body->>'visibility')
   on conflict(id) do update set body=excluded.body, visibility=excluded.visibility, revision=travel_documents.revision+1,updated=now() returning * into d;
   return public.travel_remote(d,actor);
  end if;
  if d.id is null then raise sqlstate 'PT404' using message='Journey not found.'; end if;
  if d.owner_id<>actor and (method<>'GET' or action<>'' or not public.travel_readable(d,actor)) then raise sqlstate 'PT403' using message='You do not have access to this journey.'; end if;
  if method='GET' and action='' then return public.travel_remote(d,actor); end if;
  if method='DELETE' and action='' then delete from public.travel_documents where id=ident; return '{"ok":true}'; end if;
  if method='POST' and action='link' then
   insert into public.travel_links(token_hash,document_id) values(body->>'token_hash',ident); return '{"ok":true}';
  end if;
  if method='POST' and action='revoke' then
   delete from public.travel_links where document_id=ident; delete from public.travel_grants where document_id=ident;
   update public.travel_documents set visibility='private',body=jsonb_set(travel_documents.body,'{visibility}','"private"'),revision=revision+1,updated=now() where id=ident; return '{"ok":true}';
  end if;
 end if;
 if path='/v1/conversations' then
  if method='GET' then return coalesce((select jsonb_agg(public.travel_conversation(c.id,actor) order by c.created desc) from public.travel_conversations c join public.travel_members m on c.id=m.conversation_id where m.user_id=actor),'[]'::jsonb); end if;
  if method='POST' then
   if jsonb_typeof(body->'members')<>'array' or jsonb_array_length(body->'members') not between 1 and 30 or length(trim(body->>'name')) not between 1 and 100 then raise sqlstate 'PT400' using message='Choose a name and 1–30 friends.'; end if;
   ids=array(select distinct value::uuid from jsonb_array_elements_text(body->'members'));
   foreach v in array ids loop
    if v=actor or not public.travel_friends(actor,v) then raise sqlstate 'PT403' using message='All invited members must be accepted friends.'; end if;
   end loop;
   if cardinality(ids)=1 then
    select m.conversation_id into cid from public.travel_members m where m.user_id=actor and exists(select 1 from public.travel_members n where n.conversation_id=m.conversation_id and n.user_id=ids[1]) and (select count(*) from public.travel_members n where n.conversation_id=m.conversation_id)=2 limit 1;
    if cid is not null then return public.travel_conversation(cid,actor); end if;
   end if;
   insert into public.travel_conversations(name,creator_id) values(body->>'name',actor) returning id into cid;
   insert into public.travel_members values(cid,actor);
   foreach v in array ids loop insert into public.travel_members values(cid,v); end loop;
   return public.travel_conversation(cid,actor);
  end if;
 end if;
 if path ~ '^/v1/conversations/[a-fA-F0-9-]{36}/messages$' then
  cid=split_part(path,'/',4)::uuid; perform public.travel_conversation(cid,actor);
  if method='GET' then return coalesce((select jsonb_agg(public.travel_message(z) order by z.created) from (select * from public.travel_messages where conversation_id=cid order by created desc limit 300) z),'[]'::jsonb); end if;
  if method='POST' then
   ident=nullif(body->>'documentID','')::uuid;
   if length(coalesce(body->>'text',''))>5000 or (trim(coalesce(body->>'text',''))='' and ident is null) then raise sqlstate 'PT400' using message='Add a message or journey.'; end if;
   if ident is not null then
    select * into d from public.travel_documents where id=ident for update;
    if d.id is null or d.owner_id<>actor then raise sqlstate 'PT403' using message='Only the owner can share this journey.'; end if;
    for v in select user_id from public.travel_members where conversation_id=cid and user_id<>actor loop
     -- Lock friendship rows against concurrent revocation while granting access.
     perform 1 from public.travel_friendships where a=least(actor,v) and b=greatest(actor,v) and status='accepted' for share;
     if not found then raise sqlstate 'PT403' using message='Every recipient must still be your friend to share a journey.'; end if;
     insert into public.travel_grants values(ident,v) on conflict do nothing;
    end loop;
   end if;
   insert into public.travel_messages(conversation_id,sender_id,text,document_id) values(cid,actor,coalesce(body->>'text',''),ident) returning id into mid;
   return (select public.travel_message(m) from public.travel_messages m where id=mid);
  end if;
 end if;
 raise sqlstate 'PT404' using message='Endpoint not found.';
end $$;

-- Functions are not callable by public clients, even when PUBLIC inherits EXECUTE.
revoke all on function public.travel_limit(text,integer,integer),public.travel_friends(uuid,uuid),public.travel_user(uuid),public.travel_readable(public.travel_documents,uuid),public.travel_remote(public.travel_documents,uuid),public.travel_conversation(uuid,uuid),public.travel_message(public.travel_messages),public.travel_dispatch(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.travel_limit(text,integer,integer),public.travel_friends(uuid,uuid),public.travel_user(uuid),public.travel_readable(public.travel_documents,uuid),public.travel_remote(public.travel_documents,uuid),public.travel_conversation(uuid,uuid),public.travel_message(public.travel_messages),public.travel_dispatch(uuid,text,text,jsonb) to service_role;
