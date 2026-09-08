-- Typed, private intents on the existing conversation and sharing path.
alter table public.travel_messages add column trip_request jsonb,
 add column reply_to uuid references public.travel_messages(id) on delete set null;
create index travel_messages_reply on public.travel_messages(reply_to) where reply_to is not null;
create index travel_messages_requests on public.travel_messages(conversation_id) where trip_request is not null;

create or replace function public.travel_message(m public.travel_messages) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',m.id,'sender',public.travel_user(m.sender_id),'text',m.text,
 'documentID',m.document_id,'createdAt',extract(epoch from m.created),
 'tripRequest',m.trip_request,'replyTo',m.reply_to,
 'documentIsTemplate',(select coalesce((d.body->>'isTemplate')::boolean,false) from public.travel_documents d where d.id=m.document_id));
$$;

create or replace function public.travel_conversation(cid uuid,actor uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.travel_members where conversation_id=cid and user_id=actor) then
  raise sqlstate 'PT403' using message='You are not a member of this conversation.';
 end if;
 return (select jsonb_build_object('id',c.id,'name',c.name,'members',
  (select jsonb_agg(public.travel_user(m.user_id) order by p.name) from public.travel_members m join public.travel_profiles p on p.id=m.user_id where m.conversation_id=cid),
  'pendingRequests',(select count(*) from public.travel_messages q where q.conversation_id=cid and q.trip_request is not null
    and q.sender_id<>actor and public.travel_friends(actor,q.sender_id)
    and not exists(select 1 from public.travel_messages r where r.reply_to=q.id and r.document_id is not null)))
 from public.travel_conversations c where c.id=cid);
end $$;

create function public.travel_send_message(actor uuid,cid uuid,body jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare intent jsonb; target public.travel_messages; reply uuid; result jsonb; mid uuid; member uuid;
begin
 -- Membership is checked before validating or looking up any private message IDs.
 perform public.travel_conversation(cid,actor);
 intent=nullif(body->'tripRequest','null'::jsonb);
 if intent is not null then
  if (select count(*) from public.travel_members where conversation_id=cid) < 2 then raise sqlstate 'PT400' using message='Choose a friend to receive your request.'; end if;
  if jsonb_typeof(intent)<>'object' or jsonb_typeof(intent->'city') is distinct from 'string'
   or length(trim(intent->>'city')) not between 1 and 120
   or jsonb_typeof(intent->'month') is distinct from 'string'
   or (intent->>'month') !~ '^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$'
   or nullif(body->>'replyTo','') is not null or nullif(body->>'documentID','') is not null then
   raise sqlstate 'PT400' using message='Choose a destination and a valid travel month.';
  end if;
  -- Only explicitly supported intent fields are stored.
  intent=jsonb_build_object('city',trim(intent->>'city'),'month',intent->>'month');
  for member in select user_id from public.travel_members where conversation_id=cid and user_id<>actor loop
   perform 1 from public.travel_friendships where a=least(actor,member) and b=greatest(actor,member) and status='accepted' for share;
   if not found then raise sqlstate 'PT403' using message='Trip requests can only be sent to accepted friends.'; end if;
  end loop;
 end if;
 if nullif(body->>'replyTo','') is not null then
  if (body->>'replyTo') !~ '^[a-fA-F0-9-]{36}$' then raise sqlstate 'PT400' using message='Invalid trip request.'; end if;
  begin reply=(body->>'replyTo')::uuid; exception when invalid_text_representation then raise sqlstate 'PT400' using message='Invalid trip request.'; end;
  select * into target from public.travel_messages where id=reply and conversation_id=cid for share;
  if target.id is null or target.trip_request is null or target.sender_id=actor then
   raise sqlstate 'PT400' using message='Reply to a trip request from someone in this conversation.';
  end if;
  if nullif(body->>'documentID','') is null then raise sqlstate 'PT400' using message='Choose a trip or template to answer this request.'; end if;
 end if;
 -- Reuse ownership, friendship locks, redaction and document-grant behavior, in one transaction.
 result=public.travel_dispatch(actor,'POST','/v1/conversations/'||cid::text||'/messages',body);
 mid=(result->>'id')::uuid;
 update public.travel_messages set trip_request=intent,reply_to=reply where id=mid;
 return (select public.travel_message(m) from public.travel_messages m where id=mid);
end $$;
revoke all on function public.travel_send_message(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.travel_send_message(uuid,uuid,jsonb) to service_role;
