-- Sandbox cancellation is a separate operation; a cancelled booking never implies a refund.
alter table public.travel_hotel_checkouts add column cancellation jsonb;
alter table public.travel_hotel_checkouts add column cancellation_attempts integer not null default 0;
create index travel_hotel_cancellation_due on public.travel_hotel_checkouts(next_check)
 where cancellation->>'state' in ('queued','submitting','pending');

create function public.travel_hotel_cancel_prepare(actor uuid,target uuid,expected_updated timestamptz,snapshot jsonb)
returns public.travel_hotel_checkouts language plpgsql security invoker set search_path='' as $$
declare c public.travel_hotel_checkouts;
begin
 select * into c from public.travel_hotel_checkouts where owner=actor and id=target for update;
 if not found then raise sqlstate 'PT404' using message='Booking unavailable.'; end if;
 if c.cancellation->>'state' in ('queued','submitting','pending','cancelled','needs_support') then return c; end if;
 if c.updated_at<>expected_updated or c.state<>'confirmed' or c.booking is null then raise sqlstate 'PT409' using message='Booking changed. Refresh before cancelling.'; end if;
 update public.travel_hotel_checkouts set cancellation=snapshot,cancellation_attempts=0,updated_at=now() where id=target returning * into c;
 return c;
end $$;
create function public.travel_hotel_cancel_accept(actor uuid,target uuid,version uuid)
returns public.travel_hotel_checkouts language plpgsql security invoker set search_path='' as $$
declare c public.travel_hotel_checkouts;
begin
 select * into c from public.travel_hotel_checkouts where owner=actor and id=target for update;
 if not found then raise sqlstate 'PT404' using message='Booking unavailable.'; end if;
 if c.cancellation->>'version' is distinct from version::text then raise sqlstate 'PT409' using message='Review the current cancellation terms.'; end if;
 if c.cancellation->>'state' in ('queued','submitting','pending','cancelled','needs_support') then return c; end if;
 if c.state<>'confirmed' or c.cancellation->>'state' <> 'review' then raise sqlstate 'PT409' using message='Cancellation unavailable.'; end if;
 if (c.cancellation->>'expiresAt')::timestamptz <= now() then raise sqlstate 'PT410' using message='Cancellation review expired. Check the terms again.'; end if;
 update public.travel_hotel_checkouts set cancellation=cancellation||jsonb_build_object('state','queued','acceptedAt',now()),next_check=now(),updated_at=now() where id=target returning * into c;
 return c;
end $$;
create function public.travel_hotel_cancel_claim()
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.travel_hotel_checkouts; op text;
begin
 update public.travel_hotel_checkouts set cancellation=cancellation||'{"state":"expired"}'::jsonb,updated_at=now()
 where cancellation->>'state' in ('review','queued') and (cancellation->>'expiresAt')::timestamptz<=now();
 select * into c from public.travel_hotel_checkouts where cancellation->>'state' in ('queued','submitting','pending')
 and next_check<=now() and (lease_until is null or lease_until<now()) order by next_check limit 1 for update skip locked;
 if not found then return null; end if;
 op:=case when c.cancellation->>'state'='queued' then 'cancel' else 'lookup' end;
 update public.travel_hotel_checkouts set cancellation=cancellation||jsonb_build_object('state',case when op='cancel' then 'submitting' else 'pending' end),
 lease_token=gen_random_uuid(),lease_until=now()+interval '90 seconds',next_check=now()+interval '1 minute',cancellation_attempts=cancellation_attempts+1,updated_at=now()
 where id=c.id returning * into c;
 return jsonb_build_object('checkout',to_jsonb(c),'operation',op);
end $$;
revoke all on function public.travel_hotel_cancel_prepare(uuid,uuid,timestamptz,jsonb), public.travel_hotel_cancel_accept(uuid,uuid,uuid), public.travel_hotel_cancel_claim() from public,anon,authenticated;
grant execute on function public.travel_hotel_cancel_prepare(uuid,uuid,timestamptz,jsonb), public.travel_hotel_cancel_accept(uuid,uuid,uuid), public.travel_hotel_cancel_claim() to service_role;

create or replace function public.travel_hotel_tick() returns void language plpgsql security invoker set search_path = '' as $$
declare ticket uuid;
begin
  delete from public.travel_hotel_jobs where expires_at < now();
  -- Abandoned review data has no operational purpose after expiration.
  update public.travel_hotel_checkouts set state='expired',private_payload=null,updated_at=now() where state='review' and expires_at <= now();
  update public.travel_hotel_checkouts set private_payload=null where owner is null and state not in ('queued','submitting','pending_confirmation');
  update public.travel_hotel_checkouts set cancellation=cancellation||'{"state":"expired"}'::jsonb,updated_at=now() where cancellation->>'state' in ('review','queued') and (cancellation->>'expiresAt')::timestamptz<=now();
  if not exists(select 1 from public.travel_hotel_checkouts where cancellation->>'state' in ('queued','submitting','pending') and next_check<=now() and (lease_until is null or lease_until<now())) and not exists(select 1 from public.travel_hotel_checkouts where state in ('queued','submitting','pending_confirmation','prebooking') and next_check<=now() and (lease_until is null or lease_until<now())) then return; end if;
  insert into public.travel_hotel_jobs default values returning id into ticket;
  perform net.http_post(url:='https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api/internal/hotel-checkouts',
    headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('ticket',ticket),timeout_milliseconds:=60000);
end;
$$;
