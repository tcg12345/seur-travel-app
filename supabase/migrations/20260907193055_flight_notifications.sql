-- Device tokens are private, server-only data, using Seur's existing session auth.
create table public.travel_flight_watches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.travel_profiles(id) on delete cascade,
  session_hash text not null references public.travel_sessions(token_hash) on delete cascade,
  installation_id uuid not null,
  device_token text not null,
  environment text not null check (environment in ('sandbox','production')),
  flight_id text not null,
  ident text not null,
  departure_day date not null,
  snapshot jsonb not null,
  activity_token text,
  activity_id text,
  reminder_sent boolean not null default false,
  enabled boolean not null default true,
  next_check timestamptz not null default now(),
  expires_at timestamptz not null,
  updated_at timestamptz not null default now(),
  unique(user_id, installation_id, flight_id)
);
create index travel_flight_watches_due on public.travel_flight_watches(next_check) where enabled;
create index travel_flight_watches_owner on public.travel_flight_watches(user_id, installation_id);
create index travel_flight_watches_session on public.travel_flight_watches(session_hash);
alter table public.travel_flight_watches enable row level security;
revoke all on public.travel_flight_watches from public, anon, authenticated;
grant all on public.travel_flight_watches to service_role;

-- Single-use, short-lived worker tickets avoid embedding a reusable key in cron.
create table public.travel_push_jobs (id uuid primary key default gen_random_uuid(), expires_at timestamptz not null default now() + interval '10 minutes');
alter table public.travel_push_jobs enable row level security;
revoke all on public.travel_push_jobs from public, anon, authenticated;
grant all on public.travel_push_jobs to service_role;
create function public.travel_push_claim_job(ticket uuid) returns boolean language sql security invoker set search_path = '' as $$
  with claimed as (delete from public.travel_push_jobs where id=ticket and expires_at > now() returning id)
  select exists(select 1 from claimed);
$$;
create function public.travel_push_claim_watches() returns setof public.travel_flight_watches language sql security invoker set search_path = '' as $$
  with due as (
    select id from public.travel_flight_watches w where enabled and next_check <= now() and expires_at > now()
      and exists (select 1 from public.travel_sessions s where s.token_hash=w.session_hash and s.expires > now())
    order by next_check limit 20 for update skip locked
  ) update public.travel_flight_watches w set next_check=now()+interval '15 minutes'
    from due where w.id=due.id returning w.*;
$$;
revoke all on function public.travel_push_claim_job(uuid), public.travel_push_claim_watches() from public, anon, authenticated;
grant execute on function public.travel_push_claim_job(uuid), public.travel_push_claim_watches() to service_role;

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create function public.travel_push_tick() returns void language plpgsql security invoker set search_path = '' as $$
declare ticket uuid;
begin
  delete from public.travel_push_jobs where expires_at < now();
  delete from public.travel_flight_watches where expires_at < now() - interval '1 day';
  -- No worker invocation or FlightAware traffic when nobody is following a flight.
  if not exists(select 1 from public.travel_flight_watches where enabled and next_check <= now() and expires_at > now()) then return; end if;
  insert into public.travel_push_jobs default values returning id into ticket;
  perform net.http_post(
    url := 'https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api/internal/flight-notifications',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('ticket', ticket), timeout_milliseconds := 120000
  );
end;
$$;
revoke all on function public.travel_push_tick() from public, anon, authenticated, service_role;
select cron.schedule('seur-flight-notifications', '*/5 * * * *', 'select public.travel_push_tick()');
