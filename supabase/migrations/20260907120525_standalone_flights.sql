-- Standalone flight records use the same authenticated Edge API boundary as trips.
create table public.travel_flights (
 owner_id uuid not null references public.travel_profiles(id) on delete cascade,
 id uuid not null,
 body jsonb not null check (jsonb_typeof(body) = 'object'),
 updated_at timestamptz not null default now(),
 primary key (owner_id, id)
);
alter table public.travel_flights enable row level security;
revoke all on public.travel_flights from public, anon, authenticated;
grant all on public.travel_flights to service_role;
create policy service_only on public.travel_flights for all to service_role using (true) with check (true);
