-- Sandbox only. No card data, charges, production keys or direct client grants.
create table public.travel_hotel_checkouts (
  id uuid primary key,
  owner uuid references auth.users(id) on delete set null,
  quote_id uuid not null,
  request_hash text not null,
  environment text not null default 'sandbox' check (environment = 'sandbox'),
  state text not null check (state in ('prebooking','review','prebook_unknown','expired','queued','submitting','pending_confirmation','confirmed','needs_support')),
  review jsonb not null,
  private_payload text,
  prebook_id text,
  client_reference text not null unique,
  quote_version uuid not null default gen_random_uuid(),
  accepted_at timestamptz,
  expires_at timestamptz not null,
  lease_token uuid,
  lease_until timestamptz,
  next_check timestamptz not null default now(),
  attempts integer not null default 0,
  booking jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner, quote_id)
);
create index travel_hotel_checkouts_owner on public.travel_hotel_checkouts(owner, created_at desc);
create index travel_hotel_checkouts_due on public.travel_hotel_checkouts(next_check)
  where state in ('queued','submitting','pending_confirmation','prebooking');
alter table public.travel_hotel_checkouts enable row level security;
revoke all on public.travel_hotel_checkouts from public, anon, authenticated;
grant all on public.travel_hotel_checkouts to service_role;

-- Account deletion detaches the minimal operational record. Only an already
-- accepted attempt keeps encrypted guests until confirmation/reconciliation.
create function public.travel_hotel_checkout_detach() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.owner is null and new.state not in ('queued','submitting','pending_confirmation') then new.private_payload := null; end if;
  return new;
end;
$$;
revoke all on function public.travel_hotel_checkout_detach() from public, anon, authenticated;
create trigger travel_hotel_checkout_detach before update on public.travel_hotel_checkouts for each row execute function public.travel_hotel_checkout_detach();

create function public.travel_hotel_checkout_create(actor uuid, target uuid, quote uuid, fingerprint text, snapshot jsonb, payload text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare c public.travel_hotel_checkouts; inserted boolean;
begin
  insert into public.travel_hotel_checkouts(id,owner,quote_id,request_hash,state,review,private_payload,client_reference,expires_at,lease_token,lease_until)
  values(target,actor,quote,fingerprint,'prebooking',snapshot,payload,'seur-test-'||target,now()+interval '5 minutes',gen_random_uuid(),now()+interval '90 seconds')
  on conflict do nothing returning * into c;
  inserted := found;
  if not inserted then
    select * into c from public.travel_hotel_checkouts where owner=actor and (id=target or quote_id=quote) order by created_at limit 1;
    if not found then raise sqlstate 'PT409' using message='Checkout unavailable. Start again from room options.'; end if;
    if c.request_hash <> fingerprint then raise sqlstate 'PT409' using message='This room option already has a checkout with different guest details.'; end if;
  end if;
  return jsonb_build_object('checkout',to_jsonb(c),'created',inserted);
end;
$$;

create function public.travel_hotel_checkout_accept(actor uuid, target uuid, version uuid)
returns public.travel_hotel_checkouts language plpgsql security invoker set search_path = '' as $$
declare c public.travel_hotel_checkouts;
begin
  select * into c from public.travel_hotel_checkouts where id=target and owner=actor for update;
  if not found then raise sqlstate 'PT404' using message='Checkout unavailable.'; end if;
  if c.quote_version <> version then raise sqlstate 'PT409' using message='Review the current price and terms before confirming.'; end if;
  if c.accepted_at is not null then return c; end if;
  if c.state <> 'review' then raise sqlstate 'PT409' using message='This checkout is not ready to confirm.'; end if;
  if c.expires_at <= now() then raise sqlstate 'PT410' using message='This price has expired. Choose a fresh room option.'; end if;
  update public.travel_hotel_checkouts set state='queued',accepted_at=now(),next_check=now(),updated_at=now() where id=target returning * into c;
  return c;
end;
$$;

-- A durable claim precedes every supplier call. Once submission starts, only
-- reference lookup is allowed; a crash must never generate another purchase.
create function public.travel_hotel_checkout_claim(target uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare c public.travel_hotel_checkouts; operation text;
begin
  update public.travel_hotel_checkouts set state='prebook_unknown',private_payload=null,lease_token=null,lease_until=null,updated_at=now()
    where state='prebooking' and lease_until < now();
  update public.travel_hotel_checkouts set state='expired',private_payload=null,updated_at=now()
    where state in ('review','queued') and expires_at <= now();
  select * into c from public.travel_hotel_checkouts
    where (target is null or id=target) and state in ('queued','submitting','pending_confirmation')
      and accepted_at is not null and next_check<=now() and (lease_until is null or lease_until < now())
    order by next_check limit 1 for update skip locked;
  if not found then return null; end if;
  operation := case when c.state='queued' then 'book' else 'lookup' end;
  update public.travel_hotel_checkouts set state=case when operation='book' then 'submitting' else 'pending_confirmation' end,
    lease_token=gen_random_uuid(),lease_until=now()+interval '90 seconds',next_check=now()+interval '1 minute',attempts=attempts+1,updated_at=now()
    where id=c.id returning * into c;
  return jsonb_build_object('checkout',to_jsonb(c),'operation',operation);
end;
$$;
revoke all on function public.travel_hotel_checkout_create(uuid,uuid,uuid,text,jsonb,text), public.travel_hotel_checkout_accept(uuid,uuid,uuid), public.travel_hotel_checkout_claim(uuid) from public, anon, authenticated;
grant execute on function public.travel_hotel_checkout_create(uuid,uuid,uuid,text,jsonb,text), public.travel_hotel_checkout_accept(uuid,uuid,uuid), public.travel_hotel_checkout_claim(uuid) to service_role;

-- Dedicated short-lived single-use tickets, separate from notification workers.
create table public.travel_hotel_jobs (id uuid primary key default gen_random_uuid(), expires_at timestamptz not null default now()+interval '5 minutes');
alter table public.travel_hotel_jobs enable row level security;
revoke all on public.travel_hotel_jobs from public, anon, authenticated;
grant all on public.travel_hotel_jobs to service_role;
create function public.travel_hotel_claim_job(ticket uuid) returns boolean language sql security invoker set search_path = '' as $$
  with claimed as (delete from public.travel_hotel_jobs where id=ticket and expires_at > now() returning id)
  select exists(select 1 from claimed);
$$;
revoke all on function public.travel_hotel_claim_job(uuid) from public, anon, authenticated;
grant execute on function public.travel_hotel_claim_job(uuid) to service_role;
create function public.travel_hotel_tick() returns void language plpgsql security invoker set search_path = '' as $$
declare ticket uuid;
begin
  delete from public.travel_hotel_jobs where expires_at < now();
  -- Abandoned review data has no operational purpose after expiration.
  update public.travel_hotel_checkouts set state='expired',private_payload=null,updated_at=now() where state='review' and expires_at <= now();
  update public.travel_hotel_checkouts set private_payload=null where owner is null and state not in ('queued','submitting','pending_confirmation');
  if not exists(select 1 from public.travel_hotel_checkouts where state in ('queued','submitting','pending_confirmation','prebooking') and next_check<=now() and (lease_until is null or lease_until<now())) then return; end if;
  insert into public.travel_hotel_jobs default values returning id into ticket;
  perform net.http_post(url:='https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api/internal/hotel-checkouts',
    headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('ticket',ticket),timeout_milliseconds:=60000);
end;
$$;
revoke all on function public.travel_hotel_tick() from public, anon, authenticated, service_role;
select cron.schedule('seur-hotel-checkouts','* * * * *','select public.travel_hotel_tick()');
